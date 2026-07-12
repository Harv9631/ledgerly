-- Interaction: sprint, primary action (swing/shoot/place fire), eat/use, drop
--
-- Keeps its OWN copy of the latest InventoryUpdate snapshot via its own
-- listener (HUD.client.lua does the same; the two scripts share no state).
-- Snapshot convention: empty slots are `false`, equipped is an index or nil.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ItemDefs = require(ReplicatedStorage:WaitForChild("ItemDefs"))
local RemoteSetup = require(ReplicatedStorage:WaitForChild("RemoteSetup"))
local Remotes = RemoteSetup.Get()

local LocalPlayer = Players.LocalPlayer

-- ===== Key bindings / tuning =====
local SPRINT_KEY = Enum.KeyCode.LeftShift
local EAT_USE_KEY = Enum.KeyCode.F
local DROP_KEY = Enum.KeyCode.X
local PRIMARY_GAMEPAD_BUTTON = Enum.KeyCode.ButtonR2
local DEFAULT_COOLDOWN = 0.5 -- for actions without a def.cooldown (e.g. Wood -> PlaceFire)

local snapshot = nil
local lastPrimary = 0 -- os.clock() of the last primary action sent

Remotes.InventoryUpdate.OnClientEvent:Connect(function(snap)
	if typeof(snap) ~= "table" then
		return
	end
	snapshot = snap
end)
-- Listener is live: request the current snapshot (closes the join-time
-- FireClient-before-listener race; remotes don't queue).
Remotes.RequestInventory:FireServer()

-- Returns slotIndex, item, def for the equipped slot, or nil if nothing usable.
local function getEquipped()
	if not snapshot or not snapshot.equipped then
		return nil
	end
	local item = snapshot.hotbar and snapshot.hotbar[snapshot.equipped]
	if not item then -- empty slots are `false`
		return nil
	end
	local def = ItemDefs[item.id]
	if not def then
		return nil
	end
	return snapshot.equipped, item, def
end

-- Client-side cooldown gate matching def.cooldown to avoid remote spam;
-- the server remains authoritative on actual action rates.
local function onPrimaryAction()
	local _, _, def = getEquipped()
	if not def then
		return
	end
	local cooldown = def.cooldown or DEFAULT_COOLDOWN
	if os.clock() - lastPrimary < cooldown then
		return
	end
	if def.type == "Melee" then
		lastPrimary = os.clock()
		Remotes.SwingWeapon:FireServer()
	elseif def.type == "Ranged" then
		local camera = workspace.CurrentCamera
		if camera then
			lastPrimary = os.clock()
			Remotes.FireProjectile:FireServer(camera.CFrame.LookVector)
		end
	elseif def.type == "Wood" then
		lastPrimary = os.clock()
		Remotes.PlaceFire:FireServer()
	end
end

local function onEatUseKey()
	local slotIndex, _, def = getEquipped()
	if not slotIndex then
		return
	end
	if def.type == "Food" then
		Remotes.EatItem:FireServer(slotIndex)
	elseif def.type == "Medkit" then
		Remotes.UseItem:FireServer(slotIndex)
	end
end

local function onDropKey()
	local slotIndex = getEquipped()
	if slotIndex then
		Remotes.DropItem:FireServer(slotIndex)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == SPRINT_KEY then
		Remotes.SetSprinting:FireServer(true)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == PRIMARY_GAMEPAD_BUTTON then
		onPrimaryAction()
	elseif input.KeyCode == EAT_USE_KEY then
		onEatUseKey()
	elseif input.KeyCode == DROP_KEY then
		onDropKey()
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	-- Deliberately not gameProcessed-guarded: a sprint must always be releasable.
	if input.KeyCode == SPRINT_KEY then
		Remotes.SetSprinting:FireServer(false)
	end
end)

-- InputEnded does not fire for keys still held while Alt-Tabbing away, so a
-- focus loss would otherwise leave sprint stuck on.
UserInputService.WindowFocusReleased:Connect(function()
	Remotes.SetSprinting:FireServer(false)
end)
