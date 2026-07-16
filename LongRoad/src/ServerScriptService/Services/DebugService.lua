-- DebugService: Studio-only chat commands for solo-testing the journey.
-- Chat commands are inherently Studio-only here: we gate on RunService:IsStudio()
-- once at Init and skip connecting entirely when disabled, so production servers
-- pay zero cost. We use the legacy Player.Chatted signal (per plan); it still fires
-- in Studio with the default TextChatService chat, which is all we need.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DebugService = {}

local deps

-- Parse a strictly-finite number from a token. Returns nil for missing/NaN/inf/garbage.
local function parseNumber(token)
	local n = tonumber(token)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

-- Resolve a player's live character parts, or nil (+ reason) if unavailable.
local function getChar(player)
	local char = player.Character
	if not char then
		return nil, "no character"
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil, "character not alive"
	end
	return char, root, humanoid
end

-- Teleport helper: positions carry Y=0 (resolved at bake), so we pivot 50 studs up
-- and let the character fall onto whatever ground is baked there.
local function teleportTo(char, position)
	char:PivotTo(CFrame.new(position + Vector3.new(0, 50, 0)))
end

local handlers = {}

-- /tp <1-4|cp1-cp5|end>
handlers.tp = function(player, args)
	local target = (args[1] or ""):lower()
	local char = getChar(player)
	if not char then
		print("[Debug] /tp: character not alive")
		return
	end
	local Config = deps.Config
	local pos
	if target == "end" then
		pos = Config.EXTRACTION_POSITION
	elseif target:match("^cp%d+$") then
		local idx = tonumber(target:sub(3))
		local cp = idx and Config.CHECKPOINTS[idx]
		if cp then
			pos = cp.position
		end
	elseif target:match("^%d+$") then
		local zone = Config.ZONES[tonumber(target)]
		if zone then
			pos = Vector3.new(0, 0, zone.zStart + 50) -- nudge inside the zone
		end
	end
	if not pos then
		print("[Debug] usage: /tp <1-4|cp1-cp5|end>")
		return
	end
	teleportTo(char, pos)
	print(string.format("[Debug] tp %s -> (%d, %d, %d)", player.Name, pos.X, pos.Y, pos.Z))
end

-- /give <ItemId> [count]
handlers.give = function(player, args)
	local requested = args[1]
	if not requested then
		print("[Debug] usage: /give <ItemId> [count]")
		return
	end
	-- Prefer exact casing; fall back to a case-insensitive match so /give arrow works.
	local itemId = deps.ItemDefs[requested] and requested or nil
	if not itemId then
		local lowered = requested:lower()
		for id in pairs(deps.ItemDefs) do
			if id:lower() == lowered then
				itemId = id
				break
			end
		end
	end
	if not itemId then
		print("[Debug] /give: unknown item '" .. requested .. "'")
		return
	end
	local count = 1
	if args[2] then
		local n = parseNumber(args[2])
		if not n or n < 1 then
			print("[Debug] /give: count must be a positive number")
			return
		end
		count = math.floor(n)
	end
	local ok, placed = deps.Inventory.GiveItem(player, itemId, count)
	if ok then
		print(string.format("[Debug] gave %s x%d to %s (%d placed)", itemId, count, player.Name, placed))
	else
		print("[Debug] /give: failed (inventory full or invalid)")
	end
end

