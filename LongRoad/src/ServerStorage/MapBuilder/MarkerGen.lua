--[[
	MarkerGen: fills Workspace.Markers with invisible marker parts that ModelPlacer
	(Task 4) and runtime services resolve by EXACT name. Runs in Studio right after
	TerrainGen.Build(), so marker Y comes from raycasting the real baked terrain
	(fallback: TerrainGen.HeightAt). Deterministic: one seeded Random, nothing else.
]]
local MarkerGen = {}

local Config = require(game:GetService("ReplicatedStorage").GameConfig)
local TerrainGen = require(script.Parent.TerrainGen)

-- ===== Tunables =====
local SEED = 1337
local RAY_UP, RAY_LEN = 400, 450 -- cast origin height / length
local ROAD_HALF = 50             -- keep scattered props off |X| < 50
local SPAWN_CLEAR = 60           -- no props within this radius of SPAWN_POSITION
local EDGE_PAD = 50              -- keep scatter away from the map edge
-- Forest
local FOREST_TREES, FOREST_PINE_RATIO, TREE_GAP = 600, 0.7, 25
local FOREST_BERRY, FOREST_MUSHROOM, FOREST_ROCK, FOREST_BRANCH, FOREST_MONSTERS = 60, 30, 40, 80, 10
-- Suburbs
local HOUSE_XS = { -140, -60, 60, 140 }
local HOUSE_Z_START, HOUSE_Z_END, HOUSE_Z_STEP = 3080, 5920, 80
local HOUSE_KEEP = 80 / 144      -- keep ~80 of the 4x36 = 144 grid candidates
local HOUSE_TIER2_CHANCE = 0.3
local HOUSE_FRONT_OFFSET = 15    -- half footprint (10) + 5 studs
local STORE_COUNT, STORE_X, STORE_FRONT_OFFSET = 12, 220, 20
local SUBURB_MONSTERS, SUBURB_BRANCH = 20, 20
-- Highlands
local HL_TREES_NORTH, HL_TREES_SOUTH = 32, 118 -- 150 total, split by band size
local HL_ROCKS, HL_BRANCH, HL_MONSTERS = 80, 40, 12
local BRIDGE_POS = Vector3.new(0, 14, 6400) -- fixed deck height; never raycast (water below)
local PASS_LOOT = 10             -- tier-2 loot near the pass corridor
local PASS_X_MIN, PASS_X_MAX = -700, -100
-- City
local RUIN_XS = { -800, -600, -400, -200, 200, 400, 600, 800 }
local RUIN_Z_START, RUIN_Z_END, RUIN_Z_STEP = 9100, 11700, 200
local RUIN_KEEP = 0.9            -- 8 x 14 = 112 candidates -> ~100 kept
local CITY_LOOT, CITY_LOOT_T2_CHANCE, CITY_LOOT_SPREAD = 60, 0.7, 30
local TOXIC_COUNT, TOXIC_RADIUS, TOXIC_ROAD_CLEAR = 6, 30, 80
local CITY_MONSTERS = 30

local rng, folder, counts -- reset at the top of Build()

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { workspace.Terrain }

