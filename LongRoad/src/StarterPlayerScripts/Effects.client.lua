-- Effects: frost overlay (low warmth), rain particles/atmosphere, hostile player highlights
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local LocalPlayer = Players.LocalPlayer

-- Frost overlay
local FROST_EDGE_FRACTION = 0.15 -- each edge frame covers 15% of the screen
local FROST_COLOR = Color3.fromRGB(205, 230, 255)
local FROST_TINT = Color3.fromRGB(200, 220, 255)
local FROST_SATURATION = -0.2

-- Rain
local RAIN_HEIGHT_OFFSET = 40
local RAIN_RATE = 180
local RAIN_SPEED = 60
local RAIN_LIFETIME = 1
local RAIN_COLOR = Color3.fromRGB(175, 190, 215)
local RAIN_TRANSPARENCY = 0.35
local RAIN_PARTICLE_SIZE = 0.15
local RAIN_EMITTER_SIZE = Vector3.new(80, 1, 80)
local RAIN_ATMOSPHERE_DENSITY = 0.5
local RAIN_ATMOSPHERE_HAZE = 2.5

-- Hostile marking
local HOSTILE_OUTLINE_COLOR = Color3.fromRGB(255, 60, 60)
local HOSTILE_HIGHLIGHT_NAME = "HostileHighlight"

-- ===== Frost overlay =====
local frostGui = Instance.new("ScreenGui")
frostGui.Name = "FrostOverlay"
frostGui.IgnoreGuiInset = true
frostGui.DisplayOrder = 100
frostGui.ResetOnSpawn = false
frostGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Four edge frames, each fading to transparent toward screen center.
local FROST_EDGES = {
	{ size = UDim2.new(1, 0, FROST_EDGE_FRACTION, 0), position = UDim2.new(0, 0, 0, 0), rotation = 90 },
	{ size = UDim2.new(1, 0, FROST_EDGE_FRACTION, 0), position = UDim2.new(0, 0, 1 - FROST_EDGE_FRACTION, 0), rotation = -90 },
	{ size = UDim2.new(FROST_EDGE_FRACTION, 0, 1, 0), position = UDim2.new(0, 0, 0, 0), rotation = 0 },
	{ size = UDim2.new(FROST_EDGE_FRACTION, 0, 1, 0), position = UDim2.new(1 - FROST_EDGE_FRACTION, 0, 0, 0), rotation = 180 },
}
local frostFrames = {}
for _, edge in ipairs(FROST_EDGES) do
	local frame = Instance.new("Frame")
	frame.Size = edge.size
	frame.Position = edge.position
	frame.BackgroundColor3 = FROST_COLOR
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = edge.rotation
	gradient.Transparency = NumberSequence.new(0, 1)
	gradient.Parent = frame
	frame.Parent = frostGui
	table.insert(frostFrames, frame)
end

local frostCC = Instance.new("ColorCorrectionEffect")
frostCC.Name = "FrostColorCorrection"
frostCC.Enabled = false
frostCC.Parent = Lighting

local function updateFrost()
	local warmth = LocalPlayer:GetAttribute("Warmth")
	local intensity = 0
	if warmth ~= nil and warmth < Config.LOW_STAT then
		intensity = math.clamp((Config.LOW_STAT - warmth) / Config.LOW_STAT, 0, 1)
	end
	for _, frame in ipairs(frostFrames) do
		frame.BackgroundTransparency = 1 - intensity
	end
	frostCC.Enabled = intensity > 0
	frostCC.TintColor = Color3.new(1, 1, 1):Lerp(FROST_TINT, intensity)
	frostCC.Saturation = FROST_SATURATION * intensity
end

LocalPlayer:GetAttributeChangedSignal("Warmth"):Connect(updateFrost)
updateFrost()

