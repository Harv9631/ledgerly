# The Long Road — Game Design Spec

**Date:** 2026-07-11
**Status:** Approved by Harvey
**Project location:** `C:\Users\harve\LongRoad` (Rojo + Luau, same workflow as Dress to Survive)

## Concept

A journey-survival Roblox game. Players trek across a huge realistic map — pine forest,
abandoned suburbs, a river and mountain highlands, and a final ruined city — and must
reach the Extraction Point at the far end alive. Along the way they manage hunger and
warmth (gather food, build fires), fight or avoid monsters, dodge environmental hazards,
and contend with other players (full PvP with optional squads).

- **Run format:** open drop-in journey. Players spawn at the start zone whenever they
  join and travel at their own pace.
- **Target journey time:** 30–45 minutes for a decent player who doesn't die.
- **Visuals:** realistic. Harvey supplies realistic models in Studio; scripts generate
  terrain and place models via a marker system (placeholders until models exist).

## World & Progression

Map is roughly 4000×12000 studs, StreamingEnabled, four zones in sequence:

1. **Zone 1 — Pine Forest (start).** Dense trees, a stream, berry bushes and mushrooms.
   Tutorial-easy; first campfire spot teaches the fire mechanic. Mild monsters at night only.
2. **Zone 2 — Abandoned Suburbs.** Overgrown houses and strip malls to loot (canned food,
   melee weapons). Collapsing floors as hazards; more monsters indoors.
3. **Zone 3 — River & Highlands.** Wide river crossing (bridge = PvP hotspot, or risky
   swim with a cold penalty only a fire can fix), cliffs, and a cold mountain pass where
   warmth drains fast.
4. **Zone 4 — Ruined City (finale).** Dense urban ruins, best loot (ranged weapons),
   heaviest monster presence, toxic zones to route around. **Extraction Point** at the
   far edge ends the run.

**Checkpoints (5):** Forest camp → Suburb gas station → Bridge/river camp → Mountain pass
shelter → City gate. Touching one sets respawn. Death = respawn at last checkpoint; items
drop where you died in a loot bag anyone can take, despawning after 2 minutes.

**Finishing:** reaching the Extraction Point awards currency and a leaderboard entry
(fastest time, total completions), then teleports the player back to the start to run
again. Currency buys cosmetic perks and starter kits.

**Day/night cycle:** ~12 minutes real time. Night = aggressive monster spawns, faster
warmth drain, low visibility. Fires become genuinely necessary at night.

## Survival Systems

**Hunger (0–100):** drains ~1 point per 20 seconds, faster while sprinting. Below 25:
no sprinting. At 0: health drains. Food sources:
- Berries/mushrooms foraged in forest (small fill; mushrooms risk sickness)
- Canned food looted from buildings (big fill)
- Cooked meat — raw meat drops from certain monsters/animals, must be cooked at a fire
  (best fill; rewards the fire loop)

**Warmth (0–100):** drains at night, in rain, in the mountain pass, and hard after
swimming. Below 25: slower movement, frost screen effect. At 0: health drains. Restored
by standing near a fire, or slowly inside sheltered checkpoint zones.

**Fires:** gather wood by chopping trees or picking up branches (axe speeds it up).
3 wood = campfire, placeable on ground anywhere. Burns ~3 minutes; feed wood to extend.
Fires restore warmth, cook meat, and ward off monsters within their light radius — but
firelight is visible from far away, revealing your position to other players. Core
night-time risk/reward.

**Inventory:** 6-slot hotbar + 6-slot backpack. Item types: weapons, food, wood, medkits,
flares. No crafting tree beyond fires in v1 (YAGNI — crafting can come later).

## Combat & Players

**Weapons:** melee tier ladder — plank → bat → fire axe (ascending damage/speed). Rare
ranged: bow (Zone 3+), crossbow (Zone 4), limited arrows. Same weapons vs monsters and
players. Server-authoritative hit detection with swing cooldowns; no combo system.

**Monsters:**
- **Shamblers** — slow, common, indoors and at night
- **Stalkers** — fast forest predators, night only, flee from fire
- **Brutes** — rare city mini-bosses guarding the best loot

**Squads:** invite via player list, max 4. No friendly fire; shared checkpoint respawn
(respawn at a squad-mate's checkpoint if further along); can drop items for each other.

**PvP:** enabled everywhere against non-squad players. Killing a player marks the killer
"Hostile" (red name-tint) for 5 minutes so aggressors are visible.

## Architecture

### Map pipeline (bake in Studio)

A `MapBuilder` module run **once** in Studio via a command-bar one-liner:
1. Sculpts all four zones of smooth terrain (hills, river, cliffs, roads).
2. Places invisible **marker parts** across the map, named by category
   (`Marker_Tree_Pine`, `Marker_Building_House`, `Marker_Loot_Canned`, …).
3. A `ModelPlacer` step swaps every marker for a random matching model from
   `ReplicatedStorage/Assets/<Category>/<Name>` with rotation/scale variance.
   Missing categories get readable placeholder shapes, so the game is fully playable
   before any real models exist. Re-running the placer upgrades visuals with zero code
   changes.

The baked map is saved into the place file; servers start instantly.

### Server systems (one module each, event-driven)

| Module | Responsibility |
|---|---|
| `SurvivalService` | Hunger/warmth ticks, sickness, death causes |
| `FireService` | Fire placement, fuel, warmth/cook/ward radius |
| `LootService` | Zone loot spawns, respawn timers, death-drop bags |
| `MonsterService` | Spawn rules by zone/time, chase AI, fire avoidance |
| `CombatService` | Server-authoritative melee/ranged validation, PvP + Hostile marking |
| `SquadService` | Invites, no friendly fire, shared checkpoints |
| `ProgressService` | Checkpoints, extraction, currency, leaderboards (DataStore) |
| `DayNightService` | Clock, lighting, monster spawn-rate multiplier |

### Client

HUD (hunger/warmth bars, hotbar), ProximityPrompt interactions (loot / chop / place fire),
cold and night screen effects, squad UI.

### Anti-cheat basics

Server validates all eating/damage/pickups. Movement sanity checks (teleport/speed
detection) since the game is a race to the end.

### Persistence

DataStore: currency, perks, best time, total completions. Run progress (checkpoint,
inventory) is per-session only — leaving mid-run restarts the trek. Keeps v1 scope sane.

### Testing

- Solo-testing flags (MIN_PLAYERS-style) as in Dress to Survive.
- `DebugService` (Studio-only): teleport-to-zone and stat-set commands so every zone can
  be verified without 30-minute walks.

## Out of Scope for v1

- Crafting beyond campfires
- Base building
- Mid-run save/rejoin
- Procedural map variation
- Monetization passes (design later once the core loop is proven)
