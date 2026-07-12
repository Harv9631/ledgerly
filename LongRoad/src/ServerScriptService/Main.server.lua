-- Main: bootstraps all services in dependency order
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteSetup = require(ReplicatedStorage:WaitForChild("RemoteSetup"))

local servicesFolder = script.Parent:WaitForChild("Services")
local deps = {
	Remotes = RemoteSetup.Get(),
	Config = require(ReplicatedStorage:WaitForChild("GameConfig")),
	ItemDefs = require(ReplicatedStorage:WaitForChild("ItemDefs")),
}

-- Dependency order matters: earlier services must not require later ones.
local ORDER = {
	"DayNightService", "InventoryService", "SurvivalService", "FireService",
	"LootService", "CombatService", "MonsterService", "SquadService",
	"ProgressService", "AntiCheatService", "DebugService",
}

for _, name in ipairs(ORDER) do
	local mod = servicesFolder:FindFirstChild(name)
	if mod then
		local service = require(mod)
		deps[name:gsub("Service$", "")] = service
	end
end
for _, name in ipairs(ORDER) do
	local key = name:gsub("Service$", "")
	if deps[key] and deps[key].Init then
		deps[key].Init(deps)
		print("[Main] " .. name .. " initialized")
	end
end
