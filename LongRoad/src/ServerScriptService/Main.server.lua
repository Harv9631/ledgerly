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
		local ok, result = pcall(require, mod)
		if ok then
			deps[name:gsub("Service$", "")] = result
		else
			warn("[Main] failed to load " .. name .. ": " .. tostring(result))
		end
	end
end
for _, name in ipairs(ORDER) do
	local key = name:gsub("Service$", "")
	if deps[key] and deps[key].Init then
		local ok, err = pcall(deps[key].Init, deps)
		if ok then
			print("[Main] " .. name .. " initialized")
		else
			warn("[Main] failed to init " .. name .. ": " .. tostring(err))
		end
	end
end
