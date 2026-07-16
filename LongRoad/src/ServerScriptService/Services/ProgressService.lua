-- ProgressService: run lifecycle — checkpoint progress, death (drop to a bag),
-- extraction rewards, currency, starter kits, leaderstats, and DataStore
-- persistence.
--
-- State model:
--   * profiles[player] = { currency, completions, bestTime (seconds | nil),
--                          ownedKits = { kitId, ... } } — always present (a
--     default is created synchronously on join; the async load then fills it).
--   * profileLoaded[player] = did the DataStore read succeed? A NEW player (nil
--     data, ok read) counts as loaded and IS saveable; a read FAILURE stays
--     false and we NEVER save over it (would clobber real data with defaults).
--
-- Attribute ownership: `Currency` and `CheckpointIndex` are plain player
-- attributes (also written by DebugService's /set currency and /checkpoint).
-- They are the live values: awards/deductions read-modify-write the attribute,
-- and save-time pulls the attribute back into the profile. `OwnedKits` is a
-- comma-joined string attribute the client reads to flip Buy -> Owned.
-- `RunStartTime` (os.time) is set on join and reset on each extraction, and is
-- what extraction reads to compute elapsed. CheckpointIndex is per-run (resets
-- to 0 each run) and is NOT persisted.
--
-- RunFinished payload (server -> client, victory banner): {
--   elapsed = number (run seconds), reward = number (currency awarded),
--   completions = number (new total), bestTime = number (new best, seconds) }
--
-- DataStore verify in Studio needs Game Settings -> Security -> Enable Studio
-- Access to API Services. Without it GetAsync/SetAsync throw; the pcall paths
-- below degrade to a default profile with profileLoaded=false (warn once), so
-- everything works in-session but nothing persists.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- Checkpoint/extraction detection is XZ-planar only (the target Y is ground
-- level, the root sits a few studs above), matching SurvivalService's
-- isNearCheckpoint. Radii live in GameConfig (CHECKPOINT_RADIUS/EXTRACTION_RADIUS).
local ZONE_SCAN_INTERVAL = 2
local AUTOSAVE_INTERVAL = 120
local RESPAWN_TIME = 5
local LOAD_RETRIES = 3
local RUN_HOUR = 3600      -- full-bonus below 30min, zero at 60min (see timeBonus)
local BONUS_WINDOW = 1800
local BINDTOCLOSE_DEADLINE = 25 -- seconds; below Roblox's ~30s shutdown budget, leaving margin

-- Spawn/checkpoint positions carry Y=0 in Config; we resolve real ground Y once
-- at Init by raycasting down onto the baked map, then spawn SPAWN_OFFSET above it.
-- SPAWN_Y_LIFT is only the fallback when a raycast misses (map not baked): pivot
-- high and let the character fall, like DebugService's /tp.
local SPAWN_OFFSET = 4
local SPAWN_Y_LIFT = 50
local GROUND_RAY_HEIGHT = 500 -- ray origin Y; well above the tallest baked terrain

local ProgressService = {}

local deps
local Config

local profiles = {}          -- player -> profile table (see header)
local profileLoaded = {}     -- player -> bool (read succeeded; gate every save)
local extracting = {}        -- player -> true while standing in the extraction radius (edge-trigger guard)
local store                  -- DataStore handle, or nil if GetDataStore threw (Studio w/o API access)
local warnedNoStore = false  -- warn-once flag for the degraded (no persistence) path
local spawnCFrames = {}      -- index (0 = spawn, 1..N = checkpoints) -> ground-resolved CFrame (built at Init)

local function notify(player, text)
	deps.Remotes.Notify:FireClient(player, text)
end

local function defaultProfile()
	return { currency = 0, completions = 0, bestTime = nil, ownedKits = {} }
end

-- mm:ss, or "-" when there is no best time yet.
local function formatTime(seconds)
	if not seconds then
		return "-"
	end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

local function withinXZ(pos, target, radius)
	local dx = pos.X - target.X
	local dz = pos.Z - target.Z
	return dx * dx + dz * dz <= radius * radius
end

-- Live root+humanoid, or nil in both slots (so any `if not root` guard fires).
local function getLiveChar(player)
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root, humanoid
end

-- Resolves a Config position (Y=0) to a spawn CFrame sitting SPAWN_OFFSET above
-- the baked ground. Raycasts down onto everything except water; a miss means the
-- map isn't baked, so we fall back to the high lift (pivot up, fall onto ground).
local function resolveGround(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true -- don't land on the river surface
	local origin = Vector3.new(position.X, GROUND_RAY_HEIGHT, position.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -GROUND_RAY_HEIGHT * 2, 0), params)
	if result then
		return CFrame.new(position.X, result.Position.Y + SPAWN_OFFSET, position.Z)
	end
	return CFrame.new(position + Vector3.new(0, SPAWN_Y_LIFT, 0))
end

-- ===== Kits =====

local function kitById(kitId)
	for _, kit in ipairs(Config.STARTER_KITS) do
		if kit.id == kitId then
			return kit
		end
	end
	return nil
end

local function ownsKit(profile, kitId)
	return table.find(profile.ownedKits, kitId) ~= nil
end

local function updateOwnedKitsAttribute(player)
	local profile = profiles[player]
	player:SetAttribute("OwnedKits", profile and table.concat(profile.ownedKits, ",") or "")
end

-- Grants every owned kit's items. Called at each RUN START (join + extraction),
-- NOT on death-respawn (that stays a within-run event, items already lost).
-- GiveItem pushes its own inventory update and keeps whatever fits (a full
-- inventory shouldn't happen on a fresh run, but partial fills are harmless).
local function grantOwnedKits(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	for _, kit in ipairs(Config.STARTER_KITS) do
		if ownsKit(profile, kit.id) then
			for _, itemId in ipairs(kit.items) do
				deps.Inventory.GiveItem(player, itemId, 1)
			end
		end
	end
end

-- ===== Leaderstats =====

local function syncLeaderstats(player)
	local ls = player:FindFirstChild("leaderstats")
	local profile = profiles[player]
	if not ls or not profile then
		return
	end
	local completions = ls:FindFirstChild("Completions")
	if completions then
		completions.Value = profile.completions
	end
	local bestTime = ls:FindFirstChild("Best Time")
	if bestTime then
		bestTime.Value = formatTime(profile.bestTime)
	end
	-- Currency mirrors its attribute via the signal wired in setupLeaderstats.
end

local function setupLeaderstats(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"

	local completions = Instance.new("IntValue")
	completions.Name = "Completions"
	completions.Parent = ls

	local bestTime = Instance.new("StringValue")
	bestTime.Name = "Best Time"
	bestTime.Value = "-"
	bestTime.Parent = ls

	local currency = Instance.new("IntValue")
	currency.Name = "Currency"
	currency.Parent = ls

	ls.Parent = player

	-- Keep Currency in lockstep with the attribute (awards, deductions, /set).
	local function syncCurrency()
		currency.Value = player:GetAttribute("Currency") or 0
	end
	player:GetAttributeChangedSignal("Currency"):Connect(syncCurrency)
	syncCurrency()
end

-- ===== DataStore =====

local function profileKey(player)
	return "Player_" .. player.UserId
end

-- Returns (profile, success). success is true when the read itself succeeded —
-- INCLUDING a new player whose data is nil. Only a genuine failure (no store,
-- or all retries threw) returns false, which blocks saving for this session.
local function fetchProfile(player)
	if not store then
		if not warnedNoStore then
			warnedNoStore = true
			warn("[ProgressService] no DataStore (Studio API access off?); running without persistence")
		end
		return defaultProfile(), false
	end
	local key = profileKey(player)
	for attempt = 1, LOAD_RETRIES do
		local ok, result = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			local profile = defaultProfile()
			if type(result) == "table" then
				profile.currency = tonumber(result.currency) or 0
				profile.completions = tonumber(result.completions) or 0
				profile.bestTime = tonumber(result.bestTime) -- nil when absent
				if type(result.ownedKits) == "table" then
					for _, id in ipairs(result.ownedKits) do
						if kitById(id) and not table.find(profile.ownedKits, id) then
							table.insert(profile.ownedKits, id)
						end
					end
				end
			end
			return profile, true
		end
		warn(("[ProgressService] load attempt %d for %s failed: %s"):format(attempt, player.Name, tostring(result)))
		if attempt < LOAD_RETRIES then
			task.wait(2 ^ (attempt - 1)) -- 1s, 2s backoff between tries
		end
	end
	return defaultProfile(), false
end

-- Never saves over a failed load. Pulls live attribute values into the profile
-- first. Autosave and PlayerRemoving can both call this for the same player;
-- SetAsync is atomic per key so the race resolves last-write-wins (acceptable —
-- both write the same up-to-date snapshot).
-- No session locking: if the same UserId is live on two servers (e.g. a fast
-- rejoin onto a different instance), the later save wins and the earlier
-- server's progress is lost. UpdateAsync/ProfileService-style session locking is
-- deliberately out of scope for v1 (single-key SetAsync is enough here).
local function saveProfile(player)
	if not store or not profileLoaded[player] then
		return
	end
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.currency = player:GetAttribute("Currency") or profile.currency
	local ok, err = pcall(function()
		store:SetAsync(profileKey(player), {
			currency = profile.currency,
			completions = profile.completions,
			bestTime = profile.bestTime,
			ownedKits = profile.ownedKits,
		})
	end)
	if not ok then
		warn(("[ProgressService] save for %s failed: %s"):format(player.Name, tostring(err)))
	end
end

-- ===== Spawning / checkpoints =====

-- Highest CheckpointIndex across the player's squad (respawn at a squad-mate's
-- checkpoint if further). GetMembers returns {} for a solo player, so we seed
-- from the player's own attribute; 0/absent means the start line.
local function resolveCheckpointIndex(player)
	local best = player:GetAttribute("CheckpointIndex") or 0
	for _, member in ipairs(deps.Squad.GetMembers(player)) do
		local idx = member:GetAttribute("CheckpointIndex") or 0
		if idx > best then
			best = idx
		end
	end
	return best
end

-- Ground-resolved spawn CFrame for a checkpoint index (0 = start line). Out-of-
-- range indices fall back to the start (spawnCFrames always has key 0).
local function spawnCFrameForIndex(index)
	return spawnCFrames[index] or spawnCFrames[0]
end

-- Prefetches streaming around the destination (Workspace.StreamingEnabled) so
-- the client has terrain to land on, then pivots. RequestStreamAroundAsync
-- YIELDS, so callers MUST run this off any synchronous hot path (the scan loop);
-- the character is re-checked after the yield in case it died/despawned.
local function streamAndPivot(player, character, target)
	pcall(function()
		player:RequestStreamAroundAsync(target.Position)
	end)
	if character.Parent and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(target)
	end
end

-- Places the fresh character at its resolved checkpoint. Waits for the root to
-- exist (Roblox positions the character a moment after CharacterAdded). Always
-- invoked via task.spawn, so the streaming yield in streamAndPivot is safe.
local function placeAtCheckpoint(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	streamAndPivot(player, character, spawnCFrameForIndex(resolveCheckpointIndex(player)))
end

local function onDied(player, character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local deathPos = root and root.Position
	local items = deps.Inventory.ClearAll(player)
	-- No bag for an empty inventory (e.g. dying at spawn); LootService also
	-- validates and no-ops on an empty stack list.
	if deathPos and #items > 0 then
		deps.Loot.SpawnDeathBag(deathPos, items)
	end
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	task.spawn(placeAtCheckpoint, player, character)
	if humanoid then
		humanoid.Died:Connect(function()
			onDied(player, character)
		end)
	end
end

-- ===== Extraction =====

local function completeRun(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local startTime = player:GetAttribute("RunStartTime") or os.time()
	local elapsed = math.max(0, os.time() - startTime)
	local timeBonus = Config.TIME_BONUS_MAX * math.clamp((RUN_HOUR - elapsed) / BONUS_WINDOW, 0, 1)
	local reward = math.floor(Config.EXTRACTION_REWARD + timeBonus)

	player:SetAttribute("Currency", (player:GetAttribute("Currency") or 0) + reward)
	profile.completions += 1
	if not profile.bestTime or elapsed < profile.bestTime then
		profile.bestTime = elapsed
	end
	syncLeaderstats(player)

	deps.Remotes.RunFinished:FireClient(player, {
		elapsed = elapsed,
		reward = reward,
		completions = profile.completions,
		bestTime = profile.bestTime,
	})

	-- Reset for the next run (order per spec).
	player:SetAttribute("CheckpointIndex", 0)
	deps.Inventory.ClearAll(player)
	grantOwnedKits(player)
	player:SetAttribute("RunStartTime", os.time())
	-- Teleport off the scan loop's synchronous path: streamAndPivot yields on
	-- RequestStreamAroundAsync, and the loop must not yield mid-pass.
	local character = player.Character
	if character then
		task.spawn(streamAndPivot, player, character, spawnCFrameForIndex(0))
	end
end

-- One scan pass covers checkpoints (advance to a further one) and extraction
-- (edge-triggered so a player parked in the radius fires exactly once per run).
local function scanPlayer(player)
	local root = getLiveChar(player) -- dead players don't extract or progress
	if not root then
		extracting[player] = nil
		return
	end
	local pos = root.Position

	local current = player:GetAttribute("CheckpointIndex") or 0
	for idx, cp in ipairs(Config.CHECKPOINTS) do
		if idx > current and withinXZ(pos, cp.position, Config.CHECKPOINT_RADIUS) then
			current = idx
			player:SetAttribute("CheckpointIndex", idx)
			notify(player, "Checkpoint: " .. cp.name)
		end
	end

	if withinXZ(pos, Config.EXTRACTION_POSITION, Config.EXTRACTION_RADIUS) then
		if not extracting[player] then
			extracting[player] = true
			completeRun(player)
		end
	else
		extracting[player] = nil
	end
end

-- ===== Remotes =====

-- Buy a starter kit: deduct currency, record ownership. Items are delivered at
-- run start (join + extraction), so the purchase takes effect from the next run.
local function onBuyKit(player, kitId)
	if type(kitId) ~= "string" then
		return
	end
	local kit = kitById(kitId)
	local profile = profiles[player]
	if not kit or not profile then
		return
	end
	if ownsKit(profile, kit.id) then
		return -- already owned: silent no-op (client already shows "Owned")
	end
	local currency = player:GetAttribute("Currency") or 0
	if currency < kit.cost then
		notify(player, "Not enough currency for " .. kit.name)
		return
	end
	player:SetAttribute("Currency", currency - kit.cost)
	table.insert(profile.ownedKits, kit.id)
	updateOwnedKitsAttribute(player)
	notify(player, "Purchased " .. kit.name)
end

-- ===== Join / leave =====

local function onPlayerAdded(player)
	-- Synchronous default so every consumer (scan loop, extraction, BuyKit) sees
	-- a profile immediately; the async load fills real values in when it lands.
	profiles[player] = defaultProfile()
	profileLoaded[player] = false

	player:SetAttribute("Currency", 0)
	player:SetAttribute("CheckpointIndex", 0)
	player:SetAttribute("RunStartTime", os.time())
	player:SetAttribute("OwnedKits", "")
	setupLeaderstats(player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	task.spawn(function()
		local profile, success = fetchProfile(player)
		if not player.Parent then
			return -- left mid-load; nothing to apply
		end
		if success then
			profiles[player] = profile
			profileLoaded[player] = true
		end
		-- Apply on both paths (default profile on failure just re-writes zeros).
		-- This REPLACES the Currency attribute with the loaded value, clobbering
		-- any change made during the (sub-second to a few seconds) load window.
		-- Only reachable today via DebugService /set currency mid-load; a real
		-- award needs a 30min+ run, so it can't land inside the window.
		local applied = profiles[player]
		player:SetAttribute("Currency", applied.currency)
		updateOwnedKitsAttribute(player)
		syncLeaderstats(player)
		grantOwnedKits(player) -- initial run-start kit grant
	end)
end

local function onPlayerRemoving(player)
	saveProfile(player)
	profiles[player] = nil
	profileLoaded[player] = nil
	extracting[player] = nil
end

function ProgressService.Init(depsIn)
	deps = depsIn
	Config = deps.Config

	Players.RespawnTime = RESPAWN_TIME -- respawn feeds back into placeAtCheckpoint

	-- Ground-resolve every spawn point once (the map is baked into the place file
	-- before any script runs, so the raycasts hit). Index 0 = start line.
	spawnCFrames[0] = resolveGround(Config.SPAWN_POSITION)
	for idx, cp in ipairs(Config.CHECKPOINTS) do
		spawnCFrames[idx] = resolveGround(cp.position)
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[ProgressService] GetDataStore failed: " .. tostring(result))
	end

	deps.Remotes.BuyKit.OnServerEvent:Connect(onBuyKit)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		if not profiles[player] then
			onPlayerAdded(player)
			if player.Character then
				task.spawn(onCharacterAdded, player, player.Character)
			end
		end
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- BindToClose gets ~30s. Save every present player IN PARALLEL (one task each)
	-- so the total is bounded by a single save's latency — sequential saves would
	-- blow the budget on a full server, especially with the per-key ~6s write
	-- cooldown queuing behind a recent autosave. Wait on a completion counter up
	-- to BINDTOCLOSE_DEADLINE; saveProfile is pcall'd and fast-skips no store /
	-- unloaded profiles, so a straggler can't hang shutdown past the deadline.
	game:BindToClose(function()
		local present = Players:GetPlayers()
		local remaining = #present
		if remaining == 0 then
			return
		end
		for _, player in ipairs(present) do
			task.spawn(function()
				saveProfile(player)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + BINDTOCLOSE_DEADLINE
		while remaining > 0 and os.clock() < deadline do
			task.wait()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(ZONE_SCAN_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local scanOk, err = pcall(scanPlayer, player)
				if not scanOk then
					warn("[ProgressService] scan error for " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				saveProfile(player)
			end
		end
	end)
end

return ProgressService
