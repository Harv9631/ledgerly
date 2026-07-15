-- CombatService: server-authoritative melee & ranged combat, PvP squad guard,
-- and hostile-marking of players who kill other players.
--
-- The client (Interaction.client.lua) fires SwingWeapon / FireProjectile with a
-- client-side cooldown for feel, but the server re-validates everything (equip,
-- cooldown, ammo, aim direction) and is the sole authority on damage.
--
-- Damage attribution (RegisterDamage vs the internal path):
--   * dealDamage() is the ONLY thing that damages via combat. It is always
--     player-initiated, so it records the attacker AND sets LastDeathCause="PvP"
--     on a lethal blow to a player (SurvivalService's convention: set before the
--     damage that kills).
--   * RegisterDamage(victimChar, attackerPlayer) only records attribution memory
--     used to decide who to brand hostile when the victim later dies. It never
--     deals damage. MonsterService (Task 11) deals its own damage and sets its
--     own LastDeathCause="Monster", but calls RegisterDamage(char, nil) so a
--     monster landing the killing blow OVERWRITES any stale player attribution —
--     a player who traded a hit seconds earlier is not wrongly branded.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local MONSTER_TAG = "Monster"
local PROJECTILE_SIZE = Vector3.new(0.2, 0.2, 1.6) -- long axis is +Z, aligned to travel
local PROJECTILE_COLOR = Color3.fromRGB(120, 90, 55)
local EPSILON = 1e-3

local CombatService = {}

local deps
local projectilesFolder
local activeProjectiles = {} -- array of { part, dir, damage, shooter, traveled, expiry, params, exclude }

-- Per-player / per-character state, cleaned up on leave.
local lastPrimary = {} -- player -> os.clock() of last swing/shot (shared gate: no swap-to-bypass)
local lastHit = {}     -- character (player only) -> { attacker = player|nil, expiry }
local playerConns = {} -- player -> array of connections to disconnect

-- Cached in Init from Config.
local rangeSq, coneCos, spawnOffset, maxDistance, lifetime

local function getLiveChar(player)
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil
	end
	return character, root, humanoid
end

-- Climb to the nearest Model owning a Humanoid (character or monster).
local function resolveHumanoid(inst)
	local model = inst
	while model and model ~= workspace do
		if model:IsA("Model") then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return model, humanoid
			end
		end
		model = model.Parent
	end
	return nil, nil
end

-- ===== Attribution =====

function CombatService.RegisterDamage(victimChar, attackerPlayer)
	-- Only player victims are tracked: monsters are never branded hostile and
	-- MonsterService owns their death. Storing nil clears prior player
	-- attribution (see file header).
	if not victimChar or not Players:GetPlayerFromCharacter(victimChar) then
		return
	end
	local attacker = (typeof(attackerPlayer) == "Instance" and attackerPlayer:IsA("Player"))
		and attackerPlayer or nil
	lastHit[victimChar] = { attacker = attacker, expiry = os.clock() + deps.Config.DAMAGER_MEMORY }
end

-- Sole combat damage path. attackerPlayer is always a player here. Squad-mates
-- and self are never damaged. Returns true if damage was actually applied.
local function dealDamage(victimChar, humanoid, amount, attackerPlayer)
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
	if victimPlayer then
		if victimPlayer == attackerPlayer then
			return false
		end
		if deps.Squad and deps.Squad.SameSquad(attackerPlayer, victimPlayer) then
			return false
		end
		if humanoid.Health <= amount then
			victimPlayer:SetAttribute("LastDeathCause", "PvP")
		end
	end
	CombatService.RegisterDamage(victimChar, attackerPlayer)
	humanoid:TakeDamage(amount)
	return true
end

-- Squad-mates aren't valid melee targets so the swing can pass to a real enemy.
local function isFriendly(attacker, targetChar)
	local tp = Players:GetPlayerFromCharacter(targetChar)
	if not tp then
		return false
	end
	return tp == attacker or (deps.Squad ~= nil and deps.Squad.SameSquad(attacker, tp) == true)
end

-- ===== Melee =====

