-- SurvivalService: hunger/warmth drain, wet/sick timers, toxic zones, sprint,
-- and the Eat/UseMedkit consumption API called by InventoryService's handlers.
--
-- Stats live as player attributes (Hunger, Warmth, Wet, Sick, Sprinting) so
-- they replicate to the owning client for HUD display with no extra remotes.
local Players = game:GetService("Players")

local TOXIC_DPS = 4      -- damage per second inside a toxic zone
local WET_DRAIN_MULT = 2 -- warmth drains doubled while wet

local SurvivalService = {}

local deps
local state = {} -- player -> { wetExpiry, sickExpiry, inToxic }
local toxicZones = {} -- { {x, z, radiusSq} }, cached once (markers are static)
local rng = Random.new()

local function notify(player, text)
	deps.Remotes.Notify:FireClient(player, text)
end

local function cacheToxicZones()
	local folder = workspace:FindFirstChild("Markers")
	if not folder then
		warn("[SurvivalService] Workspace.Markers missing (unbaked place); toxic zones disabled")
		return
	end
	for _, marker in ipairs(folder:GetChildren()) do
		local radius = marker:GetAttribute("Radius")
		if marker.Name == "Marker_ToxicZone" and radius then
			table.insert(toxicZones, { x = marker.Position.X, z = marker.Position.Z, radiusSq = radius ^ 2 })
		end
	end
end

-- Zone checks compare X/Z only: marker/checkpoint Y is ground level, the
-- player's root sits a few studs above it.
local function isInToxicZone(pos)
	for _, zone in ipairs(toxicZones) do
		if (pos.X - zone.x) ^ 2 + (pos.Z - zone.z) ^ 2 <= zone.radiusSq then
			return true
		end
	end
	return false
end

local function isNearCheckpoint(pos)
	local Config = deps.Config
	for _, cp in ipairs(Config.CHECKPOINTS) do
		if (pos.X - cp.position.X) ^ 2 + (pos.Z - cp.position.Z) ^ 2 <= Config.CHECKPOINT_SHELTER_RADIUS ^ 2 then
			return true
		end
	end
	return false
end

-- Tags the pending death so ProgressService (Task 14) can report the cause.
local function applyDamage(player, humanoid, amount, cause)
	if humanoid.Health <= amount then
		player:SetAttribute("LastDeathCause", cause)
	end
	humanoid:TakeDamage(amount)
end

