-- HUD: hotbar, stat bars, notifications, backpack panel, starter-kit shop, and
-- the extraction victory banner (all built from code)
--
-- Snapshot convention: InventoryUpdate delivers {hotbar, backpack, equipped}
-- where empty slots are `false` (dense arrays survive remote serialization).
-- Interaction.client.lua keeps its OWN copy via its own InventoryUpdate
-- listener; HUD state is not shared between the two scripts.
--
-- Kits: the "Kits" button (top-right) toggles a list of Config.STARTER_KITS.
-- Owned state comes from the `OwnedKits` player attribute (a comma-joined string
-- of kit ids that ProgressService sets); a Buy button fires BuyKit and flips to
-- "Owned" once the attribute reflects the purchase.
--
-- Victory banner: RunFinished delivers { elapsed, reward, completions, bestTime }
-- and shows a centered banner for BANNER_DURATION seconds. A token guards the
-- hide timer so a second RunFinished can't hide a fresher banner early.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ItemDefs = require(ReplicatedStorage:WaitForChild("ItemDefs"))
local RemoteSetup = require(ReplicatedStorage:WaitForChild("RemoteSetup"))
local Remotes = RemoteSetup.Get()

local LocalPlayer = Players.LocalPlayer

-- ===== Constants =====
local SLOT_SIZE = 48
local SLOT_GAP = 6
local SLOT_COLOR = Color3.fromRGB(25, 25, 30)
local SLOT_TRANSPARENCY = 0.35
local SLOT_CORNER_RADIUS = 6
local EQUIP_STROKE_COLOR = Color3.fromRGB(255, 255, 255)
local EQUIP_STROKE_THICKNESS = 2
local TEXT_COLOR = Color3.fromRGB(230, 230, 230)
local DIM_TEXT_COLOR = Color3.fromRGB(160, 160, 160)

local BAR_WIDTH = 220
local BAR_HEIGHT = 14
local BAR_GAP = 4
local BAR_BG_COLOR = Color3.fromRGB(18, 18, 22)
local HUNGER_COLOR = Color3.fromRGB(235, 150, 40)
local WARMTH_COLOR = Color3.fromRGB(70, 200, 235)
local LOW_FLASH_COLOR = Color3.fromRGB(255, 60, 60)
local LOW_FLASH_TIME = 0.4

local NOTIFY_DURATION = 3
local MAX_NOTIFICATIONS = 3
local NOTIFY_WIDTH = 340
local NOTIFY_HEIGHT = 28

local HOTBAR_BOTTOM_MARGIN = 16
local BARS_BOTTOM_MARGIN = HOTBAR_BOTTOM_MARGIN + SLOT_SIZE + 12
local BACKPACK_BOTTOM_MARGIN = BARS_BOTTOM_MARGIN + BAR_HEIGHT * 2 + BAR_GAP + 12

local HOTBAR_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
}
local BACKPACK_KEY = Enum.KeyCode.Tab

local snapshot = nil -- latest InventoryUpdate payload

-- ===== Disable conflicting core UIs =====
-- Backpack: the default backpack UI appears whenever a weapon Tool is equipped;
-- its ContextActionService bindings swallow the 1-6 hotkeys (gameProcessedEvent
-- = true) and core-UI unequips desync the server's equipped state.
-- PlayerList: Tab would toggle both our backpack panel and Roblox's player
-- list; SquadUI (Task 13) builds its own list, so the core one is redundant.
-- SetCoreGuiEnabled can throw if called before CoreGui is ready, so retry
-- (capped: give up with a warn rather than loop forever on a real failure).
task.spawn(function()
	local MAX_CORE_GUI_ATTEMPTS = 10
	local DISABLED_CORE_GUIS = { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.PlayerList }
	for _, coreGuiType in ipairs(DISABLED_CORE_GUIS) do
		local disabled = false
		for _ = 1, MAX_CORE_GUI_ATTEMPTS do
			if pcall(function()
				StarterGui:SetCoreGuiEnabled(coreGuiType, false)
			end) then
				disabled = true
				break
			end
			task.wait(0.5)
		end
		if not disabled then
			warn("[HUD] giving up disabling core UI: " .. tostring(coreGuiType))
		end
	end
end)

