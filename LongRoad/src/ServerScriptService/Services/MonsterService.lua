-- MonsterService: spawns and drives three undead types (Shambler, Stalker,
-- Brute) with a simple Idle/Chase/Attack state machine. No PathfindingService in
-- v1: terrain is walkable by design, so chase is straight-line Humanoid:MoveTo.
--
-- Concurrency: one 10s spawner loop and one 0.25s AI loop drive everything — no
-- thread-per-monster. Neither loop yields mid-iteration, and Humanoid.Died only
-- fires at a yield point, so the `monsters` table is never mutated mid-traversal
-- (removing the current key during pairs() is legal in Luau). All rigs live under
-- workspace.RuntimeMonsters (other systems' raycasts exclude that exact name).
--
-- Damage attribution: a monster deals its own damage. Before a lethal blow it
-- sets the victim's LastDeathCause="Monster" (SurvivalService's convention) and
-- calls Combat.RegisterDamage(char, nil) so a monster kill overwrites any stale
-- player attribution rather than wrongly branding a passer-by hostile.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MONSTER_TAG = "Monster"
local SPAWN_INTERVAL = 10          -- seconds between spawner passes
local AI_INTERVAL = 0.25           -- seconds between AI ticks
local ATTACK_RANGE = 4
local ATTACK_RANGE_SQ = ATTACK_RANGE ^ 2
local ATTACK_COOLDOWN = 1          -- seconds between a monster's hits
local WANDER_RADIUS = 40           -- idle waypoint distance
local SPAWN_MIN_PLAYER_DIST = 80   -- spawn markers must be this far from every player
local BRUTE_RESPAWN = 600          -- 10 min after a Brute dies its post refills
local DESPAWN_WALK_TIME = 3        -- nightOnly types walk off this long, then vanish
local TAU = math.pi * 2

local TYPE_COLORS = {
	Shambler = Color3.fromRGB(90, 130, 70),  -- sickly green
	Stalker  = Color3.fromRGB(20, 20, 24),   -- near-black (red eyes added)
	Brute    = Color3.fromRGB(110, 76, 46),  -- brown
}
local TYPE_SCALE = { Shambler = 1, Stalker = 1, Brute = 2 }

local MonsterService = {}

local deps
local rng
local runtimeFolder
local hasSpawns = false
local spawnMarkersByZone = {}      -- zoneName -> { marker parts }
local brutePosts = {}              -- { { position, model, deadUntil } }
local templateCache = {}           -- typeName -> Model template or false
local monsters = {}                -- rig model -> monster state

-- ===== Helpers =====

local function isNight()
	if deps.DayNight and deps.DayNight.IsNight then
		return deps.DayNight.IsNight()
	end
	return workspace:GetAttribute("IsNight") == true
end

-- No live player character within minDist of pos (X/Y/Z).
local function farFromPlayers(pos, minDist)
	local minSq = minDist * minDist
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = root.Position - pos
			if d.X ^ 2 + d.Y ^ 2 + d.Z ^ 2 < minSq then
				return false
			end
		end
	end
	return true
end

local function targetInfo(player)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return char, humanoid, root
	end
	return nil
end

-- Nearest live player within maxRange of pos. avoidWarded skips players standing
-- in a fire ward (fearsFire acquisition). Returns player, char, humanoid, root.
local function nearestTarget(pos, maxRange, avoidWarded)
	local bestSq = maxRange * maxRange
	local best, bestChar, bestHum, bestRoot
	for _, player in ipairs(Players:GetPlayers()) do
		local char, humanoid, root = targetInfo(player)
		if char then
			local tp = root.Position
			if not (avoidWarded and deps.Fire and deps.Fire.IsFireWarded(tp)) then
				local sq = (tp.X - pos.X) ^ 2 + (tp.Y - pos.Y) ^ 2 + (tp.Z - pos.Z) ^ 2
				if sq <= bestSq then
					bestSq = sq
					best, bestChar, bestHum, bestRoot = player, char, humanoid, root
				end
			end
		end
	end
	return best, bestChar, bestHum, bestRoot
end

local function isWarded(pos)
	return deps.Fire ~= nil and deps.Fire.IsFireWarded(pos)
end

-- ===== Rig construction =====

local function makeWeld(a, b)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = a
	weld.Part1 = b
	weld.Parent = a
end

