# Quick Reference: FFXIV 1.x Architecture Lookup Tables

**Single-page reference for the most-used facts** from the 158
findings (61 EXE + 85 Lua + 12 correlation). Use this when you need a
fast lookup; refer to the named finding files for full context.

Last updated: 2026-05-27 (after the master-walk completion + thunk
disassembly session)

## 1. All 17 Native Master Blocks (EXE-confirmed)

```text
Class                 Master address    Slots   Walked   _u.lua match
-----                 --------------    -----   ------   ------------
DirectorBaseClass     0x00758260          5      5/5     5 EXACT
ItemBaseClass         0x00753dd0         20     20/20    19 + 1 internal
WorldMaster           0x00754c70         23     23/23    23 EXACT
DesktopWidget         0x00757ea0         44     44/44    44 EXACT
global                0x007582e0         15     15/15    15 EXACT
GroupBaseClass        0x00757b70         16     16/16    15 + 1 internal
Math                  0x00740ec0          4      4/4     4 EXACT
WidgetBaseClass       0x00754a60         24     24/24    24 EXACT
AreaMaster            0x00753cf0          9      9/9     9 EXACT
PlayerBase            0x00753f90         99     99/99    94 + 5 internal
NpcBaseClass          0x00754850         24     24/24    23 + 1 internal
ActorBaseClass        0x00753c30          8      8/8     7 + 1 internal
AreaBaseClass         0x00754e70          1      1/1     0 + 1 internal (stub)
CharaBaseClass        0x007574a0         82     82/82    76 + 6 internal
SpreadSheet           0x00758670         10     10/10    10 EXACT
Debug                 0x00757ce0         20     20/20    4 + 16 INTERNAL
Sequence              0x007547d0          5      5/5     4 + 1 internal

NO MASTER (100% pure Lua wrappers):
String, Table

TOTAL:                                  409    409
```

## 2. Disassembled Thunks (6) + Wire Opcodes

```text
Lua API                C++ thunk                          Address       Wire opcode
-------                ---------                          -------       -----------
_createActor           global_cpp_createActor_thunk       0x00709640    (none; coroutine)
_defineClass           global_cpp_defineClass_thunk       0x006dcc30    (none; local)
_wait                  ActorBase_cpp_wait_thunk           0x006dbcb0    (none; coroutine)
_getData (SSD)         SpreadSheet_cpp_getData_thunk      0x0070a720    (none; sync mem)
_loadKeyTemporarily    SpreadSheet_cpp_loadKey..._thunk   0x006f0840    (disk I/O async)
_updateWork            CharaBase_cpp_updateWork_thunk     0x006e7670    0x12F (Zone OUT)
```

## 3. Wire Opcodes Confirmed

```text
OUTBOUND (Zone channel):
  0x12d  PacketBuilder_opcode_0x12d_200B_tagged   (5+ variants)
  0x12e  ZoneOut_send_opcode_0x12e_104B           (RPC carrier)
  0x12f  WorkSync_buildAndSendPacket_opcode_0x12f (state sync, C->S)
  0x132  Item _updateWork carrier (via Lua_sendByteUshortAt0x68)
  0x133  WorkSyncAlt_serializePayloadAndSend_opcode_0x133
  0x135  ZoneOut_send_opcode_0x135_24B_dword     (subscribe to bindingId)

INBOUND (Zone channel):
  0x12d-? various event handlers in table @ 0x00fdfb80 (224 slots)
  S->C state-push opcode: TBD (uses binding-id format, not pinned)
```

## 4. Async / Coroutine Pattern (ResumeChecker Hierarchy)

```text
Base interfaces:
  Component::Lua::GameEngine::ResumeCheckerInterface  (script yields)
  Component::Lua::GameEngine::FunctionEndCallbackInterface (I/O completion)

Known ResumeChecker subclasses (concrete):
  OnInitResumeChecker      16 B    backs _createActor   actor init done
  WaitResumeChecker        40 B    backs _wait          timer deadline
  LoadDataResumeChecker   148 B    backs _loadKey*      disk load done

Predicted (high confidence):
  ~8 more _wait* bindings each with own subclass
  (waitForGroup, waitForTurning, waitForCharaSchedulerFinished, etc.)

Coroutine context API:
  CoroutineContext_isTrackingEnabled   FUN_00cd27d0
  CoroutineContext_pushResumeChecker   FUN_00cd2860
  CoroutineContext_pushEndCallback     FUN_00cd28c0 (NEW)
  CoroutineContext_findPendingCallback FUN_00cd2630 (NEW)
  ScriptCoroutineKey_construct         FUN_00713f80
```

