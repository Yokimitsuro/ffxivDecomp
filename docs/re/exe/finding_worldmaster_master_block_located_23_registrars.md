# Finding: WorldMaster Master Block Located -- 23 Registrars + 5 Sampled

Locates the **WorldMaster_registerAllLuaBindings** master block via
xref tracing from a pre-named WorldMaster binding
(`Lua_worldMaster__lookAtPlayerTutorial`). Confirms 23 registrar
slots matching the `world/worldmaster_u.lua` count exactly.

This brings total master blocks identified to **7** and total
registrars catalogued to **254+**.

## 1. WorldMaster master block (FUN_00754c70)

```text
Master:         WorldMaster_registerAllLuaBindings @ 0x00754c70
Total slots:    23 registrars
Renamed:        master + 5 sampled registrars

Vs _u.lua:      world/worldmaster_u.lua declares 23 bindings
                EXACT MATCH (no internal bindings hidden)
```

## 2. The 5 sampled WorldMaster registrars (confirmed)

```text
Slot   Address      Lua binding name             Category
----   -------      ----------------             --------
  1    0x00752750   _getMyPlayer                 Player accessor (singleton!)
  2    0x007528a0   _getServerTime               Time system
  3    0x007529f0   _getPendingCutSceneActor     CutScene
  6    0x00752b40   _getHydaelynHour             Hydaelyn time
  9    0x00752f30   _getHydaelynMoon             Hydaelyn time
```

These match perfectly the WorldMaster bindings catalogued earlier in
`finding_native_bindings_enumeration_charabase_worldmaster_director_desktopwidget.md`.

## 3. Discovery method

Used a **string xref tracing technique**:

```text
1. Found pre-named function: Lua_worldMaster__lookAtPlayerTutorial @ 0x006e6d90
   (This is one of the WorldMaster binding's C++ thunks)

2. Looked at xrefs to 0x006e6d90 (the thunk's address)
   Found 2 data references in Register_lookAtPlayerTutorial_LuaBinding
   (also pre-named, at 0x0073b550)

3. Looked at xrefs to Register_lookAtPlayerTutorial_LuaBinding
   Found 1 call from FUN_00754c70

4. Decompiled FUN_00754c70 -- it has 23 sequential registrar calls
   matching the WorldMaster pattern. Confirmed!
```

This is a **reliable methodology** for finding any class's master:
1. Find one binding (pre-named) with `Lua_<className>__<method>` pattern
2. Look at its xrefs to find the Register function
3. Look at Register function's xrefs to find the master

## 4. WorldMaster's distinctive functor factory

```text
WorldMaster uses functor factory FUN_00726ca0
```

This is the **6th distinct functor factory** observed:
- ActorBase: 0x00726300 / 0x007263b0
- Item: 0x00726670
- PlayerBase: 0x007267d0
- NpcBase: 0x0072d400 / 0x0072d4b0
- CharaBase: 0x00726460 / 0x00726510
- **WorldMaster: 0x00726ca0** (NEW)

The factories cluster at 0x00726xxx + 0x0072dxxx. They likely
correspond to distinct RTTI types in the engine's class hierarchy.

## 5. Updated master block inventory (7 located)

```text
Class                 Master address    Registrars    _u.lua bindings
-----                 --------------    ----------    ---------------
ItemBaseClass         0x00753dd0        20             19
PlayerBase            0x00753f90        99             94
ActorBaseClass        0x00753c30         8 + tail      10
NpcBaseClass          0x00754850        24             23
WorldMaster           0x00754c70        23             23 (NEW; EXACT MATCH)
AreaBaseClass         0x00754e70         1 (stub)       9 (multi-master)
CharaBaseClass        0x007574a0        83             76

TOTAL master blocks identified: 7
TOTAL registrars catalogued:    254+
```

The address clustering is even tighter than initially observed:
0x00753-0x00754 (Item / Player / ActorBase / NpcBase / WorldMaster /
AreaBase) and 0x00757 (CharaBase).

## 6. Annotations made

```text
RENAMES (6):
  - 0x00754c70 -> WorldMaster_registerAllLuaBindings (master)
  - 0x00752750 -> WorldMaster_registerLua_getMyPlayer
  - 0x007528a0 -> WorldMaster_registerLua_getServerTime
  - 0x007529f0 -> WorldMaster_registerLua_getPendingCutSceneActor
  - 0x00752b40 -> WorldMaster_registerLua_getHydaelynHour
  - 0x00752f30 -> WorldMaster_registerLua_getHydaelynMoon
```

## 7. Confidence

```text
Confirmed:
  - WorldMaster master @ 0x00754c70 has exactly 23 registrar slots
  - Matches world/worldmaster_u.lua's 23 binding count EXACTLY
  - 5 sampled bindings confirmed (_getMyPlayer, _getServerTime,
    _getPendingCutSceneActor, _getHydaelynHour, _getHydaelynMoon)
  - WorldMaster uses functor factory FUN_00726ca0 (6th distinct)
  - xref tracing methodology works: 0x006e6d90 → Register_xxx →
    FUN_00754c70

Likely (High):
  - The remaining 18 WorldMaster registrars all map 1:1 to the
    remaining _u.lua bindings (tutorial: 7, chocobo: 4, logging: 2,
    localization: 2, misc: 3)
  - The 6 functor factories correspond to 6 RTTI base types in the
    Lua C++ class hierarchy

Likely (Medium):
  - DesktopWidget master block can be found via same xref technique
    (search for "Lua_desktopWidget__" prefix didn't work; need to
    find one DesktopWidget binding via different angle)
```

## 8. Cross-references

- `finding_native_bindings_enumeration_charabase_worldmaster_director_desktopwidget.md`
  -- WorldMaster's 23 bindings enumerated from _u.lua
- `finding_actor_area_masters_located_with_8_more_registrars.md`
  -- prior masters + multi-master pattern discovery

## 9. Next test

```text
1. Walk the remaining 18 WorldMaster registrars
2. Find DesktopWidget master (43 bindings expected)
3. Find AreaMaster subclass that registers the 9 Area user-facing
   bindings (multi-master pattern follow-up)
4. Find Group/PartyGroup masters
```

## Commit suggestion

```
docs(re/exe): WorldMaster master block located @ 0x00754c70 -- 23 registrars + 5 sampled
```
