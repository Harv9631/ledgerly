-- RemoteSetup: creates (server) or fetches (client) all RemoteEvents
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	-- client -> server
	"EatItem", "UseItem", "EquipSlot", "DropItem", "PlaceFire", "AddFuel",
	"CookMeat", "SwingWeapon", "FireProjectile", "SquadInvite", "SquadResponse",
	"SquadLeave", "BuyKit", "SetSprinting",
	-- server -> client
	"InventoryUpdate", "Notify", "TimeUpdate", "SquadUpdate", "RunFinished",
}

local RemoteSetup = {}
function RemoteSetup.Get()
	local folder
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		for _, name in ipairs(REMOTE_NAMES) do
			if not folder:FindFirstChild(name) then
				local r = Instance.new("RemoteEvent")
				r.Name = name
				r.Parent = folder
			end
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes")
	end
	local remotes = {}
	for _, name in ipairs(REMOTE_NAMES) do
		remotes[name] = folder:WaitForChild(name)
	end
	return remotes
end
return RemoteSetup
