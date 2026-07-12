local TerrainGen = {}
local Config = require(game:GetService("ReplicatedStorage").GameConfig)

local CELL = 40
local SEED = 1337
local MIN_HEIGHT = 4 -- floor outside the river so noise can never dig below the water table

-- Road runs along X=0 through Suburbs and City (zones 2 and 4)
local SUBURBS = Config.ZONES[2]
local CITY = Config.ZONES[4]

local function zoneAt(z)
	for i, zone in ipairs(Config.ZONES) do
		if z >= zone.zStart and z < zone.zEnd then return i, zone end
	end
	return #Config.ZONES, Config.ZONES[#Config.ZONES]
end

-- Height profile per zone index: {baseHeight, amplitude, material}
local PROFILE = {
	[1] = { base = 20, amp = 12, material = Enum.Material.Grass },      -- Forest: rolling
	[2] = { base = 16, amp = 5,  material = Enum.Material.Grass },      -- Suburbs: gentle
	[3] = { base = 24, amp = 30, material = Enum.Material.Rock },       -- Highlands: rugged
	[4] = { base = 14, amp = 4,  material = Enum.Material.Concrete },   -- City: flat rubble
}

function TerrainGen.HeightAt(x, z)
	local zi = zoneAt(z)
	local p = PROFILE[zi]
	local n = math.noise(x / 400 + SEED, z / 400 + SEED)      -- broad hills
	local n2 = math.noise(x / 90, z / 90) * 0.3               -- detail
	local h = p.base + (n + n2) * p.amp
	-- Mountain pass: raise dramatically, leaving a walkable saddle near X=-400
	if z >= Config.MOUNTAIN_Z[1] and z <= Config.MOUNTAIN_Z[2] then
		local ridge = 60 * math.sin(math.pi * (z - Config.MOUNTAIN_Z[1]) / (Config.MOUNTAIN_Z[2] - Config.MOUNTAIN_Z[1]))
		local saddle = math.clamp(math.abs(x + 400) / 300, 0, 1) -- 0 at pass, 1 away
		h += ridge * saddle
	end
	-- River: carve below water level
	local inRiver = z >= Config.RIVER_Z[1] and z <= Config.RIVER_Z[2]
	if inRiver then
		h = 2
	end
	-- Road strip along X=0 through Suburbs and City: flatten to zone base
	if math.abs(x) < 15 and ((z >= SUBURBS.zStart and z < SUBURBS.zEnd) or z >= CITY.zStart) then
		h = p.base
	end
	-- Guard against noise digging holes below the water table (river band excepted)
	if not inRiver then
		h = math.max(h, MIN_HEIGHT)
	end
	return h, p.material
end

function TerrainGen.Build()
	local terrain = workspace.Terrain
	terrain:Clear()
	local halfW = Config.MAP_WIDTH / 2
	for x = -halfW, halfW - CELL, CELL do
		for z = 0, Config.MAP_LENGTH - CELL, CELL do
			local h, mat = TerrainGen.HeightAt(x + CELL / 2, z + CELL / 2)
			local cf = CFrame.new(x + CELL / 2, h / 2, z + CELL / 2)
			terrain:FillBlock(cf, Vector3.new(CELL, h, CELL), mat)
		end
		if x % 400 == 0 then task.wait() end -- yield so Studio stays responsive
	end
	-- River water
	local rz1, rz2 = Config.RIVER_Z[1], Config.RIVER_Z[2]
	terrain:FillBlock(
		CFrame.new(0, 8, (rz1 + rz2) / 2),
		Vector3.new(Config.MAP_WIDTH, 12, rz2 - rz1),
		Enum.Material.Water
	)
	print("[TerrainGen] done")
end

return TerrainGen
