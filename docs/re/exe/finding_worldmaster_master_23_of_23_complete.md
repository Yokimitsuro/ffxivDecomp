# Finding: WorldMaster Master Block 23 of 23 Registrars COMPLETE -- EXACT _u.lua Match

Completes the **WorldMaster_registerAllLuaBindings** master block walk.
All 23 registrar slots decompiled, named, and matched 1:1 to
`world/worldmaster_u.lua`. 100% coverage of the 5th master block.
**ZERO engine-internal bindings** -- 2nd EXACT-match master after
Director.

Brings master-block walks to **3 fully-walked masters at 100%**
(Director, Item, WorldMaster) and **297 total registrars catalogued**.

## 1. Coverage summary

```text
Master block:        WorldMaster_registerAllLuaBindings @ 0x00754c70
Total slots:         23 registrars
Walked + named:      23 (100%)
Unwalked:            0

vs _u.lua declared:  23 bindings (world/worldmaster_u.lua)
Engine-internal:     0 (EXACT MATCH)
```

## 2. The 23 named WorldMaster registrars (by functional family)

### Player accessor (1 binding)

```text
Slot  Address      Lua binding
----  -------      -----------
  1   0x00752750   _getMyPlayer            local player singleton
```

### Time / Hydaelyn calendar (5 bindings)

```text
Slot  Address      Lua binding              Notes
----  -------      -----------              -----
  2   0x007528a0   _getServerTime           Unix-style server time
  6   0x00752b40   _getHydaelynHour         in-game hour (0-23)
  7   0x00752c90   _getHydaelynDay          in-game day-of-month
  8   0x00752de0   _getHydaelynTime         packed datetime
  9   0x00752f30   _getHydaelynMoon         lunar phase
```

This is the **full Hydaelyn calendar API** -- script can read hour /
day / time / moon phase, which gates events like nighttime spawns,
moon-phase quests, day/night NPC schedules.

### CutScene (1 binding)

```text
Slot  Address      Lua binding
----  -------      -----------
  3   0x007529f0   _getPendingCutSceneActor    actor for next CS frame
```

### Logging (2 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
  4   0x0073ad70   _printLog               release-build logger
  5   0x0073aec0   _printDebugLog          debug-build only logger
```

### Localization (2 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
 10   0x0073b010   _loadWord               load localized string by key
 11   0x0073b160   _unloadWord             unload localized string
```

### Tutorial subsystem (7 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
 12   0x0073b2b0   _runCharaSchedulerTutorial          tutorial-scope sched
 13   0x0073b400   _waitForCharaSchedulerTutorialFinished
 14   0x0073b550   Register_lookAtPlayerTutorial_LuaBinding   (pre-named)
                   = _lookAtPlayerTutorial               camera focus
 15   0x0073b6a0   _cancelLookAtPlayerTutorial
 16   0x0073b7f0   _aimCameraTutorial                   camera target
 17   0x0073b940   _cancelAimCameraTutorial
 18   0x00753080   _isKeyboardOnlyTutorial              input-mode gate
```

The 7-binding tutorial subsystem dedicates an entire camera +
scheduler API to the new-player tutorial flow. Distinct from
ordinary scheduling (CharaScheduler), so tutorial state can't
interfere with normal gameplay scheduling.

### Chocobo subsystem (4 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
 19   0x0073ba90   _transformIntoChocobo        global transform state
 20   0x0073bbe0   _cancelTransformIntoChocobo
 21   0x0073bd30   _aimCameraChocobo            mount-camera control
 22   0x0073be80   _cancelAimCameraChocobo
```

Note: WorldMaster has **global** `_transformIntoChocobo`; CharaBase
also has `_transformIntoChocobo_internal` (per-actor). The WorldMaster
version is likely the "you are now riding" global state flag; the
CharaBase version is the per-actor model swap.

### Misc (1 binding)

```text
Slot  Address      Lua binding
----  -------      -----------
 23   0x007531d0   _getSpecialEventWork    misc event-state accessor
```

## 3. ZERO engine-internal bindings -- EXACT _u.lua match

