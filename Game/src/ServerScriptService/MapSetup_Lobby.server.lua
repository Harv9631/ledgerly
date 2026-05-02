-- MapSetup_Lobby.server.lua — Lobby STRUCTURE (skyscraper edition)
-- Builds: SpawnLocation, floor, glass curtain walls, tall Art Deco columns,
--         glass atrium ceiling, mezzanine balcony, building facade, Ready Zone
-- Decorations are in MapSetup_LobbyDecor.server.lua

local LOBBY_CENTER = Vector3.new(0, 0, 80)

-- ============================================================
-- SPAWN LOCATION — created FIRST, parented directly to workspace
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
lobbySpawn.Parent = workspace

local mapFolder = workspace:WaitForChild("DressToSurviveMap", 10)
if not mapFolder then
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "DressToSurviveMap"
	mapFolder.Parent = workspace
end

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

local ROSE_GOLD = Color3.fromRGB(200, 150, 120)

-- ============================================================
-- FLOOR — pink marble, 120x120
-- ============================================================
part("LobbyFloor", Vector3.new(120, 0.4, 120), LOBBY_CENTER + Vector3.new(0, 0.2, 0),
	Color3.fromRGB(255, 240, 245), Enum.Material.Marble)
part("LobbyGoldCenter", Vector3.new(18, 0.5, 18), LOBBY_CENTER + Vector3.new(0, 0.35, 0),
	Color3.fromRGB(220, 170, 160), Enum.Material.Marble)
part("LobbyStar1", Vector3.new(12, 0.52, 3), LOBBY_CENTER + Vector3.new(0, 0.36, 0),
	Color3.fromRGB(230, 180, 170), Enum.Material.Marble)
part("LobbyStar2", Vector3.new(3, 0.52, 12), LOBBY_CENTER + Vector3.new(0, 0.36, 0),
	Color3.fromRGB(230, 180, 170), Enum.Material.Marble)

-- ============================================================
-- GLASS CURTAIN WALLS — semi-transparent, city visible through
-- ============================================================
local GLASS_CLR = Color3.fromRGB(50, 70, 90)
local STEEL_CLR = Color3.fromRGB(28, 30, 36)
local GLASS_H   = 40  -- full height of glass section

-- North wall split with 30-stud doorway gap in the center
part("GlassNL", Vector3.new(46, GLASS_H, 0.5), Vector3.new(-38, GLASS_H/2, 19),
	GLASS_CLR, Enum.Material.Glass, nil, {Transparency=0.25, CanCollide=true})
part("GlassNR", Vector3.new(46, GLASS_H, 0.5), Vector3.new(38, GLASS_H/2, 19),
	GLASS_CLR, Enum.Material.Glass, nil, {Transparency=0.25, CanCollide=true})
part("GlassS", Vector3.new(122, GLASS_H, 0.5), Vector3.new(0, GLASS_H/2, 141),
	GLASS_CLR, Enum.Material.Glass, nil, {Transparency=0.25, CanCollide=true})
part("GlassE", Vector3.new(0.5, GLASS_H, 122), Vector3.new(61, GLASS_H/2, 80),
	GLASS_CLR, Enum.Material.Glass, nil, {Transparency=0.25, CanCollide=true})
part("GlassW", Vector3.new(0.5, GLASS_H, 122), Vector3.new(-61, GLASS_H/2, 80),
	GLASS_CLR, Enum.Material.Glass, nil, {Transparency=0.25, CanCollide=true})

-- Vertical steel mullions every 20 studs
for _, x in ipairs({-60,-40,-20,0,20,40,60}) do
	part("MullionN_"..x, Vector3.new(1,GLASS_H,1), Vector3.new(x, GLASS_H/2, 19),
		STEEL_CLR, Enum.Material.Metal, nil, {Reflectance=0.1})
	part("MullionS_"..x, Vector3.new(1,GLASS_H,1), Vector3.new(x, GLASS_H/2, 141),
		STEEL_CLR, Enum.Material.Metal, nil, {Reflectance=0.1})
end
for _, z in ipairs({20,40,60,80,100,120,140}) do
	part("MullionE_"..z, Vector3.new(1,GLASS_H,1), Vector3.new(61, GLASS_H/2, z),
		STEEL_CLR, Enum.Material.Metal, nil, {Reflectance=0.1})
	part("MullionW_"..z, Vector3.new(1,GLASS_H,1), Vector3.new(-61, GLASS_H/2, z),
		STEEL_CLR, Enum.Material.Metal, nil, {Reflectance=0.1})
end

-- ============================================================
-- BUILDING FACADE — solid concrete above glass (Y=40 to Y=120)
-- ============================================================
local CONCRETE  = Color3.fromRGB(38, 40, 48)
local FACADE_H  = 80
local FACADE_Y  = 40 + FACADE_H / 2   -- = 80