-- ===== ScreenGui =====
local gui = Instance.new("ScreenGui")
gui.Name = "LongRoadHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- ===== Slot factory =====
local function makeSlot(parent, index, showNumber)
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	button.BackgroundColor3 = SLOT_COLOR
	button.BackgroundTransparency = SLOT_TRANSPARENCY
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.LayoutOrder = index

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, SLOT_CORNER_RADIUS)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = EQUIP_STROKE_COLOR
	stroke.Thickness = EQUIP_STROKE_THICKNESS
	stroke.Enabled = false
	stroke.Parent = button

	if showNumber then
		local numberLabel = Instance.new("TextLabel")
		numberLabel.Size = UDim2.fromOffset(14, 14)
		numberLabel.Position = UDim2.fromOffset(3, 2)
		numberLabel.BackgroundTransparency = 1
		numberLabel.Font = Enum.Font.GothamBold
		numberLabel.TextSize = 11
		numberLabel.TextColor3 = DIM_TEXT_COLOR
		numberLabel.Text = tostring(index)
		numberLabel.Parent = button
	end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -6, 1, -18)
	nameLabel.Position = UDim2.new(0, 3, 0, 12)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 10
	nameLabel.TextWrapped = true
	nameLabel.TextColor3 = TEXT_COLOR
	nameLabel.Text = ""
	nameLabel.Parent = button

	local countLabel = Instance.new("TextLabel")
	countLabel.Size = UDim2.fromOffset(24, 12)
	countLabel.AnchorPoint = Vector2.new(1, 1)
	countLabel.Position = UDim2.new(1, -3, 1, -2)
	countLabel.BackgroundTransparency = 1
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 11
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
	countLabel.TextColor3 = TEXT_COLOR
	countLabel.Text = ""
	countLabel.Parent = button

	button.Parent = parent
	return { button = button, nameLabel = nameLabel, countLabel = countLabel, stroke = stroke }
end

local function makeSlotRow(name, slotCount, bottomMargin, showNumbers)
	local row = Instance.new("Frame")
	row.Name = name
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -bottomMargin)
	row.Size = UDim2.fromOffset(slotCount * SLOT_SIZE + (slotCount - 1) * SLOT_GAP, SLOT_SIZE)
	row.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.Parent = row
	row.Parent = gui
	local slots = {}
	for i = 1, slotCount do
		slots[i] = makeSlot(row, i, showNumbers)
	end
	return row, slots
end

-- ===== Hotbar + backpack panel =====
local _, hotbarSlots = makeSlotRow("Hotbar", Config.HOTBAR_SLOTS, HOTBAR_BOTTOM_MARGIN, true)
local backpackPanel, backpackSlots = makeSlotRow("Backpack", Config.BACKPACK_SLOTS, BACKPACK_BOTTOM_MARGIN, false)
backpackPanel.Visible = false

local function renderRow(slotUIs, slotData, equippedIndex)
	for i, ui in ipairs(slotUIs) do
		local item = slotData and slotData[i] or nil -- `false` = empty slot
		if item then
			local def = ItemDefs[item.id]
			ui.nameLabel.Text = def and def.name or tostring(item.id)
			ui.countLabel.Text = item.count > 1 and ("x" .. item.count) or ""
		else
			ui.nameLabel.Text = ""
			ui.countLabel.Text = ""
		end
		ui.stroke.Enabled = equippedIndex == i
	end
end

local function render()
	renderRow(hotbarSlots, snapshot and snapshot.hotbar, snapshot and snapshot.equipped)
	renderRow(backpackSlots, snapshot and snapshot.backpack, nil)
end

for i, ui in ipairs(hotbarSlots) do
	ui.button.Activated:Connect(function()
		Remotes.EquipSlot:FireServer(i)
	end)
end
-- Clicking an open backpack slot swaps it with the equipped hotbar slot
-- (or slot 1 when nothing is equipped).
for i, ui in ipairs(backpackSlots) do
	ui.button.Activated:Connect(function()
		if backpackPanel.Visible then
			local target = (snapshot and snapshot.equipped) or 1
			Remotes.EquipSlot:FireServer({ swap = { backpack = i, hotbar = target } })
		end
	end)
