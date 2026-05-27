# Finding: ActorBase + Area Master Blocks Located -- 8 More Registrars Named

Locates 2 additional master blocks: **ActorBaseClass** (8 visible
registrars) and **AreaBaseClass** (1-binding stub master). Brings
total identified master blocks to **6** and total named registrars
to **231**.

## 1. ActorBaseClass master block (FUN_00753c30)

```text
Master:    ActorBaseClass_registerAllLuaBindings @ 0x00753c30
Slots:     8 + 1 final tail = 9 registrars
Renamed:   YES, all 8 walked

Vs _u.lua: actor_u.lua declares 10 bindings
           (3 _lua + 7 _cpp = 10)
Discrepancy: 9 registrars vs 10 declarations -- 1 binding may be
inherited from another base, or 1 _lua wrapper isn't registered
through the master block
```

### The 8 ActorBase registrars (walked + named)

```text
Slot   Address      Lua binding name
----   -------      ----------------
  1    0x0072df60   _callSuperClassFunction          (THE OOP base)
  2    0x0072e0b0   _wait                              (yield/sleep)
  3    0x0072e200   _restrictYieldFunction_internal   ENGINE-INTERNAL
                                                       (yield restriction
                                                        for coroutines)
  4    0x00742760   _setLoopInterval                   per-actor tick
  5    0x007497a0   _getCurrentAreaMaster              zone reference
  6    0x0072e350   _loadTextDataPermanently           text load
  7    0x0072e4a0   _delete                            destruct actor
  8    0x007498f0   _getStaticActorID                  static actor ID
```

This is THE FOUNDATIONAL CLASS -- every actor (Player, NPC, Widget,
Director, etc.) inherits these 8 methods. The most critical:
- `_callSuperClassFunction`: used by every `_callSuperClassFunc`
  call across the corpus (every class's `_onInit` uses this for
  super-chain init)
- `_delete`: the universal actor destructor
- `_wait`: the canonical yield mechanism

One engine-internal discovered:
- `_restrictYieldFunction_internal` -- restricts which functions can
  yield (probably for coroutine safety in engine-critical paths)

## 2. AreaBaseClass master block (FUN_00754e70)

```text
Master:    AreaBaseClass_registerAllLuaBindings @ 0x00754e70
Slots:     1 registrar (stub master!)
Renamed:   YES

Vs _u.lua: area_u.lua declares 9 bindings
           (_canRideChocobo, _canStealth, _countHamletSupplyRanking,
            _getHamletSupplyRanking, _getRegion, _getZoneName,
            _isInn, _isWarpRideChocobo, _setInstanceRaid)
Discrepancy: ONLY 1 registered here (_getAreaType, an engine-internal
binding NOT in _u.lua)
```

### The 1 Area registrar (so far)

```text
Slot   Address      Lua binding name
----   -------      ----------------
  1    0x00753a40   _getAreaType_internal               ENGINE-INTERNAL
```

This is the **smallest master block found so far**. The 9 _u.lua
Area bindings (Chocobo, Stealth, Hamlet Supply, etc.) must be
registered in a DIFFERENT master block -- likely an AreaMaster
subclass or per-area-type concrete classes.

This is a useful finding: **the `_u.lua` declaration count is NOT
always equal to the master block size**. Some classes have their
bindings split across multiple masters (e.g., AreaBase declares 1
internal binding; the 9 user-facing bindings live in subclass masters).

## 3. Updated master block inventory (6 located)

```text
Class                 Master address    Registrars    _u.lua bindings
-----                 --------------    ----------    ---------------
ItemBaseClass         0x00753dd0        20             19
PlayerBase            0x00753f90        99             94
ActorBaseClass        0x00753c30         8 + tail      10
NpcBaseClass          0x00754850        24             23
AreaBaseClass         0x00754e70         1 (stub!)      9 (others elsewhere)
CharaBaseClass        0x007574a0        83             76

TOTAL master blocks identified: 6
TOTAL registrars catalogued:    231 + tail = ~235
```

## 4. The "stub master" pattern (NEW discovery)

AreaBaseClass registers only 1 native binding through its own master.
This suggests a **multi-master pattern** for some classes:

```text
class AreaBase {
    // 1 engine-internal binding registered through THIS master
}

class AreaMaster : AreaBase {
    // 9 user-facing bindings registered through ANOTHER master
    (Chocobo, Stealth, Hamlet Supply, etc.)
}
```