-- /set <hunger|warmth|health|currency> <n>
handlers.set = function(player, args)
	local stat = (args[1] or ""):lower()
	local value = parseNumber(args[2])
	if value == nil then
		print("[Debug] usage: /set <hunger|warmth|health|currency> <n>")
		return
	end
	if stat == "hunger" or stat == "warmth" then
		local statName = stat == "hunger" and "Hunger" or "Warmth"
		deps.Survival.SetStat(player, statName, value) -- clamps to STAT_MAX
		print(string.format("[Debug] set %s %s = %s (clamped 0..%d)",
			player.Name, statName, tostring(value), deps.Config.STAT_MAX))
	elseif stat == "health" then
		local _, _, humanoid = getChar(player)
		if not humanoid then
			print("[Debug] /set health: character not alive")
			return
		end
		if value <= 0 then
			print("[Debug] /set health: value must be > 0 (not a kill switch)")
			return
		end
		humanoid.Health = math.min(value, humanoid.MaxHealth)
		print(string.format("[Debug] set %s Health = %d", player.Name, humanoid.Health))
	elseif stat == "currency" then
		local amount = math.max(0, math.floor(value))
		player:SetAttribute("Currency", amount) -- ProgressService (Task 14) owns this later
		print(string.format("[Debug] set %s Currency = %d", player.Name, amount))
	else
		print("[Debug] usage: /set <hunger|warmth|health|currency> <n>")
	end
end

-- /time <day|night>
handlers.time = function(_, args)
	local mode = (args[1] or ""):lower()
	if mode == "day" then
		deps.DayNight.ForceState(false)
		print("[Debug] time -> day")
	elseif mode == "night" then
		deps.DayNight.ForceState(true)
		print("[Debug] time -> night")
	else
		print("[Debug] usage: /time <day|night>")
	end
end

-- /rain <on|off>
handlers.rain = function(_, args)
	local mode = (args[1] or ""):lower()
	if mode == "on" then
		deps.DayNight.ForceRain(true)
		print("[Debug] rain -> on")
	elseif mode == "off" then
		deps.DayNight.ForceRain(false)
		print("[Debug] rain -> off")
	else
		print("[Debug] usage: /rain <on|off>")
	end
end

-- /spawnmonster <Type>
handlers.spawnmonster = function(player, args)
	local requested = args[1]
	if not requested or not deps.Config.MONSTERS[requested] then
		local names = {}
		for name in pairs(deps.Config.MONSTERS) do
			table.insert(names, name)
		end
		print("[Debug] usage: /spawnmonster <" .. table.concat(names, "|") .. ">")
		return
	end
	local char, root = getChar(player)
	if not char then
		print("[Debug] /spawnmonster: character not alive")
		return
	end
	local pos = root.Position + root.CFrame.LookVector * 20
	local monster = deps.Monster.SpawnMonster(requested, pos)
	if monster then
		print(string.format("[Debug] spawned %s 20 studs ahead of %s", requested, player.Name))
	else
		print("[Debug] /spawnmonster: spawn failed")
	end
end

-- /checkpoint <n>
handlers.checkpoint = function(player, args)
	local n = parseNumber(args[1])
	local maxIdx = #deps.Config.CHECKPOINTS
	if n == nil or n ~= math.floor(n) or n < 1 or n > maxIdx then
		print(string.format("[Debug] usage: /checkpoint <1-%d>", maxIdx))
		return
	end
	player:SetAttribute("CheckpointIndex", n) -- ProgressService (Task 14) owns respawn later
	print(string.format("[Debug] set %s CheckpointIndex = %d", player.Name, n))
end

local function onChatted(player, message)
	if message:sub(1, 1) ~= "/" then
		return
	end
	local parts = string.split(message, " ")
	local command = parts[1]:sub(2):lower()
	local args = {}
	for i = 2, #parts do
		if parts[i] ~= "" then
			table.insert(args, parts[i])
		end
	end
	local handler = handlers[command]
	if handler then
		handler(player, args)
	else
		print("[Debug] unknown command '/" .. command .. "'. Commands: "
			.. "/tp /give /set /time /rain /spawnmonster /checkpoint")
	end
end

local function watchPlayer(player)
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
end

function DebugService.Init(depsIn)
	deps = depsIn
	if not (deps.Config.DEBUG_COMMANDS and RunService:IsStudio()) then
		return -- disabled: connect nothing so production servers pay zero cost
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	print("[Debug] commands active (Studio): /tp /give /set /time /rain /spawnmonster /checkpoint")
end

return DebugService
