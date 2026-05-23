# Finding: `CaravanGuardDirector` — Escort Event Mechanics

The CaravanGuard event in 1.x — players escort 3 chocobo-pulled
caravans across the world map between cities. Largest non-instance
Director subclass (742 lines).

Sources read:

```text
director/CaravanGuardDirector.lua    742 lines (init + UI methods)
```

## Init Signature

```lua
function CaravanGuardDirector:init(town, placeStart, placeEnd,
                                     name1, name2, name3)
```

So a caravan is parametrized by:
- `town` (int8) — destination town (1=Limsa, 2=Gridania, 3=Ul'dah)
- `placeStart` / `placeEnd` (int16) — start + end map zone ids
- `name1`, `name2`, `name3` (int32) — 3 caravan NPC name ids

So **each caravan has 3 NPCs**: the master + 2 assistants probably,
or 3 named chocobos.

## `work._temp` Schema (8 fields, client-only)

```text
uiStep         integer8     -- current UI step display
isFinished     boolean      -- caravan reached destination?
town           integer8     -- destination town id (1/2/3)
placeStart     integer16    -- starting zone
placeEnd       integer16    -- destination zone
name1          integer32    -- caravan NPC 1 name id
name2          integer32    -- caravan NPC 2 name id
name3          integer32    -- caravan NPC 3 name id
```

## `work._sync` Schema (8 fields, broadcast)

```text
step             integer8           -- server-controlled progress step
progressPer      integer8           -- progress percentage (0-100)
finishTime       integer32          -- timeout timestamp
chocoboStatus    array[3] integer8  -- 3 chocobo states (e.g.
                                       0=idle/1=moving/2=fleeing/3=down)
chocoboHPStatus  array[3] integer8  -- HP % for each chocobo
markerX          array[3] float     -- per-chocobo X position
markerY          array[3] float     -- per-chocobo Y position
markerZ          array[3] float     -- per-chocobo Z position
```

**3 chocobos** in the caravan. Each one tracks: status, HP%, and
3D position. The position arrays drive the minimap markers.

## `work._tag` (4 sync tags, for efficient updates)

```text
{step,     1, [{step}, {finishTime}]}
{progress, 1, [{progressPer}]}
{status,   1, [{chocoboStatus}, {markerX}, {markerY}, {markerZ}]}
{hp,       1, [{chocoboHPStatus}]}
```

Bundles for different update frequencies:
- `step` tag — when caravan crosses progress milestones (every ~25%)
- `progress` tag — frequent (1-5 sec) per-percent updates
- `status` tag — when chocobo state changes (attacked, escaped)
- `hp` tag — when chocobos take damage

So a server pushing the active caravan state distributes updates
across these 4 tags. The `progress` + `status` are hot-path
(updated multiple times per second); `step` and `hp` are
event-driven.

## `processUIInit` — Step-Based Logic

```lua
function CaravanGuardDirector:processUIInit()
  if work.step < 40:
    -- In transit -- show minimap marker at chocobo 1's position
    desktopWidget:setMiniMapWidgetMarkerData(2, 0, 1,
                                              markerX[1],
                                              markerY[1],
                                              markerZ[1])
  else:
    -- Arrived at destination -- play town-specific arrival effect
    if town == 1:  desktopWidget:openPublicEffectWidget(14)  -- Limsa
    elif town == 2: desktopWidget:openPublicEffectWidget(15)  -- Gridania
    elif town == 3: desktopWidget:openPublicEffectWidget(16)  -- Ul'dah
  end
end
```

Step thresholds:
- `step < 40`: caravan still in transit → minimap markers show
- `step >= 40`: arrived → trigger arrival celebration effect

Public effect IDs:
- **14** = Limsa Lominsa arrival
- **15** = Gridania arrival
- **16** = Ul'dah arrival

So the 3 city-states each have their own "caravan arrived" canned
animation (firework display, NPC cheers, etc.).

## The `step` Field Progression

Server-side step counter likely follows:
- 0..40 = in transit (UI shows minimap markers + progress bar)
- 40+ = arrived (UI shows arrival effects)

The granularity of step values (likely 0..50 or 0..100) controls
how often the `progress` tag updates fire client-side.

## Assessment

```text
Confirmed:
  - CaravanGuard has 3 chocobos per caravan (parallel arrays).
  - 3 NPC names per caravan (master + assistants).
  - 3 destination towns: Limsa (1), Gridania (2), Ul'dah (3).
  - Step counter < 40 = in transit, >= 40 = arrived.
  - 4 sync tags split state for efficient delta updates.
  - Per-chocobo state: status enum + HP% + 3D position.

Likely (High):
  - The 3 chocobos can be attacked individually (each has its own
    HP). Players escort by killing approaching mobs and reviving
    downed chocobos.
  - The chocoboStatus enum probably has values: 0=idle, 1=moving,
    2=stopped/attacked, 3=fleeing, 4=fallen.
  - Caravan path runs over multiple zone boundaries (placeStart
    to placeEnd are zone ids; the route between them is
    server-scripted).

Likely (Medium):
  - The arrival effects (14/15/16) play in the destination zone
    and visible to all players in that zone, not just escort
    participants -- creating a sense of community arrival.
  - The minimap markers (one per chocobo) let the client render
    the caravan's position even when the chocobos aren't on screen.

Speculative:
  - 1.x's caravan was a global event (similar to FFXI's gardening
    or FF14 ARR's hunts) -- spawning on a timer, drawing escort
    volunteers, rewarding XP/items on success.
  - The 3-chocobo design lets the event scale dynamically: more
    players = each chocobo gets more guards; fewer players = some
    chocobos may be undefended.
```

## Server Implementation Picture

A caravan event:

```text
1. SERVER SPAWNS CARAVAN (on timer or trigger):
   - Allocate CaravanGuardDirector instance
   - Set town, placeStart, placeEnd, name1/2/3
   - Set initial chocobo state (3 chocobos at start position)
   - Push to all visible clients in start zone

2. TRANSIT (hot loop, ~1 Hz):
   - Server moves chocobos along scripted path
   - Push markerX/Y/Z + chocoboStatus via "status" tag
   - Push progressPer (percent) via "progress" tag
   - Players see minimap markers + progress bar

3. COMBAT ENCOUNTERS (event-driven):
   - Mobs spawn near caravan; players engage
   - On chocobo damage: push chocoboHPStatus via "hp" tag
   - On chocobo down: push status[i] = 4 via "status" tag

4. ARRIVAL (step crosses 40):
   - Server pushes step = 40+ via "step" tag
   - Clients trigger town-specific arrival effect
   - Caravan despawns; rewards distributed
   - Director actor cleaned up via _onFinalize
```

Wire surface is small: 4 tags × ~10 bytes each = ~40 bytes per
caravan update, at 1 Hz = ~40 bytes/sec per visible client.
Negligible bandwidth even for many simultaneous caravan events.

The caravan event design closes another sample of the Director
pattern in action — it's the same lifecycle as InstanceRaid but
for **a multi-zone moving event** instead of an instanced zone.
