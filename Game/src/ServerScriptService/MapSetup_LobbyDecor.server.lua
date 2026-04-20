-- MapSetup_LobbyDecor.server.lua — Lobby DECORATIONS
-- Builds: chandeliers, Style Bar, Photo Booth, velvet sofas, neon sign, ambient decor
-- Must run AFTER MapSetup_Lobby.server.lua (waits for mapFolder)

local LOBBY_CENTER = Vector3.new(0, 0, 80)

-- Wait for the map folder (created by MapSetup.server.lua or MapSetup_Lobby.server.lua)
local mapFolder = workspace:WaitForChild("DressToSurviveMap", 15)
if not mapFolder then
	warn("[MapSetup_LobbyDecor] DressToSurviveMap not found — decorations skipped")
	return
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

local function addLight(parent, lightType, props)
	local light = Instance.new(lightType)
	for k, v in pairs(props) do light[k] = v end
	light.Parent = parent
	return light
end

local ROSE_GOLD = Color3.fromRGB(200, 150, 120)

-- ============================================================
-- CHANDELIERS (4) — hung from ceiling at Y=20.8
-- ============================================================
local chandelierPositions = {
	Vector3.new(-28, 20.8, 60),
	Vector3.new( 28, 20.8, 60),
	Vector3.new(-28, 20.8, 100),
	Vector3.new( 28, 20.8, 100),
}
for i, cp in ipairs(chandelierPositions) do
	-- Mounting disk (ceiling attachment)
	part("ChanBase_"..i, Vector3.new(5, 0.4, 5), cp,
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.3})
	-- Stem
	part("ChanStem_"..i, Vector3.new(0.5, 4, 0.5), cp + Vector3.new(0, -2, 0),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance = 0.3})
	-- Crystal tiers (translucent lavender)
	part("ChanTier1_"..i, Vector3.new(9, 0.4, 9),   cp + Vector3.new(0, -4.2, 0),
		Color3.fromRGB(230, 210, 255), Enum.Material.SmoothPlastic, nil, {Transparency = 0.4})
	part("ChanTier2_"..i, Vector3.new(7, 0.4, 7),   cp + Vector3.new(0, -5.0, 0),
		Color3.fromRGB(230, 210, 255), Enum.Material.SmoothPlastic, nil, {Transparency = 0.4})
	local tier3 = part("ChanTier3_"..i, Vector3.new(5, 0.4, 5), cp + Vector3.new(0, -5.8, 0),
		Color3.fromRGB(240, 220, 255), Enum.Material.SmoothPlastic, nil, {Transparency = 0.3})
	-- Point light inside the lowest tier
	addLight(tier3, "PointLight", {
		Color = Color3.fromRGB(255, 230, 200),
		Brightness = 3,
		Range = 28,
	})
end

-- ============================================================
-- STYLE BAR — back-left wall (Layout B)
-- RACK_BASE: X=-55, Z=120 (LOBBY_CENTER offset: -55, 0, +40)
-- LobbyClothesRack.server.lua auto-connects items via AssetId attribute
-- ============================================================
local RACK_BASE = Vector3.new(-55, 0, 120)

-- Back wall panel
part("StyleBarWall", Vector3.new(0.5, 22, 76), RACK_BASE + Vector3.new(0, 11, 0),
	Color3.fromRGB(30, 12, 25), Enum.Material.SmoothPlastic)

-- "STYLE BAR" sign
local styleSign = part("StyleBarSign", Vector3.new(0.3, 2, 18), RACK_BASE + Vector3.new(0.5, 13, 0),
	Color3.fromRGB(255, 100, 180), Enum.Material.Neon)
local signGui = Instance.new("SurfaceGui")
signGui.Face = Enum.NormalId.Right
signGui.CanvasSize = Vector2.new(400, 60)
signGui.Parent = styleSign
local signLabel = Instance.new("TextLabel")
signLabel.Size = UDim2.new(1, 0, 1, 0)
signLabel.BackgroundTransparency = 1
signLabel.Text = "✦ STYLE BAR ✦"
signLabel.TextColor3 = Color3.fromRGB(255, 220, 240)
signLabel.TextScaled = true
signLabel.Font = Enum.Font.GothamBold
signLabel.Parent = signGui

