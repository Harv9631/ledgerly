-- InventoryService: server-authoritative inventory (hotbar + backpack + equipped Tool)
--
-- Data model per player: { hotbar = {[1..HOTBAR_SLOTS] = {id, count} or nil},
--                          backpack = {[1..BACKPACK_SLOTS] = ...}, equipped = index or nil,
--                          tool = Tool instance or nil }
-- Snapshots sent to clients encode empty slots as `false` (not nil) so the arrays
-- stay dense: Roblox remotes truncate sparse arrays at the first hole.
local Players = game:GetService("Players")

local MELEE_HANDLE_SIZE = Vector3.new(1, 4, 1)
local RANGED_HANDLE_SIZE = Vector3.new(1, 4, 0.5)
local DEFAULT_WEAPON_COLOR = Color3.fromRGB(120, 120, 120)
local WEAPON_COLORS = {
	Plank = Color3.fromRGB(133, 94, 66),     -- brown wood
	Bat = Color3.fromRGB(163, 162, 165),     -- gray aluminum
	FireAxe = Color3.fromRGB(99, 95, 98),    -- dark gray steel
	Bow = Color3.fromRGB(105, 64, 40),       -- dark wood
	Crossbow = Color3.fromRGB(80, 60, 50),   -- dark wood
}
local DROP_DISTANCE = 4 -- studs in front of HumanoidRootPart

local InventoryService = {}

local deps
local inventories = {} -- player -> data model above

local function notify(player, text)
	deps.Remotes.Notify:FireClient(player, text)
end

local function stackSize(def)
	return def.stack or 1
end

-- Dense deep copy: empty slots become `false` so the array serializes intact.
local function copySlots(slots, size)
	local out = table.create(size)
	for i = 1, size do
		local s = slots[i]
		out[i] = s and { id = s.id, count = s.count } or false
	end
	return out
end

-- Snapshot is a fresh deep copy every time: clients (or later mutation of the
-- returned table) can never corrupt the server-side inventory.
local function pushUpdate(player)
	local inv = inventories[player]
	if not inv then
		return
	end
	deps.Remotes.InventoryUpdate:FireClient(player, {
		hotbar = copySlots(inv.hotbar, deps.Config.HOTBAR_SLOTS),
		backpack = copySlots(inv.backpack, deps.Config.BACKPACK_SLOTS),
		equipped = inv.equipped,
	})
end

local function isValidSlot(n, max)
	return type(n) == "number" and n == math.floor(n) and n >= 1 and n <= max
end

local function createTool(player, itemId, def)
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end
	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ManualActivationOnly = false
	tool:SetAttribute("ItemId", itemId)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = def.type == "Ranged" and RANGED_HANDLE_SIZE or MELEE_HANDLE_SIZE
	handle.Color = WEAPON_COLORS[itemId] or DEFAULT_WEAPON_COLOR
	handle.CanCollide = false
	handle.Parent = tool
	tool.Parent = character
	return tool
end

-- Reconcile the Tool with whatever now sits in the equipped slot. Called after
-- every mutation: handles items landing in / leaving / swapping through the
-- equipped slot. Non-weapon items are "selected" with no Tool.
local function refreshEquipped(player)
	local inv = inventories[player]
	if not inv then
		return
	end
	local slot = inv.equipped and inv.hotbar[inv.equipped] or nil
	local def = slot and deps.ItemDefs[slot.id] or nil
	local wantsTool = def ~= nil and (def.type == "Melee" or def.type == "Ranged")
	if inv.tool then
		local stale = not inv.tool.Parent or not wantsTool or inv.tool:GetAttribute("ItemId") ~= slot.id
		if stale then
			inv.tool:Destroy()
			inv.tool = nil
		end
	end
	if wantsTool and not inv.tool then
		inv.tool = createTool(player, slot.id, def)
	end
end

