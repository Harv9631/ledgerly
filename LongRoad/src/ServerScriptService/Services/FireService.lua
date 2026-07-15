-- FireService: tree chopping, campfire placement/fueling/cooking, and the
-- warmth/ward proximity queries used by SurvivalService and MonsterService.
--
-- Concurrency: Init is YIELD-FREE — LootService inits after us and Inventory's
-- drop remotes assume LootService state exists, so a yield here would open
-- that race. ProximityPrompt.Triggered and OnServerEvent handlers are likewise
-- yield-free (they run serially on the server scheduler), so two triggers can
-- never interleave mid-handler — double-remove/double-fell races are
-- impossible. IsNearFire/IsFireWarded read only module-scope tables that start
-- empty, so they are safe to call before (or without) Init: they return false.
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local MAINTENANCE_INTERVAL = 5
local DIM_WINDOW = 30              -- last N seconds of fuel: dimmed as a warning
local PLACE_DISTANCE = 4           -- studs in front of HumanoidRootPart
local PLACE_RAY_DEPTH = 20
local MAX_SLOPE_COS = math.cos(math.rad(30)) -- reject surfaces steeper than 30 deg
local FELL_TILT = math.rad(8)      -- initial lean that lets the felled clone topple
local FELL_CLONE_LIFETIME = 4
local RESPAWN_CLEAR_RADIUS_SQ = 8 ^ 2 -- defer tree restore if a player stands this close
local LOG_COLOR = Color3.fromRGB(110, 76, 46)
local LIGHT_COLOR = Color3.fromRGB(255, 150, 50)
local SMOKE_COLOR = Color3.fromRGB(120, 120, 120)
local FULL_BRIGHTNESS, DIM_BRIGHTNESS = 2, 0.8
local FULL_FLAME_SIZE, DIM_FLAME_SIZE = 6, 3

local FireService = {}

local deps
local firesFolder -- Workspace.RuntimeFires: campfires + falling-tree clones
local placeParams -- excludes all characters + RuntimeFires (rebuilt per cast)

-- Module scope (NOT Init): the public queries must work pre-Init.
local activeFires = {}   -- model -> { x, z, pos, fuelUntil, owner, light, flame, dimmed }
local trees = {}         -- model -> { prompt, points, parts = {{part, transparency, canCollide}}, respawnAt? }
local playerFires = {}   -- player -> array of fire models, oldest first
local placeCooldown = {} -- player -> os.clock() of last successful placement
local warmthRadiusSq = 0
local wardRadiusSq = 0

local function notify(player, text)
	deps.Remotes.Notify:FireClient(player, text)
end

local function makePrompt(parent, actionText, objectText, holdDuration, range)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText or ""
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = range
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

-- ===== Tree chopping =====