-- Floor strip
part("RackFloor", Vector3.new(5, 0.3, 76), RACK_BASE + Vector3.new(2, 0.15, 0),
	Color3.fromRGB(240, 220, 235), Enum.Material.SmoothPlastic)

-- Item catalogue
local rackItems = {
	-- === BOTTOM ROW (hangs from lower bar at Y=4.5) ===
	{z=-35, name="Pink Hoodie",       assetId=607785314,  category="Shirt",   color=Color3.fromRGB(255,150,180), shape="shirt",     row="bottom"},
	{z=-30, name="Red Roblox Shirt",  assetId=855776799,  category="Shirt",   color=Color3.fromRGB(220,80,80),   shape="shirt",     row="bottom"},
	{z=-25, name="Classic Girl Top",  assetId=6163806327, category="Shirt",   color=Color3.fromRGB(220,180,255), shape="shirt",     row="bottom"},
	{z=-20, name="White Classic Top", assetId=5765003313, category="Shirt",   color=Color3.fromRGB(240,240,245), shape="shirt",     row="bottom"},
	{z=-10, name="Red Roblox Pants",  assetId=855782781,  category="Pants",   color=Color3.fromRGB(200,70,70),   shape="pants",     row="bottom"},
	{z=-5,  name="Classic Girl Pants",assetId=6163812828, category="Pants",   color=Color3.fromRGB(180,150,220), shape="pants",     row="bottom"},
	{z=0,   name="Cute Jean Shorts",  assetId=382537950,  category="Pants",   color=Color3.fromRGB(130,160,210), shape="pants",     row="bottom"},
	{z=10,  name="Glam Cape",         assetId=4047558048, category="Back",    color=Color3.fromRGB(200,80,120),  shape="accessory", row="bottom"},
	{z=15,  name="Dark Hoodie",       assetId=607785314,  category="Shirt",   color=Color3.fromRGB(60,60,65),    shape="shirt",     row="bottom"},
	{z=20,  name="Red Classic Top",   assetId=855776799,  category="Shirt",   color=Color3.fromRGB(180,80,80),   shape="shirt",     row="bottom"},
	{z=25,  name="Dark Jeans",        assetId=855782781,  category="Pants",   color=Color3.fromRGB(40,40,45),    shape="pants",     row="bottom"},
	{z=30,  name="Purple Pants",      assetId=6163812828, category="Pants",   color=Color3.fromRGB(100,80,140),  shape="pants",     row="bottom"},
	{z=35,  name="Red Cape",          assetId=4047558048, category="Back",    color=Color3.fromRGB(200,60,80),   shape="accessory", row="bottom"},
	-- === TOP ROW (hangs from upper bar at Y=9) ===
	{z=-35, name="Black Classic Top", assetId=5765045564, category="Shirt",   color=Color3.fromRGB(50,50,55),    shape="shirt",     row="top"},
	{z=-30, name="Classic White Tee", assetId=5765032559, category="TShirts", color=Color3.fromRGB(245,245,250), shape="shirt",     row="top"},
	{z=-20, name="Kitty Ears",        assetId=1028606,    category="Hats",    color=Color3.fromRGB(255,180,200), shape="hat",       row="top"},
	{z=-15, name="Bow",               assetId=1365767,    category="Hats",    color=Color3.fromRGB(255,100,150), shape="hat",       row="top"},
	{z=-5,  name="Wavy Side Hair",    assetId=4819740796, category="Hair",    color=Color3.fromRGB(160,100,60),  shape="hat",       row="top"},
	{z=0,   name="Popstar Hair",      assetId=376549236,  category="Hair",    color=Color3.fromRGB(180,130,80),  shape="hat",       row="top"},
	{z=5,   name="Brown Charmer Hair",assetId=376548738,  category="Hair",    color=Color3.fromRGB(110,70,40),   shape="hat",       row="top"},
	{z=10,  name="Blonde Braid",      assetId=4819740796, category="Hair",    color=Color3.fromRGB(230,200,120), shape="hat",       row="top"},
	{z=15,  name="Pink Bow",          assetId=1365767,    category="Hats",    color=Color3.fromRGB(255,140,180), shape="hat",       row="top"},
	{z=20,  name="Cat Ears",          assetId=1028606,    category="Hats",    color=Color3.fromRGB(255,100,150), shape="hat",       row="top"},
	{z=25,  name="Blonde Popstar",    assetId=376549236,  category="Hair",    color=Color3.fromRGB(230,190,100), shape="hat",       row="top"},
	{z=30,  name="Fashion Cape",      assetId=4047558048, category="Back",    color=Color3.fromRGB(200,50,50),   shape="accessory", row="top"},
	{z=35,  name="Charmer Hair",      assetId=376548738,  category="Hair",    color=Color3.fromRGB(60,40,30),    shape="hat",       row="top"},
}