-- Gives up to `count` of itemId. Partial fills ARE allowed: fills existing
-- stacks first, then empty hotbar slots, then empty backpack slots, keeping
-- whatever fits. Returns two values: fittedAll (false, plus Notify "Inventory
-- full", if ANY remainder did not fit; true only if the full count was placed)
-- and placedCount (how many were actually placed), so callers like
-- LootService (Task 8) can decrement pickups by exactly what was taken.
function InventoryService.GiveItem(player, itemId, count)
	local inv = inventories[player]
	local def = deps.ItemDefs[itemId]
	if not inv or not def or type(count) ~= "number" or count ~= count
		or count == math.huge or count < 1 then
		return false, 0
	end
	count = math.floor(count)
	local maxStack = stackSize(def)
	local remaining = count
	local changed = false

	local function topUp(slots, size)
		for i = 1, size do
			if remaining <= 0 then
				return
			end
			local s = slots[i]
			if s and s.id == itemId and s.count < maxStack then
				local add = math.min(maxStack - s.count, remaining)
				s.count += add
				remaining -= add
				changed = true
			end
		end
	end
	local function fillEmpty(slots, size)
		for i = 1, size do
			if remaining <= 0 then
				return
			end
			if not slots[i] then
				local add = math.min(maxStack, remaining)
				slots[i] = { id = itemId, count = add }
				remaining -= add
				changed = true
			end
		end
	end

	topUp(inv.hotbar, deps.Config.HOTBAR_SLOTS)
	topUp(inv.backpack, deps.Config.BACKPACK_SLOTS)
	fillEmpty(inv.hotbar, deps.Config.HOTBAR_SLOTS)
	fillEmpty(inv.backpack, deps.Config.BACKPACK_SLOTS)

	if changed then
		refreshEquipped(player) -- item may have landed in the equipped slot
		pushUpdate(player)
	end
	if remaining > 0 then
		notify(player, "Inventory full")
		return false, count - remaining
	end
	return true, count
end

-- Removes exactly `count`, or nothing at all (returns false if the player
-- lacks that many). Drains backpack stacks first, then hotbar, so equipped
-- weapons survive longest. If the equipped slot empties, its Tool is destroyed
-- (the slot stays selected, matching "equipping an empty slot selects it").
function InventoryService.RemoveItem(player, itemId, count)
	local inv = inventories[player]
	if not inv or type(count) ~= "number" or count ~= count
		or count == math.huge or count < 1 then
		return false
	end
	count = math.floor(count)
	if InventoryService.CountItem(player, itemId) < count then
		return false
	end
	local remaining = count
	local function take(slots, size)
		for i = 1, size do
			if remaining <= 0 then
				return
			end
			local s = slots[i]
			if s and s.id == itemId then
				local sub = math.min(s.count, remaining)
				s.count -= sub
				remaining -= sub
				if s.count <= 0 then
					slots[i] = nil
				end
			end
		end
	end
	take(inv.backpack, deps.Config.BACKPACK_SLOTS)
	take(inv.hotbar, deps.Config.HOTBAR_SLOTS)
	refreshEquipped(player)
	pushUpdate(player)
	return true
end

function InventoryService.CountItem(player, itemId)
	local inv = inventories[player]
	if not inv then
		return 0
	end
	local total = 0
	for i = 1, deps.Config.HOTBAR_SLOTS do
		local s = inv.hotbar[i]
		if s and s.id == itemId then
			total += s.count
		end
	end
	for i = 1, deps.Config.BACKPACK_SLOTS do
		local s = inv.backpack[i]
		if s and s.id == itemId then
			total += s.count
		end
	end
	return total
end

function InventoryService.HasItem(player, itemId, count)
	return InventoryService.CountItem(player, itemId) >= (count or 1)
end

-- Read-only slot inspection for SurvivalService's Eat/UseMedkit re-validation
-- (Task 7). Returns a copy so callers can never mutate inventory state.
-- container: "hotbar" | "backpack".
function InventoryService.GetSlot(player, container, index)
	local inv = inventories[player]
	if not inv then
		return nil
	end
	local slots, size
	if container == "hotbar" then
		slots, size = inv.hotbar, deps.Config.HOTBAR_SLOTS
	elseif container == "backpack" then
		slots, size = inv.backpack, deps.Config.BACKPACK_SLOTS
	else
		return nil
	end
	if not isValidSlot(index, size) then
		return nil
	end
	local s = slots[index]
	return s and { id = s.id, count = s.count } or nil
end

function InventoryService.GetEquipped(player)
	local inv = inventories[player]
	local slot = inv and inv.equipped and inv.hotbar[inv.equipped] or nil
	return slot and slot.id or nil
end

function InventoryService.GetEquippedSlot(player)
	local inv = inventories[player]
	return inv and inv.equipped or nil
end

-- Empties everything (including unequip/Tool destroy) and returns a flat
-- array of {id, count} stacks for death-bag spawning (Task 14).
function InventoryService.ClearAll(player)
	local inv = inventories[player]
	if not inv then
		return {}
	end
	local dropped = {}
	local function drain(slots, size)
		for i = 1, size do
			local s = slots[i]
			if s then
				table.insert(dropped, { id = s.id, count = s.count })
				slots[i] = nil
			end
		end
	end
	drain(inv.hotbar, deps.Config.HOTBAR_SLOTS)
	drain(inv.backpack, deps.Config.BACKPACK_SLOTS)
	inv.equipped = nil
	refreshEquipped(player) -- destroys the Tool
	pushUpdate(player)
	return dropped
end

-- ===== Remote handlers (everything validated server-side) =====

-- payload: number 1..HOTBAR_SLOTS = toggle-equip that hotbar slot (empty slot
-- just selects; re-equipping the equipped slot unequips), OR
-- {swap = {backpack = b, hotbar = h}} = swap backpack slot b with hotbar slot h.
-- Malformed payloads are rejected silently.
local function onEquipSlot(player, payload)
	local inv = inventories[player]
	if not inv then
		return
	end
	if type(payload) == "number" then
		if not isValidSlot(payload, deps.Config.HOTBAR_SLOTS) then
			return
		end
		inv.equipped = (inv.equipped == payload) and nil or payload
		refreshEquipped(player)
		pushUpdate(player)
	elseif type(payload) == "table" and type(payload.swap) == "table" then
		local b, h = payload.swap.backpack, payload.swap.hotbar
		if not isValidSlot(b, deps.Config.BACKPACK_SLOTS) or not isValidSlot(h, deps.Config.HOTBAR_SLOTS) then
			return
		end
		inv.backpack[b], inv.hotbar[h] = inv.hotbar[h], inv.backpack[b]
		refreshEquipped(player) -- h may be the equipped slot
		pushUpdate(player)
	end
end

-- Drops ONE item from a hotbar slot. LootService (Task 8) may not exist yet:
-- without it there is nowhere to put the pickup, so the drop is refused and
-- the item is NOT removed.
local function onDropItem(player, slotIndex)
	local inv = inventories[player]
	if not inv or not isValidSlot(slotIndex, deps.Config.HOTBAR_SLOTS) then
		return
	end
	local slot = inv.hotbar[slotIndex]
	if not slot then
		return
	end
	if not deps.Loot then
		notify(player, "Not yet")
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local dropPosition = root.Position + root.CFrame.LookVector * DROP_DISTANCE
	local itemId = slot.id
	slot.count -= 1
	if slot.count <= 0 then
		inv.hotbar[slotIndex] = nil
	end
	refreshEquipped(player)
	pushUpdate(player)
	deps.Loot.SpawnPickup(dropPosition, itemId, 1)
end

-- Eating/medkits route to SurvivalService (Task 7), which validates effects
-- and calls RemoveItem itself. We only pre-validate the slot's item type.
local function onEatItem(player, slotIndex)
	local inv = inventories[player]
	if not inv or not isValidSlot(slotIndex, deps.Config.HOTBAR_SLOTS) then
		return
	end
	local slot = inv.hotbar[slotIndex]
	local def = slot and deps.ItemDefs[slot.id]
	if not def or def.type ~= "Food" then
		return
	end
	if deps.Survival and deps.Survival.Eat then
		deps.Survival.Eat(player, slotIndex)
	else
		notify(player, "Not yet")
	end
end

local function onUseItem(player, slotIndex)
	local inv = inventories[player]
	if not inv or not isValidSlot(slotIndex, deps.Config.HOTBAR_SLOTS) then
		return
	end
	local slot = inv.hotbar[slotIndex]
	local def = slot and deps.ItemDefs[slot.id]
	if not def or def.type ~= "Medkit" then
		return
	end
	if deps.Survival and deps.Survival.UseMedkit then
		deps.Survival.UseMedkit(player, slotIndex)
	else
		notify(player, "Not yet")
	end
end

local function watchPlayer(player)
	inventories[player] = { hotbar = {}, backpack = {}, equipped = nil, tool = nil }
	player.CharacterAdded:Connect(function()
		local inv = inventories[player]
		if not inv then
			return
		end
		-- The Tool died with the old character; clear equipped state.
		if inv.tool then
			inv.tool:Destroy()
		end
		inv.tool = nil
		inv.equipped = nil
		pushUpdate(player) -- also serves as the initial snapshot for fresh clients
	end)
end

function InventoryService.Init(depsIn)
	deps = depsIn
	deps.Remotes.EquipSlot.OnServerEvent:Connect(onEquipSlot)
	deps.Remotes.DropItem.OnServerEvent:Connect(onDropItem)
	deps.Remotes.EatItem.OnServerEvent:Connect(onEatItem)
	deps.Remotes.UseItem.OnServerEvent:Connect(onUseItem)
	-- Clients request a snapshot once their InventoryUpdate listener is live:
	-- closes the FireClient-before-listener race on join (remotes don't queue).
	deps.Remotes.RequestInventory.OnServerEvent:Connect(pushUpdate)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		if not inventories[player] then
			watchPlayer(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		local inv = inventories[player]
		if inv and inv.tool then
			inv.tool:Destroy()
		end
		inventories[player] = nil
	end)
end

return InventoryService
