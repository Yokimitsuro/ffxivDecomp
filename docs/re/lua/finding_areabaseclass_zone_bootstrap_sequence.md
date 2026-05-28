# Finding: areabaseclass.lua -- Zone Bootstrap Sequence (the "make-client-progress" entry flow)

**Maps the zone-entry bootstrap** — the AreaBase lifecycle that runs
when the client loads a zone. This is the sequence a server must
support to make the client progress past the loading screen (a stated
goal of the interoperability research).

AreaBaseClass (9s5989r57y9rr.lua, 471 lines) is the per-zone container
actor that owns the zone's CSV data, actor population count, and
per-frame content loop.

## 1. Zone lifecycle

```text
create(self, ?, isInstanceRaid, isEntranceDesion)
   ↓ (constructor -- called when zone actor is created)
_onInit(self, ...)                                    [296-376]
   ↓ 1. _callSuperClassFunc("_onInit")  -- ActorBase init
   ↓ 2. Declare areaWork._temp schema (see #2)
   ↓ 3. areaWork.isInstanceRaid = arg; areaWork.isEntranceDesion = arg
   ↓ 4. _setInstanceRaid(isInstanceRaid)
   ↓ 5. _setLoopInterval(1)              -- per-frame zone tick
   ↓ 6. FIRST-ZONE-LOAD (if desktopWidget doesn't exist yet):
   ↓      loadCommonTableData(region, zoneName)  -- shared CSVs
   ↓      _loadSpreadSheetPermanently()           -- zone data sheets
   ↓ 7. IF INN (_isInn): create "cutReplaySheet" SpreadSheet actor
   ↓                     (cutscene replay feature in inns)
   ↓
_onLoop(self)  [per-frame, interval=1]                [429-437]
   ↓ -> processLoop(self)  (empty in base; subclasses add content logic)
   ↓
_onFinalize(self)                                     [471]
   (zone teardown)
```

## 2. areaWork schema

```text
areaWork._temp (transient zone state):
  actorNumber       integer16   count of actors currently in zone
  isInstanceRaid    boolean     is this an instance/raid zone
  isEntranceDesion  boolean     entrance "decision" state (zone-in confirm?)
  _assignForChild   64          64-slot allocation for child actor bindings

WORK ACCESSORS (generic key-value over self.work):
  initWork / getTempWork / getSaveWork  -> read self.work[key]
  setTempWork / setSaveWork             -> write self.work[key]
  (area work is a flat key-value table; no save/temp tier split
   like charaWork -- the "Save/Temp" names are logical only)
```

The **_assignForChild = 64** is significant: a zone reserves 64 child
slots, suggesting a soft cap of ~64 actors assigned per area container
(matches the spawn pipeline's per-zone population + the 0x18d batch
255-record capacity for larger lists).

## 3. Zone type prefixes (category map)

From the work-actor naming logic:

```text
Zone category   Prefix
-------------   ------
Field           Fld
Dungeon         Dgn
Town            Twn
Battle          Btl
Test            Tes
Event           Evt
Ship            Shp
Office          Ofc
```

These 3-letter prefixes classify zones and drive CSV/actor naming.
Server zone tables should use the same categorization. The set
(Field/Dungeon/Town/Battle/Ship/Office + Test/Event) is the complete
1.x zone taxonomy.

## 4. SpreadSheet actor factory (prepareSpreadSheet)

```text
prepareSpreadSheet(self, sheetPath, skipDerive)        [381-423]
   ↓ if not skipDerive:
   ↓   name = lowerCamelCase(split(basename(sheetPath), "_")) .. "Sheet"
   ↓ if _isExistActor(name): return _getActorByName(name)
   ↓ else: return _createActor(name, "SpreadSheet", ..., sheetPath)

Creates (or reuses) a SpreadSheet data-actor for a zone CSV. The
sheet name is derived from the CSV path: basename -> lowerCamelCase
-> + "Sheet". E.g. "area/zoneName_data" -> "zoneNameDataSheet".

This is how a zone loads its specific data tables as queryable actors.
```

## 5. Zone-entry server bootstrap (the critical sequence)