So `area_u.lua` declares the 9 bindings against the "area" class
namespace, but the actual master block registering them is on a
SUBCLASS. This is a clean way to keep base-class engine API minimal
while letting subclasses register user-facing methods.

## 5. Where the OTHER Area bindings might live

Hypothesis (likely correct): there's an **AreaMaster** class with
its own master block somewhere in the binary that registers the 9
user-facing Area bindings. To find it:
1. Search xrefs of `_getRegion` or `_getZoneName` string registrar
2. Walk back to its master block

The same multi-master pattern likely applies to:
- GROUP (15 bindings in _u.lua, maybe split across GroupBase +
  PartyGroup, LinkshellGroup, etc.)
- WORLDMASTER (23 bindings, may have WorldMaster + child masters)

## 6. Functor factories observed (per class)

```text
Class                  Functor factory
-----                  ---------------
ActorBaseClass         FUN_00726300 / FUN_007263b0
ItemBaseClass          FUN_00726670
PlayerBase             Functor_pool_alloc (FUN_007267d0)
NpcBaseClass           FUN_0072d400 / FUN_0072d4b0
CharaBaseClass         FUN_00726460 / FUN_00726510
```

5 distinct functor factories so far. Each likely differs by RTTI
type tag for the C++ thunk's class binding.

## 7. Annotations made in Ghidra

```text
RENAMES (12):
  - 0x00753c30 -> ActorBaseClass_registerAllLuaBindings (master)
  - 0x00754e70 -> AreaBaseClass_registerAllLuaBindings (master, stub)
  - 0x0072df60 -> ActorBaseClass_registerLua_callSuperClassFunction
  - 0x0072e0b0 -> ActorBaseClass_registerLua_wait
  - 0x0072e200 -> ActorBaseClass_registerLua_restrictYieldFunction_internal
  - 0x00742760 -> ActorBaseClass_registerLua_setLoopInterval
  - 0x007497a0 -> ActorBaseClass_registerLua_getCurrentAreaMaster
  - 0x0072e350 -> ActorBaseClass_registerLua_loadTextDataPermanently
  - 0x0072e4a0 -> ActorBaseClass_registerLua_delete
  - 0x007498f0 -> ActorBaseClass_registerLua_getStaticActorID
  - 0x00753a40 -> AreaBaseClass_registerLua_getAreaType_internal
```

## 8. Confidence

```text
Confirmed:
  - ActorBaseClass master @ 0x00753c30 with 8 visible registrars
  - All 8 ActorBase registrar bindings extracted + named
  - AreaBaseClass master @ 0x00754e70 has just 1 registrar
    (_getAreaType_internal, NOT in _u.lua)
  - The 9 user-facing Area bindings (_canRideChocobo, etc.) are
    registered elsewhere -- likely in a subclass master
  - The "_u.lua count != master block size" assumption hypothesis
    confirmed (master count doesn't always match)
  - 1 new engine-internal binding: _restrictYieldFunction

Likely (High):
  - The 9 Area user-facing bindings are in an AreaMaster subclass
    master block (not yet located)
  - Similar multi-master split applies to Group (15 declared but
    maybe split across PartyGroup/LinkshellGroup/etc.)
  - The 5 functor factories correspond to 5 RTTI-distinct base
    types in the Lua C++ class hierarchy

Likely (Medium):
  - _restrictYieldFunction controls which Lua functions can call
    coroutine.yield (engine-critical code paths shouldn't yield)
  - The functor factory dispatch determines which "type tag" the
    binding produces (e.g., Player vs NPC vs Item references)
```

## 9. Cross-references

- `finding_charabase_item_master_blocks_located.md` -- located the
  first 2 master blocks (CharaBase + Item)
- `finding_charabase_80_of_83_registrars_complete.md` -- full
  CharaBase walk
- `finding_native_bindings_inventory_complete_387_of_439.md` -- the
  _u.lua catalog that this finding cross-references

## 10. Next test

```text
1. Find the AreaMaster subclass master block (registers 9 Area
   bindings)
2. Find WorldMaster master block (23 bindings expected)
3. Find DesktopWidget master block (43 bindings)
4. Find Group/PartyGroup/LinkshellGroup masters (15+ bindings)
5. Walk Item 20 registrars
```

## Commit suggestion

```
docs(re/exe): ActorBase 8 + Area 1 (stub) masters located -- 11 registrars named + multi-master pattern discovered
```