## 5. WorkSync State Replication

```text
C -> S (player UI actions, rare):
  Lua: actor:_updateWork("category", "field", subIdx, listIdx)
   -> WorkPath built (2-4 components, 176 bytes)
   -> WorkSync_dispatchOrEnqueue
   -> Look up in actor's red-black tree (WorkPathTree_lowerBound)
   -> If sync-flag SET: predictive apply via UpdateQueue
   -> Always: WorkSync_serializePayloadAndSend
   -> Wire: opcode 0x12F, 56-byte packet, STRING payload

S -> C (server broadcast, frequent):
  Opcode: TBD (0x130/0x131/0x132 candidates)
  Format: actorId + bindingId(u16) + value (u8/u16/u24/u32)
  ~6-14 byte packets
  Client side: 4 BitPacked WRITERS apply to actor+0x214 storage
   - BitPacked_writeByte_type1   0x00d11d30
   - BitPacked_writeShort_type2  0x00d11e90
   - BitPacked_writeUint24_type3 0x00d11fd0
   - BitPacked_writeUint32_type4 0x00d12080

C -> S subscribe:
  Lua: queryBinding(bindingId)
  Wire: opcode 0x135, 24-byte packet
```

## 6. The Actor Lifecycle (T0 -> T3)

```text
T0  Engine startup
    - C++ classes have vtables baked in
    - 17 master registrars run (wire 409 Lua names to C++ thunks)
    - global module's binding IDs assigned

T1  Script load: _defineClass for each Lua class
    - ClassRegistry_addDerivedClass creates child entry
    - Forward declarations supported via pending map (engine+0x204)
    - Child inherits parent's vtable (including vtable[0x6c] = spawn ctor)
    - Finalize via ClassRegistry_clearPendingFlag

T2  Script: local x = _createActor(name, "ClassName", ...)
    - Look up class in registry
    - vtable[0x6c] dispatched: per-class polymorphic ctor
    - 16-byte OnInitResumeChecker returned
    - Script YIELDS via CoroutineContext_pushResumeChecker

T3  Actor's async _onInit completes
    - Engine sets readyFlag on the checker
    - Coroutine pump wakes the yielded script
    - Script continues; actor reference is now usable
```

## 7. Data Loading: 132 of 164 Critical CSVs Mapped

### MECHANISM 1: SpreadSheet (35 SHARED tables, loaded at engine init)

```text
Item subsystem (6):  itemData, equipment, weapon, armor, accessory, materia
Commands (4):        command, gameCommand, gameCommandBasic, debugCommand
Quests (3):          quest, quest_reward, quest_new_reward
Guildleve (5):       guildleve, guildleve_UI, passiveGL_craft,
                     passiveGL_icon, guildlevePack
Shop (5):            shopBase, shopItem, marketItem, gcSealShopItem, blackMarket
GC/Hamlet (3):       gcRank, itemGcExSupply, itemHamletSupply
Map (4):             mapNavi_data, aetheryte_2Dmap, actorclass, cutReplay
Misc (5):            achievement, compatibility, status, tribe, exp_BPCost

Loaded by 4 init files:
  judge/commonJudge.lua            -- 9 item-related
  judge/judgeMaster.lua            -- 2 (command + status)
  area/areabaseclass_yalogic.lua   -- 22 (loadCommonTableData)
  chara/npc/debug/monsterListGen.lua -- 2

+ 4 ad-hoc creators (CutScene, QuestBase, AreaBase, CommandDebugger)
```

### MECHANISM 2: _loadTextDataPermanently (97 PER-CLASS tables)

```text
NPC populace types (53):  populace*.csv -- 1 CSV per NPC type
Zone templates (6):       dft*.csv -- Forest/Lake/Rocks/Sea/Sand/Wilderness
Raid dungeons (11):       raidDungeon*, raidFst/Roc/etc.
Event objects (11):       bookShelf, elevator, gimmick*, object*
Passive guildleve (8):    pgAeth/Conv/pgl*/pgHaml
Misc (8):                 aetheryte hierarchy, retainer, etc.

API: instance:_loadTextDataPermanently(actorClassId, csvBaseName)
Loaded by: 250+ per-class scripts each in their _onInit
```