-- Section labels
local sectionLabels = {
	{z=-28, y=5.5,  text="TOPS"},
	{z=-5,  y=5.5,  text="BOTTOMS"},
	{z=10,  y=5.5,  text="ACCESSORIES"},
	{z=-33, y=10.5, text="TOPS"},
	{z=-18, y=10.5, text="HATS"},
	{z=-2,  y=10.5, text="HAIR"},
	{z=22,  y=5.5,  text="MORE STYLES"},
	{z=22,  y=10.5, text="ACCESSORIES"},
}
for _, sec in ipairs(sectionLabels) do
	local divider = part("RackSec_"..sec.text.."_"..sec.y, Vector3.new(0.2, 1.2, 0.2),
		RACK_BASE + Vector3.new(2.5, sec.y, sec.z),
		Color3.fromRGB(255,150,200), Enum.Material.Neon)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Right
	sg.CanvasSize = Vector2.new(200, 60)
	sg.Parent = divider
	local sl = Instance.new("TextLabel")
	sl.Size = UDim2.new(1,0,1,0)
	sl.BackgroundTransparency = 1
	sl.Text = sec.text
	sl.TextColor3 = Color3.fromRGB(255,200,230)
	sl.TextScaled = true
	sl.Font = Enum.Font.GothamBold
	sl.Parent = sg
end