-- ===== Rain =====
local rainPart = Instance.new("Part")
rainPart.Name = "RainEmitterPart"
rainPart.Anchored = true
rainPart.CanCollide = false
rainPart.CanQuery = false
rainPart.CanTouch = false
rainPart.CastShadow = false
rainPart.Transparency = 1
rainPart.Size = RAIN_EMITTER_SIZE
rainPart.Parent = Workspace

local rainEmitter = Instance.new("ParticleEmitter")
rainEmitter.Enabled = false
rainEmitter.Rate = RAIN_RATE
rainEmitter.Speed = NumberRange.new(RAIN_SPEED)
rainEmitter.Lifetime = NumberRange.new(RAIN_LIFETIME)
rainEmitter.EmissionDirection = Enum.NormalId.Bottom
rainEmitter.Orientation = Enum.ParticleOrientation.VelocityParallel
rainEmitter.Color = ColorSequence.new(RAIN_COLOR)
rainEmitter.Transparency = NumberSequence.new(RAIN_TRANSPARENCY)
rainEmitter.Size = NumberSequence.new(RAIN_PARTICLE_SIZE)
rainEmitter.Parent = rainPart

local rainActive = false
local savedDensity, savedHaze

RunService.Heartbeat:Connect(function()
	if not rainActive then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera then
		rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, RAIN_HEIGHT_OFFSET, 0))
	end
end)

local function setRainActive(on)
	if on == rainActive then
		return
	end
	rainActive = on
	rainEmitter.Enabled = on
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if on then
		if not atmosphere then
			atmosphere = Instance.new("Atmosphere")
			atmosphere.Parent = Lighting
		end
		savedDensity = atmosphere.Density
		savedHaze = atmosphere.Haze
		atmosphere.Density = RAIN_ATMOSPHERE_DENSITY
		atmosphere.Haze = math.max(atmosphere.Haze, RAIN_ATMOSPHERE_HAZE)
	elseif atmosphere and savedDensity ~= nil then
		atmosphere.Density = savedDensity
		atmosphere.Haze = savedHaze
	end
end

-- Rain state comes from a workspace attribute, not the TimeUpdate remote:
-- attributes replicate and are readable at any join time, so a late joiner
-- gets the current state instead of missing an unqueued RemoteEvent fire.
workspace:GetAttributeChangedSignal("IsRaining"):Connect(function()
	setRainActive(workspace:GetAttribute("IsRaining") == true)
end)
setRainActive(workspace:GetAttribute("IsRaining") == true)

-- ===== Hostile highlights =====
local hostileConnections = {} -- player -> { RBXScriptConnection }

-- Applies/refreshes/removes the highlight based on the current HostileUntil attribute.
local function updateHostileHighlight(player)
	local character = player.Character
	if not character then
		return
	end
	local hostileUntil = player:GetAttribute("HostileUntil")
	local remaining = (typeof(hostileUntil) == "number") and (hostileUntil - os.time()) or 0
	local existing = character:FindFirstChild(HOSTILE_HIGHLIGHT_NAME)
	if remaining > 0 then
		if not existing then
			local highlight = Instance.new("Highlight")
			highlight.Name = HOSTILE_HIGHLIGHT_NAME
			highlight.FillTransparency = 1
			highlight.OutlineColor = HOSTILE_OUTLINE_COLOR
			highlight.OutlineTransparency = 0
			highlight.Adornee = character
			highlight.Parent = character
		end
		-- Re-check at expiry: the attribute may have been refreshed by another kill.
		task.delay(remaining, function()
			if player.Parent and player.Character == character then
				updateHostileHighlight(player)
			end
		end)
	elseif existing then
		existing:Destroy()
	end
end

local function watchPlayer(player)
	local connections = {}
	table.insert(connections, player:GetAttributeChangedSignal("HostileUntil"):Connect(function()
		updateHostileHighlight(player)
	end))
	table.insert(connections, player.CharacterAdded:Connect(function()
		updateHostileHighlight(player)
	end))
	hostileConnections[player] = connections
	updateHostileHighlight(player)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	local connections = hostileConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		hostileConnections[player] = nil
	end
end)
