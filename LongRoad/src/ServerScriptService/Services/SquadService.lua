-- SquadService: friendly squads (max 4) with invites, and the no-friendly-fire
-- API that CombatService keys off. A squad is { id, members = {player, ...} };
-- each member carries a string `SquadId` attribute (nil when squad-less) that
-- the client reads to paint green squad-mate outlines.
--
-- Concurrency / safety contract (CombatService calls SameSquad from its damage
-- choke point and per projectile-passthrough hit):
--   * SameSquad and GetMembers read ONLY module-scope tables (initialized at
--     require time, before Init), touch no deps, and never yield or error, so
--     they are safe to call pre-Init (return false / empty) and cheap enough to
--     run per damage event.
--   * A departed Player object may be passed (projectiles outlive their shooter
--     up to a few seconds): PlayerRemoving clears that player's squad entry, so
--     SameSquad(departed, ...) reads nil and returns false. false in every
--     doubtful case.
--   * OnServerEvent handlers run serially and yield-free, so no invite/response
--     can interleave mid-handler.
--
-- SquadUpdate payload (full per-player snapshot, rebuilt fresh each push, like
-- InventoryService — the client re-renders wholesale and treats it as
-- idempotent). Both keys are always present so the table serializes intact:
--   squad  = { id = string, members = { {name=string, userId=number}, ... } }
--            OR false  (not in a squad)
--   invite = { inviter = string, expiresAt = number (os.time seconds) }
--            OR false  (no pending incoming invite)
-- The members array is dense (built by table.insert of live members only), so
-- there are no nil holes to truncate replication; `false` is the sentinel for
-- the two optional top-level fields.
local Players = game:GetService("Players")

local MAX_SQUAD_SIZE = 4
local INVITE_EXPIRY = 30    -- seconds (os.time); the client shows a matching countdown
local INVITE_RATE_LIMIT = 1 -- seconds (os.clock) between invites sent per player

local SquadService = {}

local deps

-- Module scope (NOT Init): the public queries must work pre-Init, so these
-- start empty rather than being built in Init.
local squads = {}       -- squadId -> { id = string, members = { player, ... } }
local playerSquad = {}   -- player -> squadId (nil = squad-less)
local invites = {}       -- target player -> { inviter = player, inviterName, expiresAt }
local lastInvite = {}    -- player -> os.clock() of their last sent invite (rate limit)
local nextSquadId = 0

local function notify(player, text)
	deps.Remotes.Notify:FireClient(player, text)
end

-- Returns the target's pending invite, lazily expiring (and clearing) it if the
-- 30s window has passed. Lazy expiry only: the client runs its own dismiss timer
-- for the visual, and the server re-checks here on every read, so a stale entry
-- can never be accepted or block a fresh invite.
local function getPendingInvite(target)
	local invite = invites[target]
	if not invite then
		return nil
	end
	if os.time() >= invite.expiresAt then
		invites[target] = nil
		return nil
	end
	return invite
end

local function buildSnapshot(player)
	local squadField = false
	local id = playerSquad[player]
	local squad = id and squads[id]
	if squad then
		local members = {}
		for _, member in ipairs(squad.members) do
			table.insert(members, { name = member.Name, userId = member.UserId })
		end
		squadField = { id = id, members = members }
	end
	local inviteField = false
	-- A squadded player can never legitimately hold an invite (onInvite rejects
	-- squadded targets), so suppress any straggler — e.g. the mutual-invite race
	-- where both players invited each other and one just joined the other's
	-- squad: without this, the new member would see a dangling invite prompt over
	-- their fresh squad frame.
	if not squadField then
		local invite = getPendingInvite(player)
		if invite then
			inviteField = { inviter = invite.inviterName, expiresAt = invite.expiresAt }
		end
	end
	return { squad = squadField, invite = inviteField }
end

-- FireClient to a leaving player is harmless, but guard so PlayerRemoving pushes
-- only reach members who are still present.
local function pushUpdate(player)
	if not player.Parent then
		return
	end
	deps.Remotes.SquadUpdate:FireClient(player, buildSnapshot(player))
end

-- Removes a player from their squad (voluntary leave OR leaving the game).
-- Disband ordering: SquadId attributes are cleared BEFORE the SquadUpdate
-- pushes. The client treats the attribute (drives green highlights) and the
-- SquadUpdate (drives the roster frame) as two INDEPENDENT idempotent signals
-- and re-evaluates each on arrival, so cross-signal network ordering is not
-- load-bearing — clearing attributes first just keeps the server's own view
-- consistent while it builds the snapshots.
local function removeFromSquad(player)
	local id = playerSquad[player]
	local squad = id and squads[id]
	if not squad then
		return
	end
	local i = table.find(squad.members, player)
	if i then
		table.remove(squad.members, i)
	end
	playerSquad[player] = nil
	player:SetAttribute("SquadId", nil)
	pushUpdate(player) -- clear the leaver's own squad frame (no-op if they left the game)

	if #squad.members <= 1 then
		-- Disband: a one-person squad is no squad. Clear the survivor too.
		squads[id] = nil
		local survivor = squad.members[1]
		if survivor then
			playerSquad[survivor] = nil
			survivor:SetAttribute("SquadId", nil)
			notify(survivor, "Squad disbanded")
			pushUpdate(survivor)
		end
	else
		for _, member in ipairs(squad.members) do
			pushUpdate(member)
		end
	end