part("FacadeN", Vector3.new(124,FACADE_H,2), Vector3.new(0, FACADE_Y, 18),
	CONCRETE, Enum.Material.SmoothPlastic)
part("FacadeS", Vector3.new(124,FACADE_H,2), Vector3.new(0, FACADE_Y, 142),
	CONCRETE, Enum.Material.SmoothPlastic)
part("FacadeE", Vector3.new(2,FACADE_H,124), Vector3.new(62, FACADE_Y, 80),
	CONCRETE, Enum.Material.SmoothPlastic)
part("FacadeW", Vector3.new(2,FACADE_H,124), Vector3.new(-62, FACADE_Y, 80),
	CONCRETE, Enum.Material.SmoothPlastic)

-- Horizontal window bands on facade every 12 studs
local WIN_CLR = Color3.fromRGB(140, 170, 200)
for y = 50, 116, 12 do
	part("WinN_"..y, Vector3.new(120,5,0.4), Vector3.new(0, y, 17.8),
		WIN_CLR, Enum.Material.Glass, nil, {Transparency=0.35})
	part("WinS_"..y, Vector3.new(120,5,0.4), Vector3.new(0, y, 142.2),
		WIN_CLR, Enum.Material.Glass, nil, {Transparency=0.35})
	part("WinE_"..y, Vector3.new(0.4,5,120), Vector3.new(62.2, y, 80),
		WIN_CLR, Enum.Material.Glass, nil, {Transparency=0.35})
	part("WinW_"..y, Vector3.new(0.4,5,120), Vector3.new(-62.2, y, 80),
		WIN_CLR, Enum.Material.Glass, nil, {Transparency=0.35})
end

-- ============================================================
-- COLUMNS — Art Deco, full height Y=0 to Y=40
-- ============================================================
local colPos = {
	Vector3.new(-40, 0, 40),  Vector3.new(40, 0, 40),
	Vector3.new(-40, 0, 70),  Vector3.new(40, 0, 70),
	Vector3.new(-40, 0, 90),  Vector3.new(40, 0, 90),
	Vector3.new(-40, 0, 120), Vector3.new(40, 0, 120),
}
for i, cp in ipairs(colPos) do
	part("ColumnShaft_"..i,   Vector3.new(2,40,2),     cp + Vector3.new(0, 20, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.25})
	part("ColumnBase_"..i,    Vector3.new(3,0.8,3),    cp + Vector3.new(0, 0.4, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.25})
	part("ColumnBand_"..i,    Vector3.new(3.2,1.2,3.2), cp + Vector3.new(0, 22, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.35})
	part("ColumnCapital_"..i, Vector3.new(3.5,0.8,3.5), cp + Vector3.new(0, 40.4, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.35})
end

-- ============================================================
-- GLASS ATRIUM CEILING at Y=40
-- ============================================================
part("AtriumGlass", Vector3.new(120,0.4,120), LOBBY_CENTER + Vector3.new(0, 40, 0),
	Color3.fromRGB(60,80,110), Enum.Material.Glass, nil, {Transparency=0.35})