-- Surface Y at (x, z); nil if the ray hit water (no markers in the river).
local function groundY(x, z)
	local hit = workspace:Raycast(Vector3.new(x, RAY_UP, z), Vector3.new(0, -RAY_LEN, 0), rayParams)
	if hit then
		if hit.Material == Enum.Material.Water then return nil end
		return hit.Position.Y
	end
	return (TerrainGen.HeightAt(x, z)) -- ray missed (shouldn't happen post-bake)
end

-- For fixed markers that must always exist (checkpoints/spawn/extraction).
local function groundYAlways(x, z)
	return groundY(x, z) or (TerrainGen.HeightAt(x, z))
end

local function makeMarker(name, cf)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.CanCollide = false
	part.Anchored = true
	part.CFrame = cf
	part.Parent = folder
	counts[name] = (counts[name] or 0) + 1
	return part
end

-- Scatter `count` markers in a Z band via rejection sampling (bounded tries, no
-- infinite loop). Always rejects the road strip and the spawn clearing.
-- opts: xMin/xMax (default map-wide), minGap, reject(x, z) -> true to skip, onPlace(marker)
local function scatter(count, zStart, zEnd, makeName, opts)
	opts = opts or {}
	local xMin = opts.xMin or -Config.MAP_WIDTH / 2 + EDGE_PAD
	local xMax = opts.xMax or Config.MAP_WIDTH / 2 - EDGE_PAD
	local spawn = Config.SPAWN_POSITION
	local placed = {}
	local tries = 0
	while #placed < count and tries < count * 20 do
		tries += 1
		local x = rng:NextNumber(xMin, xMax)
		local z = rng:NextNumber(zStart + 20, zEnd - 20)
		local ok = math.abs(x) >= ROAD_HALF
			and (x - spawn.X) ^ 2 + (z - spawn.Z) ^ 2 >= SPAWN_CLEAR ^ 2
			and not (opts.reject and opts.reject(x, z))
		if ok and opts.minGap then
			for _, p in ipairs(placed) do
				if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < opts.minGap ^ 2 then
					ok = false
					break
				end
			end
		end
		if ok then
			local y = groundY(x, z) -- nil = water, reject
			if y then
				table.insert(placed, Vector3.new(x, y, z))
				local name = if type(makeName) == "function" then makeName() else makeName
				local marker = makeMarker(name, CFrame.new(x, y, z))
				if opts.onPlace then opts.onPlace(marker) end
			end
		end
	end
	return #placed
end

local function zoneTagger(zoneName)
	return function(marker)
		marker:SetAttribute("Zone", zoneName)
	end
end

-- ===== Zones =====
local function buildForest()
	local zone = Config.ZONES[1]
	local trees = scatter(FOREST_TREES, zone.zStart, zone.zEnd, function()
		return if rng:NextNumber() < FOREST_PINE_RATIO then "Marker_Tree_Pine" else "Marker_Tree_Oak"
	end, { minGap = TREE_GAP })
	local berry = scatter(FOREST_BERRY, zone.zStart, zone.zEnd, "Marker_Bush_Berry")
	local mushroom = scatter(FOREST_MUSHROOM, zone.zStart, zone.zEnd, "Marker_Bush_Mushroom")
	local rocks = scatter(FOREST_ROCK, zone.zStart, zone.zEnd, "Marker_Rock")
	local branches = scatter(FOREST_BRANCH, zone.zStart, zone.zEnd, "Marker_Branch")
	local monsters = scatter(FOREST_MONSTERS, zone.zStart, zone.zEnd, "Marker_MonsterSpawn", { onPlace = zoneTagger("Forest") })
	print(("[MarkerGen] Forest: %d trees, %d berry, %d mushroom, %d rock, %d branch, %d monster"):format(
		trees, berry, mushroom, rocks, branches, monsters))
end

-- Building marker facing the road (X=0) + a loot marker 5 studs in front of its footprint.
local function placeBuildingWithLoot(name, x, z, frontOffset, lootTier)
	local y = groundY(x, z)
	if not y then return false end
	makeMarker(name, CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(0, y, z)))
	local lootX = if x > 0 then x - frontOffset else x + frontOffset
	local loot = makeMarker("Marker_Loot", CFrame.new(lootX, groundY(lootX, z) or y, z))
	loot:SetAttribute("LootTier", lootTier)
	return true
end

local function buildSuburbs()
	local zone = Config.ZONES[2]
	local houses = 0
	for z = HOUSE_Z_START, HOUSE_Z_END, HOUSE_Z_STEP do
		for _, x in ipairs(HOUSE_XS) do
			if rng:NextNumber() < HOUSE_KEEP then
				local tier = if rng:NextNumber() < HOUSE_TIER2_CHANCE then 2 else 1
				if placeBuildingWithLoot("Marker_Building_House", x, z, HOUSE_FRONT_OFFSET, tier) then
					houses += 1
				end
			end
		end
	end
	local stores = 0
	for i = 1, STORE_COUNT do
		local x = if i % 2 == 0 then STORE_X else -STORE_X
		local z = zone.zStart + (zone.zEnd - zone.zStart) * i / (STORE_COUNT + 1)
		if placeBuildingWithLoot("Marker_Building_Store", x, z, STORE_FRONT_OFFSET, 2) then
			stores += 1
		end
	end
	local branches = scatter(SUBURB_BRANCH, zone.zStart, zone.zEnd, "Marker_Branch")
	local monsters = scatter(SUBURB_MONSTERS, zone.zStart, zone.zEnd, "Marker_MonsterSpawn", { onPlace = zoneTagger("Suburbs") })
	print(("[MarkerGen] Suburbs: %d houses, %d stores (+1 loot each), %d branch, %d monster"):format(
		houses, stores, branches, monsters))
end

