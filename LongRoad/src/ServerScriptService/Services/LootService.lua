-- LootService: forage nodes (bushes/branches), tiered loot crates, ground
-- pickups, and death bags.
--
-- Concurrency: ProximityPrompt.Triggered handlers run serially on the server
-- scheduler and every handler here is yield-free, so two triggers can never
-- interleave mid-handler — double-loot races are impossible. All per-node/
-- crate/pickup state lives in local tables keyed by instance; one shared 5s
-- maintenance loop sweeps expiries (respawn/refill/despawn) and drops entries
-- whose instances were destroyed externally (Parent == nil).
local Players = game:GetService("Players")

local MAINTENANCE_INTERVAL = 5
local SETTLE_RAY_LENGTH = 100

-- Depleted-bush visuals: hide these decoration parts (ModelPlacer placeholder
-- names) so a picked-clean bush reads as such. Wood (branches) hides ALL parts
-- instead (the branch was taken). Real user models without these part names
-- fall back gracefully to prompt-only deactivation.
local HIDE_PART_NAMES = { Berries = "Berry", Mushroom = "Stem" }

local CRATE_COLORS = {
	[1] = Color3.fromRGB(196, 164, 120), -- tan
	[2] = Color3.fromRGB(121, 92, 60),   -- darker wood
	[3] = Color3.fromRGB(48, 44, 42),    -- near-black
}
local PICKUP_COLOR = Color3.fromRGB(160, 130, 90)
local BACKPACK_COLOR = Color3.fromRGB(110, 76, 46)
local CRATE_EMPTY_TRANSPARENCY = 0.6
local TAU = math.pi * 2

local LootService = {}

local deps
local rng
local runtimeFolder, pickupsFolder, cratesFolder
local settleParams -- excludes RuntimeLoot + characters (rebuilt per settle)

local nodes = {}  -- root instance -> { prompt, itemId, hideParts?, expiry? }
local crates = {} -- crate part   -> { prompt, tier, expiry? }
local drops = {}  -- part -> { kind = "pickup"/"bag", expiry, ... }

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

local function makeBillboard(parent, text)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 120, 0, 28)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return label
end

-- Drop position may be mid-air (dropped while jumping): ray straight down
-- against everything except runtime loot and player characters (a death bag
-- settling on a corpse would float once the corpse despawns); miss -> keep
-- the given position.
local function settleOnGround(position, halfHeight)
	local exclude = { runtimeFolder }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	settleParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(position, Vector3.new(0, -SETTLE_RAY_LENGTH, 0), settleParams)
	if hit then
		return Vector3.new(position.X, hit.Position.Y + halfHeight, position.Z)
	end
	return position
end

