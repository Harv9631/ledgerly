--[[
	ModelPlacer: turns Workspace.Markers into the visual world under Workspace.Map.
	Runs in Studio after MarkerGen (see MapBuilder/init.lua).
	Idempotent: destroys Workspace.Map first and rebuilds everything from markers;
	the markers themselves are NEVER destroyed or moved, so re-running Place() after
	dropping real models into ReplicatedStorage.Assets upgrades the world visuals
	with zero code changes. Deterministic: one seeded Random, nothing else.
]]
local ModelPlacer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== Tunables =====
local SEED = 7331
local RAY_UP, RAY_LEN = 50, 200  -- cast from 50 studs above the marker, straight down
local SINK = 0.5                 -- bases sink this far into the ground
local TAU = math.pi * 2
local CYL_UP = CFrame.Angles(0, 0, math.rad(90)) -- cylinders lie along X; stand them up
local FLIP = CFrame.Angles(0, math.pi, 0)        -- WedgePart tall face is +Z; flip mirrors it

local C = {
	trunk = Color3.fromRGB(86, 60, 38),
	pine = Color3.fromRGB(32, 86, 36),    -- dark green
	oak = Color3.fromRGB(64, 138, 48),    -- brighter green
	rock = Color3.fromRGB(120, 120, 122),
	bush = Color3.fromRGB(52, 110, 44),
	berry = Color3.fromRGB(190, 30, 40),
	mushroomCap = Color3.fromRGB(196, 172, 132), -- tan
	mushroomStem = Color3.fromRGB(238, 230, 210), -- cream
	houseWall = Color3.fromRGB(222, 205, 170),   -- beige
	roof = Color3.fromRGB(70, 70, 74),
	door = Color3.fromRGB(25, 25, 28),
	storeWall = Color3.fromRGB(150, 150, 152),
	sign = Color3.fromRGB(176, 158, 122),        -- faded
	ruin = Color3.fromRGB(78, 78, 82),
	wood = Color3.fromRGB(126, 96, 60),
	tent = Color3.fromRGB(104, 118, 82),
	pole = Color3.fromRGB(140, 140, 145),
	flag = Color3.fromRGB(200, 60, 50),
	beacon = Color3.fromRGB(60, 220, 90),
	concrete = Color3.fromRGB(130, 130, 130),
}

local rng -- reset at the top of Place()

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }

-- ===== Helpers =====
local function mkPart(parent, props)
	local p = Instance.new(props.class or "Part")
	p.Anchored = true
	p.Size = props.size
	p.CFrame = props.cf
	p.Material = props.material or Enum.Material.SmoothPlastic
	if props.color then p.Color = props.color end
	p.CanCollide = props.collide == true
	if props.shape then p.Shape = props.shape end -- only ever passed for class "Part"
	p.Name = props.name or "Part"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function newModel(name)
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- Ground the marker: ray from 50 above straight down against Terrain only; hit Y is
-- ground (sunk by SINK). Ray miss -> the marker's own Y. Marker_Bridge is EXEMPT
-- (exactCFrame): built at the marker's exact CFrame (fixed deck height over water).
local function targetCFrame(marker, spec)
	if spec.exactCFrame then
		return marker.CFrame
	end
	local pos = marker.Position
	local hit = workspace:Raycast(pos + Vector3.new(0, RAY_UP, 0), Vector3.new(0, -RAY_LEN, 0), rayParams)
	local groundY
	if hit then
		groundY = hit.Position.Y
	else
		-- Surface bake anomalies instead of silently falling back to the marker's Y
		warn("[ModelPlacer] ray miss at " .. marker.Name .. " " .. tostring(pos))
		groundY = pos.Y
	end
	-- Buildings/fixed props keep the marker's rotation (MarkerGen faced houses at the
	-- road); scattered nature props get a random yaw.
	local rot = if spec.keepRotation
		then marker.CFrame.Rotation
		else CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	return CFrame.new(pos.X, groundY - SINK, pos.Z) * rot
end

local warnedAssets -- reset each Place(): warn once per assets path, not once per marker

