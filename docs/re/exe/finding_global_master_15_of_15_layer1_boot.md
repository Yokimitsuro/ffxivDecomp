# Finding: global Module Master Block 15 of 15 -- LAYER 1 BOOT SURFACE

**THE FOUNDATION LAYER NOW MAPPED.** Locates the
**global_registerAllLuaBindings** master block at FUN_007582e0 via
string-xref tracing. Walks ALL 15 registrar slots in one batch.
Reveals the LAYER 1 bootstrap API that ALL other classes depend on.

This is **the most architecturally foundational class** in the 1.x
Lua surface -- it's the class system + actor lifecycle + static actor
registry + UTF-8 string helpers that everything else uses.

**10th master block identified. 356 total registrars catalogued.**

## 1. global module master block (FUN_007582e0)

```text
Master:         global_registerAllLuaBindings @ 0x007582e0
Total slots:    15 registrars
Renamed:        master + ALL 15 registrars (100% walked)
Address span:   0x0073c270-0x00757350 (cluster around 0x0073cxxx +
                0x00753xxx + 0x00741xxx)

Vs _u.lua:      global_u.lua estimate was ~25 bindings -- ACTUAL 15
                The 25 estimate conflated bindings from "system" /
                other modules. global is leaner than expected.
```

## 2. The 15 named global registrars (by functional family)

### Class System (3 bindings) -- THE OOP FOUNDATION

```text
Slot  Address      Lua binding
----  -------      -----------
  1   0x0073c270   _defineClass        derived-class definition
  2   0x0073c3c0   _defineBaseClass    abstract/root class definition
  6   0x00753470   _isInstanceOf       RTTI / class membership query
```