end

-- ===== Public API (safe pre-Init: tables start empty, deps untouched) =====

-- Are two DISTINCT live players in the same squad? Self returns false: a player
-- is not their own squad-mate, and every consumer already short-circuits the
-- self case before calling here, so false is both safe and unsurprising.
function SquadService.SameSquad(p1, p2)
	if typeof(p1) ~= "Instance" or typeof(p2) ~= "Instance" then
		return false
	end
	if not p1:IsA("Player") or not p2:IsA("Player") or p1 == p2 then
		return false
	end
	local s1 = playerSquad[p1]
	return s1 ~= nil and s1 == playerSquad[p2]
end

-- All members of the player's squad (including the player), or {} if squad-less.
-- Returns a fresh array so callers can't mutate our roster.
function SquadService.GetMembers(player)
	local id = playerSquad[player]
	local squad = id and squads[id]
	if not squad then
		return {}
	end
	local out = {}
	for _, member in ipairs(squad.members) do
		table.insert(out, member)
	end
	return out
end

-- ===== Remote handlers (all inputs validated: exploiters send garbage) =====

local function onInvite(inviter, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		return
	end
	if target == inviter or target.Parent == nil then
		return
	end
	local now = os.clock()
	if now - (lastInvite[inviter] or -math.huge) < INVITE_RATE_LIMIT then
		return -- invite-spam guard: silent
	end
	-- Joining a squad requires leaving your current one first, so a target who is
	-- already in ANY squad can't be invited.
	if playerSquad[target] then
		notify(inviter, target.Name .. " is already in a squad")
		return
	end
	local id = playerSquad[inviter]
	if id and squads[id] and #squads[id].members >= MAX_SQUAD_SIZE then
		notify(inviter, "Your squad is full")
		return
	end
	-- One pending invite per target: a fresh invite from a DIFFERENT inviter
	-- replaces the old one (mirrors the client, which shows one prompt at a time
	-- and replaces on a new arrival). A duplicate from the SAME inviter is a
	-- no-op so the target isn't re-prompted.
	local existing = getPendingInvite(target)
	if existing and existing.inviter == inviter then
		return
	end
	lastInvite[inviter] = now
	invites[target] = {
		inviter = inviter,
		inviterName = inviter.Name,
		expiresAt = os.time() + INVITE_EXPIRY,
	}
	pushUpdate(target)
	notify(inviter, "Invited " .. target.Name)
end

local function onResponse(responder, inviterName, accepted)
	if typeof(inviterName) ~= "string" then
		return
	end
	local invite = getPendingInvite(responder)
	if not invite or invite.inviterName ~= inviterName then
		return -- no live invite addressed to them from that inviter (expired/stale/forged)
	end
	invites[responder] = nil -- consumed on any response

	if accepted ~= true then
		pushUpdate(responder) -- dismiss the prompt
		local inviter = invite.inviter
		if inviter.Parent then
			notify(inviter, responder.Name .. " declined your invite")
		end
		return
	end

	local inviter = invite.inviter
	if inviter.Parent == nil or inviter == responder then
		notify(responder, "That player is no longer available")
		pushUpdate(responder)
		return
	end
	if playerSquad[responder] then
		-- Raced into a squad since the invite was sent; keep them where they are.
		pushUpdate(responder)
		return
	end

	local id = playerSquad[inviter]
	local squad = id and squads[id]
	if not squad then
		-- Inviter was squad-less: form a new squad around them.
		nextSquadId += 1
		id = "squad" .. nextSquadId
		squad = { id = id, members = { inviter } }
		squads[id] = squad
		playerSquad[inviter] = id
		inviter:SetAttribute("SquadId", id)
	end
	if #squad.members >= MAX_SQUAD_SIZE then
		-- Squad filled up between invite and accept.
		notify(responder, "That squad is full now")
		pushUpdate(responder)
		return
	end

	table.insert(squad.members, responder)
	playerSquad[responder] = id
	responder:SetAttribute("SquadId", id)
	for _, member in ipairs(squad.members) do
		pushUpdate(member)
		if member ~= responder then
			notify(member, responder.Name .. " joined the squad")
		end
	end
	notify(responder, "Joined " .. inviter.Name .. "'s squad")
end

local function onLeave(player)
	removeFromSquad(player)
end

local function onPlayerRemoving(player)
	removeFromSquad(player) -- auto-remove; may disband / notify the rest
	invites[player] = nil   -- drop their incoming invite
	for target, invite in pairs(invites) do
		if invite.inviter == player then
			invites[target] = nil
			pushUpdate(target) -- clear a prompt whose inviter just left
		end
	end
	lastInvite[player] = nil
end

function SquadService.Init(depsIn)
	deps = depsIn
	deps.Remotes.SquadInvite.OnServerEvent:Connect(onInvite)
	deps.Remotes.SquadResponse.OnServerEvent:Connect(onResponse)
	deps.Remotes.SquadLeave.OnServerEvent:Connect(onLeave)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return SquadService