local function buildHighlands()
	local zone = Config.ZONES[3]
	local trees = scatter(HL_TREES_NORTH, zone.zStart, Config.RIVER_Z[1], "Marker_Tree_Pine", { minGap = TREE_GAP })
		+ scatter(HL_TREES_SOUTH, Config.RIVER_Z[2], Config.MOUNTAIN_Z[1], "Marker_Tree_Pine", { minGap = TREE_GAP })
	local rocks = scatter(HL_ROCKS, zone.zStart, zone.zEnd, "Marker_Rock") -- river water auto-rejected
	local branches = scatter(HL_BRANCH, Config.RIVER_Z[2], Config.MOUNTAIN_Z[1], "Marker_Branch")
	makeMarker("Marker_Bridge", CFrame.new(BRIDGE_POS))
	local monsters = scatter(HL_MONSTERS, zone.zStart, zone.zEnd, "Marker_MonsterSpawn", { onPlace = zoneTagger("Highlands") })
	local loot = scatter(PASS_LOOT, Config.MOUNTAIN_Z[1], Config.MOUNTAIN_Z[2], "Marker_Loot", {
		xMin = PASS_X_MIN,
		xMax = PASS_X_MAX,
		onPlace = function(marker) marker:SetAttribute("LootTier", 2) end,
	})
	print(("[MarkerGen] Highlands: %d pine, %d rock, %d branch, 1 bridge, %d monster, %d pass loot"):format(
		trees, rocks, branches, monsters, loot))
end

local function buildCity()
	local zone = Config.ZONES[4]
	local ruins = {}
	for z = RUIN_Z_START, RUIN_Z_END, RUIN_Z_STEP do
		for _, x in ipairs(RUIN_XS) do
			if rng:NextNumber() < RUIN_KEEP then
				local y = groundY(x, z)
				if y then
					makeMarker("Marker_Building_Ruin", CFrame.new(x, y, z))
					table.insert(ruins, Vector3.new(x, y, z))
				end
			end
		end
	end
	local loot, tries = 0, 0
	while loot < CITY_LOOT and tries < CITY_LOOT * 20 and #ruins > 0 do
		tries += 1
		local base = ruins[rng:NextInteger(1, #ruins)]
		local x = base.X + rng:NextNumber(-CITY_LOOT_SPREAD, CITY_LOOT_SPREAD)
		local z = base.Z + rng:NextNumber(-CITY_LOOT_SPREAD, CITY_LOOT_SPREAD)
		if math.abs(x) >= ROAD_HALF then
			local y = groundY(x, z)
			if y then
				local marker = makeMarker("Marker_Loot", CFrame.new(x, y, z))
				marker:SetAttribute("LootTier", if rng:NextNumber() < CITY_LOOT_T2_CHANCE then 2 else 3)
				loot += 1
			end
		end
	end
	local toxic = scatter(TOXIC_COUNT, zone.zStart, zone.zEnd, "Marker_ToxicZone", {
		reject = function(x) return math.abs(x) < TOXIC_ROAD_CLEAR end, -- always routable via the road
		onPlace = function(marker) marker:SetAttribute("Radius", TOXIC_RADIUS) end,
	})
	local monsters = scatter(CITY_MONSTERS, zone.zStart, zone.zEnd, "Marker_MonsterSpawn", { onPlace = zoneTagger("City") })
	print(("[MarkerGen] City: %d ruins, %d loot, %d toxic, %d monster"):format(#ruins, loot, toxic, monsters))
end

local function buildGlobal()
	for i, cp in ipairs(Config.CHECKPOINTS) do
		local marker = makeMarker("Marker_Checkpoint",
			CFrame.new(cp.position.X, groundYAlways(cp.position.X, cp.position.Z), cp.position.Z))
		marker:SetAttribute("CheckpointIndex", i)
		marker:SetAttribute("CheckpointName", cp.name)
	end
	local ext = Config.EXTRACTION_POSITION
	makeMarker("Marker_Extraction", CFrame.new(ext.X, groundYAlways(ext.X, ext.Z), ext.Z))
	local spawn = Config.SPAWN_POSITION
	makeMarker("Marker_Spawn", CFrame.new(spawn.X, groundYAlways(spawn.X, spawn.Z), spawn.Z))
	print(("[MarkerGen] Global: %d checkpoints, 1 extraction, 1 spawn"):format(#Config.CHECKPOINTS))
end

function MarkerGen.Build()
	rng = Random.new(SEED)
	counts = {}
	local existing = workspace:FindFirstChild("Markers")
	if existing then existing:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "Markers"
	folder.Parent = workspace
	buildForest()
	buildSuburbs()
	buildHighlands()
	buildCity()
	buildGlobal()
	local total = 0
	for _, n in pairs(counts) do total += n end
	print(("[MarkerGen] done — %d markers total"):format(total))
end

return MarkerGen
