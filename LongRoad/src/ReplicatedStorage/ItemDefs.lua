-- ItemDefs: every item in the game, keyed by ItemId
-- type: "Melee" | "Ranged" | "Ammo" | "Food" | "Wood" | "Medkit" | "Flare"
local ItemDefs = {
	Plank      = { type = "Melee",  name = "Plank",       damage = 10, cooldown = 1.2, chopPower = 1 },
	Bat        = { type = "Melee",  name = "Baseball Bat",damage = 15, cooldown = 1.0, chopPower = 1 },
	FireAxe    = { type = "Melee",  name = "Fire Axe",    damage = 22, cooldown = 1.1, chopPower = 2 },
	Bow        = { type = "Ranged", name = "Bow",         damage = 30, cooldown = 1.5, ammo = "Arrow" },
	Crossbow   = { type = "Ranged", name = "Crossbow",    damage = 45, cooldown = 2.0, ammo = "Arrow" },
	Arrow      = { type = "Ammo",   name = "Arrow",       stack = 10 },
	Berries    = { type = "Food",   name = "Berries",     hunger = 10, sickChance = 0 },
	Mushroom   = { type = "Food",   name = "Mushroom",    hunger = 15, sickChance = 0.2 },
	CannedFood = { type = "Food",   name = "Canned Food", hunger = 40, sickChance = 0 },
	RawMeat    = { type = "Food",   name = "Raw Meat",    hunger = 5,  sickChance = 0.5, cooksInto = "CookedMeat" },
	CookedMeat = { type = "Food",   name = "Cooked Meat", hunger = 60, sickChance = 0 },
	Wood       = { type = "Wood",   name = "Wood",        stack = 6 },
	Medkit     = { type = "Medkit", name = "Medkit",      heal = 50 },
	Flare      = { type = "Flare",  name = "Flare",       duration = 30 },
}
return ItemDefs
