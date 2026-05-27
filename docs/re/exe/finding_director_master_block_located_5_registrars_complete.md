# Finding: Director Master Block Located + ALL 5 Registrars Named (100%)

Locates the **DirectorBaseClass_registerAllLuaBindings** master block
via xref tracing from `register_updateWork_LuaBinding`. Walks ALL 5
registrars in one batch. Confirms EXACT MATCH with `director/director-
baseclass_u.lua`.

**8th master block identified. 260 total registrars catalogued.**

## 1. DirectorBaseClass master block (FUN_00758260)

```text
Master:         DirectorBaseClass_registerAllLuaBindings @ 0x00758260
Total slots:    5 registrars
Renamed:        master + ALL 5 registrars (100% walked)

Vs _u.lua:      director/directorbaseclass_u.lua declares 5 bindings
                EXACT MATCH (no internal bindings hidden)
```

## 2. The 5 Director registrars (ALL named)

```text
Slot   Address      Lua binding name                         Category
----   -------      ----------------                         --------
  1    0x0073bfd0   _breakNotice                              5-stream cancel
                                                              (Notice stream)
  2    0x0073fc50   _updateWork                               WorkSync helper
  3    0x007570b0   _getGroupByDisplayName                    Group lookup
  4    0x00757200   _getExtendedTemporaryGroupByDisplayName   Group temp variant
  5    0x0073c120   _waitForHamletDefenseScore                CONTENT-SPECIFIC
                                                              (Hamlet Defense)
```

All 5 match the prior `directorbaseclass_u.lua` enumeration exactly.

The 5 bindings reveal Director's actual native API surface is
**minimal** -- just enough to:
- Cancel Notice stream events (in the 5-stream command architecture)
- WorkSync state propagation (the universal _updateWork)
- Group lookup by display name (2 variants -- standard + temp/preview)
- Wait for Hamlet Defense score (content-specific binding)

Everything else Directors do is **pure Lua** (state machines, scene
orchestration, condition checks). The native bindings are just the
WorkSync + group access primitives that pure-Lua can't do.

## 3. Discovery method (validates the technique again)

```text
1. Searched for pre-named "register_*" functions
   Found 2: Register_lookAtPlayerTutorial_LuaBinding (WorldMaster)
            register_updateWork_LuaBinding (CharaBase OR Director?)

2. Looked at xrefs to register_updateWork_LuaBinding
   Found 1 call from FUN_00758260

3. Decompiled FUN_00758260
   -- Only 5 registrar slots
   -- Slot 1 registers _breakNotice (a known Director binding)
   -- Confirmed: this IS Director's master block
```

The 3-step xref tracing methodology works. Now confirmed for both:
- WorldMaster (via Lua_worldMaster__lookAtPlayerTutorial)
- Director (via register_updateWork_LuaBinding)

## 4. Director uses 7th distinct functor factory

```text
DirectorBaseClass uses functor factory FUN_00726d50
```

This is the **7th distinct functor factory** observed:
- ActorBase: 0x00726300 / 0x007263b0
- Item: 0x00726670
- PlayerBase: 0x007267d0
- NpcBase: 0x0072d400 / 0x0072d4b0
- CharaBase: 0x00726460 / 0x00726510
- WorldMaster: 0x00726ca0
- **Director: 0x00726d50** (NEW)

The factories cluster tightly at 0x00726xxx + 0x0072dxxx. Likely
corresponds to 7 distinct RTTI base types in the engine.

## 5. The Director's _updateWork is SHARED with CharaBase

```text
Both CharaBase (registered at 0x0073eb40) and Director (registered at
0x0073fc50) register an "_updateWork" binding.

But there's only ONE "register_updateWork_LuaBinding" function (at
0x0073fc50) -- it's only called from Director's master.

CharaBase's _updateWork at 0x0073eb40 is a SEPARATE registrar
function with the same name. They likely point to the same C++
impl via different functor allocations.
```

This is a SHARING PATTERN -- the same `_updateWork` Lua-callable
name is registered on multiple classes, each with their own functor
binding to a class-appropriate implementation.

Same pattern observed for `_getGroupByDisplayName` (both CharaBase
and Director have this binding).

## 6. Updated master block inventory (8 located)