-- R6-less code rig: colliding HumanoidRootPart (the physics body), a welded torso
-- block and head ball, plus a Humanoid. Built at the origin; the caller pivots it
-- onto the ground. Returns model, humanoid, root.
local function buildRig(typeName)
	local scale = TYPE_SCALE[typeName] or 1
	local color = TYPE_COLORS[typeName] or Color3.fromRGB(120, 120, 120)
	local torsoSize = Vector3.new(2, 2, 1) * scale
	local headSize = Vector3.new(1.2, 1.2, 1.2) * scale

	local model = Instance.new("Model")
	model.Name = typeName

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = torsoSize
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CFrame.new(0, 0, 0)
	root.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = torsoSize
	torso.Color = color
	torso.Material = Enum.Material.SmoothPlastic
	torso.CanCollide = false
	torso.CFrame = CFrame.new(0, 0, 0)
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = headSize
	head.Color = color
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.CFrame = CFrame.new(0, torsoSize.Y / 2 + headSize.Y / 2, 0)
	head.Parent = model

	makeWeld(root, torso)
	makeWeld(torso, head)

	if typeName == "Stalker" then
		for _, side in ipairs({ -1, 1 }) do
			local eye = Instance.new("Part")
			eye.Name = "Eye"
			eye.Shape = Enum.PartType.Ball
			eye.Size = Vector3.new(0.25, 0.25, 0.25) * scale
			eye.Color = Color3.fromRGB(255, 25, 25)
			eye.Material = Enum.Material.Neon
			eye.CanCollide = false
			eye.CFrame = head.CFrame * CFrame.new(0.28 * side * scale, 0.1 * scale, -headSize.Z / 2)
			eye.Parent = model
			makeWeld(head, eye)
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HipHeight = 0
	humanoid.Parent = model

	model.PrimaryPart = root
	return model, humanoid, root
end

-- Optional real-rig swap (same idea as ModelPlacer): a Model with a Humanoid under
-- ReplicatedStorage.Assets.Monsters.<Type> is cloned instead of the code rig.
local function getTemplate(typeName)
	if templateCache[typeName] ~= nil then
		return templateCache[typeName] or nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Monsters")
	local node = folder and folder:FindFirstChild(typeName)
	local template = false
	if node and node:IsA("Model") and node:FindFirstChildOfClass("Humanoid")
		and node:FindFirstChild("HumanoidRootPart") then
		template = node
	end
	templateCache[typeName] = template
	return template or nil
end

-- ===== Loot & teardown =====

local function dropLootFor(m, pos)
	if not deps.Loot or not deps.Loot.SpawnPickup then
		return
	end
	if m.isBrute then
		if rng:NextNumber() < 0.5 then
			deps.Loot.SpawnPickup(pos, "Crossbow", 1)
		else
			deps.Loot.SpawnPickup(pos, "Arrow", 5)
		end
		deps.Loot.SpawnPickup(pos, "RawMeat", 2)
	elseif rng:NextNumber() < deps.Config.MONSTER_MEAT_CHANCE then
		deps.Loot.SpawnPickup(pos, "RawMeat", 1)
	end
end

-- Destroy the rig BEFORE dropping loot so LootService's settle ray (which does not
-- exclude RuntimeMonsters) can't land the pickup on the corpse.
local function destroyMonster(model, m, dropLoot)
	if m._dead then
		return
	end
	m._dead = true
	monsters[model] = nil
	if m.diedConn then
		m.diedConn:Disconnect()
		m.diedConn = nil
	end
	if m.brutePost then
		m.brutePost.model = nil
		m.brutePost.deadUntil = os.clock() + BRUTE_RESPAWN
	end
	local pos = m.root.Position
	model:Destroy()
	if dropLoot then
		dropLootFor(m, pos)
	end
end

-- ===== Spawning =====