-- Rack bars and poles
part("RackBarTop", Vector3.new(0.4, 0.4, 74), RACK_BASE + Vector3.new(2, 9, 0),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
part("RackBarLow", Vector3.new(0.4, 0.4, 74), RACK_BASE + Vector3.new(2, 4.5, 0),
	ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
for _, pz in ipairs({-36,-18,0,18,36}) do
	part("RackPole_"..pz, Vector3.new(0.5,10,0.5), RACK_BASE + Vector3.new(2, 5, pz),
		ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
end

-- Build clickable items
for i, item in ipairs(rackItems) do
	local isTop = (item.row == "top")
	local rowOffset = isTop and 4.5 or 0
	local itemPos = RACK_BASE + Vector3.new(2, 0, item.z)

	if item.shape == "shirt" then
		part("Hanger_"..i, Vector3.new(2.5,0.15,0.15), itemPos + Vector3.new(0, 4.5+rowOffset, 0),
			Color3.fromRGB(200,180,170), Enum.Material.Metal)
		local sp = part("RackShirt_"..i, Vector3.new(1.8,3,0.4), itemPos + Vector3.new(0, 2.5+rowOffset, 0),
			item.color, Enum.Material.Fabric)
		part("RackSlvL_"..i, Vector3.new(1.2,0.4,0.35), itemPos + Vector3.new(-1.4, 3.5+rowOffset, 0),
			item.color, Enum.Material.Fabric)
		part("RackSlvR_"..i, Vector3.new(1.2,0.4,0.35), itemPos + Vector3.new(1.4, 3.5+rowOffset, 0),
			item.color, Enum.Material.Fabric)
		local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance=12; cd.Parent=sp
		sp:SetAttribute("AssetId", item.assetId)
		sp:SetAttribute("Category", item.category)
		sp:SetAttribute("ItemName", item.name)

	elseif item.shape == "pants" then
		local pp = part("RackPants_"..i, Vector3.new(1.5,0.5,2), itemPos + Vector3.new(0, 0.3+rowOffset, 0),
			item.color, Enum.Material.Fabric)
		part("PantsFold_"..i, Vector3.new(1.3,0.3,1.8), itemPos + Vector3.new(0, 0.7+rowOffset, 0),
			item.color, Enum.Material.Fabric)
		local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance=12; cd.Parent=pp
		pp:SetAttribute("AssetId", item.assetId)
		pp:SetAttribute("Category", item.category)
		pp:SetAttribute("ItemName", item.name)

	elseif item.shape == "hat" then
		local shelfY = 0 + rowOffset
		part("HatShelf_"..i, Vector3.new(2,0.2,2), itemPos + Vector3.new(0, shelfY, 0),
			Color3.fromRGB(240,220,230), Enum.Material.SmoothPlastic)
		part("HatNeck_"..i, Vector3.new(0.5,1,0.5), itemPos + Vector3.new(0, shelfY+0.7, 0),
			Color3.fromRGB(240,220,210), Enum.Material.SmoothPlastic)
		part("HatMannHead_"..i, Vector3.new(1,1,1), itemPos + Vector3.new(0, shelfY+1.7, 0),
			Color3.fromRGB(240,220,210), Enum.Material.SmoothPlastic, nil, {Shape=Enum.PartType.Ball})
		local hp
		if item.category == "Hats" then
			hp = part("RackHat_"..i, Vector3.new(1.6,0.5,1.6), itemPos + Vector3.new(0, shelfY+2.4, 0),
				item.color, Enum.Material.SmoothPlastic)
			part("HatBrim_"..i, Vector3.new(2,0.1,1.2), itemPos + Vector3.new(0, shelfY+2.2, 0.5),
				item.color, Enum.Material.SmoothPlastic)
		else
			hp = part("RackHat_"..i, Vector3.new(1.2,1.2,1.2), itemPos + Vector3.new(0, shelfY+2.5, 0),
				item.color, Enum.Material.SmoothPlastic, nil, {Shape=Enum.PartType.Ball})
		end
		local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance=12; cd.Parent=hp
		hp:SetAttribute("AssetId", item.assetId)
		hp:SetAttribute("Category", item.category)
		hp:SetAttribute("ItemName", item.name)

	elseif item.shape == "accessory" then
		local shelfY = 0.4 + rowOffset
		part("AccShelf_"..i, Vector3.new(2.2,0.8,2.2), itemPos + Vector3.new(0, shelfY, 0),
			Color3.fromRGB(240,220,230), Enum.Material.SmoothPlastic)
		local ap = part("RackAcc_"..i, Vector3.new(1,1,1), itemPos + Vector3.new(0, shelfY+0.9, 0),
			item.color, Enum.Material.SmoothPlastic, nil, {Reflectance=0.3})
		local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance=12; cd.Parent=ap
		ap:SetAttribute("AssetId", item.assetId)
		ap:SetAttribute("Category", item.category)
		ap:SetAttribute("ItemName", item.name)
	end
end

-- Shoe display
local shoeItems = {
	{z=-34, name="Hot Pink Sneakers", assetId=382537950,  category="Pants", color=Color3.fromRGB(255,20,147),  accent=Color3.fromRGB(200,0,100),  shelf=0},
	{z=-27, name="Classic Red Heels", assetId=855782781,  category="Pants", color=Color3.fromRGB(230,20,20),   accent=Color3.fromRGB(160,10,10),  shelf=0},
	{z=-20, name="Neon Green Kicks",  assetId=6163812828, category="Pants", color=Color3.fromRGB(50,255,100),  accent=Color3.fromRGB(30,180,60),  shelf=0},
	{z=-34, name="White Boots",       assetId=382537950,  category="Pants", color=Color3.fromRGB(255,255,255), accent=Color3.fromRGB(220,200,210), shelf=1},
	{z=-27, name="Purple Platforms",  assetId=855782781,  category="Pants", color=Color3.fromRGB(160,80,220),  accent=Color3.fromRGB(100,40,160), shelf=1},
	{z=-20, name="Gold Stilettos",    assetId=6163812828, category="Pants", color=Color3.fromRGB(255,200,50),  accent=Color3.fromRGB(180,140,30), shelf=1},
}
part("ShoeBackPanel", Vector3.new(0.5,7,22), RACK_BASE + Vector3.new(0.3,4,-27),
	Color3.fromRGB(240,220,235), Enum.Material.SmoothPlastic)
for tier = 0, 1 do
	local shelfPart = part("ShoeShelf_"..tier, Vector3.new(6,0.3,22),
		RACK_BASE + Vector3.new(2.5, 1.5+tier*3, -27),
		Color3.fromRGB(230,180,165), Enum.Material.SmoothPlastic, nil, {Reflectance=0.3})
	addLight(shelfPart, "PointLight", {Color=Color3.fromRGB(255,240,250), Brightness=0.8, Range=8})
end
for si, shoe in ipairs(shoeItems) do
	local shelfY = 1.5 + shoe.shelf * 3
	local shoeTopY = shelfY + 0.9
	local soleY = shelfY + 0.25
	local leftShoe = part("Shoe_"..si.."L", Vector3.new(2,1.5,3), RACK_BASE + Vector3.new(1.5, shoeTopY, shoe.z),
		shoe.color, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
	local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance=15; cd.Parent=leftShoe
	leftShoe:SetAttribute("AssetId", shoe.assetId)
	leftShoe:SetAttribute("Category", shoe.category)
	leftShoe:SetAttribute("ItemName", shoe.name)
	part("Shoe_"..si.."R", Vector3.new(2,1.5,3), RACK_BASE + Vector3.new(3.5, shoeTopY, shoe.z),
		shoe.color, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
	part("ShoeSole_"..si.."L", Vector3.new(2.05,0.2,3.05), RACK_BASE + Vector3.new(1.5, soleY, shoe.z),
		shoe.accent, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
	part("ShoeSole_"..si.."R", Vector3.new(2.05,0.2,3.05), RACK_BASE + Vector3.new(3.5, soleY, shoe.z),
		shoe.accent, Enum.Material.SmoothPlastic, nil, {CanCollide=false})
end

-- ============================================================
-- PHOTO BOOTH — back-right wall (Layout B)
-- ============================================================
local BOOTH_CENTER = Vector3.new(45, 0, 120)

-- Backdrop wall (bright pink, against back wall Z=140)
local backdrop = part("PhotoBoothBackdrop", Vector3.new(22, 14, 0.5), BOOTH_CENTER + Vector3.new(0, 7, 19.8),
	Color3.fromRGB(255, 80, 170), Enum.Material.SmoothPlastic)
local bGui = Instance.new("SurfaceGui")
bGui.Face = Enum.NormalId.Front
bGui.CanvasSize = Vector2.new(500, 160)
bGui.Parent = backdrop
local bLabel = Instance.new("TextLabel")
bLabel.Size = UDim2.new(1,0,0.4,0)
bLabel.BackgroundTransparency = 1
bLabel.Text = "✦ PHOTO BOOTH ✦"
bLabel.TextColor3 = Color3.fromRGB(255, 240, 255)
bLabel.TextScaled = true
bLabel.Font = Enum.Font.GothamBold
bLabel.Parent = bGui

-- Side frame panels
part("BoothFrameL", Vector3.new(0.5,14,20), BOOTH_CENTER + Vector3.new(-11, 7, 10),
	Color3.fromRGB(180, 60, 140), Enum.Material.SmoothPlastic)
part("BoothFrameR", Vector3.new(0.5,14,20), BOOTH_CENTER + Vector3.new(11, 7, 10),
	Color3.fromRGB(180, 60, 140), Enum.Material.SmoothPlastic)
-- Floor area
part("BoothFloor", Vector3.new(22,0.2,20), BOOTH_CENTER + Vector3.new(0, 0.1, 10),
	Color3.fromRGB(255, 180, 220), Enum.Material.SmoothPlastic)
-- Spotlight from above
local boothLight = part("BoothSpotAnchor", Vector3.new(0.3,0.3,0.3), BOOTH_CENTER + Vector3.new(0,20,10),
	Color3.new(1,1,1), Enum.Material.SmoothPlastic, nil, {Transparency=1})
addLight(boothLight, "SpotLight", {
	Face=Enum.NormalId.Bottom,
	Color=Color3.fromRGB(255,200,240), Brightness=1.5, Range=22, Angle=60,
})

-- ============================================================
-- VELVET SOFAS — 2 left wall, 2 right wall
-- ============================================================
local MAROON = Color3.fromRGB(110, 20, 45)

-- Left sofas: seat at X=-57, back at X=-59.5 (against X=-60 wall), facing right
for i, zpos in ipairs({70, 90}) do
	part("SofaSeatL_"..i, Vector3.new(5,1.5,2.5), Vector3.new(-57, 0.75, zpos), MAROON, Enum.Material.Fabric)
	part("SofaBackL_"..i, Vector3.new(0.8,3,2.5), Vector3.new(-59.5, 1.5, zpos), MAROON, Enum.Material.Fabric)
	part("SofaArmFL_"..i, Vector3.new(5.2,2,0.5), Vector3.new(-57, 1, zpos-1.5), MAROON, Enum.Material.Fabric)
	part("SofaArmBL_"..i, Vector3.new(5.2,2,0.5), Vector3.new(-57, 1, zpos+1.5), MAROON, Enum.Material.Fabric)
	for _, lz in ipairs({zpos-1, zpos+1}) do
		part("SofaLegFL_"..i.."_"..lz, Vector3.new(0.4,0.5,0.4), Vector3.new(-55, 0.25, lz),
			ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
		part("SofaLegBL_"..i.."_"..lz, Vector3.new(0.4,0.5,0.4), Vector3.new(-59, 0.25, lz),
			ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
	end
end
-- Right sofas: seat at X=57, back at X=59.5 (against X=60 wall), facing left
for i, zpos in ipairs({70, 90}) do
	part("SofaSeatR_"..i, Vector3.new(5,1.5,2.5), Vector3.new(57, 0.75, zpos), MAROON, Enum.Material.Fabric)
	part("SofaBackR_"..i, Vector3.new(0.8,3,2.5), Vector3.new(59.5, 1.5, zpos), MAROON, Enum.Material.Fabric)
	part("SofaArmFR_"..i, Vector3.new(5.2,2,0.5), Vector3.new(57, 1, zpos-1.5), MAROON, Enum.Material.Fabric)
	part("SofaArmBR_"..i, Vector3.new(5.2,2,0.5), Vector3.new(57, 1, zpos+1.5), MAROON, Enum.Material.Fabric)
	for _, lz in ipairs({zpos-1, zpos+1}) do
		part("SofaLegFR_"..i.."_"..lz, Vector3.new(0.4,0.5,0.4), Vector3.new(55, 0.25, lz),
			ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
		part("SofaLegBR_"..i.."_"..lz, Vector3.new(0.4,0.5,0.4), Vector3.new(59, 0.25, lz),
			ROSE_GOLD, Enum.Material.Metal, nil, {Reflectance=0.3})
	end
end

-- ============================================================
-- NEON SIGN — back wall, center
-- ============================================================
local neonSign = part("MainNeonSign", Vector3.new(50, 5, 0.5), LOBBY_CENTER + Vector3.new(0, 12, 59.8),
	Color3.fromRGB(255, 80, 160), Enum.Material.Neon)
local nGui = Instance.new("SurfaceGui")
nGui.Face = Enum.NormalId.Front
nGui.CanvasSize = Vector2.new(800, 100)
nGui.Parent = neonSign
local nLabel = Instance.new("TextLabel")
nLabel.Size = UDim2.new(1,0,1,0)
nLabel.BackgroundTransparency = 1
nLabel.Text = "DRESS TO SURVIVE"
nLabel.TextColor3 = Color3.fromRGB(255, 240, 255)
nLabel.TextScaled = true
nLabel.Font = Enum.Font.GothamBold
nLabel.Parent = nGui

-- ============================================================
-- AMBIENT DECOR — balloon clusters at corner columns
-- ============================================================
local balloonColors = {
	Color3.fromRGB(255,150,200), Color3.fromRGB(255,180,220),
	Color3.fromRGB(220,130,255), Color3.fromRGB(255,200,240),
}
local balloonAnchors = {
	Vector3.new(-40, 0, 40), Vector3.new(40, 0, 40),
	Vector3.new(-40, 0, 120), Vector3.new(40, 0, 120),
}
for ci, ba in ipairs(balloonAnchors) do
	for b = 1, 3 do
		local bx = (b - 2) * 1.5
		local bz = (b == 2) and 1 or 0
		part("Balloon_"..ci.."_"..b, Vector3.new(1.2,1.4,1.2),
			ba + Vector3.new(bx + 2, 4 + b * 1.2, bz + 2),
			balloonColors[((ci + b - 2) % 4) + 1], Enum.Material.SmoothPlastic,
			nil, {Shape=Enum.PartType.Ball, CanCollide=false})
	end
end

print("[MapSetup_LobbyDecor] Decorations built")