-- Falling visual: a throwaway physics clone leans 8 deg and topples/sinks for
-- a few seconds. CanCollide false on every part so nobody gets trapped under
-- it; cloned ProximityPrompts are stripped so the corpse isn't choppable.
local function spawnFallingClone(model)
	local clone = model:Clone()
	for _, inst in ipairs(clone:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = false
		elseif inst:IsA("ProximityPrompt") then
			inst:Destroy()
		end
	end
	clone:PivotTo(clone:GetPivot() * CFrame.Angles(FELL_TILT, 0, 0))
	clone.Parent = firesFolder -- keeps it out of placement raycasts
	Debris:AddItem(clone, FELL_CLONE_LIFETIME)
end

local function fellTree(model, tree, player)
	-- Partial fit (or none) is fine: GiveItem notifies "Inventory full" itself
	-- and the tree falls regardless — chopping with a full pack wastes wood.
	deps.Inventory.GiveItem(player, "Wood", deps.Config.TREE_WOOD_YIELD)
	spawnFallingClone(model)
	-- Hide the original until the maintenance loop restores it.
	tree.prompt.Enabled = false
	for _, rec in ipairs(tree.parts) do
		rec.part.Transparency = 1
		rec.part.CanCollide = false
		rec.part.CanQuery = false -- else the invisible trunk still blocks raycasts (melee LOS, arrows)
	end
	tree.points = 0
	tree.respawnAt = os.clock() + deps.Config.TREE_RESPAWN
end

-- A trunk materializing inside a camping player would stick or fling them, so
-- restoration is deferred to a later sweep while anyone stands on the stump.
local function isTreeSpotClear(tree)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local pos = root.Position
			if (pos.X - tree.x) ^ 2 + (pos.Z - tree.z) ^ 2 <= RESPAWN_CLEAR_RADIUS_SQ then
				return false
			end
		end
	end
	return true
end

local function restoreTree(tree)
	tree.respawnAt = nil
	tree.points = 0
	for _, rec in ipairs(tree.parts) do
		rec.part.Transparency = rec.transparency
		rec.part.CanCollide = rec.canCollide
		rec.part.CanQuery = rec.canQuery
	end
	tree.prompt.Enabled = true
end

local function onChopTriggered(model, tree, player)
	if tree.respawnAt then -- prompt is disabled while felled; belt and braces
		return
	end
	local equippedId = deps.Inventory.GetEquipped(player)
	local def = equippedId and deps.ItemDefs[equippedId]
	tree.points += (def and def.chopPower) or 1 -- bare hands / non-axe = 1
	if tree.points >= deps.Config.TREE_CHOPS_BASE then
		fellTree(model, tree, player)
	end
end

local function setupTrees()
	local map = workspace:FindFirstChild("Map")
	local treeFolder = map and map:FindFirstChild("Trees")
	if not treeFolder then
		warn("[FireService] Workspace.Map.Trees missing (unbaked place); chopping disabled")
		return
	end
	for _, model in ipairs(treeFolder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("Choppable") and model.PrimaryPart then
			local pivot = model:GetPivot().Position
			local tree = { points = 0, parts = {}, x = pivot.X, z = pivot.Z }
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(tree.parts, {
						part = part,
						transparency = part.Transparency,
						canCollide = part.CanCollide,
						canQuery = part.CanQuery,
					})
				end
			end
			tree.prompt = makePrompt(model.PrimaryPart, "Chop", "Tree",
				deps.Config.CHOP_HOLD, deps.Config.CHOP_PROMPT_RANGE)
			trees[model] = tree
			tree.prompt.Triggered:Connect(function(player)
				onChopTriggered(model, tree, player)
			end)
		end
	end
end

-- ===== Campfires =====

local function setDimmed(state, dimmed)
	if state.dimmed == dimmed then
		return
	end
	state.dimmed = dimmed
	state.light.Brightness = dimmed and DIM_BRIGHTNESS or FULL_BRIGHTNESS
	state.flame.Size = dimmed and DIM_FLAME_SIZE or FULL_FLAME_SIZE
end

-- Removes the fire everywhere: activeFires, its owner's list, the workspace.
-- Destroy on an already-destroyed model is a no-op, so the Parent==nil sweep
-- path reuses this too.
local function extinguishFire(model)
	local state = activeFires[model]
	if not state then
		return
	end
	activeFires[model] = nil
	local list = playerFires[state.owner]
	if list then
		local i = table.find(list, model)
		if i then
			table.remove(list, i)
		end
	end
	model:Destroy()
end

local function onAddWood(model, player)
	local state = activeFires[model]
	if not state then
		return
	end
	local now = os.clock()
	-- Fully stoked: if the FIRE_MAX_FUEL cap would swallow more than half this
	-- wood's fuel value, refuse WITHOUT consuming it — no silent waste.
	if (now + deps.Config.FIRE_MAX_FUEL) - state.fuelUntil < deps.Config.FIRE_FUEL_PER_WOOD / 2 then
		notify(player, "The fire is fully stoked")
		return
	end
	if not deps.Inventory.RemoveItem(player, "Wood", 1) then
		notify(player, "You need Wood")
		return
	end
	state.fuelUntil = math.min(state.fuelUntil + deps.Config.FIRE_FUEL_PER_WOOD,
		now + deps.Config.FIRE_MAX_FUEL)
	setDimmed(state, state.fuelUntil - now <= DIM_WINDOW) -- feeding restores brightness
	notify(player, ("Fire fed — ~%dm left"):format(math.max(1, math.ceil((state.fuelUntil - now) / 60))))
end

local function onCookMeat(model, player)
	local state = activeFires[model]
	local cookedId = deps.ItemDefs.RawMeat and deps.ItemDefs.RawMeat.cooksInto
	if not state or not cookedId or not deps.ItemDefs[cookedId] then
		return
	end
	if not deps.Inventory.RemoveItem(player, "RawMeat", 1) then
		notify(player, "You need Raw Meat")
		return
	end
	local _, placed = deps.Inventory.GiveItem(player, cookedId, 1)
	if placed == 0 then
		-- Full inventory (GiveItem already notified). Hand the raw meat back;
		-- if even THAT fails, drop it beside the fire rather than eat it.
		local _, refunded = deps.Inventory.GiveItem(player, "RawMeat", 1)
		if refunded == 0 and deps.Loot and deps.Loot.SpawnPickup then
			deps.Loot.SpawnPickup(state.pos + Vector3.new(0, 1, 0), "RawMeat", 1)
		end
		return
	end
	notify(player, ("%s ready"):format(deps.ItemDefs[cookedId].name))
end

local function buildCampfire(position, owner, now)
	local Config = deps.Config
	local model = Instance.new("Model")
	model.Name = "Campfire"
	for i = 0, 2 do -- three crossed logs lying low
		local log = Instance.new("Part")
		log.Name = "Log"
		log.Shape = Enum.PartType.Cylinder
		log.Size = Vector3.new(4, 0.8, 0.8)
		log.Anchored = true
		log.CanCollide = false
		log.Material = Enum.Material.Wood
		log.Color = LOG_COLOR
		log.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0))
			* CFrame.Angles(0, math.rad(60) * i, math.rad(8))
		log.Parent = model
	end
	local core = Instance.new("Part") -- invisible anchor for light/fx/prompts
	core.Name = "Core"
	core.Size = Vector3.new(2, 2, 2)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
	local light = Instance.new("PointLight")
	light.Color = LIGHT_COLOR
	light.Range = Config.FIRE_LIGHT_RANGE
	light.Brightness = FULL_BRIGHTNESS
	light.Parent = core
	local flame = Instance.new("Fire")
	flame.Size = FULL_FLAME_SIZE
	flame.Heat = 10
	flame.Parent = core
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(SMOKE_COLOR)
	smoke.Rate = 8
	smoke.Lifetime = NumberRange.new(1.5, 3)
	smoke.Speed = NumberRange.new(2, 4) -- emits along core's up axis: rising
	smoke.Size = NumberSequence.new(0.5, 2)
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Parent = core
	core.Parent = model
	model.PrimaryPart = core

	activeFires[model] = {
		pos = position, x = position.X, z = position.Z,
		fuelUntil = now + Config.FIRE_BURN_TIME,
		owner = owner, light = light, flame = flame, dimmed = false,
	}

	local addPrompt = makePrompt(core, "Add Wood", "Campfire", 0.5, Config.CHOP_PROMPT_RANGE)
	local cookPrompt = makePrompt(core, "Cook Meat", "Campfire",
		Config.FIRE_COOK_TIME, Config.CHOP_PROMPT_RANGE)
	-- G, not F: F is Interaction.client's eat key — a player holding F here with
	-- RawMeat equipped could EAT it raw (sick risk) instead of cooking it.
	cookPrompt.KeyboardKeyCode = Enum.KeyCode.G -- distinct key so both prompts show
	cookPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	cookPrompt.UIOffset = Vector2.new(0, 64)
	addPrompt.Triggered:Connect(function(player)
		onAddWood(model, player)
	end)
	cookPrompt.Triggered:Connect(function(player)
		onCookMeat(model, player)
	end)
	model.Parent = firesFolder
	return model