local function spawnMonster(typeName, position, zoneName, brutePost)
	local def = deps.Config.MONSTERS[typeName]
	if not def then
		return nil
	end
	local model, humanoid, root
	local template = getTemplate(typeName)
	if template then
		model = template:Clone()
		humanoid = model:FindFirstChildOfClass("Humanoid")
		root = model:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then
			model:Destroy()
			model, humanoid, root = buildRig(typeName)
		end
	else
		model, humanoid, root = buildRig(typeName)
	end

	humanoid.MaxHealth = def.health
	humanoid.Health = def.health
	humanoid.WalkSpeed = def.speed
	humanoid.BreakJointsOnDeath = false -- we own teardown; no ragdoll in v1
	model:SetAttribute("MonsterType", typeName)
	CollectionService:AddTag(model, MONSTER_TAG)

	-- Sit the rig's bounding-box bottom just above the ground marker (works for
	-- both the code rig and a cloned real rig, whose pivot may be centered).
	model:PivotTo(CFrame.new(position))
	local bb, size = model:GetBoundingBox()
	local lift = (position.Y + 0.5) - (bb.Position.Y - size.Y / 2)
	model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	model.Parent = runtimeFolder
	pcall(function()
		root:SetNetworkOwner(nil) -- server simulates monsters
	end)

	local m = {
		model = model, humanoid = humanoid, root = root, def = def,
		typeName = typeName, zone = zoneName,
		aggroRange = def.aggroRange,
		breakRangeSq = (def.aggroRange * 1.5) ^ 2,
		fearsFire = def.fearsFire,
		nightOnly = def.nightOnly,
		isBrute = typeName == "Brute",
		brutePost = brutePost,
		lastAttack = -math.huge,
	}
	monsters[model] = m
	m.diedConn = humanoid.Died:Connect(function()
		destroyMonster(model, m, true)
	end)
	return model
end

local function pickType(zoneName, night)
	if zoneName == "Suburbs" or zoneName == "City" then
		return "Shambler"
	end
	-- Forest and Highlands: Stalkers stalk at night, Shamblers shuffle by day.
	return night and "Stalker" or "Shambler"
end

local function countZone(zoneName)
	local n = 0
	for _, m in pairs(monsters) do
		if m.zone == zoneName and not m.isBrute then
			n += 1
		end
	end
	return n
end

local function pickSpawnMarker(markers)
	local candidates = {}
	for _, marker in ipairs(markers) do
		if marker.Parent and farFromPlayers(marker.Position, SPAWN_MIN_PLAYER_DIST) then
			table.insert(candidates, marker)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

-- Dawn: nightOnly monsters walk away from the nearest player, then vanish.
local function despawnNightMonsters()
	for _, m in pairs(monsters) do
		if m.nightOnly and not m.despawnAt then
			local pos = m.root.Position
			local _, _, _, nearestRoot = nearestTarget(pos, math.huge, false)
			local awayDir = m.root.CFrame.LookVector
			if nearestRoot then
				local playerPos = nearestRoot.Position
				local flat = Vector3.new(pos.X - playerPos.X, 0, pos.Z - playerPos.Z)
				if flat.Magnitude > 1e-3 then
					awayDir = flat.Unit
				end
			end
			m.humanoid:MoveTo(pos + awayDir * 40)
			m.target = nil
			m.despawnAt = os.clock() + DESPAWN_WALK_TIME
		end
	end
end

local function spawnTick()
	if not hasSpawns then
		return
	end
	local night = isNight()
	if not night then
		despawnNightMonsters()
	end

	local now = os.clock()
	for _, post in ipairs(brutePosts) do
		if not post.model and (not post.deadUntil or now >= post.deadUntil)
			and farFromPlayers(post.position, SPAWN_MIN_PLAYER_DIST) then
			post.model = spawnMonster("Brute", post.position, "City", post)
			post.deadUntil = nil
		end
	end

	for _, zone in ipairs(deps.Config.ZONES) do
		local markers = spawnMarkersByZone[zone.name]
		if markers and #markers > 0 then
			local mult = night and deps.Config.NIGHT_SPAWN_MULT or 1
			local cap = (deps.Config.MONSTER_CAPS[zone.name] or 0) * mult
			if countZone(zone.name) < cap then
				local marker = pickSpawnMarker(markers)
				if marker then
					spawnMonster(pickType(zone.name, night), marker.Position, zone.name, nil)
				end
			end
		end
	end
end

-- ===== AI =====

local function attack(m, player, char, humanoid, now)
	if now - m.lastAttack < ATTACK_COOLDOWN then
		return
	end
	m.lastAttack = now
	local dmg = m.def.damage
	if humanoid.Health <= dmg then
		player:SetAttribute("LastDeathCause", "Monster")
	end
	if deps.Combat and deps.Combat.RegisterDamage then
		deps.Combat.RegisterDamage(char, nil)
	end
	humanoid:TakeDamage(dmg)
end