-- Returns the placeable (Model/BasePart) children of Assets.<path>, or nil if the
-- folder is missing or has none. Non-placeable children (Folders, Scripts, Decals,
-- ...) are skipped with a one-time warn so a bad Assets layout doesn't silently
-- fall back to placeholders and confuse the bake.
local function findAssets(path)
	if not path then return nil end -- placeholder-only category
	local node = ReplicatedStorage:FindFirstChild("Assets")
	for _, seg in ipairs(string.split(path, "/")) do
		if not node then return nil end
		node = node:FindFirstChild(seg)
	end
	if not node then return nil end
	local candidates, skipped = {}, 0
	for _, child in ipairs(node:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			table.insert(candidates, child)
		else
			skipped += 1
		end
	end
	if skipped > 0 and not warnedAssets[path] then
		warnedAssets[path] = true
		warn(("[ModelPlacer] Assets.%s: skipped %d non-placeable child(ren) — only Model/BasePart are cloned"):format(
			path:gsub("/", "."), skipped))
	end
	if #candidates > 0 then return candidates end
	return nil
end

-- Clone a random real asset (Model or BasePart) and place it at cf.
local function placeReal(candidates, cf)
	local template = candidates[rng:NextInteger(1, #candidates)]
	local scale = rng:NextNumber(0.9, 1.15)
	local clone = template:Clone()
	if clone:IsA("BasePart") then
		-- ScaleTo only exists on Model: wrap single Parts/MeshParts in a Model so
		-- scaling and PivotTo behave identically to multi-part assets.
		local wrap = newModel(clone.Name)
		clone.Parent = wrap
		wrap.PrimaryPart = clone
		clone = wrap
	end
	clone:ScaleTo(scale)
	clone:PivotTo(cf) -- cf already carries random yaw (or marker rotation for buildings)
	-- Studio model pivots default to the bounding-box CENTER, so PivotTo(cf) alone
	-- would place real assets half-buried. Shift the model up so its bounding-box
	-- BOTTOM sits at cf's Y (rotation stays intact).
	local bb, size = clone:GetBoundingBox()
	local lift = cf.Position.Y - (bb.Position.Y - size.Y / 2)
	if math.abs(lift) > 1e-4 then
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, lift, 0))
	end
	return clone
end

-- ===== Placeholder builders (base sits at cf; every Model gets a PrimaryPart) =====
local function buildTree(cf, leafColor, s1, s2)
	local scale = rng:NextNumber(0.85, 1.3)
	local m = newModel("Tree")
	local h = 14 * scale
	local trunk = mkPart(m, { name = "Trunk", size = Vector3.new(h, 2 * scale, 2 * scale),
		cf = cf * CFrame.new(0, h / 2, 0) * CYL_UP, shape = Enum.PartType.Cylinder,
		material = Enum.Material.Wood, color = C.trunk, collide = true })
	mkPart(m, { name = "CanopyLow", size = Vector3.one * (s1 * scale),
		cf = cf * CFrame.new(0, h * 0.85, 0), shape = Enum.PartType.Ball,
		material = Enum.Material.Grass, color = leafColor })
	mkPart(m, { name = "CanopyHigh", size = Vector3.one * (s2 * scale),
		cf = cf * CFrame.new(0, h * 0.85 + s1 * scale * 0.45, 0), shape = Enum.PartType.Ball,
		material = Enum.Material.Grass, color = leafColor })
	m.PrimaryPart = trunk
	return m
end

local function buildPine(cf) return buildTree(cf, C.pine, 10, 7) end
local function buildOak(cf) return buildTree(cf, C.oak, 12, 8) end

local function buildRock(cf)
	local m = newModel("Rock")
	local d = rng:NextNumber(4, 10)
	-- ball centered at ground level = sunk half into the ground
	local p = mkPart(m, { name = "Rock", size = Vector3.one * d, cf = cf,
		shape = Enum.PartType.Ball, material = Enum.Material.Slate, color = C.rock, collide = true })
	m.PrimaryPart = p
	return m
end

local function buildBerryBush(cf)
	local m = newModel("BerryBush")
	local body = mkPart(m, { name = "Bush", size = Vector3.one * 4, cf = cf * CFrame.new(0, 2, 0),
		shape = Enum.PartType.Ball, material = Enum.Material.Grass, color = C.bush })
	for _ = 1, 5 do -- tiny berries embedded on the upper surface
		local theta, phi = rng:NextNumber(0, TAU), rng:NextNumber(0.5, 1.35)
		local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
		mkPart(m, { name = "Berry", size = Vector3.one * 0.6,
			cf = cf * CFrame.new(Vector3.new(0, 2, 0) + dir * 2),
			shape = Enum.PartType.Ball, color = C.berry })
	end
	m.PrimaryPart = body
	return m
end

local function buildMushroomBush(cf)
	local m = newModel("MushroomBush")
	local body = mkPart(m, { name = "Bush", size = Vector3.one * 3, cf = cf * CFrame.new(0, 1.5, 0),
		shape = Enum.PartType.Ball, material = Enum.Material.Grass, color = C.mushroomCap })
	for i = 1, 3 do -- small cream stems poking up out of the cap
		local a = TAU * i / 3
		mkPart(m, { name = "Stem", size = Vector3.new(1.6, 0.5, 0.5),
			cf = cf * CFrame.new(math.cos(a) * 0.9, 2.9, math.sin(a) * 0.9) * CYL_UP,
			shape = Enum.PartType.Cylinder, color = C.mushroomStem })
	end
	m.PrimaryPart = body
	return m
end

local function buildBranch(cf)
	local m = newModel("Branch")
	local tilt = CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8))) -- slight lean; yaw comes from cf
	local p = mkPart(m, { name = "Branch", size = Vector3.new(5, 0.8, 0.8),
		cf = cf * CFrame.new(0, 0.5, 0) * tilt, shape = Enum.PartType.Cylinder,
		material = Enum.Material.Wood, color = C.wood })
	m.PrimaryPart = p
	return m