local function getLiveHumanoid(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return (humanoid and humanoid.Health > 0) and humanoid or nil
end

local function resetStats(player)
	local Config = deps.Config
	player:SetAttribute("Hunger", Config.STAT_MAX)
	player:SetAttribute("Warmth", Config.STAT_MAX)
	player:SetAttribute("Wet", false)
	player:SetAttribute("Sick", false)
	player:SetAttribute("Sprinting", false)
end

local function tickPlayer(player, now)
	local s = state[player]
	if not s then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local Config = deps.Config
	local dt = Config.SURVIVAL_TICK
	local rootPos = root.Position

	-- Expire wet/sick timers
	if player:GetAttribute("Wet") and now >= s.wetExpiry then
		player:SetAttribute("Wet", false)
	end
	if player:GetAttribute("Sick") and now >= s.sickExpiry then
		player:SetAttribute("Sick", false)
	end

	-- Hunger drain (sprint multiplier only while actually moving)
	local hungerRate = Config.HUNGER_DRAIN
	if player:GetAttribute("Sprinting") and humanoid.MoveDirection.Magnitude > 0.1 then
		hungerRate *= Config.HUNGER_SPRINT_MULT
	end
	if player:GetAttribute("Sick") then
		hungerRate *= Config.SICK_HUNGER_MULT
	end
	local hunger = math.max(0, player:GetAttribute("Hunger") - hungerRate * dt)
	player:SetAttribute("Hunger", hunger)

	-- Warmth: regen sources (fire beats shelter) are mutually exclusive with drain
	local warmth = player:GetAttribute("Warmth")
	if deps.Fire and deps.Fire.IsNearFire and deps.Fire.IsNearFire(rootPos) then
		warmth += Config.FIRE_WARMTH_REGEN * dt
	elseif isNearCheckpoint(rootPos) then
		warmth += Config.SHELTER_WARMTH_REGEN * dt
	else
		local rate = deps.DayNight.IsNight() and Config.WARMTH_DRAIN_NIGHT or Config.WARMTH_DRAIN_DAY
		-- Simplification: no roof check — rain applies to everyone outdoors or not.
		if deps.DayNight.IsRaining() then
			rate *= Config.WARMTH_RAIN_MULT
		end
		if rootPos.Z >= Config.MOUNTAIN_Z[1] and rootPos.Z <= Config.MOUNTAIN_Z[2] then
			rate += Config.WARMTH_MOUNTAIN_EXTRA
		end
		if player:GetAttribute("Wet") then
			rate *= WET_DRAIN_MULT
		end
		warmth -= rate * dt
	end
	warmth = math.clamp(warmth, 0, Config.STAT_MAX)
	player:SetAttribute("Warmth", warmth)

	-- Starvation / freezing damage
	if hunger <= 0 then
		applyDamage(player, humanoid, Config.STARVE_DPS * dt, "Starvation")
	end
	if warmth <= 0 and humanoid.Health > 0 then
		applyDamage(player, humanoid, Config.FREEZE_DPS * dt, "Freezing")
	end

	-- Toxic zones: notify once per contiguous entry
	local inToxic = isInToxicZone(rootPos)
	if inToxic then
		if not s.inToxic then
			notify(player, "Toxic air! Get out!")
		end
		if humanoid.Health > 0 then
			applyDamage(player, humanoid, TOXIC_DPS * dt, "Toxic")
		end
	end
	s.inToxic = inToxic

	-- Movement: cold overrides sprint; sprint requires hunger above the low mark.
	-- Only assign on change to avoid replicating WalkSpeed every tick.
	local targetSpeed
	if warmth < Config.LOW_STAT then
		targetSpeed = Config.COLD_WALK_SPEED
	elseif player:GetAttribute("Sprinting") and hunger > Config.LOW_STAT then
		targetSpeed = Config.SPRINT_SPEED
	else
		targetSpeed = Config.WALK_SPEED
	end
	if humanoid.WalkSpeed ~= targetSpeed then
		humanoid.WalkSpeed = targetSpeed
	end
end

local function onCharacterAdded(player, character)
	local s = state[player]
	if not s then
		return
	end
	-- Death = fresh stats: respawn always starts at full
	resetStats(player)
	s.wetExpiry = 0
	s.sickExpiry = 0
	s.inToxic = false
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = deps.Config.WALK_SPEED
	humanoid.StateChanged:Connect(function(_, newState)
		if newState ~= Enum.HumanoidStateType.Swimming then
			return
		end
		if not player:GetAttribute("Wet") then
			player:SetAttribute("Warmth", math.max(0, player:GetAttribute("Warmth") - deps.Config.SWIM_WARMTH_HIT))
			player:SetAttribute("Wet", true)
		end
		s.wetExpiry = os.clock() + deps.Config.WET_DURATION -- re-entering refreshes the timer
	end)
end

local function watchPlayer(player)
	state[player] = { wetExpiry = 0, sickExpiry = 0, inToxic = false }
	resetStats(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

-- ===== API (InventoryService pre-validates item type, we re-validate here) =====

function SurvivalService.Eat(player, slotIndex)
	local slot = deps.Inventory.GetSlot(player, "hotbar", slotIndex)
	local def = slot and deps.ItemDefs[slot.id]
	local s = state[player]
	if not s or not def or def.type ~= "Food" or not getLiveHumanoid(player) then
		return false
	end
	if not deps.Inventory.RemoveItem(player, slot.id, 1) then
		return false
	end
	local Config = deps.Config
	player:SetAttribute("Hunger", math.min(Config.STAT_MAX, player:GetAttribute("Hunger") + def.hunger))
	if def.sickChance and def.sickChance > 0 and rng:NextNumber() < def.sickChance then
		player:SetAttribute("Sick", true)
		s.sickExpiry = os.clock() + Config.SICK_DURATION
		notify(player, "You feel sick...")
	end
	return true
end

function SurvivalService.UseMedkit(player, slotIndex)
	local slot = deps.Inventory.GetSlot(player, "hotbar", slotIndex)
	local def = slot and deps.ItemDefs[slot.id]
	local humanoid = getLiveHumanoid(player)
	if not state[player] or not def or def.type ~= "Medkit" or not humanoid then
		return false
	end
	if not deps.Inventory.RemoveItem(player, slot.id, 1) then
		return false
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + def.heal)
	return true
end

function SurvivalService.GetStats(player)
	return {
		hunger = player:GetAttribute("Hunger"),
		warmth = player:GetAttribute("Warmth"),
		wet = player:GetAttribute("Wet"),
		sick = player:GetAttribute("Sick"),
	}
end

-- Clamped setter for DebugService (Task 12)
function SurvivalService.SetStat(player, stat, value)
	if (stat == "Hunger" or stat == "Warmth") and type(value) == "number" and value == value then
		player:SetAttribute(stat, math.clamp(value, 0, deps.Config.STAT_MAX))
	end
end

function SurvivalService.Init(depsIn)
	deps = depsIn
	cacheToxicZones()

	deps.Remotes.SetSprinting.OnServerEvent:Connect(function(player, on)
		if type(on) == "boolean" then
			player:SetAttribute("Sprinting", on)
		end
	end)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		if not state[player] then
			watchPlayer(player)
			if player.Character then
				task.spawn(onCharacterAdded, player, player.Character)
			end
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(deps.Config.SURVIVAL_TICK)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(tickPlayer, player, now)
				if not ok then
					warn("[SurvivalService] tick error for " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return SurvivalService