-- Idle/pace wander: a fresh random waypoint on a per-monster jitter timer.
local function wander(m, now, pos, radius, minDelay, maxDelay)
	if m.nextWander and now < m.nextWander then
		return
	end
	local ang = rng:NextNumber(0, TAU)
	local dist = rng:NextNumber(radius * 0.2, radius)
	m.humanoid:MoveTo(pos + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist))
	m.nextWander = now + rng:NextNumber(minDelay, maxDelay)
end

local function stepMonster(m, now)
	local humanoid, root = m.humanoid, m.root
	if humanoid.Health <= 0 or not root.Parent then
		return -- Died handler owns teardown
	end
	local pos = root.Position

	if m.despawnAt then
		if now >= m.despawnAt then
			destroyMonster(m.model, m, false)
		end
		return
	end

	-- Maintain an existing chase (hysteresis: acquire at aggroRange, drop at 1.5x).
	if m.target then
		local char, tHum, tRoot = targetInfo(m.target)
		if not char then
			m.target = nil
		else
			local tp = tRoot.Position
			local sq = (tp.X - pos.X) ^ 2 + (tp.Y - pos.Y) ^ 2 + (tp.Z - pos.Z) ^ 2
			if sq > m.breakRangeSq or (m.fearsFire and isWarded(tp)) then
				m.target = nil -- lost them / they reached fire (fearing types flee)
			elseif not m.fearsFire and isWarded(pos) then
				wander(m, now, pos, 6, 1, 2.5) -- at the ward edge: pace, don't advance
				return
			else
				humanoid:MoveTo(tp)
				if sq <= ATTACK_RANGE_SQ then
					attack(m, m.target, char, tHum, now)
				end
				return
			end
		end
	end

	-- No target: try to acquire, else wander.
	local newTarget, _, _, tRoot = nearestTarget(pos, m.aggroRange, m.fearsFire)
	if newTarget then
		m.target = newTarget
		m.nextWander = nil
		humanoid:MoveTo(tRoot.Position)
	else
		wander(m, now, pos, WANDER_RADIUS, 3, 6)
	end
end

-- ===== Init =====

local function cacheMarkers()
	local folder = workspace:FindFirstChild("Markers")
	if not folder then
		warn("[MonsterService] Workspace.Markers missing (unbaked place); spawning disabled")
		return
	end
	local cityBand
	for _, zone in ipairs(deps.Config.ZONES) do
		spawnMarkersByZone[zone.name] = {}
		if zone.name == "City" then
			cityBand = zone
		end
	end
	local cityLoot = {}
	for _, marker in ipairs(folder:GetChildren()) do
		if marker.Name == "Marker_MonsterSpawn" then
			local zone = marker:GetAttribute("Zone")
			if zone and spawnMarkersByZone[zone] then
				table.insert(spawnMarkersByZone[zone], marker)
			end
		elseif marker.Name == "Marker_Loot" and cityBand then
			local z = marker.Position.Z
			if z >= cityBand.zStart and z <= cityBand.zEnd then
				table.insert(cityLoot, marker)
			end
		end
	end
	-- Three highest-tier city loot clusters become fixed Brute posts.
	table.sort(cityLoot, function(a, b)
		return (a:GetAttribute("LootTier") or 0) > (b:GetAttribute("LootTier") or 0)
	end)
	for i = 1, math.min(3, #cityLoot) do
		table.insert(brutePosts, { position = cityLoot[i].Position, model = nil, deadUntil = nil })
	end

	local total = #brutePosts
	for _, list in pairs(spawnMarkersByZone) do
		total += #list
	end
	hasSpawns = total > 0
	if not hasSpawns then
		warn("[MonsterService] no Marker_MonsterSpawn markers found; spawning disabled")
	end
end

function MonsterService.Init(depsIn)
	deps = depsIn
	rng = Random.new()

	runtimeFolder = workspace:FindFirstChild("RuntimeMonsters") or Instance.new("Folder")
	runtimeFolder.Name = "RuntimeMonsters"
	runtimeFolder.Parent = workspace

	cacheMarkers()

	Players.PlayerRemoving:Connect(function(player)
		for _, m in pairs(monsters) do
			if m.target == player then
				m.target = nil
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SPAWN_INTERVAL)
			local ok, err = pcall(spawnTick)
			if not ok then
				warn("[MonsterService] spawn error: " .. tostring(err))
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AI_INTERVAL)
			local now = os.clock()
			for _, m in pairs(monsters) do
				local ok, err = pcall(stepMonster, m, now)
				if not ok then
					warn("[MonsterService] AI error: " .. tostring(err))
				end
			end
		end
	end)
end

return MonsterService