end

-- ===== Stat bars (attribute-driven; nil = full) =====
local barsFrame = Instance.new("Frame")
barsFrame.Name = "StatBars"
barsFrame.AnchorPoint = Vector2.new(0.5, 1)
barsFrame.Position = UDim2.new(0.5, 0, 1, -BARS_BOTTOM_MARGIN)
barsFrame.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT * 2 + BAR_GAP)
barsFrame.BackgroundTransparency = 1
barsFrame.Parent = gui

local function makeStatBar(attributeName, fillColor, order)
	local bg = Instance.new("Frame")
	bg.Name = attributeName .. "Bar"
	bg.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	bg.Position = UDim2.fromOffset(0, (order - 1) * (BAR_HEIGHT + BAR_GAP))
	bg.BackgroundColor3 = BAR_BG_COLOR
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 4)
	bgCorner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill
	fill.Parent = bg
	bg.Parent = barsFrame

	-- Flash red only while below LOW_STAT (tween loop starts/stops on the edge).
	local flashing = false
	local flashTween = nil
	local function update()
		local value = LocalPlayer:GetAttribute(attributeName)
		if value == nil then
			value = Config.STAT_MAX -- attribute not set yet: default full
		end
		fill.Size = UDim2.new(math.clamp(value / Config.STAT_MAX, 0, 1), 0, 1, 0)
		local low = value < Config.LOW_STAT
		if low and not flashing then
			flashing = true
			flashTween = TweenService:Create(fill,
				TweenInfo.new(LOW_FLASH_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundColor3 = LOW_FLASH_COLOR })
			flashTween:Play()
		elseif not low and flashing then
			flashing = false
			flashTween:Cancel()
			flashTween = nil
			fill.BackgroundColor3 = fillColor
		end
	end
	LocalPlayer:GetAttributeChangedSignal(attributeName):Connect(update)
	update()
end

makeStatBar("Hunger", HUNGER_COLOR, 1)
makeStatBar("Warmth", WARMTH_COLOR, 2)

-- ===== Notifications (top-center, queue of 3, oldest expires first) =====
local noteContainer = Instance.new("Frame")
noteContainer.Name = "Notifications"
noteContainer.AnchorPoint = Vector2.new(0.5, 0)
noteContainer.Position = UDim2.new(0.5, 0, 0, 24)
noteContainer.Size = UDim2.fromOffset(NOTIFY_WIDTH, (NOTIFY_HEIGHT + 4) * MAX_NOTIFICATIONS)
noteContainer.BackgroundTransparency = 1
local noteLayout = Instance.new("UIListLayout")
noteLayout.FillDirection = Enum.FillDirection.Vertical
noteLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
noteLayout.SortOrder = Enum.SortOrder.LayoutOrder
noteLayout.Padding = UDim.new(0, 4)
noteLayout.Parent = noteContainer
noteContainer.Parent = gui

local activeNotes = {}
local noteCounter = 0

Remotes.Notify.OnClientEvent:Connect(function(text)
	if typeof(text) ~= "string" then
		return
	end
	if #activeNotes >= MAX_NOTIFICATIONS then
		local oldest = table.remove(activeNotes, 1)
		oldest:Destroy()
	end
	noteCounter += 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, NOTIFY_HEIGHT)
	label.BackgroundColor3 = SLOT_COLOR
	label.BackgroundTransparency = SLOT_TRANSPARENCY
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = TEXT_COLOR
	label.Text = text
	label.LayoutOrder = noteCounter
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, SLOT_CORNER_RADIUS)
	corner.Parent = label
	label.Parent = noteContainer
	table.insert(activeNotes, label)
	task.delay(NOTIFY_DURATION, function()
		local idx = table.find(activeNotes, label)
		if idx then
			table.remove(activeNotes, idx)
		end
		label:Destroy()
	end)
end)

-- ===== Input: 1-6 equips, Tab toggles backpack =====
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == BACKPACK_KEY then
		backpackPanel.Visible = not backpackPanel.Visible
		return
	end
	local n = HOTBAR_KEYS[input.KeyCode]
	if n and n <= Config.HOTBAR_SLOTS then
		Remotes.EquipSlot:FireServer(n)
	end
