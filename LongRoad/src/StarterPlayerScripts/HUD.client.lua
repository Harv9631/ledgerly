-- HUD: hotbar, stat bars, notifications, backpack panel (all built from code)
--
-- Snapshot convention: InventoryUpdate delivers {hotbar, backpack, equipped}
-- where empty slots are `false` (dense arrays survive remote serialization).
-- Interaction.client.lua keeps its OWN copy via its own InventoryUpdate
-- listener; HUD state is not shared between the two scripts.
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