end

local function buildHouse(cf)
	local m = newModel("House")
	local body = mkPart(m, { name = "Body", size = Vector3.new(30, 20, 24), cf = cf * CFrame.new(0, 10, 0),
		material = Enum.Material.Concrete, color = C.houseWall, collide = true })
	-- Gable roof: two wedges, tall faces meeting at the ridge (local z = 0)
	mkPart(m, { name = "RoofA", class = "WedgePart", size = Vector3.new(30, 6, 12),
		cf = cf * CFrame.new(0, 23, -6), material = Enum.Material.Slate, color = C.roof, collide = true })
	mkPart(m, { name = "RoofB", class = "WedgePart", size = Vector3.new(30, 6, 12),
		cf = cf * CFrame.new(0, 23, 6) * FLIP, material = Enum.Material.Slate, color = C.roof, collide = true })
	-- Marker LookVector faces the road (MarkerGen), so the door goes on the local -Z face
	mkPart(m, { name = "Door", size = Vector3.new(4, 7, 0.5), cf = cf * CFrame.new(0, 3.5, -12.2),
		color = C.door, collide = true })
	m.PrimaryPart = body
	return m
end

local function buildStore(cf)
	local m = newModel("Store")
	local body = mkPart(m, { name = "Body", size = Vector3.new(40, 12, 30), cf = cf * CFrame.new(0, 6, 0),
		material = Enum.Material.Concrete, color = C.storeWall, collide = true })
	mkPart(m, { name = "Roof", size = Vector3.new(44, 1, 34), cf = cf * CFrame.new(0, 12.5, 0),
		material = Enum.Material.Concrete, color = C.roof, collide = true }) -- flat slab overhang
	mkPart(m, { name = "Door", size = Vector3.new(5, 8, 0.5), cf = cf * CFrame.new(0, 4, -15.2),
		color = C.door, collide = true })
	mkPart(m, { name = "Sign", size = Vector3.new(12, 3, 0.6), cf = cf * CFrame.new(0, 10.5, -15.4),
		material = Enum.Material.Wood, color = C.sign })
	m.PrimaryPart = body
	return m
end

local function buildRuin(cf)
	local m = newModel("Ruin")
	local h = rng:NextNumber(15, 60) -- per-instance height variety (seeded)
	local body = mkPart(m, { name = "Body", size = Vector3.new(25, h, 25), cf = cf * CFrame.new(0, h / 2, 0),
		material = Enum.Material.Concrete, color = C.ruin, collide = true })
	for _ = 1, rng:NextInteger(3, 5) do -- rubble scattered at the base
		local d = rng:NextNumber(2, 4)
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(14, 19)
		mkPart(m, { name = "Rubble", size = Vector3.one * d,
			cf = cf * CFrame.new(math.cos(a) * r, d * 0.35, math.sin(a) * r),
			shape = Enum.PartType.Ball, material = Enum.Material.Concrete, color = C.ruin, collide = true })
	end
	m.PrimaryPart = body
	return m