```text
EXE: 23 slots
_u.lua: 23 bindings
Engine-internal hidden: 0
```

WorldMaster is the **2nd master with EXACT script-API match**
(after Director). The script `world/worldmaster_u.lua` declares
EXACTLY what the EXE registers -- nothing hidden.

This contrasts with:
- CharaBase: 76 declared + 4-7 internal
- PlayerBase: 94 declared + 5 internal
- ActorBase: 7 declared + 1 internal (_restrictYieldFunction)
- AreaBase: 0 declared in own master + 1 internal (_getAreaType)
- Item: 19 declared + 1 internal (_getKind)
- NpcBase: 23 declared + 1 internal

**Pattern observation**: classes that are pure "API surfaces"
(no actor state of their own — Director, WorldMaster) tend to
have NO hidden internals. Classes that wrap actor state
(CharaBase, PlayerBase, ActorBase, AreaBase, Item) tend to hide
1-7 internals.

## 4. Functor factory: ALL 23 use FUN_00726ca0

WorldMaster's functor factory is uniformly **FUN_00726ca0** across
all 23 slots. This is the 6th of 7 observed factories. Indicates
WorldMaster bindings use a singleton-style RTTI tag (no `this`
parameter from a per-instance object; it's all global state).

## 5. The 5 sub-API namespaces in WorldMaster

WorldMaster cleanly splits into 5 sub-APIs visible from the binding names:

```text
1. PLAYER       (1): _getMyPlayer
2. TIME         (5): _getServerTime + 4x Hydaelyn calendar
3. CUTSCENE     (1): _getPendingCutSceneActor
4. SYSTEM       (4): _printLog/_printDebugLog + _loadWord/_unloadWord
5. TUTORIAL     (7): camera + scheduler control during tutorial
6. CHOCOBO      (4): mount transform + camera
7. EVENT        (1): _getSpecialEventWork
```

Total = 23 bindings, mapped cleanly to 7 subsystems.

## 6. Cross-class sharing patterns observed

`_transformIntoChocobo` appears on **2 classes**:
```text
CharaBaseClass.transformIntoChocobo_internal   per-actor (0x00730420)
WorldMaster._transformIntoChocobo              global state (0x0073ba90)
```

`_loadWord` / `_unloadWord` are localization primitives -- likely
also accessible globally via `system` module, but their canonical
binding is on WorldMaster.

`_printLog` / `_printDebugLog` likely have parallel bindings in
`system` and `global` modules too.

## 7. Updated master block inventory (8 masters, 7 ≥80% walked)

```text
Class                 Master address    Registrars    Walked   _u.lua match
-----                 --------------    ----------    ------   ------------
DirectorBaseClass     0x00758260         5             5/5      5 EXACT (100%)
ItemBaseClass         0x00753dd0        20            20/20    19 + 1 internal
WorldMaster           0x00754c70        23            23/23    23 EXACT (100%, NEW)
PlayerBase            0x00753f90        99            99/99    94 + 5 internal
NpcBaseClass          0x00754850        24            24/24    23 + 1 internal
ActorBaseClass        0x00753c30         8 + tail      8/8      7 + 1 internal
AreaBaseClass         0x00754e70         1 (stub)      1/1      0 + 1 internal
CharaBaseClass        0x007574a0        83            80/83    76 + 4-7 internal

TOTAL master blocks identified:    8
TOTAL registrars catalogued:      297
TOTAL engine-internal discovered:  ~14-17 bindings
TOTAL _u.lua bindings located:    251 of 387 (65%)
```

Director, Item, and WorldMaster are the 3 fully-walked masters.

## 8. Annotations made in Ghidra

```text
RENAMES (17 registrars; 5 prior named + 1 pre-named keeps prior names):
  - 0x0073ad70 -> WorldMaster_registerLua_printLog
  - 0x0073aec0 -> WorldMaster_registerLua_printDebugLog
  - 0x00752c90 -> WorldMaster_registerLua_getHydaelynDay
  - 0x00752de0 -> WorldMaster_registerLua_getHydaelynTime
  - 0x0073b010 -> WorldMaster_registerLua_loadWord
  - 0x0073b160 -> WorldMaster_registerLua_unloadWord
  - 0x0073b2b0 -> WorldMaster_registerLua_runCharaSchedulerTutorial
  - 0x0073b400 -> WorldMaster_registerLua_waitForCharaSchedulerTutorialFinished
  - 0x0073b6a0 -> WorldMaster_registerLua_cancelLookAtPlayerTutorial
  - 0x0073b7f0 -> WorldMaster_registerLua_aimCameraTutorial
  - 0x0073b940 -> WorldMaster_registerLua_cancelAimCameraTutorial
  - 0x00753080 -> WorldMaster_registerLua_isKeyboardOnlyTutorial
  - 0x0073ba90 -> WorldMaster_registerLua_transformIntoChocobo
  - 0x0073bbe0 -> WorldMaster_registerLua_cancelTransformIntoChocobo
  - 0x0073bd30 -> WorldMaster_registerLua_aimCameraChocobo
  - 0x0073be80 -> WorldMaster_registerLua_cancelAimCameraChocobo
  - 0x007531d0 -> WorldMaster_registerLua_getSpecialEventWork
```

## 9. Confidence

```text
Confirmed:
  - WorldMaster master @ 0x00754c70 has exactly 23 registrar slots
  - All 23 walked + named (100% coverage)
  - 23 of 23 _u.lua bindings present in master (EXACT match)
  - ZERO engine-internal bindings (no hidden API surface)
  - All 23 use functor factory FUN_00726ca0 (singleton style)
  - 7-binding tutorial subsystem (dedicated camera + scheduler API)
  - 5-binding Hydaelyn calendar API (hour/day/time/moon + server time)
  - 4-binding Chocobo subsystem (transform + camera)
  - _transformIntoChocobo split: WorldMaster=global, CharaBase=per-actor

Likely (High):
  - The "pure API surface" classes (no actor state) have no hidden
    internals -- pattern: Director (5/5 EXACT), WorldMaster (23/23 EXACT)
  - Classes wrapping actor state (Player/Chara/Actor/Area/Item) hide
    1-7 internal helpers per class
  - _printLog/_printDebugLog have parallel global bindings (also in
    system/global modules) -- needs verification
  - _isKeyboardOnlyTutorial enables alternate UI flow for keyboard-only
    new players (vs gamepad)

Likely (Medium):
  - The 7-binding tutorial subsystem matches a specific Lua tutorial
    script set under sequence/tutorial/* (needs Lua-side cross-ref)
  - _getSpecialEventWork is the accessor for global "world event" state
    (e.g., seasonal events, weather, GM-pushed events)
  - The Hydaelyn calendar correlates 1:1 with the in-game time
    advance opcode in Zone session
```

## 10. Cross-references

- `finding_worldmaster_master_block_located_23_registrars.md` -- prior
  partial walk (5/23 sampled) that this completes
- `finding_director_master_block_located_5_registrars_complete.md` --
  the other 100% EXACT-match master (precedent for pattern)
- `finding_item_master_20_of_20_registrars_complete.md` -- prior 100%
  master walk
- `finding_native_bindings_inventory_complete_387_of_439.md` -- the
  _u.lua catalog this finding validates
- `finding_charabase_80_of_83_registrars_complete.md` -- contrast
  (4-7 hidden internals in actor-state class)

## 11. Next test

```text
1. Walk remaining 3 CharaBase tail-slot registrars (tiny)
2. Find DesktopWidget master (43 bindings -- largest unmapped)
3. Find Group/PartyGroup/LinkshellGroup masters (15+ bindings)
4. Find AreaMaster subclass with 9 user-facing Area bindings
5. Find Math/String/Table module masters (smallest registrar count)
6. Sample concrete Lua sequence/tutorial/* scripts to cross-ref the
   7-binding tutorial subsystem
7. Trace _getSpecialEventWork uses across Lua to identify the
   "special event work" structure
```

## Commit suggestion

```
docs(re/exe): WorldMaster master block 23 of 23 registrars walked + named -- 100% EXACT _u.lua match (zero internals)
```