end)

-- ===== Starter-kit shop (top-right) =====
local KIT_ROW_HEIGHT = 46
local KIT_PANEL_WIDTH = 220
local ACCENT_COLOR = Color3.fromRGB(70, 200, 120)
local OWNED_COLOR = Color3.fromRGB(90, 90, 100)

local kitsButton = Instance.new("TextButton")
kitsButton.Name = "KitsButton"
kitsButton.AnchorPoint = Vector2.new(1, 0)
kitsButton.Position = UDim2.new(1, -16, 0, 16)
kitsButton.Size = UDim2.fromOffset(80, 30)
kitsButton.BackgroundColor3 = SLOT_COLOR
kitsButton.BackgroundTransparency = SLOT_TRANSPARENCY
kitsButton.BorderSizePixel = 0
kitsButton.Font = Enum.Font.GothamBold
kitsButton.TextSize = 14
kitsButton.TextColor3 = TEXT_COLOR
kitsButton.Text = "Kits"
kitsButton.AutoButtonColor = true
local kitsButtonCorner = Instance.new("UICorner")
kitsButtonCorner.CornerRadius = UDim.new(0, SLOT_CORNER_RADIUS)
kitsButtonCorner.Parent = kitsButton
kitsButton.Parent = gui

local kitsPanel = Instance.new("Frame")
kitsPanel.Name = "KitsPanel"
kitsPanel.AnchorPoint = Vector2.new(1, 0)
kitsPanel.Position = UDim2.new(1, -16, 0, 52)
kitsPanel.Size = UDim2.fromOffset(KIT_PANEL_WIDTH, KIT_ROW_HEIGHT * #Config.STARTER_KITS + 8)
kitsPanel.BackgroundColor3 = BAR_BG_COLOR
kitsPanel.BackgroundTransparency = 0.15
kitsPanel.BorderSizePixel = 0
kitsPanel.Visible = false
local kitsPanelCorner = Instance.new("UICorner")
kitsPanelCorner.CornerRadius = UDim.new(0, SLOT_CORNER_RADIUS)
kitsPanelCorner.Parent = kitsPanel
local kitsLayout = Instance.new("UIListLayout")
kitsLayout.FillDirection = Enum.FillDirection.Vertical
kitsLayout.SortOrder = Enum.SortOrder.LayoutOrder
kitsLayout.Padding = UDim.new(0, 4)
kitsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
kitsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
kitsLayout.Parent = kitsPanel
kitsPanel.Parent = gui

-- One row per kit; buyButton flips to a non-interactive "Owned" tag once owned.
local kitRows = {}
for i, kit in ipairs(Config.STARTER_KITS) do
	local row = Instance.new("Frame")
	row.Name = "Kit_" .. kit.id
	row.Size = UDim2.new(1, -12, 0, KIT_ROW_HEIGHT - 4)
	row.BackgroundTransparency = 1
	row.LayoutOrder = i

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -70, 0, 18)
	nameLabel.Position = UDim2.fromOffset(0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = TEXT_COLOR
	nameLabel.Text = kit.name
	nameLabel.Parent = row

	local costLabel = Instance.new("TextLabel")
	costLabel.Size = UDim2.new(1, -70, 0, 14)
	costLabel.Position = UDim2.fromOffset(0, 22)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Enum.Font.Gotham
	costLabel.TextSize = 11
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.TextColor3 = DIM_TEXT_COLOR
	costLabel.Text = kit.cost .. " currency"
	costLabel.Parent = row

	local buyButton = Instance.new("TextButton")
	buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, 0, 0.5, 0)
	buyButton.Size = UDim2.fromOffset(60, 26)
	buyButton.BackgroundColor3 = ACCENT_COLOR
	buyButton.BorderSizePixel = 0
	buyButton.Font = Enum.Font.GothamBold
	buyButton.TextSize = 13
	buyButton.TextColor3 = Color3.fromRGB(20, 20, 20)
	buyButton.Text = "Buy"
	buyButton.AutoButtonColor = true
	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 4)
	buyCorner.Parent = buyButton
	buyButton.Activated:Connect(function()
		Remotes.BuyKit:FireServer(kit.id)
	end)
	buyButton.Parent = row

	row.Parent = kitsPanel
	kitRows[kit.id] = buyButton