end

local function onPlaceFire(player)
	local Config = deps.Config
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	if now - (placeCooldown[player] or -math.huge) < Config.FIRE_PLACE_COOLDOWN then
		return -- spam guard: silent
	end
	if not deps.Inventory.HasItem(player, "Wood", Config.FIRE_WOOD_COST) then
		notify(player, ("You need %d Wood"):format(Config.FIRE_WOOD_COST))
		return
	end
	local origin = root.Position + root.CFrame.LookVector * PLACE_DISTANCE
	-- Exclude EVERY character (LootService's settle pattern), not just the
	-- placer's: hitting another player's head would leave a floating fire.
	local exclude = { firesFolder }
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	placeParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(origin, Vector3.new(0, -PLACE_RAY_DEPTH, 0), placeParams)
	if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < MAX_SLOPE_COS then
		notify(player, "Can't place a fire here")
		return
	end
	if not deps.Inventory.RemoveItem(player, "Wood", Config.FIRE_WOOD_COST) then
		return -- unreachable after HasItem (handlers are serial + yield-free)
	end
	placeCooldown[player] = now
	local model = buildCampfire(hit.Position, player, now)
	local list = playerFires[player]
	if not list then
		list = {}
		playerFires[player] = list
	end
	table.insert(list, model)
	while #list > Config.FIRE_MAX_PER_PLAYER do
		local oldest = list[1]
		extinguishFire(oldest) -- oldest; extinguishFire shifts the list itself
		if list[1] == oldest then
			table.remove(list, 1) -- insurance: no state entry; never spin forever
		end
	end
	notify(player, "Campfire placed")
end

-- ===== Shared maintenance loop =====

local function sweep(now)
	for model, state in pairs(activeFires) do
		if not model.Parent or now >= state.fuelUntil then
			extinguishFire(model)
		else
			setDimmed(state, state.fuelUntil - now <= DIM_WINDOW)
		end
	end
	for model, tree in pairs(trees) do
		if not model.Parent then
			trees[model] = nil
		elseif tree.respawnAt and now >= tree.respawnAt and isTreeSpotClear(tree) then
			restoreTree(tree) -- occupied stump: retried next sweep
		end
	end
end

-- ===== Public API (safe pre-Init: tables start empty, so both return false) =====

-- Squared X/Z distance, matching SurvivalService's zone convention (fire sits
-- at ground level, the player's root a few studs above). Allocation-free:
-- MonsterService polls IsFireWarded every 0.25s per monster.
function FireService.IsNearFire(position)
	for _, state in pairs(activeFires) do
		if (position.X - state.x) ^ 2 + (position.Z - state.z) ^ 2 <= warmthRadiusSq then
			return true
		end
	end
	return false
end

function FireService.IsFireWarded(position)
	for _, state in pairs(activeFires) do
		if (position.X - state.x) ^ 2 + (position.Z - state.z) ^ 2 <= wardRadiusSq then
			return true
		end
	end
	return false
end

function FireService.GetActiveFireCount()
	local n = 0
	for _ in pairs(activeFires) do
		n += 1
	end
	return n
end

function FireService.Init(depsIn)
	deps = depsIn
	warmthRadiusSq = deps.Config.FIRE_WARMTH_RADIUS ^ 2
	wardRadiusSq = deps.Config.FIRE_WARD_RADIUS ^ 2

	firesFolder = workspace:FindFirstChild("RuntimeFires") or Instance.new("Folder")
	firesFolder.Name = "RuntimeFires"
	firesFolder.Parent = workspace

	placeParams = RaycastParams.new()
	placeParams.FilterType = Enum.RaycastFilterType.Exclude

	setupTrees()

	deps.Remotes.PlaceFire.OnServerEvent:Connect(onPlaceFire)

	Players.PlayerRemoving:Connect(function(player)
		playerFires[player] = nil -- their fires burn on; extinguish tolerates no list
		placeCooldown[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(MAINTENANCE_INTERVAL)
			local ok, err = pcall(sweep, os.clock())
			if not ok then
				warn("[FireService] sweep error: " .. tostring(err))
			end
		end
	end)
end

return FireService