local function onSwing(player)
	local character, root = getLiveChar(player)
	if not character then
		return
	end
	local equippedId = deps.Inventory.GetEquipped(player)
	local def = equippedId and deps.ItemDefs[equippedId]
	if not def or def.type ~= "Melee" then
		return
	end
	local now = os.clock()
	if now - (lastPrimary[player] or -math.huge) < def.cooldown then
		return
	end
	lastPrimary[player] = now

	local origin = root.Position
	local look = root.CFrame.LookVector
	local best, bestHum, bestRoot, bestDistSq

	local function consider(targetChar)
		if targetChar == character then
			return
		end
		local humanoid = targetChar:FindFirstChildOfClass("Humanoid")
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
			or (humanoid and humanoid.RootPart)
		if not humanoid or humanoid.Health <= 0 or not targetRoot then
			return
		end
		if isFriendly(player, targetChar) then
			return
		end
		local offset = targetRoot.Position - origin
		local distSq = offset.X ^ 2 + offset.Y ^ 2 + offset.Z ^ 2
		if distSq > rangeSq then
			return
		end
		-- A target basically on top of us is always "in front"; otherwise gate
		-- by the cone (dot of unit-offset with facing).
		if distSq > EPSILON ^ 2 and offset.Unit:Dot(look) < coneCos then
			return
		end
		if not bestDistSq or distSq < bestDistSq then
			best, bestHum, bestRoot, bestDistSq = targetChar, humanoid, targetRoot, distSq
		end
	end

	for _, monster in ipairs(CollectionService:GetTagged(MONSTER_TAG)) do
		if monster:IsDescendantOf(workspace) then
			consider(monster)
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			consider(other.Character)
		end
	end

	if best then
		-- Occlusion: no reaching through a solid wall. Exclude both characters
		-- so the attacker's own body and the target don't count as blockers.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, best }
		if not workspace:Raycast(origin, bestRoot.Position - origin, params) then
			dealDamage(best, bestHum, def.damage, player)
		end
	end
end

-- ===== Ranged =====

local function spawnProjectile(shooter, shooterChar, position, dir, damage)
	local part = Instance.new("Part")
	part.Name = "Projectile"
	part.Size = PROJECTILE_SIZE
	part.Color = PROJECTILE_COLOR
	part.Material = Enum.Material.Wood
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false -- never obstruct anyone else's raycasts (placement, other shots)
	part.CFrame = CFrame.lookAt(position, position + dir)
	part.Parent = projectilesFolder

	local exclude = { shooterChar, projectilesFolder }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	table.insert(activeProjectiles, {
		part = part, dir = dir, damage = damage, shooter = shooter,
		traveled = 0, expiry = os.clock() + lifetime, params = params, exclude = exclude,
	})
end

local function onFire(player, direction)
	if typeof(direction) ~= "Vector3" then
		return
	end
	-- Reject NaN and zero/infinite-length aim before touching it.
	if direction.X ~= direction.X or direction.Y ~= direction.Y or direction.Z ~= direction.Z then
		return
	end
	local mag = direction.Magnitude
	if mag < EPSILON or mag == math.huge then
		return
	end
	local unit = direction / mag

	local character, root = getLiveChar(player)
	if not character then
		return
	end
	local equippedId = deps.Inventory.GetEquipped(player)
	local def = equippedId and deps.ItemDefs[equippedId]
	if not def or def.type ~= "Ranged" then
		return
	end
	local now = os.clock()
	if now - (lastPrimary[player] or -math.huge) < def.cooldown then
		return
	end
	if not def.ammo or not deps.Inventory.HasItem(player, def.ammo, 1) then
		return
	end
	if not deps.Inventory.RemoveItem(player, def.ammo, 1) then
		return
	end
	lastPrimary[player] = now
	-- Muzzle sits a few studs ahead, but if a thin wall is between the shooter
	-- and that offset, spawn AT the shooter so the shot can't originate past
	-- cover. Shooter is excluded so this never self-hits.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, projectilesFolder }
	local spawnPos = root.Position
	if not workspace:Raycast(root.Position, unit * spawnOffset, params) then
		spawnPos = root.Position + unit * spawnOffset
	end
	spawnProjectile(player, character, spawnPos, unit, def.damage)
end