-- Rose gold frame grid (strips every 20 studs)
for _, x in ipairs({-40,-20,0,20,40}) do
	part("AtriumFX_"..x, Vector3.new(0.8,0.8,120), LOBBY_CENTER + Vector3.new(x, 39.8, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
end
for _, z in ipairs({-40,-20,0,20,40}) do
	part("AtriumFZ_"..z, Vector3.new(120,0.8,0.8), LOBBY_CENTER + Vector3.new(0, 39.8, z),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
end
-- Border
part("AtriumBdrN", Vector3.new(120,1.5,1.5), LOBBY_CENTER + Vector3.new(0, 39.6, -59),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
part("AtriumBdrS", Vector3.new(120,1.5,1.5), LOBBY_CENTER + Vector3.new(0, 39.6, 59),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
part("AtriumBdrE", Vector3.new(1.5,1.5,120), LOBBY_CENTER + Vector3.new(59, 39.6, 0),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
part("AtriumBdrW", Vector3.new(1.5,1.5,120), LOBBY_CENTER + Vector3.new(-59, 39.6, 0),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})

-- ============================================================
-- MEZZANINE BALCONY at Y=22 — dark marble ring around perimeter
-- ============================================================
local MZ = 22.5   -- mezzanine Y center
local MZ_CLR = Color3.fromRGB(35, 18, 35)
part("MezzN", Vector3.new(122,1,14), Vector3.new(0, MZ, 26),   MZ_CLR, Enum.Material.Marble)
part("MezzS", Vector3.new(122,1,14), Vector3.new(0, MZ, 134),  MZ_CLR, Enum.Material.Marble)
part("MezzE", Vector3.new(12,1,94),  Vector3.new(55, MZ, 80),  MZ_CLR, Enum.Material.Marble)
part("MezzW", Vector3.new(12,1,94),  Vector3.new(-55, MZ, 80), MZ_CLR, Enum.Material.Marble)

-- Mezzanine railing (inner edge)
local RL = MZ + 1.5   -- rail Y
part("MRailN", Vector3.new(98,0.3,0.3), Vector3.new(0, RL, 33),  ROSE_GOLD, Enum.Material.Metal, nil, {CanCollide=false, Reflectance=0.3})
part("MRailS", Vector3.new(98,0.3,0.3), Vector3.new(0, RL, 127), ROSE_GOLD, Enum.Material.Metal, nil, {CanCollide=false, Reflectance=0.3})
part("MRailE", Vector3.new(0.3,0.3,94),Vector3.new(49, RL, 80),  ROSE_GOLD, Enum.Material.Metal, nil, {CanCollide=false, Reflectance=0.3})
part("MRailW", Vector3.new(0.3,0.3,94),Vector3.new(-49, RL, 80), ROSE_GOLD, Enum.Material.Metal, nil, {CanCollide=false, Reflectance=0.3})
for _, x in ipairs({-40,-20,0,20,40}) do
	part("MPostN_"..x, Vector3.new(0.3,3,0.3), Vector3.new(x, MZ+1.5, 33),  ROSE_GOLD, Enum.Material.Metal, nil, {CanCollide=false})
	part("MPostS_"..x, Vector3.new(0.3,3,0.3), Vector3.new(x, MZ+1.5, 127), ROSE_GOLD, Enum.Material.Metal, nil, {CanCollide=false})
end
for _, z in ipairs({40,60,80,100,120}) do
	part("MPostE_"..z, Vector3.new(0.3,3,0.3), Vector3.new(49, MZ+1.5, z),  ROSE_GOLD, Enum.Material.Metal, nil, {CanCollide=false})
	part("MPostW_"..z, Vector3.new(0.3,3,0.3), Vector3.new(-49, MZ+1.5, z), ROSE_GOLD, Enum.Material.Metal, nil, {CanCollide=false})
end

-- ============================================================
-- UPPER FLOORS visible through atrium glass
-- ============================================================
for fi, fy in ipairs({50, 62, 74}) do
	part("UpperFloor_"..fi, Vector3.new(118,0.5,118), Vector3.new(0, fy, 80),
		Color3.fromRGB(50,35,50), Enum.Material.SmoothPlastic, nil, {Transparency=0.3})
	part("FloorLight_"..fi, Vector3.new(80,0.2,80), Vector3.new(0, fy-0.4, 80),
		Color3.fromRGB(255,230,210), Enum.Material.Neon, nil, {Transparency=0.75})
end

-- ============================================================
-- READY ZONE at (0, 0, 50)
-- ============================================================
local GOLD_COLOR = Color3.fromRGB(220, 170, 120)
local DARK_RED   = Color3.fromRGB(120, 20, 30)

part("ReadyZoneFloor", Vector3.new(30,0.3,30), Vector3.new(0, 0.35, 50),
	Color3.fromRGB(200, 165, 100), Enum.Material.SmoothPlastic)
local postPos = {
	Vector3.new(-15,1.5,35), Vector3.new(0,1.5,35), Vector3.new(15,1.5,35),
	Vector3.new(-15,1.5,65), Vector3.new(0,1.5,65), Vector3.new(15,1.5,65),
	Vector3.new(-15,1.5,50), Vector3.new(15,1.5,50),
}
for i, pp in ipairs(postPos) do
	part("RopePost_"..i, Vector3.new(0.4,3,0.4), pp,
		GOLD_COLOR, Enum.Material.Metal, nil, {CanCollide=false, Reflectance=0.3})
	part("RopePostCap_"..i, Vector3.new(0.7,0.7,0.7), pp + Vector3.new(0, 1.55, 0),
		GOLD_COLOR, Enum.Material.Metal, nil, {CanCollide=false, Reflectance=0.3, Shape=Enum.PartType.Ball})
end
part("RopeN", Vector3.new(30.2,0.15,0.15), Vector3.new(0, 2.6, 35),  DARK_RED, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
part("RopeS", Vector3.new(30.2,0.15,0.15), Vector3.new(0, 2.6, 65),  DARK_RED, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
part("RopeW", Vector3.new(0.15,0.15,30.2), Vector3.new(-15, 2.6, 50), DARK_RED, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
part("RopeE", Vector3.new(0.15,0.15,30.2), Vector3.new(15, 2.6, 50),  DARK_RED, Enum.Material.SmoothPlastic, nil, {CanCollide=false})

-- ============================================================
-- CARPET RUNNER
-- ============================================================
part("CarpetRunner", Vector3.new(6,0.1,30), Vector3.new(0, 0.55, 65),
	Color3.fromRGB(220, 80, 130), Enum.Material.Fabric)

print("[MapSetup_Lobby] Skyscraper structure built")