-- Weighted roll: weights are normalized by dividing the roll across the sum,
-- so any positive weights work (the shipped tables just happen to sum to 100).
local function rollLoot(tier)
	local tbl = deps.Config.LOOT_TABLES[math.clamp(tier, 1, 3)]
	local total = 0
	for _, entry in ipairs(tbl) do
		total += entry[3]
	end
	local roll = rng:NextNumber() * total
	for _, entry in ipairs(tbl) do
		roll -= entry[3]
		if roll <= 0 then
			return entry[1], entry[2]
		end
	end
	local last = tbl[#tbl] -- float-edge safety; unreachable in practice
	return last[1], last[2]
end

-- ===== Forage nodes =====

local function onForageTriggered(node, player)
	if node.expiry then -- prompt is disabled while depleted; belt and braces
		return
	end
	local _, placed = deps.Inventory.GiveItem(player, node.itemId, 1)
	if placed == 0 then
		return -- GiveItem already notified "Inventory full"; node stays active
	end
	node.prompt.Enabled = false
	node.expiry = os.clock() + deps.Config.FORAGE_RESPAWN
	-- Branches vanish entirely; bushes hide just their berries/stems (the bush
	-- body stays visible, reading as picked clean).
	if node.hideParts then
		for _, rec in ipairs(node.hideParts) do
			rec.part.Transparency = 1
			rec.part.CanCollide = false
		end
	end
end

local function reactivateNode(node)
	node.expiry = nil
	node.prompt.Enabled = true
	if node.hideParts then
		for _, rec in ipairs(node.hideParts) do
			rec.part.Transparency = rec.transparency
			rec.part.CanCollide = rec.canCollide
		end
	end
end

local function setupForageNodes()
	local map = workspace:FindFirstChild("Map")
	if not map then
		warn("[LootService] Workspace.Map missing (unbaked place); forage nodes disabled")
		return
	end
	for _, inst in ipairs(map:GetDescendants()) do
		local itemId = inst:GetAttribute("Forageable")
		local def = itemId and deps.ItemDefs[itemId]
		if def then
			local holder
			if inst:IsA("BasePart") then
				holder = inst
			elseif inst:IsA("Model") then
				holder = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
			end
			if holder then
				local node = { itemId = itemId }
				node.prompt = makePrompt(holder, "Forage", def.name,
					deps.Config.FORAGE_HOLD, deps.Config.FORAGE_PROMPT_RANGE)
				-- Record originals for hide/restore: branches hide every part,
				-- bushes hide only their named decoration parts (if any exist).
				local hideName = HIDE_PART_NAMES[itemId]
				local hideParts = {}
				local parts = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
				for _, part in ipairs(parts) do
					if part:IsA("BasePart") and (itemId == "Wood" or part.Name == hideName) then
						table.insert(hideParts, {
							part = part,
							transparency = part.Transparency,
							canCollide = part.CanCollide,
						})
					end
				end
				if #hideParts > 0 then
					node.hideParts = hideParts
				end
				nodes[inst] = node
				node.prompt.Triggered:Connect(function(player)
					onForageTriggered(node, player)
				end)
			end
		end
	end
end

-- ===== Loot crates =====

local function onCrateTriggered(crate, state, player)
	if state.expiry then -- searched and waiting on refill
		return
	end
	local itemId, count = rollLoot(state.tier)
	local _, placed = deps.Inventory.GiveItem(player, itemId, count)
	if placed == 0 then
		return -- looter full: crate stays STOCKED, GiveItem already notified
	end
	notify(player, ("Found: %dx %s"):format(placed, deps.ItemDefs[itemId].name))
	state.prompt.Enabled = false
	crate.Transparency = CRATE_EMPTY_TRANSPARENCY
	state.expiry = os.clock() + deps.Config.CRATE_REFILL
end

local function setupCrates()
	local markers = workspace:FindFirstChild("Markers")
	if not markers then
		warn("[LootService] Workspace.Markers missing (unbaked place); loot crates disabled")
		return
	end
	for _, marker in ipairs(markers:GetChildren()) do
		if marker.Name == "Marker_Loot" then
			local tier = math.clamp(math.floor(tonumber(marker:GetAttribute("LootTier")) or 1), 1, 3)
			local crate = Instance.new("Part")
			crate.Name = "LootCrate"
			crate.Size = Vector3.new(3, 3, 3)
			crate.CFrame = CFrame.new(marker.Position + Vector3.new(0, 1.5, 0))
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
			crate.Anchored = true
			crate.Material = Enum.Material.WoodPlanks
			crate.Color = CRATE_COLORS[tier]
			local state = { tier = tier }
			state.prompt = makePrompt(crate, "Search", "Supply Crate",
				deps.Config.SEARCH_HOLD, deps.Config.FORAGE_PROMPT_RANGE)
			crates[crate] = state
			state.prompt.Triggered:Connect(function(player)
				onCrateTriggered(crate, state, player)
			end)
			crate.Parent = cratesFolder
		end
	end
end

-- ===== Pickups + death bags (public API) =====

local function destroyDrop(part)
	drops[part] = nil
	part:Destroy()
end

function LootService.SpawnPickup(position, itemId, count)
	local def = deps.ItemDefs[itemId]
	if not def or type(count) ~= "number" or count ~= count
		or count == math.huge or count < 1 then
		return nil
	end
	count = math.floor(count)
	local part = Instance.new("Part")
	part.Name = "Pickup"
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Position = settleOnGround(position, 0.75)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.WoodPlanks
	part.Color = PICKUP_COLOR
	local state = { kind = "pickup", itemId = itemId, count = count,
		expiry = os.clock() + deps.Config.DEATH_BAG_LIFETIME }
	state.label = makeBillboard(part, ("%dx %s"):format(count, def.name))
	local prompt = makePrompt(part, "Take", def.name, 0, deps.Config.FORAGE_PROMPT_RANGE)
	prompt.Triggered:Connect(function(player)
		local _, placed = deps.Inventory.GiveItem(player, state.itemId, state.count)
		if placed == 0 then
			return -- GiveItem notified "Inventory full"
		end
		state.count -= placed
		if state.count <= 0 then
			destroyDrop(part)
		else
			state.label.Text = ("%dx %s"):format(state.count, def.name)
		end
	end)
	drops[part] = state
	part.Parent = pickupsFolder
	return part
end

-- items: array of {id = ItemId, count = n} — exactly InventoryService.ClearAll's
-- return shape. Returns the bag instance (ProgressService, Task 14).
function LootService.SpawnDeathBag(position, items)
	local stacks = {}
	for _, s in ipairs(items) do
		if deps.ItemDefs[s.id] and type(s.count) == "number" and s.count == s.count
			and s.count ~= math.huge and s.count >= 1 then
			table.insert(stacks, { id = s.id, count = math.floor(s.count) })
		end
	end
	if #stacks == 0 then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = "Backpack"
	part.Size = Vector3.new(2, 2, 2.5)
	part.Position = settleOnGround(position, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Fabric
	part.Color = BACKPACK_COLOR
	local state = { kind = "bag", stacks = stacks,
		expiry = os.clock() + deps.Config.DEATH_BAG_LIFETIME }
	makeBillboard(part, "Backpack")
	local prompt = makePrompt(part, "Loot", "Backpack", 0, deps.Config.FORAGE_PROMPT_RANGE)
	prompt.Triggered:Connect(function(player)
		-- Iterate a COPY of the remaining stacks (entries are shared references,
		-- so decrements land in state.stacks); rebuild the live list afterwards.
		local snapshot = table.clone(state.stacks)
		for _, s in ipairs(snapshot) do
			local fittedAll, placed = deps.Inventory.GiveItem(player, s.id, s.count)
			s.count -= placed
			if not fittedAll then
				break -- looter full (placed 0 or partial); GiveItem already notified
			end
		end
		local remaining = {}
		for _, s in ipairs(state.stacks) do
			if s.count > 0 then
				table.insert(remaining, s)
			end
		end
		state.stacks = remaining
		if #remaining == 0 then
			destroyDrop(part)
		end
	end)
	drops[part] = state
	part.Parent = pickupsFolder
	return part
end

-- ===== Shared maintenance loop =====

local function sweep(now)
	for inst, node in pairs(nodes) do
		if not inst.Parent then
			nodes[inst] = nil
		elseif node.expiry and now >= node.expiry then
			reactivateNode(node)
		end
	end
	for crate, state in pairs(crates) do
		if not crate.Parent then
			crates[crate] = nil
		elseif state.expiry and now >= state.expiry then
			state.expiry = nil
			state.prompt.Enabled = true
			crate.Transparency = 0
		end
	end
	for part, state in pairs(drops) do
		if not part.Parent then
			drops[part] = nil
		elseif now >= state.expiry then
			destroyDrop(part)
		end
	end
end

function LootService.Init(depsIn)
	deps = depsIn
	rng = Random.new() -- unseeded: runtime loot should differ per server

	runtimeFolder = workspace:FindFirstChild("RuntimeLoot") or Instance.new("Folder")
	runtimeFolder.Name = "RuntimeLoot"
	runtimeFolder.Parent = workspace
	cratesFolder = runtimeFolder:FindFirstChild("Crates") or Instance.new("Folder")
	cratesFolder.Name = "Crates"
	cratesFolder.Parent = runtimeFolder
	pickupsFolder = runtimeFolder:FindFirstChild("Pickups") or Instance.new("Folder")
	pickupsFolder.Name = "Pickups"
	pickupsFolder.Parent = runtimeFolder

	settleParams = RaycastParams.new()
	settleParams.FilterType = Enum.RaycastFilterType.Exclude

	setupForageNodes()
	setupCrates()

	task.spawn(function()
		while true do
			task.wait(MAINTENANCE_INTERVAL)
			local ok, err = pcall(sweep, os.clock())
			if not ok then
				warn("[LootService] sweep error: " .. tostring(err))
			end
		end
	end)
end

return LootService