These 3 bindings ARE THE LUA OO SYSTEM in 1.x. Every other
`classname:method` definition routes through `_defineClass` or
`_defineBaseClass`. `_isInstanceOf` is the runtime type check
(equivalent to C++'s `dynamic_cast<X*>(obj) != nullptr`).

### Actor Lifecycle (5 bindings) -- THE ACTOR CREATE/QUERY API

```text
Slot  Address      Lua binding
----  -------      -----------
  3   0x00757350   _createActor             spawn actor by classname
  4   0x00753320   _canCreateActorByName    can we spawn given name?
  5   0x0073c510   _getActorByName          find existing actor by name
  7   0x0073c660   _isExistActor            actor exists check
  8   0x00741a30   _getStaticActor          fetch fixed-id static actor
```

`_createActor` is **THE actor factory** -- every NPC, widget, item,
director, sequence spawn ultimately routes through this binding.
The 3 query helpers (`_canCreate...`, `_isExist...`, `_getActorByName`)
prevent spawn errors / enable script-side existence checks.

### Static Actor Subsystem (2 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
 10   0x00741b80   _isExistStaticActor               exists check
 11   0x0073c7b0   _prepareAllCommandStaticActor     bulk pre-warm
```

Static actors = world-fixed actors with stable IDs (NPCs that never
move/despawn, e.g., quest givers). `_prepareAllCommandStaticActor`
appears to bulk-initialize command handlers for all static actors --
likely called during zone load to warm the command-dispatch tables.

### Quest CutScene Support (1 binding)

```text
Slot  Address      Lua binding
----  -------      -----------
  9   0x007535c0   _getQuestActorForCutSceneReplay
```

When a player REPLAYS a cutscene (1.x had CS replay; ARR kept this),
the script needs to retrieve the actor reference that was used in
the original quest scene. This binding handles the lookup.

### UTF-8 String Helpers (2 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
 12   0x0073c900   _getUTF8StringLength       char count
 13   0x0073ca50   _getUTF8StringByteLength   byte count
```

Critical for Japanese/multi-byte text handling. Lua's native `#str`
gives byte count, but for character-correct truncation (chat box
limits, nameplate truncation) scripts need codepoint counts.

### Display Name Normalization (2 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
 14   0x00753710   _normalizeDisplayName      casefold/strip-format
 15   0x00753860   _replaceMacroCodeString    expand <macro> codes
                                              in chat/text strings
```

`_normalizeDisplayName` is used to compare player names case-
insensitively / strip control codes (for /target lookups,
chat /msg etc).

`_replaceMacroCodeString` expands embedded `<macro>` codes in
strings -- e.g., `<player>` -> "Yoshi P", `<hour>` -> "14".
This is the text-templating subsystem.

## 3. ZERO engine-internal bindings -- 4th EXACT match

```text
EXE: 15 slots
Categorized: 15 bindings (3 + 5 + 2 + 1 + 2 + 2 = 15)
Engine-internal hidden: 0
```

global is the **4th master with EXACT script-API match** (after
Director, WorldMaster, DesktopWidget). Pure API surface, no actor
state, no hidden internals.

Refined pattern (now 4 of 4 confirmed):

```text
EXACT _u.lua match (NO hidden internals):
  Director         5/5    (pure controller)
  WorldMaster     23/23   (singleton, global state)
  DesktopWidget   44/44   (UI primitive surface)
  global          15/15   (boot/foundation API)         NEW

Hidden internals (1-7 per class):
  CharaBase       80 + 4-7 internal (actor state)
  PlayerBase      99 + 5 internal (actor state)
  ActorBase        8 + 1 internal (foundational instance)
  AreaBase         1 + 0 (stub master)
  Item            20 + 1 internal (inventory state)
  NpcBase         24 + 1 internal (actor state)
```

**Confirmed rule**: classes that are PURE API SURFACES (no `this`
actor instance) have NO hidden internals (4 of 4). Classes that
wrap a per-instance actor state hide 1-7 engine internals.

## 4. global uses 10th distinct functor factory

```text
All 15 global slots use functor factory FUN_00726e00
```

This is the **10th distinct functor factory** observed:

```text
Class            Functor factory
-----            ---------------
ActorBase        0x00726300 / 0x007263b0
CharaBase        0x00726460 / 0x00726510
Item             0x00726670
PlayerBase       0x007267d0
DesktopWidget    0x00726bf0 / 0x00726b40
WorldMaster      0x00726ca0
Director         0x00726d50
global           0x00726e00                  (NEW; 10th factory)
NpcBase          0x0072d400 / 0x0072d4b0
```

All factories cluster at 0x00726xxx (8 of them) + 0x0072dxxx (2 of
them). The clean clustering strongly suggests these are 10 RTTI
type-tag IDs in the engine's class hierarchy.

## 5. Why the global module is the LAYER 1 of the architecture

```text
LAYER 1 (BOOT):                         global (this finding)
  _defineClass + _defineBaseClass       Make classes
  _createActor + _getActorByName        Instantiate actors
  _isExistActor + _isInstanceOf         Query

LAYER 2 (ACTORS/CLASSES):               ActorBase / CharaBase /
  Class-specific bindings               PlayerBase / NpcBase /
  attached to instances                 Item / Director / Area /
                                        WorldMaster (singleton)

LAYER 3 (DOMAIN HELPERS):               DesktopWidget (UI hub) +
  Specialized subsystems                future Group / Math / etc.
```

Without LAYER 1, none of LAYERs 2 or 3 could exist. Every other class
gets instantiated via `_createActor` (from a name registered via
`_defineClass`). Every script-side `obj:isInstance(klass)` call
routes through `_isInstanceOf`.

This is why locating this master matters architecturally -- it's the
foundation under everything we've already documented.

## 6. Updated master block inventory (10 masters, 5 at 100%)

```text
Class                 Master address    Registrars    Walked   _u.lua match
-----                 --------------    ----------    ------   ------------
DirectorBaseClass     0x00758260         5             5/5      5 EXACT
ItemBaseClass         0x00753dd0        20            20/20    19 + 1 internal
WorldMaster           0x00754c70        23            23/23    23 EXACT
DesktopWidget         0x00757ea0        44            44/44    44 EXACT
global                0x007582e0        15            15/15    15 EXACT (NEW)
PlayerBase            0x00753f90        99            99/99    94 + 5 internal
NpcBaseClass          0x00754850        24            24/24    23 + 1 internal
ActorBaseClass        0x00753c30         8 + tail      8/8      7 + 1 internal
AreaBaseClass         0x00754e70         1 (stub)      1/1      0 + 1 internal
CharaBaseClass        0x007574a0        83            80/83    76 + 4-7 internal

TOTAL master blocks identified:    10 (up from 9)
TOTAL registrars catalogued:      356 (up from 341)
TOTAL engine-internal discovered:  ~13-16 bindings
TOTAL _u.lua bindings located:    309 of ~387 (80%)
```

5 of 10 masters are at 100% coverage with EXACT _u.lua match.

## 7. Key methodology refinement (string-xref technique stabilized)

The 3-step string-xref tracing methodology used 4 times now:
- WorldMaster (via Lua_worldMaster__lookAtPlayerTutorial)
- Director (via register_updateWork_LuaBinding)
- DesktopWidget (via 4 unique binding strings)
- **global (via 3 unique binding strings: _createActor, _defineClass,
  _getStaticActor)**

The string-xref variant is now the **default** technique:

```text
1. Pick 3-4 binding names from _u.lua that are unique to the target class
   (avoid generic names like _updateWork that appear in multiple classes)
2. Search EXE strings for each (mcp__ghidra__list_strings filter=name)
3. Xref each string to find the registrar function
4. Xref each registrar to find the common-caller master
5. Decompile master, extract slot addresses, batch-decompile slots
6. Extract binding names from each slot's FUN_00447260 call
7. Bulk rename + write finding + commit
```

Per-master time: ~10-15 minutes once the technique is fluent.

## 8. Annotations made in Ghidra (16 renames in this finding)

```text
RENAMES (1 master + 15 registrars):
  - 0x007582e0 -> global_registerAllLuaBindings (master)
  - 0x0073c270 -> global_registerLua_defineClass
  - 0x0073c3c0 -> global_registerLua_defineBaseClass
  - 0x00757350 -> global_registerLua_createActor
  - 0x00753320 -> global_registerLua_canCreateActorByName
  - 0x0073c510 -> global_registerLua_getActorByName
  - 0x00753470 -> global_registerLua_isInstanceOf
  - 0x0073c660 -> global_registerLua_isExistActor
  - 0x00741a30 -> global_registerLua_getStaticActor
  - 0x007535c0 -> global_registerLua_getQuestActorForCutSceneReplay
  - 0x00741b80 -> global_registerLua_isExistStaticActor
  - 0x0073c7b0 -> global_registerLua_prepareAllCommandStaticActor
  - 0x0073c900 -> global_registerLua_getUTF8StringLength
  - 0x0073ca50 -> global_registerLua_getUTF8StringByteLength
  - 0x00753710 -> global_registerLua_normalizeDisplayName
  - 0x00753860 -> global_registerLua_replaceMacroCodeString
```

## 9. Confidence

```text
Confirmed:
  - global master @ 0x007582e0 has exactly 15 registrar slots
  - All 15 walked + named (100% coverage)
  - 15 of 15 distinct bindings present in master (EXACT match)
  - ZERO engine-internal bindings (no hidden API surface)
  - All 15 use functor factory FUN_00726e00 (10th factory)
  - 6 functional sub-APIs cleanly partitioned:
    Class System (3), Actor Lifecycle (5), Static Actor (2),
    Quest CS (1), UTF-8 (2), Display Name (2)
  - global IS the LAYER 1 boot surface (class+actor+RTTI)

Likely (High):
  - global_u.lua's expected ~25 bindings was an estimate that conflated
    other modules (system, math, etc.); actual = 15
  - The "PURE API surface = 0 internals" rule now confirmed 4/4
    (Director, WorldMaster, DesktopWidget, global)
  - The 10 functor factories correspond to 10 RTTI type tags in the
    C++ class hierarchy
  - _prepareAllCommandStaticActor is called during zone init to
    bulk-warm command-handler tables for all static actors in the zone

Likely (Medium):
  - The "global" name in _u.lua refers to a Lua "actor" object
    representing the global namespace (rather than a class instance)
  - _replaceMacroCodeString is the engine entry-point for all
    chat/UI macros (<player>, <time>, <area>, etc.)
  - _isInstanceOf is the universal RTTI primitive that every
    `if obj:isInstance(X) then` call routes through
```

## 10. Cross-references

- `finding_desktopwidget_master_44_of_44_complete.md` -- prior
  EXACT-match master (largest until this one)
- `finding_worldmaster_master_23_of_23_complete.md` -- another EXACT
- `finding_director_master_block_located_5_registrars_complete.md`
  -- the first EXACT-match master
- `finding_item_master_20_of_20_registrars_complete.md` -- 4th 100%
- `finding_native_bindings_inventory_complete_387_of_439.md` -- the
  _u.lua catalog this validates
- `finding_native_binding_surface_439_across_19_modules.md` -- the
  overall 19-module breakdown

## 11. Next test

```text
1. Find Group/PartyGroup/LinkshellGroup masters (15+ bindings; use
   string-xref for _getGroupSize, _getMemberByIndex, etc.)
2. Find AreaMaster subclass with 9 user-facing Area bindings
   (use _canRideChocobo, _getRegion, _getZoneName as anchors)
3. Find Math/String/Table module masters (smallest registrar count)
4. Walk remaining 3 CharaBase tail-slot registrars (tiny; -> 83/83)
5. Disassemble _createActor's C++ thunk @ 0x00757350 to map the
   actor-creation factory pathway (which gets called for every
   spawn -- NPC, widget, director, sequence, etc.)
6. Disassemble _defineClass thunk to understand the class-registration
   pathway (route every classDef through this and you get a class
   registry)
```

## Commit suggestion

```
docs(re/exe): global module master 15 of 15 -- LAYER 1 BOOT SURFACE mapped (10th master; class system + actor lifecycle + RTTI all located)
```
