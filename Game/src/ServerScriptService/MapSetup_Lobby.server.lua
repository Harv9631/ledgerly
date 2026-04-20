-- MapSetup_Lobby.server.lua — Lobby STRUCTURE only
-- Builds: SpawnLocation, floor, invisible walls, columns, ceiling, Ready Zone, carpet runner
-- Decorations are in MapSetup_LobbyDecor.server.lua

-- Share the map folder created by MapSetup.server.lua (runs first alphabetically)
local mapFolder = workspace:WaitForChild("DressToSurviveMap", 10)
if not mapFolder then
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "DressToSurviveMap"
	mapFolder.Parent = workspace
end

local LOBBY_CENTER = Vector3.new(0, 0, 80)

local function part(name, size, pos, color, material, parent, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color or Color3.fromRGB(128, 128, 128)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then for k, v in pairs(props) do p[k] = v end end
	p.Parent = parent or mapFolder
	return p
end

-- ============================================================
-- SPAWN LOCATION — created FIRST so players always land here
-- ============================================================
local lobbySpawn = Instance.new("SpawnLocation")
lobbySpawn.Name = "LobbySpawn"
lobbySpawn.Size = Vector3.new(30, 0.5, 30)
lobbySpawn.Position = LOBBY_CENTER + Vector3.new(0, 0.25, 0)
lobbySpawn.Color = Color3.fromRGB(245, 220, 230)
lobbySpawn.Anchored = true
lobbySpawn.Neutral = true
lobbySpawn.Material = Enum.Material.Marble
lobbySpawn.TopSurface = Enum.SurfaceType.Smooth
lobbySpawn.BottomSurface = Enum.SurfaceType.Smooth
lobbySpawn.Parent = mapFolder

-- ============================================================
-- FLOOR — pink marble, 120x120
-- ============================================================
part("LobbyFloor", Vector3.new(120, 0.4, 120), LOBBY_CENTER + Vector3.new(0, 0.2, 0),
	Color3.fromRGB(255, 240, 245), Enum.Material.Marble)

-- Rose gold center diamond accent
part("LobbyGoldCenter", Vector3.new(18, 0.5, 18), LOBBY_CENTER + Vector3.new(0, 0.35, 0),
	Color3.fromRGB(220, 170, 160), Enum.Material.Marble)
part("LobbyStar1", Vector3.new(12, 0.52, 3), LOBBY_CENTER + Vector3.new(0, 0.36, 0),
	Color3.fromRGB(230, 180, 170), Enum.Material.Marble)
part("LobbyStar2", Vector3.new(3, 0.52, 12), LOBBY_CENTER + Vector3.new(0, 0.36, 0),
	Color3.fromRGB(230, 180, 170), Enum.Material.Marble)

-- ============================================================
-- PERIMETER WALLS — invisible, CanCollide keeps players inside
-- ============================================================
local walls = {
	{name="WallNorth", size=Vector3.new(210, 25, 1), pos=Vector3.new(0, 12, 10)},
	{name="WallSouth", size=Vector3.new(210, 25, 1), pos=Vector3.new(0, 12, 190)},
	{name="WallEast",  size=Vector3.new(1, 25, 185), pos=Vector3.new(100, 12, 100)},
	{name="WallWest",  size=Vector3.new(1, 25, 185), pos=Vector3.new(-100, 12, 100)},
}
for _, w in ipairs(walls) do
	part(w.name, w.size, w.pos, Color3.fromRGB(200, 200, 200), Enum.Material.SmoothPlastic, nil,
		{Transparency = 1, CanCollide = true})
end

-- ============================================================
-- COLUMNS — 8 rose gold, symmetric grid
-- ============================================================
local ROSE_GOLD = Color3.fromRGB(200, 150, 120)
local colPos = {
	Vector3.new(-40, 0, 40),  Vector3.new(40, 0, 40),
	Vector3.new(-40, 0, 70),  Vector3.new(40, 0, 70),
	Vector3.new(-40, 0, 90),  Vector3.new(40, 0, 90),
	Vector3.new(-40, 0, 120), Vector3.new(40, 0, 120),
}
for i, cp in ipairs(colPos) do
	part("ColumnShaft_"..i,  Vector3.new(2, 20, 2), cp + Vector3.new(0, 10, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.25})
	part("ColumnBase_"..i,   Vector3.new(3, 0.8, 3), cp + Vector3.new(0, 0.4, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.25})
	part("ColumnCapital_"..i, Vector3.new(3, 0.8, 3), cp + Vector3.new(0, 20.4, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.25})
end

-- ============================================================
-- CEILING — dark marble with rose gold trim border
-- ============================================================
part("LobbyCeiling", Vector3.new(120, 0.5, 120), LOBBY_CENTER + Vector3.new(0, 21, 0),
	Color3.fromRGB(30, 15, 30), Enum.Material.Marble)
part("CeilTrimN", Vector3.new(120, 1, 1.5), LOBBY_CENTER + Vector3.new(0, 20.5, -59),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.2})
part("CeilTrimS", Vector3.new(120, 1, 1.5), LOBBY_CENTER + Vector3.new(0, 20.5, 59),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.2})
part("CeilTrimE", Vector3.new(1.5, 1, 120), LOBBY_CENTER + Vector3.new(59, 20.5, 0),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.2})
part("CeilTrimW", Vector3.new(1.5, 1, 120), LOBBY_CENTER + Vector3.new(-59, 20.5, 0),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.2})

