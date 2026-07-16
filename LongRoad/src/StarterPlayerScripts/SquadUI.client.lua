-- SquadUI: the squad-side interface — a collapsible list to invite other
-- players, a centered incoming-invite prompt, a squad roster with live member
-- health bars, and green outlines on squad-mates.
--
-- SquadUpdate payload (full per-player snapshot from SquadService; the whole UI
-- re-renders on each one and treats it as idempotent):
--   squad  = { id = string, members = { {name=string, userId=number}, ... } } OR false
--   invite = { inviter = string, expiresIn = number (seconds remaining) }      OR false
--
-- Green highlights are attribute-driven (each player's `SquadId`), mirroring the
-- hostile-red pattern in Effects.client.lua — independent of the SquadUpdate
-- payload, so ordering between the two never matters. A squad-mate can also be
-- hostile-red (from killing a NON-squad player; no-friendly-fire keeps them from
-- hurting us), leaving two differently-named Highlights on one character — that
-- stacking is fine and intended.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage:WaitForChild("RemoteSetup"))
local Remotes = RemoteSetup.Get()

local LocalPlayer = Players.LocalPlayer

-- ===== Constants =====
local SQUAD_HIGHLIGHT_NAME = "SquadHighlight"
local SQUAD_OUTLINE_COLOR = Color3.fromRGB(80, 220, 120)

local PANEL_COLOR = Color3.fromRGB(25, 25, 30)
local PANEL_TRANSPARENCY = 0.35
local ACCENT_COLOR = Color3.fromRGB(80, 220, 120)
local DECLINE_COLOR = Color3.fromRGB(200, 80, 80)
local TEXT_COLOR = Color3.fromRGB(230, 230, 230)
local DIM_TEXT_COLOR = Color3.fromRGB(160, 160, 160)
local CORNER_RADIUS = 6

local ROW_HEIGHT = 26
local HEALTH_BAR_HEIGHT = 6
local HEALTH_BG_COLOR = Color3.fromRGB(18, 18, 22)
local PANEL_WIDTH = 200

-- ===== State =====
local currentSquad = nil  -- { id, members = { {name, userId}, ... } } or nil
local currentInvite = nil -- { inviter, expiresIn } or nil

-- ===== ScreenGui =====
local gui = Instance.new("ScreenGui")
gui.Name = "LongRoadSquadUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function withCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or CORNER_RADIUS)
	corner.Parent = instance
	return instance
end

-- ===== Squad roster frame (top-right) =====
local squadFrame = Instance.new("Frame")
squadFrame.Name = "SquadFrame"
squadFrame.AnchorPoint = Vector2.new(1, 0)
squadFrame.Position = UDim2.new(1, -12, 0, 12)
squadFrame.Size = UDim2.fromOffset(PANEL_WIDTH, 40)
squadFrame.BackgroundColor3 = PANEL_COLOR
squadFrame.BackgroundTransparency = PANEL_TRANSPARENCY
squadFrame.BorderSizePixel = 0
squadFrame.Visible = false
squadFrame.AutomaticSize = Enum.AutomaticSize.Y
withCorner(squadFrame)
squadFrame.Parent = gui

local squadLayout = Instance.new("UIListLayout")
squadLayout.FillDirection = Enum.FillDirection.Vertical
squadLayout.SortOrder = Enum.SortOrder.LayoutOrder
squadLayout.Padding = UDim.new(0, 4)
squadLayout.Parent = squadFrame

local squadPadding = Instance.new("UIPadding")
squadPadding.PaddingTop = UDim.new(0, 6)
squadPadding.PaddingBottom = UDim.new(0, 6)
squadPadding.PaddingLeft = UDim.new(0, 8)
squadPadding.PaddingRight = UDim.new(0, 8)
squadPadding.Parent = squadFrame

