-- AntiCheatService: two server-side clamps against exploiters.
--
--   1. Movement sanity — samples HumanoidRootPart every second and snaps a
--      player back when their horizontal speed stays impossibly high for
--      MAX_STRIKES consecutive samples. Server never trusts the client for
--      eating/damage/pickups (enforced elsewhere); this adds movement. Accepted
--      ceiling by design: a hacker holding speed just under SPRINT_SPEED*BUFFER
--      passes — the gate bounds how much they can cheat, it does not eliminate
--      cheating. It exists to stop blatant teleport/fly, not to be airtight.
--   2. Prompt rate limiting — AllowPrompt is a per-player token bucket that
--      FireService/LootService gate their ProximityPrompt.Triggered handlers on.
--      Exploiters call fireproximityprompt() to skip HoldDuration and trigger a
--      prompt as fast as the server accepts it (unlimited wood/loot). Prompts
--      fired faster than HoldDuration are individually legitimate-looking, so a
--      rate gate — not a hold-time measurement — is the right level.
--
-- Legit teleports (ProgressService checkpoint/extraction pivots, DebugService
-- /tp) call Excuse(player) first, which clears the movement sample and
-- suppresses checks for EXCUSE_DURATION so the pivot's position jump isn't read
-- as a speed hack.
--
-- Pre-Init safety: AllowPrompt/Excuse only touch module-scope tables and
-- constants, so they no-op safely if called before Init (FireService/LootService
-- init before us; the nil-guard at their call sites means a failed AntiCheat load
-- just passes every prompt through).
local Players = game:GetService("Players")

local AntiCheatService = {}

local deps

-- Defaults mirror GameConfig's AntiCheat section; Init overwrites them from
-- Config. Kept at module scope (not inside Init) so the public API is usable
-- before Init has run.
local SAMPLE_INTERVAL = 1
local SPEED_BUFFER = 1.8
local SPRINT_SPEED = 24
local MAX_STRIKES = 3
local EXCUSE_DURATION = 5
local PROMPT_BURST = 3
local PROMPT_REFILL = 0.75
local maxSpeed = SPRINT_SPEED * SPEED_BUFFER -- studs/sec ceiling; the per-sample budget is maxSpeed*dt
local MIN_DT = 0.1 -- floor on the per-sample dt: guards a double-fire / near-zero dt from yielding a ~0 threshold (false strike)

-- player -> { lastPos, validCFrame, strikes, excusedUntil, lastSampleTime }
--   lastPos       = the anchor position the current sample is diffed against; it
--                   is the last VALID (under-threshold) position, NOT simply the
--                   previous sample — see the strike/clean invariant in checkPlayer
--   validCFrame   = full CFrame of that same valid position (the snap-back target)
--   lastSampleTime = os.clock of the previous processed sample (for real dt)
local moveState = {}
-- player -> { tokens: number, last: number } (os.clock of last refill)
local promptBuckets = {}

local function notify(player, text)
	deps.Remotes.Notify:FireClient(player, text)
end

-- ===== Prompt rate limiting (safe pre-Init) =====

-- Token bucket: PROMPT_BURST triggers back-to-back, then one token every
-- PROMPT_REFILL seconds. Returns false when empty so the caller drops the
-- trigger. Tuned so a few quick legit pickups never trip but 20/s macro spam
-- does. First call for a player seeds a full bucket.
function AntiCheatService.AllowPrompt(player)
	local now = os.clock()
	local bucket = promptBuckets[player]
	if not bucket then
		bucket = { tokens = PROMPT_BURST, last = now }
		promptBuckets[player] = bucket
	end
	local refilled = (now - bucket.last) / PROMPT_REFILL
	if refilled > 0 then
		bucket.tokens = math.min(PROMPT_BURST, bucket.tokens + refilled)
		bucket.last = now
	end
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

-- ===== Movement excuse (safe pre-Init) =====

-- Marks a legit teleport: clears the sample state (so the post-teleport position
-- re-establishes cleanly once the window ends) and suppresses checks for
-- EXCUSE_DURATION. Also fired on CharacterAdded (respawn placement is a legit
-- pivot). No-ops if the player has no state yet (pre-Init / not tracked).
function AntiCheatService.Excuse(player)
	local state = moveState[player]
	if not state then
		return
	end
	state.excusedUntil = os.clock() + EXCUSE_DURATION
	state.lastPos = nil
	state.validCFrame = nil
	state.strikes = 0
end

-- ===== Movement sampling =====