end

-- Bridge: built at the marker's EXACT CFrame (deck at Y=14 over the river band
-- Z 6300-6500; the 220-long deck spans it with ramps). Raycast-exempt.
local function buildBridge(cf)
	local m = newModel("Bridge")
	local deck = mkPart(m, { name = "Deck", size = Vector3.new(20, 1, 220), cf = cf,
		material = Enum.Material.WoodPlanks, color = C.wood, collide = true })
	for i, x in ipairs({ -9.5, 9.5 }) do -- side rails, full length
		mkPart(m, { name = "Rail" .. i, size = Vector3.new(1, 3, 220), cf = cf * CFrame.new(x, 2, 0),
			material = Enum.Material.WoodPlanks, color = C.wood, collide = true })
	end
	-- Short ramp wedges at both ends, tall face toward the deck, sloping down to the banks
	mkPart(m, { name = "RampSouth", class = "WedgePart", size = Vector3.new(20, 6, 14),
		cf = cf * CFrame.new(0, -2.5, -117), material = Enum.Material.WoodPlanks, color = C.wood, collide = true })
	mkPart(m, { name = "RampNorth", class = "WedgePart", size = Vector3.new(20, 6, 14),
		cf = cf * CFrame.new(0, -2.5, 117) * FLIP, material = Enum.Material.WoodPlanks, color = C.wood, collide = true })
	m.PrimaryPart = deck
	return m
end

local function buildCheckpoint(cf)
	local m = newModel("Checkpoint")
	-- A-frame tent: two wedges, tall faces meeting at the ridge
	local tentA = mkPart(m, { name = "TentA", class = "WedgePart", size = Vector3.new(8, 6, 4),
		cf = cf * CFrame.new(0, 3, -2), material = Enum.Material.Fabric, color = C.tent, collide = true })
	mkPart(m, { name = "TentB", class = "WedgePart", size = Vector3.new(8, 6, 4),
		cf = cf * CFrame.new(0, 3, 2) * FLIP, material = Enum.Material.Fabric, color = C.tent, collide = true })
	mkPart(m, { name = "Flagpole", size = Vector3.new(10, 0.5, 0.5), cf = cf * CFrame.new(6, 5, 0) * CYL_UP,
		shape = Enum.PartType.Cylinder, material = Enum.Material.Metal, color = C.pole, collide = true })
	mkPart(m, { name = "Flag", size = Vector3.new(2.4, 1.4, 0.2), cf = cf * CFrame.new(7.4, 9.2, 0),
		color = C.flag }) -- non-colliding
	m.PrimaryPart = tentA
	return m
end

local function buildExtraction(cf)
	local m = newModel("ExtractionBeacon")
	local pad = mkPart(m, { name = "Pad", size = Vector3.new(12, 1, 12), cf = cf * CFrame.new(0, 0.5, 0),
		material = Enum.Material.Concrete, color = C.concrete, collide = true })
	local beam = mkPart(m, { name = "Beacon", size = Vector3.new(20, 6, 6), cf = cf * CFrame.new(0, 11, 0) * CYL_UP,
		shape = Enum.PartType.Cylinder, material = Enum.Material.Neon, color = C.beacon })
	local light = Instance.new("PointLight")
	light.Color = C.beacon
	light.Range = 60
	light.Parent = beam
	m.PrimaryPart = pad
	return m
end

local function buildSpawnPad(cf)
	local m = newModel("SpawnPad")
	local pad = mkPart(m, { name = "Pad", size = Vector3.new(12, 1, 12), cf = cf * CFrame.new(0, 0.5, 0),
		material = Enum.Material.Concrete, color = C.concrete, collide = true })
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Name = "SpawnLocation"
	spawnLoc.Size = Vector3.new(12, 1, 12)
	spawnLoc.CFrame = cf * CFrame.new(0, 1.5, 0)
	spawnLoc.Anchored = true
	spawnLoc.CanCollide = false
	spawnLoc.Transparency = 1
	spawnLoc.Neutral = true
	spawnLoc.Parent = m
	m.PrimaryPart = pad
	return m