local squadTitle = Instance.new("TextLabel")
squadTitle.Name = "Title"
squadTitle.Size = UDim2.new(1, 0, 0, 18)
squadTitle.BackgroundTransparency = 1
squadTitle.Font = Enum.Font.GothamBold
squadTitle.TextSize = 13
squadTitle.TextColor3 = TEXT_COLOR
squadTitle.TextXAlignment = Enum.TextXAlignment.Left
squadTitle.Text = "Squad"
squadTitle.LayoutOrder = 0
squadTitle.Parent = squadFrame

-- Health connections for the CURRENT roster; every rebuild disconnects them all
-- and a token invalidates any spawned Humanoid waits still pending from the old
-- roster.
local memberHealthConns = {}
local rosterToken = 0

local function clearMemberHealthConns()
	for _, conn in ipairs(memberHealthConns) do
		conn:Disconnect()
	end
	memberHealthConns = {}
end

local function setBar(fill, humanoid)
	if humanoid and humanoid.Health > 0 and humanoid.MaxHealth > 0 then
		fill.Size = UDim2.new(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 0, 1, 0)
		fill.BackgroundColor3 = ACCENT_COLOR
	else
		-- No character / dead: greyed empty bar.
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = DIM_TEXT_COLOR
	end
end

-- Hooks HealthChanged for a member's current humanoid, refreshing on respawn.
-- player may be nil (member's Player object not yet visible locally): the bar
-- just shows empty until the next SquadUpdate rebuilds it.
local function hookMemberHealth(player, fill)
	local myToken = rosterToken
	local function bindCurrent()
		if rosterToken ~= myToken then
			return
		end
		local character = player and player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and not humanoid then
			-- Humanoid can replicate a frame after the character; wait without
			-- blocking, guarded by the roster token.
			task.spawn(function()
				local hum = character:WaitForChild("Humanoid", 5)
				if rosterToken ~= myToken or not hum then
					return
				end
				table.insert(memberHealthConns, hum.HealthChanged:Connect(function()
					setBar(fill, hum)
				end))
				setBar(fill, hum)
			end)
			setBar(fill, nil)
			return
		end
		if humanoid then
			table.insert(memberHealthConns, humanoid.HealthChanged:Connect(function()
				setBar(fill, humanoid)
			end))
		end
		setBar(fill, humanoid)
	end
	if player then
		table.insert(memberHealthConns, player.CharacterAdded:Connect(bindCurrent))
		table.insert(memberHealthConns, player.CharacterRemoving:Connect(function()
			if rosterToken == myToken then
				setBar(fill, nil)
			end
		end))
	end
	bindCurrent()
end

local function makeMemberRow(member, order)
	local row = Instance.new("Frame")
	row.Name = "MemberRow"
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, ROW_HEIGHT - HEALTH_BAR_HEIGHT - 2)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = (member.userId == LocalPlayer.UserId) and ACCENT_COLOR or TEXT_COLOR
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = member.name
	nameLabel.Parent = row

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, 0, 0, HEALTH_BAR_HEIGHT)
	barBg.Position = UDim2.new(0, 0, 1, -HEALTH_BAR_HEIGHT)
	barBg.BackgroundColor3 = HEALTH_BG_COLOR
	barBg.BorderSizePixel = 0
	withCorner(barBg, 3)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = ACCENT_COLOR
	fill.BorderSizePixel = 0
	withCorner(fill, 3)
	fill.Parent = barBg
	barBg.Parent = row
	row.Parent = squadFrame

	hookMemberHealth(Players:GetPlayerByUserId(member.userId), fill)
end

local leaveButton = Instance.new("TextButton")
leaveButton.Name = "LeaveButton"
leaveButton.Size = UDim2.new(1, 0, 0, 22)
leaveButton.BackgroundColor3 = DECLINE_COLOR
leaveButton.BackgroundTransparency = 0.2
leaveButton.BorderSizePixel = 0
leaveButton.Font = Enum.Font.GothamBold
leaveButton.TextSize = 12
leaveButton.TextColor3 = TEXT_COLOR
leaveButton.Text = "Leave Squad"
leaveButton.AutoButtonColor = true
withCorner(leaveButton)
leaveButton.Parent = squadFrame
leaveButton.Activated:Connect(function()
	Remotes.SquadLeave:FireServer()
end)