local function checkPlayer(player, now)
	local state = moveState[player]
	if not state or now < state.excusedUntil then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		-- Dead / not yet spawned: drop the sample so a respawn elsewhere isn't
		-- diffed against the death position (CharacterAdded re-excuses anyway).
		state.lastPos = nil
		state.validCFrame = nil
		state.strikes = 0
		return
	end

	local pos = root.Position
	if not state.lastPos then
		state.lastPos = pos
		state.validCFrame = root.CFrame
		state.lastSampleTime = now
		state.strikes = 0
		return
	end

	-- Budget scales with REAL elapsed time, not the nominal interval: task.wait
	-- returns late under load, so a fixed 43.2-stud budget would snap a legit
	-- sprinter after a couple of slow ticks. A legit character also can't move
	-- faster than its walkspeed, so an over-budget sample means a real teleport
	-- (excused), server-scheduling lag (absorbed by the larger dt), or a hack.
	local dt = math.max(now - (state.lastSampleTime or now), MIN_DT)
	local limit = maxSpeed * dt
	-- Horizontal (XZ) distance only: a cliff fall is vertical and must not trip
	-- the gate. The SPEED_BUFFER (1.8x) plus the 3-strike rule absorb the rest.
	-- NOTE: if legit long falls ever trip this in playtesting, exempting Freefall
	-- state from strike accumulation is the knob — but a flying exploiter also
	-- sits in Freefall, so per the plan we count all states and rely on the buffer.
	local dx = pos.X - state.lastPos.X
	local dz = pos.Z - state.lastPos.Z
	if dx * dx + dz * dz > limit * limit then
		-- INVARIANT (strike): advance lastSampleTime, KEEP the anchor. We keep
		-- diffing against the last valid position, so a player who teleports and
		-- then stands still keeps striking against the pre-teleport anchor and
		-- snaps on the 3rd. Advancing lastPos here (to the post-teleport spot)
		-- would let an idle frame read as "clean" and launder the jump — that was
		-- the alternating teleport-then-idle bypass. Time MUST still advance, or
		-- the next dt inflates and legitimizes the very divergence we're tracking.
		state.strikes += 1
		state.lastSampleTime = now
		if state.strikes >= MAX_STRIKES then
			-- Snap to the last under-threshold sample and kill velocity. NOTE: the
			-- client owns its character's physics (network ownership), so it can
			-- re-diverge the very next frame; the 1s loop re-detecting and
			-- re-snapping is the accepted mitigation — this teleport is not assumed
			-- to "stick", so we don't try to lock the character server-side.
			root.CFrame = state.validCFrame
			root.AssemblyLinearVelocity = Vector3.zero
			notify(player, "Slow down.")
			state.strikes = 0
			state.lastPos = state.validCFrame.Position
		end
		return
	end

	-- INVARIANT (clean): advance BOTH the anchor and the time, and promote this
	-- position to the new snap-back target. (strike: advance time, keep anchor;
	-- clean: advance both.)
	state.strikes = 0
	state.lastPos = pos
	state.validCFrame = root.CFrame
	state.lastSampleTime = now
end

-- ===== Join / leave =====

local function onPlayerAdded(player)
	moveState[player] = { strikes = 0, excusedUntil = 0 }
	-- Spawn/respawn placement is a legit pivot (ProgressService places fresh
	-- characters). streamAndPivot ALSO re-excuses right before its pivot, which
	-- covers the case where the stream+pivot latency outlasts this window.
	player.CharacterAdded:Connect(function()
		AntiCheatService.Excuse(player)
	end)
	player.CharacterRemoving:Connect(function()
		local state = moveState[player]
		if state then
			state.lastPos = nil
			state.validCFrame = nil
			state.strikes = 0
		end
	end)
end

local function onPlayerRemoving(player)
	moveState[player] = nil
	promptBuckets[player] = nil
end

function AntiCheatService.Init(depsIn)
	deps = depsIn
	local Config = deps.Config

	SAMPLE_INTERVAL = Config.ANTICHEAT_SAMPLE_INTERVAL
	SPEED_BUFFER = Config.ANTICHEAT_SPEED_BUFFER
	SPRINT_SPEED = Config.SPRINT_SPEED
	MAX_STRIKES = Config.ANTICHEAT_MAX_STRIKES
	EXCUSE_DURATION = Config.ANTICHEAT_EXCUSE_DURATION
	PROMPT_BURST = Config.ANTICHEAT_PROMPT_BURST
	PROMPT_REFILL = Config.ANTICHEAT_PROMPT_REFILL
	maxSpeed = SPRINT_SPEED * SPEED_BUFFER

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		if not moveState[player] then
			onPlayerAdded(player)
		end
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			task.wait(SAMPLE_INTERVAL)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(checkPlayer, player, now)
				if not ok then
					warn("[AntiCheatService] check error for " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return AntiCheatService