end

-- ===== Dispatch: marker name -> assets path / Map folder / placeholder / attributes =====
-- Marker_Loot, Marker_MonsterSpawn, Marker_ToxicZone are intentionally absent:
-- runtime services consume those markers directly, no visuals are placed.
-- attrs are applied to WHATEVER goes into the Map folder (real asset or placeholder)
-- so gameplay services work identically either way.
local SPECS = {
	Marker_Tree_Pine = { assets = "Trees/Pine", folder = "Trees", builder = buildPine, attrs = { Choppable = true } },
	Marker_Tree_Oak = { assets = "Trees/Oak", folder = "Trees", builder = buildOak, attrs = { Choppable = true } },
	Marker_Rock = { assets = "Rocks", folder = "Rocks", builder = buildRock },
	Marker_Bush_Berry = { assets = "Bushes/Berry", folder = "Bushes", builder = buildBerryBush, attrs = { Forageable = "Berries" } },
	Marker_Bush_Mushroom = { assets = "Bushes/Mushroom", folder = "Bushes", builder = buildMushroomBush, attrs = { Forageable = "Mushroom" } },
	Marker_Branch = { assets = "Branches", folder = "Branches", builder = buildBranch, attrs = { Forageable = "Wood" } },
	Marker_Building_House = { assets = "Buildings/House", folder = "Buildings", builder = buildHouse, keepRotation = true },
	Marker_Building_Store = { assets = "Buildings/Store", folder = "Buildings", builder = buildStore, keepRotation = true },
	Marker_Building_Ruin = { assets = "Buildings/Ruin", folder = "Buildings", builder = buildRuin },
	Marker_Bridge = { assets = "Bridge", folder = "Bridge", builder = buildBridge, keepRotation = true, exactCFrame = true },
	Marker_Checkpoint = { folder = "Checkpoints", builder = buildCheckpoint, keepRotation = true },
	Marker_Extraction = { folder = "Extraction", builder = buildExtraction, keepRotation = true },
	Marker_Spawn = { folder = "Spawn", builder = buildSpawnPad, keepRotation = true },
}

-- ===== Main =====
function ModelPlacer.Place()
	rng = Random.new(SEED)
	warnedAssets = {}
	local markers = workspace:FindFirstChild("Markers")
	assert(markers, "[ModelPlacer] Workspace.Markers missing — run MarkerGen first")
	-- Idempotent: visuals rebuilt from scratch; markers are never destroyed or moved
	local old = workspace:FindFirstChild("Map")
	if old then old:Destroy() end
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace

	local folders, stats = {}, {}
	for _, marker in ipairs(markers:GetChildren()) do
		local spec = SPECS[marker.Name]
		if spec then
			local folder = folders[spec.folder]
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = spec.folder
				folder.Parent = map
				folders[spec.folder] = folder
				stats[spec.folder] = { real = 0, placeholder = 0 }
			end
			local cf = targetCFrame(marker, spec)
			local instance
			local candidates = findAssets(spec.assets)
			if candidates then instance = placeReal(candidates, cf) end
			local usedReal = instance ~= nil
			if not instance then instance = spec.builder(cf) end
			if spec.attrs then
				for k, v in pairs(spec.attrs) do instance:SetAttribute(k, v) end
			end
			instance.Parent = folder
			local s = stats[spec.folder]
			if usedReal then s.real += 1 else s.placeholder += 1 end
		end
	end

	-- Summary: per-category counts, real assets vs placeholders
	local names = {}
	for name in pairs(stats) do table.insert(names, name) end
	table.sort(names)
	local total = 0
	for _, name in ipairs(names) do
		local s = stats[name]
		total += s.real + s.placeholder
		print(("[ModelPlacer] %s: %d placed (%d real, %d placeholder)"):format(
			name, s.real + s.placeholder, s.real, s.placeholder))
	end
	print(("[ModelPlacer] done — %d instances total"):format(total))
end

return ModelPlacer
