-- DayNightService: drives the day/night clock, ambient lighting, and the rain schedule
local Lighting = game:GetService("Lighting")

local DAY_AMBIENT = Color3.fromRGB(70, 70, 70)
local NIGHT_AMBIENT = Color3.fromRGB(10, 10, 20)
local DAY_OUTDOOR_AMBIENT = Color3.fromRGB(128, 128, 128)
local NIGHT_OUTDOOR_AMBIENT = Color3.fromRGB(8, 8, 18)
local DAY_START_CLOCK = 6
local NIGHT_START_CLOCK = 18
local PHASE_CLOCK_SPAN = 12 -- hours of ClockTime each phase sweeps through

local DayNightService = {}

local deps
local isNight = false
local isRaining = false
local generation = 0       -- bumped by ForceState; the loop checks it every second
local forcedNight = false  -- phase requested by the latest ForceState
local rainOverride = false -- ForceRain suppresses the schedule until the next day-start roll
local rng = Random.new()

local function broadcast()
	deps.Remotes.TimeUpdate:FireAllClients(isNight, isRaining)
end

-- Workspace attributes mirror the state: attributes replicate and are readable at
-- any join time, so late joiners never miss it (RemoteEvents don't queue). This is
-- the precedent for world state; the remote still fires for change-driven consumers.
local function setNight(night)
	if isNight ~= night then
		isNight = night
		workspace:SetAttribute("IsNight", isNight)
		broadcast()
	end
end

local function setRaining(on)
	if isRaining ~= on then
		isRaining = on
		workspace:SetAttribute("IsRaining", isRaining)
		broadcast()
	end
end

-- Runs one full phase (day or night). Returns early if ForceState bumps generation.
local function runPhase(night, myGeneration)
	local Config = deps.Config
	local length = night and Config.NIGHT_LENGTH or Config.DAY_LENGTH
	local startClock = night and NIGHT_START_CLOCK or DAY_START_CLOCK

	Lighting.Ambient = night and NIGHT_AMBIENT or DAY_AMBIENT
	Lighting.OutdoorAmbient = night and NIGHT_OUTDOOR_AMBIENT or DAY_OUTDOOR_AMBIENT
	Lighting.ClockTime = startClock % 24
	setNight(night)

	-- Rain schedule: rolled fresh at each natural day start; the roll clears any override.
	local rainStart, rainStop
	if night then
		if not rainOverride then
			setRaining(false)
		end
	else
		rainOverride = false
		setRaining(false)
		if rng:NextNumber() < Config.RAIN_CHANCE then
			-- Clamp so a debug-shortened day (length < RAIN_DURATION) still ends rain in-phase.
			local window = math.max(0, length - Config.RAIN_DURATION)
			rainStart = rng:NextNumber() * window
			rainStop = math.min(rainStart + Config.RAIN_DURATION, length)
		end
	end

	local elapsed = 0
	while elapsed < length do
		task.wait(1)
		if generation ~= myGeneration then
			return
		end
		elapsed += 1
		Lighting.ClockTime = (startClock + (elapsed / length) * PHASE_CLOCK_SPAN) % 24
		if rainStart and not rainOverride then
			if elapsed >= rainStop then
				setRaining(false)
			elseif elapsed >= rainStart then
				setRaining(true)
			end
		end
	end
end

function DayNightService.Init(depsIn)
	deps = depsIn
	workspace:SetAttribute("IsNight", isNight)
	workspace:SetAttribute("IsRaining", isRaining)
	task.spawn(function()
		local phaseNight = false
		while true do
			local myGeneration = generation
			runPhase(phaseNight, myGeneration)
			if generation == myGeneration then
				phaseNight = not phaseNight
			else
				phaseNight = forcedNight
			end
		end
	end)
end

function DayNightService.IsNight()
	return isNight
end

function DayNightService.IsRaining()
	return isRaining
end

-- Skip the clock to the start of the requested phase (takes effect within ~1s).
function DayNightService.ForceState(night)
	forcedNight = night
	generation += 1
end

-- Force rain on/off immediately, overriding the schedule until the next day-start roll.
function DayNightService.ForceRain(on)
	rainOverride = true
	setRaining(on)
end

return DayNightService