local function rebuildSquadFrame()
	rosterToken += 1
	clearMemberHealthConns()
	for _, child in ipairs(squadFrame:GetChildren()) do
		if child.Name == "MemberRow" then
			child:Destroy()
		end
	end
	if not currentSquad then
		squadFrame.Visible = false
		return
	end
	squadFrame.Visible = true
	squadTitle.Text = ("Squad (%d)"):format(#currentSquad.members)
	for i, member in ipairs(currentSquad.members) do
		makeMemberRow(member, i) -- LayoutOrder 1..n keeps rows above the leave button
	end
	leaveButton.LayoutOrder = #currentSquad.members + 1
end

-- ===== Incoming invite prompt (center) =====
local invitePrompt = Instance.new("Frame")
invitePrompt.Name = "InvitePrompt"
invitePrompt.AnchorPoint = Vector2.new(0.5, 0.5)
invitePrompt.Position = UDim2.new(0.5, 0, 0.5, 0)
invitePrompt.Size = UDim2.fromOffset(320, 110)
invitePrompt.BackgroundColor3 = PANEL_COLOR
invitePrompt.BackgroundTransparency = 0.1
invitePrompt.BorderSizePixel = 0
invitePrompt.Visible = false
withCorner(invitePrompt)
invitePrompt.Parent = gui

local inviteLabel = Instance.new("TextLabel")
inviteLabel.Size = UDim2.new(1, -24, 0, 50)
inviteLabel.Position = UDim2.fromOffset(12, 12)
inviteLabel.BackgroundTransparency = 1
inviteLabel.Font = Enum.Font.GothamMedium
inviteLabel.TextSize = 15
inviteLabel.TextColor3 = TEXT_COLOR
inviteLabel.TextWrapped = true
inviteLabel.Text = ""
inviteLabel.Parent = invitePrompt

local acceptButton = Instance.new("TextButton")
acceptButton.Size = UDim2.fromOffset(140, 30)
acceptButton.Position = UDim2.new(0, 12, 1, -42)
acceptButton.BackgroundColor3 = ACCENT_COLOR
acceptButton.BackgroundTransparency = 0.1
acceptButton.BorderSizePixel = 0
acceptButton.Font = Enum.Font.GothamBold
acceptButton.TextSize = 14
acceptButton.TextColor3 = Color3.fromRGB(20, 20, 20)
acceptButton.Text = "Accept"
withCorner(acceptButton)
acceptButton.Parent = invitePrompt

local declineButton = Instance.new("TextButton")
declineButton.Size = UDim2.fromOffset(140, 30)
declineButton.Position = UDim2.new(1, -152, 1, -42)
declineButton.BackgroundColor3 = DECLINE_COLOR
declineButton.BackgroundTransparency = 0.1
declineButton.BorderSizePixel = 0
declineButton.Font = Enum.Font.GothamBold
declineButton.TextSize = 14
declineButton.TextColor3 = TEXT_COLOR
declineButton.Text = "Decline"
withCorner(declineButton)
declineButton.Parent = invitePrompt

-- A token invalidates the auto-dismiss timer of an invite that a newer one has
-- replaced (spec: a second invite replaces the first) or that a click resolved.
local inviteToken = 0

local function hideInvite()
	currentInvite = nil
	inviteToken += 1
	invitePrompt.Visible = false
end

local function showInvite(invite)
	currentInvite = invite
	inviteToken += 1
	local myToken = inviteToken
	inviteLabel.Text = invite.inviter .. " invited you to their squad"
	invitePrompt.Visible = true
	-- Client-side auto-dismiss on seconds-remaining (clock-skew-safe: the server
	-- sends time left, not an absolute stamp, and is authoritative on expiry
	-- regardless). A malformed payload just leaves the server to drive dismissal.
	if typeof(invite.expiresIn) == "number" then
		task.delay(math.max(0, invite.expiresIn), function()
			if inviteToken == myToken then
				hideInvite()
			end
		end)
	end
end

acceptButton.Activated:Connect(function()
	if currentInvite then
		Remotes.SquadResponse:FireServer(currentInvite.inviter, true)
	end
	hideInvite()
end)
declineButton.Activated:Connect(function()
	if currentInvite then
		Remotes.SquadResponse:FireServer(currentInvite.inviter, false)
	end
	hideInvite()
end)

-- ===== Player list (right side, collapsible) =====
local playerListFrame = Instance.new("Frame")
playerListFrame.Name = "PlayerListFrame"
playerListFrame.AnchorPoint = Vector2.new(1, 0.5)
playerListFrame.Position = UDim2.new(1, -12, 0.5, 0)
playerListFrame.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
playerListFrame.AutomaticSize = Enum.AutomaticSize.Y -- fits header + body
playerListFrame.BackgroundTransparency = 1
playerListFrame.Parent = gui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.Parent = playerListFrame

local listHeader = Instance.new("TextButton")
listHeader.Name = "Header"
listHeader.Size = UDim2.new(1, 0, 0, 26)
listHeader.BackgroundColor3 = PANEL_COLOR
listHeader.BackgroundTransparency = PANEL_TRANSPARENCY
listHeader.BorderSizePixel = 0
listHeader.Font = Enum.Font.GothamBold
listHeader.TextSize = 12
listHeader.TextColor3 = TEXT_COLOR
listHeader.Text = "Players  -"
listHeader.LayoutOrder = 0
withCorner(listHeader)
listHeader.Parent = playerListFrame

-- Scrolls once the roster is tall enough: grows with content (AutomaticSize +
-- AutomaticCanvasSize) but a UISizeConstraint caps its height so a populated
-- server can't run the list off-screen.
local listBody = Instance.new("ScrollingFrame")
listBody.Name = "Body"
listBody.Size = UDim2.new(1, 0, 0, 0)
listBody.BackgroundTransparency = 1
listBody.BorderSizePixel = 0
listBody.AutomaticSize = Enum.AutomaticSize.Y
listBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
listBody.CanvasSize = UDim2.new(0, 0, 0, 0)
listBody.ScrollingDirection = Enum.ScrollingDirection.Y
listBody.ScrollBarThickness = 4
listBody.LayoutOrder = 1
listBody.Parent = playerListFrame

local listBodyConstraint = Instance.new("UISizeConstraint")
listBodyConstraint.MaxSize = Vector2.new(math.huge, 300)
listBodyConstraint.Parent = listBody

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.FillDirection = Enum.FillDirection.Vertical
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Padding = UDim.new(0, 3)
bodyLayout.Parent = listBody

local listExpanded = true
listHeader.Activated:Connect(function()
	listExpanded = not listExpanded
	listBody.Visible = listExpanded
	listHeader.Text = listExpanded and "Players  -" or "Players  +"
end)

local function isSquadmate(userId)
	if not currentSquad then
		return false
	end
	for _, member in ipairs(currentSquad.members) do
		if member.userId == userId then
			return true
		end
	end
	return false
end

local function makePlayerRow(player, order)
	local row = Instance.new("Frame")
	row.Name = "PlayerRow"
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = PANEL_COLOR
	row.BackgroundTransparency = PANEL_TRANSPARENCY
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	withCorner(row)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -70, 1, 0)
	nameLabel.Position = UDim2.fromOffset(8, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = TEXT_COLOR
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = player.Name
	nameLabel.Parent = row

	local inviteButton = Instance.new("TextButton")
	inviteButton.Size = UDim2.fromOffset(56, ROW_HEIGHT - 6)
	inviteButton.Position = UDim2.new(1, -60, 0.5, 0)
	inviteButton.AnchorPoint = Vector2.new(0, 0.5)
	inviteButton.BackgroundColor3 = ACCENT_COLOR
	inviteButton.BackgroundTransparency = 0.15
	inviteButton.BorderSizePixel = 0
	inviteButton.Font = Enum.Font.GothamBold
	inviteButton.TextSize = 11
	inviteButton.TextColor3 = Color3.fromRGB(20, 20, 20)
	inviteButton.Text = "Invite"
	withCorner(inviteButton, 4)
	inviteButton.Parent = row
	inviteButton.Activated:Connect(function()
		Remotes.SquadInvite:FireServer(player)
	end)

	row.Parent = listBody
end

local function refreshPlayerList()
	for _, child in ipairs(listBody:GetChildren()) do
		if child.Name == "PlayerRow" then
			child:Destroy()
		end
	end
	local order = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and not isSquadmate(player.UserId) then
			order += 1
			makePlayerRow(player, order)
		end
	end
	listHeader.Text = listExpanded and "Players  -" or "Players  +"
end

Players.PlayerAdded:Connect(refreshPlayerList)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshPlayerList) -- run after the player is actually gone from GetPlayers()
end)