### CRITICAL TIER for server import

```text
TIER 1 (35):  boot-loaded; server must push at session init
TIER 2 (97):  per-class; lazy on actor spawn
TIER 3 (32):  truly unmapped critical (need more sweeps)
TIER 4 (625): useful tables (gear class variants, etc.)
```

## 8. Class Hierarchy (Pure-API vs Actor-State Pattern)

```text
PURE API SURFACE (zero hidden internals; 10/10 confirmed):
  Director, WorldMaster, DesktopWidget, global, Math, WidgetBase,
  AreaMaster, SpreadSheet
  (+ String, Table = no master at all; 100% pure Lua wrappers)

ACTOR STATE (hide 1-16 engine-internal bindings each):
  ActorBase (1), AreaBase (1, stub), Item (1), NpcBase (1),
  GroupBase (1), PlayerBase (5), CharaBase (4-6),
  Sequence (1), Debug (16 -- the engine dev menu API)

Multi-master pattern:
  ONLY Area uses it (AreaBase stub + AreaMaster subclass).
  All other classes are single-master.

Functor factory clusters (15 distinct factories):
  0x00726xxx (12 factories) - most classes
  0x0072cxxx (1)            - AreaMaster
  0x0072dxxx (2)            - NpcBase
```

## 9. Native Binding Surface (CORRECTED)

```text
Prior estimate (was wrong): 439 _u.lua _inl declarations
Reality: ~344 native _cpp + ~62 pure-Lua _lua wrappers

By class (most populated):
  PlayerBase       94 + 5 internal
  CharaBase        76 + 6 internal
  DesktopWidget    44
  WidgetBase       24
  WorldMaster      23
  NpcBase          23
  Item             19 + 1 internal
  GroupBase        15 + 1 internal
  global           15
  ActorBase        7 + 1 internal
  AreaMaster       9
  Debug            4 + 16 internal (extreme: 80% hidden API)
  Math             4 (only RNG; sin/cos/etc. are pure Lua)
  Sequence         4 + 1 internal
  Director         5
  AreaBase         0 + 1 stub
  String, Table    0 (100% pure Lua)
```

## 10. Item ID Ranges (FULL 1.x ITEM SPACE)

```text
Range                    Item type
-----                    ---------
1,000,000 - 1,999,999    Money / currency
2,000,001 - 2,002,048    Important quest items
3,010,000 - 3,019,999    Food
3,010,600 - 3,010,699      Drink subset
3,020,000 - 3,029,999    Potions
3,900,000 - 3,919,999    Throw weapons
3,920,000 - 3,929,999    Arrow weapons
3,930,000 - 3,939,999    Bullet weapons
3,940,000 - 3,949,999    Fishing weapons + bait subset
4,020,000 - 4,099,999    Melee weapons (Nail/Sword/Axe/Rapier/Mace/Bow/Lance/Gun)
4,100,000 - 4,109,999    Shield weapons
5,000,000 - 5,049,999    Magic weapons (Thaum/Conj/Archan)
6,000,000 - 6,099,999    Craft weapons (8 disciplines)
7,000,000 - 7,099,999    Harvest weapons (Min/Bot/Fish/Shep)
8,000,000 - 8,999,999    Armor
9,000,000 - 9,089,999    Accessories
10,000,000 - 10,199,999  Materia
11,000,000 - 15,000,000  Event items
```

## 11. itemData.csv Column Indices (DECODED)

```text
Col    Field                       (from getItemData(N) Lua calls)
---    -----                       --------------------------------
43     isUsable flag
44     mainSkill ID
45     secondarySkill ID
46     itemLevelType
47     itemLevel
48     compatibilityKey
49     param1LevelAdjustGrow
50     param1 base value
51     param1 compatibility
52     param2LevelAdjustGrow
53     param2 base value
54     param2 compatibility
55     param3LevelAdjustGrow
56     param3 base value
57     param3 compatibility
58     param4LevelAdjustGrow
64     repairSkill ID
65     repairItem ID
66     repairItemNum
67     repairLevel
68     repairCrystal type
```