-- ============================================================
-- READY ZONE — at (0, 0, 50), near runway entrance
-- ============================================================
local GOLD_COLOR  = Color3.fromRGB(220, 170, 120)
local DARK_RED    = Color3.fromRGB(120, 20, 30)

part("ReadyZoneFloor", Vector3.new(30, 0.3, 30), Vector3.new(0, 0.35, 50),
	Color3.fromRGB(200, 165, 100), Enum.Material.SmoothPlastic)

-- 8 rope posts (CanCollide=false so players walk through)
local postPos = {
	Vector3.new(-15, 1.5, 35), Vector3.new(0, 1.5, 35), Vector3.new(15, 1.5, 35),
	Vector3.new(-15, 1.5, 65), Vector3.new(0, 1.5, 65), Vector3.new(15, 1.5, 65),
	Vector3.new(-15, 1.5, 50), Vector3.new(15, 1.5, 50),
}
for i, pp in ipairs(postPos) do
	part("RopePost_"..i, Vector3.new(0.4, 3, 0.4), pp,
		GOLD_COLOR, Enum.Material.Metal, nil, {CanCollide=false, Reflectance=0.3})
	part("RopePostCap_"..i, Vector3.new(0.7, 0.7, 0.7), pp + Vector3.new(0, 1.55, 0),
		GOLD_COLOR, Enum.Material.Metal, nil, {CanCollide=false, Reflectance=0.3, Shape=Enum.PartType.Ball})
end
-- Rope segments
part("RopeN", Vector3.new(30.2, 0.15, 0.15), Vector3.new(0, 2.6, 35), DARK_RED, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
part("RopeS", Vector3.new(30.2, 0.15, 0.15), Vector3.new(0, 2.6, 65), DARK_RED, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
part("RopeW", Vector3.new(0.15, 0.15, 30.2), Vector3.new(-15, 2.6, 50), DARK_RED, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
part("RopeE", Vector3.new(0.15, 0.15, 30.2), Vector3.new(15, 2.6, 50), DARK_RED, Enum.Material.SmoothPlastic, nil, {CanCollide=false})

-- ============================================================
-- CARPET RUNNER — spawn (0,0,80) to Ready Zone (0,0,50)
-- ============================================================
part("CarpetRunner", Vector3.new(6, 0.1, 30), Vector3.new(0, 0.55, 65),
	Color3.fromRGB(220, 80, 130), Enum.Material.Fabric)

print("[MapSetup_Lobby] Structure built")