local function stepProjectiles(dt)
	local step = deps.Config.PROJECTILE_SPEED * dt
	local now = os.clock()
	for i = #activeProjectiles, 1, -1 do
		local p = activeProjectiles[i]
		local remove = false
		if not p.part.Parent or now >= p.expiry or p.traveled >= maxDistance then
			remove = true
		else
			local from = p.part.Position
			local advance = math.min(step, maxDistance - p.traveled)
			local segment = p.dir * advance
			-- Re-cast the SAME segment after passing through a friendly/self so an
			-- enemy standing just behind them is still hit this frame. Bounded:
			-- each passthrough excludes one more model, so the loop terminates.
			while true do
				local hit = workspace:Raycast(from, segment, p.params)
				if not hit then
					local to = from + segment
					p.part.CFrame = CFrame.lookAt(to, to + p.dir)
					p.traveled += advance
					break
				end
				local model, humanoid = resolveHumanoid(hit.Instance)
				local victimPlayer = model and Players:GetPlayerFromCharacter(model)
				local passthrough = victimPlayer ~= nil and (victimPlayer == p.shooter
					or (deps.Squad ~= nil and deps.Squad.SameSquad(p.shooter, victimPlayer) == true))
				if passthrough then
					-- Squad-mate or the shooter's own (respawned) character: skip.
					table.insert(p.exclude, model)
					p.params.FilterDescendantsInstances = p.exclude
				else
					if model then
						dealDamage(model, humanoid, p.damage, p.shooter)
					end
					remove = true
					break
				end
			end
		end
		if remove then
			p.part:Destroy()
			table.remove(activeProjectiles, i)
		end
	end
end

-- ===== Hostile marking =====

local function onDied(victimPlayer, character)
	local rec = lastHit[character]
	lastHit[character] = nil
	if not rec or not rec.attacker or os.clock() > rec.expiry then
		return
	end
	local killer = rec.attacker
	if killer == victimPlayer or not killer.Parent then
		return -- attacker left the game
	end
	killer:SetAttribute("HostileUntil", os.time() + deps.Config.HOSTILE_DURATION)
end

-- Yields (Humanoid replicates a frame after CharacterAdded / on hot reload),
-- so always run via task.spawn — never from Init's synchronous path.
local function bindDeath(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Connect(function()
			onDied(player, character)
		end)
	end
end

local function watchPlayer(player)
	local conns = {}
	table.insert(conns, player.CharacterAdded:Connect(function(character)
		task.spawn(bindDeath, player, character)
	end))
	table.insert(conns, player.CharacterRemoving:Connect(function(character)
		lastHit[character] = nil -- per-life memory dies with the character
	end))
	playerConns[player] = conns
	if player.Character then
		task.spawn(bindDeath, player, player.Character)
	end
end

local function cleanupPlayer(player)
	local conns = playerConns[player]
	if conns then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		playerConns[player] = nil
	end
	lastPrimary[player] = nil
	if player.Character then
		lastHit[player.Character] = nil
	end
end

-- ===== Init =====

function CombatService.Init(depsIn)
	deps = depsIn
	local Config = deps.Config
	rangeSq = Config.MAX_MELEE_RANGE ^ 2
	coneCos = math.cos(math.rad(Config.MELEE_CONE_DEGREES))
	spawnOffset = Config.PROJECTILE_SPAWN_OFFSET
	maxDistance = Config.PROJECTILE_MAX_DISTANCE
	lifetime = Config.PROJECTILE_LIFETIME

	projectilesFolder = workspace:FindFirstChild("RuntimeProjectiles") or Instance.new("Folder")
	projectilesFolder.Name = "RuntimeProjectiles"
	projectilesFolder.Parent = workspace

	deps.Remotes.SwingWeapon.OnServerEvent:Connect(onSwing)
	deps.Remotes.FireProjectile.OnServerEvent:Connect(onFire)

	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		if not playerConns[player] then
			watchPlayer(player)
		end
	end
	Players.PlayerRemoving:Connect(cleanupPlayer)

	RunService.Heartbeat:Connect(function(dt)
		if #activeProjectiles == 0 then
			return
		end
		local ok, err = pcall(stepProjectiles, dt)
		if not ok then
			warn("[CombatService] projectile step error: " .. tostring(err))
		end
	end)
end

return CombatService