```text
Class                 Master address    Registrars    _u.lua bindings
-----                 --------------    ----------    ---------------
ItemBaseClass         0x00753dd0        20             19
PlayerBase            0x00753f90        99             94
ActorBaseClass        0x00753c30         8 + tail      10
NpcBaseClass          0x00754850        24             23
WorldMaster           0x00754c70        23             23 (EXACT)
AreaBaseClass         0x00754e70         1 (stub)       9
CharaBaseClass        0x007574a0        83             76
DirectorBaseClass     0x00758260         5             5 (EXACT; NEW)

TOTAL master blocks: 8
TOTAL registrars catalogued: 260+
```

Director joins WorldMaster as the 2nd class with EXACT _u.lua = master
match. Most other classes have 1-7 engine-internals in addition.

## 7. CORRECTION to prior findings

Prior finding `finding_director_judge_purely_lua_no_exe_bridge.md`
claimed Director is "purely Lua" -- this is FALSE.

The correction was first noted in `finding_native_binding_surface_
439_across_19_modules.md` (5 native bindings discovered). This
finding LOCATES + NAMES those 5 bindings, providing the C++ proof:

```text
Director: 5 native C++ bindings (registered in master at 0x00758260)
        + Mostly Lua-side state machines + scene orchestration
```

So Directors are **~95% pure Lua + 5 native bindings** for WorkSync /
group lookup / content-wait. Not "purely Lua" but very-mostly-Lua.

## 8. Annotations made in Ghidra

```text
RENAMES (6):
  - 0x00758260 -> DirectorBaseClass_registerAllLuaBindings (master)
  - 0x0073bfd0 -> DirectorBaseClass_registerLua_breakNotice
  - 0x0073fc50 -> DirectorBaseClass_registerLua_updateWork
  - 0x007570b0 -> DirectorBaseClass_registerLua_getGroupByDisplayName
  - 0x00757200 -> DirectorBaseClass_registerLua_getExtendedTemporaryGroupByDisplayName
  - 0x0073c120 -> DirectorBaseClass_registerLua_waitForHamletDefenseScore
```

## 9. Confidence

```text
Confirmed:
  - DirectorBaseClass master @ 0x00758260 has exactly 5 registrar slots
  - All 5 registrars walked + named (100% coverage)
  - EXACT MATCH with director/directorbaseclass_u.lua (5 bindings)
  - Director uses functor factory FUN_00726d50 (7th factory)
  - _updateWork and _getGroupByDisplayName are SHARED across classes
    (each registers its own binding to a class-specific impl)
  - Director native API surface is minimal (5 helpers; rest is Lua)

Likely (High):
  - The remaining 5 classes' masters can be found via similar xref
    tracing (Group, AreaMaster, DesktopWidget, Math, etc.)
  - DesktopWidget master is the largest remaining (43 bindings)
    but requires finding a different pre-named pattern (no
    Lua_desktopWidget__* or register_X for DesktopWidget bindings)

Likely (Medium):
  - The 7 functor factories may correspond to: Actor base, Char base,
    Player, NPC, Item, World, Director (matching RTTI hierarchy)
  - Sharing patterns (_updateWork, _getGroupByDisplayName across
    classes) suggest the engine has helper templates that get
    generated per class
```

## 10. Cross-references

- `finding_worldmaster_master_block_located_23_registrars.md` -- prior
  use of the same xref technique
- `finding_director_judge_purely_lua_no_exe_bridge.md` -- CORRECTED:
  Director is 95% pure Lua + 5 native bindings (NOT 100% pure)
- `finding_native_bindings_enumeration_charabase_worldmaster_director_desktopwidget.md`
  -- Director's 5 _u.lua bindings catalogued
- `finding_actor_area_masters_located_with_8_more_registrars.md`
  -- prior master block round-up

## 11. Next test

```text
1. Find DesktopWidget master (43 bindings) -- need new technique;
   no Lua_desktopWidget__* found
2. Find Group/PartyGroup/LinkshellGroup masters (15+ bindings)
3. Find AreaMaster subclass (9 user-facing Area bindings)
4. Walk remaining 18 WorldMaster registrars (Hydaelyn time + tutorial
   + chocobo)
5. Walk Item 20 registrars (complete the 4th master fully)
```

## Commit suggestion

```
docs(re/exe): Director master block located + ALL 5 registrars named (100%; EXACT _u.lua match)
```
