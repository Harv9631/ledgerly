-- GameConfig: single source of truth for all tunable constants
local GameConfig = {}

-- ===== Map (journey runs along +Z) =====
GameConfig.MAP_WIDTH = 4000        -- X: -2000..2000
GameConfig.MAP_LENGTH = 12000      -- Z: 0..12000
GameConfig.ZONES = {
	{ name = "Forest",    zStart = 0,    zEnd = 3000 },
	{ name = "Suburbs",   zStart = 3000, zEnd = 6000 },
	{ name = "Highlands", zStart = 6000, zEnd = 9000 },
	{ name = "City",      zStart = 9000, zEnd = 12000 },
}
GameConfig.RIVER_Z = { 6300, 6500 }        -- water band across the map
GameConfig.MOUNTAIN_Z = { 7600, 8800 }     -- cold pass band
GameConfig.SPAWN_POSITION = Vector3.new(0, 0, 100)       -- Y resolved at bake
GameConfig.EXTRACTION_POSITION = Vector3.new(0, 0, 11800)
GameConfig.CHECKPOINTS = {
	{ name = "Forest Camp",      position = Vector3.new(0, 0, 1500) },
	{ name = "Gas Station",      position = Vector3.new(300, 0, 4500) },
	{ name = "Bridge Camp",      position = Vector3.new(0, 0, 6650) },
	{ name = "Mountain Shelter", position = Vector3.new(-400, 0, 8400) },
	{ name = "City Gate",        position = Vector3.new(0, 0, 9200) },
}
GameConfig.CHECKPOINT_SHELTER_RADIUS = 30  -- warmth regen zone around checkpoints

-- ===== Survival =====
GameConfig.STAT_MAX = 100
GameConfig.HUNGER_DRAIN = 0.05             -- per second
GameConfig.HUNGER_SPRINT_MULT = 2
GameConfig.WARMTH_DRAIN_DAY = 0.05
GameConfig.WARMTH_DRAIN_NIGHT = 0.4
GameConfig.WARMTH_RAIN_MULT = 2
GameConfig.WARMTH_MOUNTAIN_EXTRA = 1.0
GameConfig.SWIM_WARMTH_HIT = 40            -- instant loss entering river water
GameConfig.WET_DURATION = 60               -- seconds the Wet debuff lasts
GameConfig.WET_DRAIN_MULT = 2              -- warmth drain multiplier while wet
GameConfig.TOXIC_DPS = 4                   -- damage per second inside toxic zones
GameConfig.LOW_STAT = 25                   -- hunger<25: no sprint; warmth<25: slow+frost
GameConfig.STARVE_DPS = 2
GameConfig.FREEZE_DPS = 2
GameConfig.SICK_DURATION = 30
GameConfig.SICK_HUNGER_MULT = 3
GameConfig.SHELTER_WARMTH_REGEN = 2        -- per second at checkpoints
GameConfig.SURVIVAL_TICK = 1               -- seconds between ticks

-- ===== Movement =====
GameConfig.WALK_SPEED = 16
GameConfig.SPRINT_SPEED = 24
GameConfig.COLD_WALK_SPEED = 10

-- ===== Fires =====
GameConfig.FIRE_WOOD_COST = 3
GameConfig.FIRE_BURN_TIME = 180
GameConfig.FIRE_FUEL_PER_WOOD = 60
GameConfig.FIRE_WARMTH_RADIUS = 12
GameConfig.FIRE_WARMTH_REGEN = 5           -- per second
GameConfig.FIRE_WARD_RADIUS = 20           -- monsters keep out
GameConfig.FIRE_LIGHT_RANGE = 60
GameConfig.FIRE_COOK_TIME = 5              -- seconds to cook raw meat
GameConfig.TREE_CHOPS_BASE = 6             -- chop-points to fell a tree (axe chopPower counts double)
GameConfig.TREE_WOOD_YIELD = 3

-- ===== Day/Night =====
GameConfig.DAY_LENGTH = 480                -- seconds of day
GameConfig.NIGHT_LENGTH = 240              -- seconds of night (12 min total cycle)
GameConfig.RAIN_CHANCE = 0.3               -- per day cycle
GameConfig.RAIN_DURATION = 120

-- ===== Combat =====
GameConfig.HOSTILE_DURATION = 300          -- red-mark after player kill
GameConfig.MAX_MELEE_RANGE = 10            -- server-side reach validation
GameConfig.PROJECTILE_SPEED = 120

-- ===== Monsters =====
GameConfig.MONSTERS = {
	Shambler = { health = 60,  damage = 10, speed = 8,  aggroRange = 30, nightOnly = false, fearsFire = false },
	Stalker  = { health = 40,  damage = 15, speed = 22, aggroRange = 60, nightOnly = true,  fearsFire = true  },
	Brute    = { health = 300, damage = 30, speed = 12, aggroRange = 40, nightOnly = false, fearsFire = false },
}
GameConfig.MONSTER_CAPS = { Forest = 8, Suburbs = 14, Highlands = 10, City = 20 }
GameConfig.NIGHT_SPAWN_MULT = 2
GameConfig.MONSTER_MEAT_CHANCE = 0.5       -- raw meat drop chance

-- ===== Inventory =====
GameConfig.HOTBAR_SLOTS = 6
GameConfig.BACKPACK_SLOTS = 6
GameConfig.DEATH_BAG_LIFETIME = 120

-- ===== Loot =====
GameConfig.FORAGE_RESPAWN = 120            -- seconds until a foraged node refills
GameConfig.CRATE_REFILL = 300              -- seconds until a searched crate refills
GameConfig.FORAGE_PROMPT_RANGE = 8
GameConfig.FORAGE_HOLD = 1.5
GameConfig.SEARCH_HOLD = 2
GameConfig.LOOT_TABLES = {
	[1] = { { "CannedFood", 1, 50 }, { "Plank", 1, 25 }, { "Medkit", 1, 15 }, { "Bat", 1, 10 } },
	[2] = { { "CannedFood", 1, 30 }, { "Bat", 1, 20 }, { "Medkit", 1, 15 }, { "Arrow", 5, 15 }, { "FireAxe", 1, 10 }, { "Bow", 1, 10 } },
	[3] = { { "Arrow", 5, 25 }, { "Medkit", 1, 20 }, { "FireAxe", 1, 20 }, { "Crossbow", 1, 15 }, { "Bow", 1, 10 }, { "Flare", 1, 10 } },
}
-- each entry: { itemId, count, weight } — weights per tier sum to 100 but are normalized anyway

-- ===== Progress =====
GameConfig.EXTRACTION_REWARD = 100
GameConfig.TIME_BONUS_MAX = 100            -- linearly scaled: finish in 30min = full bonus, 60min = 0
GameConfig.DATASTORE_NAME = "LongRoad_v1"
GameConfig.STARTER_KITS = {
	{ id = "ScoutKit",   name = "Scout Kit",   cost = 150, items = { "Bat", "CannedFood", "CannedFood" } },
	{ id = "TrapperKit", name = "Trapper Kit", cost = 300, items = { "FireAxe", "Medkit", "Wood", "Wood", "Wood" } },
}

-- ===== Testing (REVERT BEFORE RELEASE) =====
GameConfig.DEBUG_COMMANDS = true           -- Studio-only chat commands

return GameConfig