## 12. Key Findings by Category (jump points)

### EXE Architecture
- `finding_smallmodules_inventory_closed_17_masters.md` -- the 17-master inventory
- `finding_createActor_thunk_async_actor_factory.md` -- async actor creation
- `finding_defineClass_thunk_class_registration_loop.md` -- class registry
- `finding_wait_thunk_universal_resume_checker_confirmed.md` -- async pattern
- `finding_updateWork_thunk_worksync_state_replication.md` -- WorkSync end-to-end
- `finding_worksync_inbound_writers_pinned.md` -- 4 BitPacked writers
- `finding_spreadsheet_thunks_exe_data_bridge.md` -- EXE-Data bridge
- `finding_inbound_dispatch_table_found.md` -- 224-slot inbound table

### Lua Architecture
- `finding_native_binding_surface_439_across_19_modules.md` -- catalog
- `finding_actor_work_schemas.md` -- charaWork/npcWork schemas
- `finding_combat_relations_and_potencial.md` -- 4-state combat
- `finding_director_baseclass_and_226_subclasses.md` -- Director hierarchy
- `finding_widget_baseclass_architecture_and_194_widgets.md` -- widget hierarchy
- `finding_party_subclasses_and_weather.md` -- Group + Director subclasses

### Correlation (Lua ↔ EXE ↔ Data)
- `finding_csv_complete_correlation_132_of_164_critical_mapped.md` -- DEFINITIVE 80% coverage
- `finding_csv_lua_correlation_35_tables_mapped.md` -- SpreadSheet init mapping
- `finding_lua_to_csv_data_bridge_concrete_correlations.md` -- bridge mechanics
- `finding_binding_id_runtime_lookup_confirmed.md` -- binding-id == field-id

### Data Catalog
- `docs/data/ffxivtool_export_overview.md` -- 803-table catalog overview
- `docs/data/ffxivtool_table_catalog.csv` -- machine-readable catalog
- `docs/data/ffxivtool_table_catalog.md` -- human-readable catalog

## 13. Coverage Summary (As of 2026-05-27)

```text
FINDINGS:                158 total
  EXE-side:               61
  Lua-side:               85
  Correlation:            12

EXE NATIVE SURFACE:     ~344 _cpp bindings + ~62 pure-Lua wrappers
  Located in masters:    409 registrar slots (100%)
  ~30 engine-internals discovered (NOT in _u.lua)
  Coverage:              ~100% of native binding surface

THUNKS DISASSEMBLED:      6 (the key architectural primitives)
WIRE OPCODES PINNED:      ~7 with handlers + ~218 inbound table slots

DATA CATALOG:            803 CSV tables
  Critical mapped:       132 of 164 (80%)
  Useful mapped:         ~371 of 625 (estimate; via _loadTextData)
  Total unique mapped:   ~503 of 803 (62.6%)

3-AXIS BRIDGE STATUS:
  Lua scripts ↔ EXE thunks        ✓ MAPPED (17 masters + 6 thunks)
  EXE async I/O ↔ CSV data         ✓ MAPPED (SpreadSheet pipeline)
  Lua scripts ↔ Wire opcodes       ✓ MAPPED (correlation findings)
  Lua scripts ↔ CSV data           ✓ MAPPED (132/164 critical)
```

## 14. What's Left

```text
HIGH-VALUE GAPS:
  - Inbound 0x12F handler not pinned (vtable walk needed)
  - 32 truly unmapped critical CSVs (likely in per-zone scripts)
  - ~125 of 625 useful CSVs (gear class variants)
  - Server S->C broadcast opcode (likely 0x130/131/132)

MEDIUM-VALUE GAPS:
  - 3 sibling _updateWork thunks (Director/Item/Group) - confirm
    pattern uniformity
  - _parseTextCommand thunk (chat dispatch)
  - _appendMessagePool thunk (chat display)
  - _isInstanceOf thunk (RTTI walk)
  - vtable[0x6c] walk for sample classes (200+ named functions)

LOW-VALUE / COSMETIC:
  - 2D map UI scripts (4 unmapped critical)
  - Localization tables (text_*)
  - System debug tables
```