-- ===== Green squad-mate highlights (attribute-driven; see header) =====
local highlightConns = {} -- player -> { RBXScriptConnection }

local function applySquadHighlight(player)
	local character = player.Character
	if not character then
		return
	end
	local mySquad = LocalPlayer:GetAttribute("SquadId")
	local theirSquad = player:GetAttribute("SquadId")
	local existing = character:FindFirstChild(SQUAD_HIGHLIGHT_NAME)
	-- Includes the local player (mySquad == theirSquad for self): highlighting my
	-- own character green is deliberate, mirroring Effects' hostile pattern which
	-- likewise watches every player uniformly.
	local shouldHighlight = mySquad ~= nil and mySquad ~= "" and theirSquad == mySquad
	if shouldHighlight then
		if not existing then
			local highlight = Instance.new("Highlight")
			highlight.Name = SQUAD_HIGHLIGHT_NAME
			highlight.FillTransparency = 1
			highlight.OutlineColor = SQUAD_OUTLINE_COLOR
			highlight.OutlineTransparency = 0
			highlight.Adornee = character
			highlight.Parent = character
		end
	elseif existing then
		existing:Destroy()
	end
end

local function reevaluateAll()
	for _, player in ipairs(Players:GetPlayers()) do
		applySquadHighlight(player)
	end
end

local function watchHighlight(player)
	local conns = {}
	table.insert(conns, player:GetAttributeChangedSignal("SquadId"):Connect(function()
		applySquadHighlight(player)
	end))
	table.insert(conns, player.CharacterAdded:Connect(function()
		applySquadHighlight(player)
	end))
	highlightConns[player] = conns
	applySquadHighlight(player)
end

-- My own SquadId changing flips who counts as a squad-mate, so re-evaluate all.
LocalPlayer:GetAttributeChangedSignal("SquadId"):Connect(reevaluateAll)

Players.PlayerAdded:Connect(watchHighlight)
for _, player in ipairs(Players:GetPlayers()) do
	watchHighlight(player)
end
Players.PlayerRemoving:Connect(function(player)
	local conns = highlightConns[player]
	if conns then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		highlightConns[player] = nil
	end
end)

-- ===== SquadUpdate driver =====
Remotes.SquadUpdate.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	currentSquad = (typeof(payload.squad) == "table") and payload.squad or nil
	if typeof(payload.invite) == "table" and typeof(payload.invite.inviter) == "string" then
		showInvite(payload.invite)
	else
		hideInvite()
	end
	rebuildSquadFrame()
	refreshPlayerList()
end)

refreshPlayerList()