```text
TO MAKE THE CLIENT PROGRESS PAST LOADING, the server must support:

1. WORLD/ZONE HANDOFF (per lobby flow findings):
   - Login -> character select -> world enter -> zone connect

2. ZONE ACTOR CREATION:
   - Client creates the AreaBase actor for the zone (local, from zone id)
   - _onInit runs: loads zone CSVs LOCALLY (loadCommonTableData +
     _loadSpreadSheetPermanently) -- these are CLIENT-LOCAL data
   - Sets loop interval = 1 (zone ticks per frame)

3. ACTOR POPULATION (server-driven):
   - Server sends spawn packets (0x17c) to populate the zone
   - Each spawn increments areaWork.actorNumber
   - Up to ~64 child-assigned actors per area

4. SCENE-READY:
   - Once zone CSVs loaded + initial actors spawned + player actor
     onInit complete (T3), the client can hide the loading screen
   - (The exact "scene ready" signal is likely a WorkSync flag or
     the player's _onInit completion + areaMaster ready state)

SERVER DATA NEEDED:
   - Zone definitions (id, name, region, category prefix, isInstanceRaid)
   - Per-zone actor population (NPCs, objects) for spawn packets
   - Zone CSVs are CLIENT-LOCAL (server doesn't push them; client
     loads from its own data files)

KEY INSIGHT: zone CSV DATA is loaded CLIENT-SIDE (not server-pushed).
The server's job is: zone handoff + actor population (spawns) +
state sync. The client already has all the static zone data locally.
```

## 6. Function inventory (16 functions)

```text
getZoneName, isNormalZone, isJailZone, isInstanceRaid, isEntranceDesion
  -- zone identity + type checks
initWork, getTempWork, getSaveWork, setTempWork, setSaveWork
  -- work key-value accessors
create, _onInit, prepareSpreadSheet, _onLoop, processLoop, _onFinalize
  -- lifecycle
```

Plus subfiles:
```text
9s5989r57y9rr_p.lua       (player-area interactions?)
9s5989r57y9rr_y9lvpq.lua  (layout -- zone geometry/regions)
kvw5/ (zone subdir)        per-zone-type logic
us1o9q59s59/ (privateArea) instanced/private zones
```

## 7. Confidence

```text
Confirmed:
  - Zone lifecycle: create -> _onInit -> _onLoop(interval=1) -> _onFinalize
  - areaWork schema: actorNumber, isInstanceRaid, isEntranceDesion,
    _assignForChild[64]
  - First-zone-load triggers CSV loading (loadCommonTableData +
    _loadSpreadSheetPermanently) -- CLIENT-LOCAL
  - Inn zones create cutReplaySheet (cutscene replay)
  - 8 zone-type prefixes (Fld/Dgn/Twn/Btl/Tes/Evt/Shp/Ofc)
  - prepareSpreadSheet = SpreadSheet data-actor factory (name from path)
  - 16 functions enumerated

Likely (High):
  - _assignForChild[64] = ~64-actor soft cap per area container
  - Zone CSVs are client-local (server doesn't push static zone data)
  - "scene ready" = player onInit (T3) + initial actor population done
  - isEntranceDesion = entrance confirmation / zone-in decision state

Speculative:
  - isJailZone = GM jail / penalty zone
  - The save/temp work split is logical-only (flat table in area)
  - kvw5 subdir holds per-zone-type processLoop overrides (content)
```

## 8. Cross-references

- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the spawn packets that populate the zone (areaWork.actorNumber)
- `finding_lobby_flow.md` -- the login/world-handoff that precedes zone entry
- `finding_bootup_state_machine.md` -- the ~58 bootup states
- `finding_csv_complete_correlation_132_of_164_critical_mapped.md`
  -- the zone CSVs loaded by loadCommonTableData
- `finding_application_mainTick_and_per_frame_subsystem_dispatch.md`
  -- the per-frame tick that drives _onLoop (interval=1)

## 9. Next test

```text
1. Read kvw5/ (zone subdir) for per-zone-type processLoop content logic
2. Read us1o9q59s59/ (privateArea) for instance/raid zone specifics
3. Read areabaseclass_layout (_y9lvpq) for zone geometry/region model
4. Find the exact "scene ready" / loading-complete signal
5. Trace loadCommonTableData -> the 22 shared CSVs (per CSV finding)
```

## Commit suggestion

```
docs(re/lua): areabaseclass.lua -- zone bootstrap sequence (create/_onInit/_onLoop); areaWork schema; 8 zone-type prefixes; zone CSVs are client-local; server job = handoff + spawn population
```