end

kitsButton.Activated:Connect(function()
	kitsPanel.Visible = not kitsPanel.Visible
end)

-- Owned set parsed from the comma-joined OwnedKits attribute.
local function renderKits()
	local owned = {}
	local raw = LocalPlayer:GetAttribute("OwnedKits")
	if type(raw) == "string" then
		for _, id in ipairs(string.split(raw, ",")) do
			if id ~= "" then
				owned[id] = true
			end
		end
	end
	for kitId, buyButton in pairs(kitRows) do
		if owned[kitId] then
			buyButton.Text = "Owned"
			buyButton.BackgroundColor3 = OWNED_COLOR
			buyButton.TextColor3 = DIM_TEXT_COLOR
			buyButton.AutoButtonColor = false
			buyButton.Active = false
		else
			buyButton.Text = "Buy"
			buyButton.BackgroundColor3 = ACCENT_COLOR
			buyButton.TextColor3 = Color3.fromRGB(20, 20, 20)
			buyButton.AutoButtonColor = true
			buyButton.Active = true
		end
	end
end
LocalPlayer:GetAttributeChangedSignal("OwnedKits"):Connect(renderKits)
renderKits()

-- ===== Victory banner (center; shown on RunFinished) =====
local BANNER_DURATION = 8

local banner = Instance.new("Frame")
banner.Name = "VictoryBanner"
banner.AnchorPoint = Vector2.new(0.5, 0.5)
banner.Position = UDim2.new(0.5, 0, 0.4, 0)
banner.Size = UDim2.fromOffset(360, 150)
banner.BackgroundColor3 = BAR_BG_COLOR
banner.BackgroundTransparency = 0.1
banner.BorderSizePixel = 0
banner.Visible = false
local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 10)
bannerCorner.Parent = banner
local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = ACCENT_COLOR
bannerStroke.Thickness = 2
bannerStroke.Parent = banner

local bannerTitle = Instance.new("TextLabel")
bannerTitle.Size = UDim2.new(1, 0, 0, 44)
bannerTitle.Position = UDim2.fromOffset(0, 12)
bannerTitle.BackgroundTransparency = 1
bannerTitle.Font = Enum.Font.GothamBold
bannerTitle.TextSize = 26
bannerTitle.TextColor3 = ACCENT_COLOR
bannerTitle.Text = "You Escaped!"
bannerTitle.Parent = banner

local bannerStats = Instance.new("TextLabel")
bannerStats.Size = UDim2.new(1, -24, 1, -64)
bannerStats.Position = UDim2.fromOffset(12, 56)
bannerStats.BackgroundTransparency = 1
bannerStats.Font = Enum.Font.GothamMedium
bannerStats.TextSize = 16
bannerStats.TextColor3 = TEXT_COLOR
bannerStats.TextYAlignment = Enum.TextYAlignment.Top
bannerStats.Text = ""
bannerStats.Parent = banner
banner.Parent = gui

local function formatBannerTime(seconds)
	if type(seconds) ~= "number" then
		return "-"
	end
	return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local bannerToken = 0
Remotes.RunFinished.OnClientEvent:Connect(function(stats)
	if typeof(stats) ~= "table" then
		return
	end
	bannerToken += 1
	local myToken = bannerToken
	bannerStats.Text = string.format(
		"Time: %s\nReward: +%d currency\nRuns completed: %d\nBest time: %s",
		formatBannerTime(stats.elapsed),
		tonumber(stats.reward) or 0,
		tonumber(stats.completions) or 0,
		formatBannerTime(stats.bestTime))
	banner.Visible = true
	task.delay(BANNER_DURATION, function()
		if myToken == bannerToken then
			banner.Visible = false
		end
	end)
end)

-- ===== Snapshot driver =====
Remotes.InventoryUpdate.OnClientEvent:Connect(function(snap)
	if typeof(snap) ~= "table" then
		return
	end
	snapshot = snap
	render()
end)
render()
-- Listener is live: request the current snapshot. Closes the race where the
-- server's FireClient (e.g. a join-time starter-kit grant) beat this script.
Remotes.RequestInventory:FireServer()
