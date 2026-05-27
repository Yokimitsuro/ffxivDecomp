# Quick Reference: FFXIV 1.x Architecture Lookup Tables

**Single-page reference for the most-used facts** from the 158
findings (61 EXE + 85 Lua + 12 correlation). Use this when you need a
fast lookup; refer to the named finding files for full context.

Last updated: 2026-05-27 (expanded: added factories, layout offsets,
class hierarchy, time/bandwidth, 3-paradigm bridge, channel constants).

For historical narrative + pre-session findings, see
`MASTER_INDEX_1.x_MODEL.md`.

---

## 1. All 17 Native Master Blocks (EXE-confirmed)

```text
Class                 Master address    Slots   Walked   _u.lua match   Functor factory
-----                 --------------    -----   ------   ------------   ---------------
DirectorBaseClass     0x00758260          5      5/5     5 EXACT        0x00726d50
ItemBaseClass         0x00753dd0         20     20/20    19 + 1 internal 0x00726670
WorldMaster           0x00754c70         23     23/23    23 EXACT        0x00726ca0
DesktopWidget         0x00757ea0         44     44/44    44 EXACT        0x00726bf0 / 0x00726b40
global                0x007582e0         15     15/15    15 EXACT        0x00726e00
GroupBaseClass        0x00757b70         16     16/16    15 + 1 internal 0x007265c0
Math                  0x00740ec0          4      4/4     4 EXACT         (RNG-only factory)
WidgetBaseClass       0x00754a60         24     24/24    24 EXACT        0x007269e0 / 0x00726a90
AreaMaster            0x00753cf0          9      9/9     9 EXACT         0x0072cd40
PlayerBase            0x00753f90         99     99/99    94 + 5 internal 0x007267d0
NpcBaseClass          0x00754850         24     24/24    23 + 1 internal 0x0072d400 / 0x0072d4b0
ActorBaseClass        0x00753c30          8      8/8     7 + 1 internal  0x00726300 / 0x007263b0
AreaBaseClass         0x00754e70          1      1/1     0 + 1 (stub)    (shared)
CharaBaseClass        0x007574a0         82     82/82    76 + 6 internal 0x00726460 / 0x00726510
SpreadSheet           0x00758670         10     10/10    10 EXACT        0x00746cb0 / 0x00746d60
Debug                 0x00757ce0         20     20/20    4 + 16 INTERNAL 0x00726930
Sequence              0x007547d0          5      5/5     4 + 1 internal  0x00726880

NO MASTER (100% pure Lua wrappers):  String, Table

TOTAL: 409 registrar slots across 17 masters
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

### Outbound (Zone channel, 9 opcodes 0x12d-0x135)

```text
Opcode  Size    Handler                                      Purpose
------  ----    -------                                      -------
0x12d   200B    PacketBuilder_opcode_0x12d_200B_tagged       Tagged container
                                                              (5+ variants: script error,
                                                               bulk state, anti-tamper)
0x12d   var     ZoneOut_sendScriptError_opcode_0x12d         Script error report
0x12e   104B    ZoneOut_send_opcode_0x12e_104B               RPC carrier
0x12e   ?       Lua_send6argRpc_via_opcode_0x12e             6-arg RPC dispatch
0x12f   56B     WorkSync_buildAndSendPacket_opcode_0x12f     State sync C->S (STRING)
0x130   ?       (TBD)
0x131   ?       (TBD)
0x132   ?       Item _updateWork carrier
                  Lua_sendByteUshortAt0x68_via_0x132         (used by ItemBaseClass)
0x133   56B?    WorkSyncAlt_serializePayloadAndSend_opcode_0x133  Alt-work-sync
0x134   ?       (TBD)
0x135   24B     ZoneOut_send_opcode_0x135_24B_dword          Subscribe to bindingId
```

### Inbound (Zone channel, table @ 0x00fdfb80, ~224 entries)

```text
Entry  Address      Handler                                     Mapped opcode
-----  -------      -------                                     -------------
  0    0x00fdfb80   FUN_00759820 -> _onTouch (begin, flag=1)    (likely 0x12d)
  1    0x00fdfb84   FUN_007598a0 -> _onTouch (end,   flag=0)
  2    0x00fdfb88   FUN_00759920 -> MyPlayer_onMoveAtSit
  3    0x00fdfb8c   complex custom dispatcher
  ... (entries 4-27 various small-payload events)
 28-34  -- 6 UNUSED slots (reserved space)
 35-37  CHAT TYPES A/B/C (/say, /yell or system, /tell with sender+recipient)
 38    _onReceiveDataPacket (generic 192B data)
 39-48  various small-payload events
 96-223 mostly default no-op (drops packet)

INBOUND opcode 0x12F handler:           NOT IN THIS TABLE (uses different path)
                                         (likely via vtable polymorphism)
```

### Other Channels

```text
Lobby channel:      8 outbound + 9 inbound opcodes
                    (per docs/packets/packet_lobby_*.md)
Chat channel:       Uses chat opcode 0x40 + channels 32/33/38/40
                    (per worldMaster._appendMessagePool routing)
```

### Chat Channel IDs

```text
Channel ID    Used by                       Purpose
----------    -------                       -------
32            worldMaster:notify            System notify (yellow)
33            worldMaster:alert             System alert (red)
38            NpcBaseClass:say              NPC dialog (white)
40            worldMaster:say               World cryer / global say
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

Known FunctionEndCallback subclasses:
  LoadDataFunctionEndCallback   40 B    SSD async loads completion

Predicted (high confidence):
  ~8 more _wait* bindings each with own ResumeChecker subclass
  (waitForGroup, waitForTurning, waitForCharaSchedulerFinished, etc.)

Coroutine context API:
  CoroutineContext_isTrackingEnabled   FUN_00cd27d0
  CoroutineContext_pushResumeChecker   FUN_00cd2860
  CoroutineContext_pushEndCallback     FUN_00cd28c0
  CoroutineContext_findPendingCallback FUN_00cd2630
  ScriptCoroutineKey_construct         FUN_00713f80
```

## 5. WorkSync State Replication

```text
C -> S (player UI actions, rare):
  Lua: actor:_updateWork("category", "field", subIdx, listIdx)
   -> WorkPath built (2-4 components, 176 bytes per instance)
   -> WorkSync_dispatchOrEnqueue (FUN_00767fc0)
   -> Look up in actor's red-black tree (WorkPathTree_lowerBound)
   -> If sync-flag SET (entry+0x29): predictive apply via UpdateQueue
   -> Always: WorkSync_serializePayloadAndSend (FUN_00767c00)
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
   - BindingStorage_writeField_lowLevel_byBindingId  0x00ce44d0

C -> S subscribe:
  Lua: queryBinding(bindingId)
  Wire: opcode 0x135, 24-byte packet
```

### WorkPath Struct Layout (176 bytes)

```text
offset  type            field             notes
------  ----            -----             -----
+0x00   std::string     structName        e.g. "charaWork", "playerWork"
+0x54   std::string     slotCategory      e.g. "parameterSave", "battleSave"
+0xa8   uint16          fieldIdx0         0 for base form
+0xaa   uint16          fieldIdx1         0 for base form
+0xac   uint8           hasFields         0 = base / 1 = with-fields
                                          (also: encoding flag for wire)
```

### Binding Storage at actor+0x214

```text
Bit-packed buffer with 4 type tags (u8/u16/u24/u32).
Read path:  Actor_readBindingUInt   @ 0x00cc7b90
            Actor_readBindingBool   @ 0x00cc7be0
            Actor_readBindingFloat  @ 0x00cc7de0
Write path: 4 BitPacked writers (above) -> lowLevel byBindingId
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

### Lua Class Inheritance Tree

```text
ActorBase
  ├── CharaBase (animated character, abstract)
  │     ├── PlayerBase
  │     └── NpcBase (and 250+ concrete NPC subclasses)
  ├── Item (and 10+ subclasses)
  ├── Director (and 226+ subclasses for instances/events)
  │     ├── InstanceRaid (dungeons, trials)
  │     ├── CaravanGuard (chocobo escort)
  │     ├── WeatherDirector
  │     └── ... 220+ more
  ├── Area / AreaMaster (zone container)
  ├── SpreadSheet (data table actor)
  ├── Sequence (cutscene playback)
  └── WidgetBaseClass (and 194 widget subclasses)
        └── DesktopWidget (singleton UI hub)

Group hierarchy (4 families):
  GroupBase
    ├── PartyGroup
    │     ├── PlayerPartyGroup
    │     └── MonsterPartyGroup
    ├── CommunityGroup
    │     ├── GrandCompanyGroup (Maelstrom/Twin Adder/Immortal Flames)
    │     └── RetainerGroup
    ├── ContentGroup (instance-scoped roster)
    └── RelationGroup (Trade/Invite/Bazaar 2-actor confirmations)

Singletons:
  global, worldMaster, desktopWidget, debug,
  itemDataSheet, equipmentSheet, ... (all the global SSDs)
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

## 12. Engine Memory Layout (LuaGameEngine + ActorBase Instance)

### LuaGameEngine instance layout (selected fields)

```text
Offset    Field                                 Notes
------    -----                                 -----
+0x008    classRegistryRoot                     Main class registry node
+0x018    nameInternTable                       String interning for names
+0x174ec  ZoneClient                            Global zone client pointer
                                                (in Application_dispatchToZoneClient)
+0x17c    classByNameMap                        Main class lookup (name -> entry)
+0x1cc    errorPool                             Collected definition errors
+0x204    pendingClassMap                       Forward-declared class entries
+0x208    pendingMapEnd
+0x20c    pendingClassEnabled                   Master pending-mode flag
```

### Class entry layout

```text
Offset    Field                Notes
------    -----                -----
+0x004    parent class ptr     Inheritance link
+0x020    derived-classes ptr  Linked list of children
+0x07c    pending flag         1 = under construction; 0 = finalized
+0x0     vtable* (at +0)       Standard C++ vtable
+0x6c    vtable[27]            POLYMORPHIC SPAWN CTOR (called by _createActor)
+0xec    vtable[59]            WorkSync dispatcher pointer (per-class)
```

### Actor instance layout (selected)

```text
Offset    Field                       Notes
------    -----                       -----
+0x14     binding metadata ptr        Used by readers
+0x7d     actor-init-complete flag    Reads return 0 if 0
+0x214    BindingStorage              Bit-packed actor field data
                                       (the actor's "work" struct in C++)
```

### WorkSync dispatcher layout (per class, at class+0xec)

```text
Offset    Field
------    -----
+0x04     WorkPath red-black tree root
+0x24     UpdateQueue (pending predictive entries)
+0x30     queue start offset
+0x34     batch flag (atomic multi-update transactions)
```

### SpreadSheet instance layout (partial)

```text
Offset    Field
------    -----
+0x60     SSD context
+0xB4     schema metadata
+0xC4     row-key hash table (uint32 keys)
+0xD8     dependency metadata
```

### CSV row entry layout

```text
Offset    Field
------    -----
+0x14     value pointer
+0x18     column-type tag byte (matches FFXIVTool header's type column)
```

### Inbound dispatch table

```text
Address: 0x00fdfb80
Stride:  4 bytes per entry
Size:    ~224 entries (= 896 bytes total)
Range:   0x00fdfb80 .. 0x00fdff00+
```

## 13. The 3 Paradigms of EXE↔Lua Communication

```text
PARADIGM 1: invokeLua (engine pushes events into Lua)
  ~80 callbacks total
  EXE calls into Lua: _onXxx event handlers (onInit, onTouch, onDeath, etc.)
  Examples: actor:_onInit, _onReceiveDataPacket, _onMoveAtSit

PARADIGM 2: registerLua (Lua calls into EXE native bindings)
  ~344 native _cpp bindings registered in 17 master blocks
  Lua calls into EXE: obj:_someMethod()
  Examples: _updateWork, _createActor, _getData, _wait

PARADIGM 3: timed dispatchers (engine polls Lua state periodically)
  Examples: _setLoopInterval per-actor tick
            coroutine pump checking ResumeChecker readiness
            WorkSync delta-broadcast at server tick
```

## 14. Eorzea Time & Bandwidth Model

```text
ECHO TIME (real-time-to-game-time conversion):
  Eorzea day      = 60 server minutes (1 real hour)
  Eorzea night    = in-game 19:00 - 04:59
  Guildleve reset = every 12 real hours
  XP boost reset  = every 12 real hours
  Anima tick      = every 4 real hours

BANDWIDTH TARGET:
  ~600 bytes/s steady state per client
  Designed for 512 Kbps DSL (with WoW-era margin)
  Achievement: per-actor HP sync at 3 Hz = 60 actors x 6 bytes x 3 = ~1.1 KB/s peak

PARTY BONUS MULTIPLIERS:
  Size 1: 1.0x   Size 2: 1.5x (duo bonus)
  Size 3: 1.4x   Size 4: 1.3x
  Size 5: 1.2x   Size 6: 1.1x

GENERAL PARAMETER (player stats):
  generalParameter[35]: 28 synced indices + 7 unsynced
  Sync tick rate bands: 0.3s / 1s / 3s / 10s / 60s
```

## 15. Key Findings by Category (jump points)

### EXE Architecture (this session's flagship findings)

- `finding_smallmodules_inventory_closed_17_masters.md` -- the 17-master inventory
- `finding_createActor_thunk_async_actor_factory.md` -- async actor creation
- `finding_defineClass_thunk_class_registration_loop.md` -- class registry
- `finding_wait_thunk_universal_resume_checker_confirmed.md` -- async pattern
- `finding_updateWork_thunk_worksync_state_replication.md` -- WorkSync end-to-end
- `finding_worksync_inbound_writers_pinned.md` -- 4 BitPacked writers
- `finding_spreadsheet_thunks_exe_data_bridge.md` -- EXE-Data bridge
- `finding_inbound_dispatch_table_found.md` -- 224-slot inbound table

### EXE Architecture (prior sessions; reference)

- `finding_binding_id_runtime_lookup_confirmed.md` -- binding-id == field-id
- `finding_worksync_wire_opcode_0x12f.md` -- opcode 0x12F outbound
- `finding_workpath_and_binding_storage_internals.md` -- WorkPath + storage
- `finding_opcode_0x135_subscribe.md` -- subscribe wire
- `finding_zone_outbound_opcode_roster.md` -- 9 outbound opcodes
- `finding_lobby_flow.md` -- 4-phase login flow
- `finding_ipc_channel_framing.md` -- PacketBufferBase architecture
- `finding_lpb_loader_chain.md` -- .lpb loader (XOR-0x73)
- `finding_lua_engine_bridge.md` -- Lua 5.1 GameEngine bridge
- `finding_zone_chat_channel_architecture.md` -- Zone/Chat with SocketThread
- `finding_bootup_state_machine.md` -- ~58 bootup states
- `finding_invokeLua_roster_closed_80_complete.md` -- 80 invokeLua callbacks
- `finding_widget_3tier_dispatcher_architecture.md` -- 3-tier widget dispatch

### Lua Architecture

- `finding_native_binding_surface_439_across_19_modules.md` -- catalog (note: 439 is the OLD overcount; reality is ~344 native; see CORRECTION in this doc)
- `finding_actor_work_schemas.md` -- charaWork/npcWork schemas (190+ fields)
- `finding_combat_relations_and_potencial.md` -- 4-state combat
- `finding_director_baseclass_and_226_subclasses.md` -- Director hierarchy
- `finding_widget_baseclass_architecture_and_194_widgets.md` -- widget hierarchy
- `finding_party_subclasses_and_weather.md` -- Group + Director subclasses
- `finding_worldmaster_complete.md` -- 24 bindings + Eorzea time cycles
- `finding_item_common_inventory.md` -- 190+ item functions, 4686 lines
- `finding_bindwork_catalog.md` -- 25+ binding IDs catalogued
- `finding_npc_dialog_protocol.md` -- say/ask family + 8 talk-turn modes
- `finding_combat_command_pipeline_and_4param_scaling.md` -- combat pipeline
- `finding_charabase_battle_real_combat_formulas.md` -- battle math
- `finding_company_group_freecompany.md` -- GC system (3 GCs)
- `finding_relation_group_family.md` -- 2-actor confirmation primitive

### Correlation (Lua ↔ EXE ↔ Data)

- `finding_csv_complete_correlation_132_of_164_critical_mapped.md` -- DEFINITIVE 80%
- `finding_csv_lua_correlation_35_tables_mapped.md` -- SpreadSheet init mapping
- `finding_lua_to_csv_data_bridge_concrete_correlations.md` -- bridge mechanics
- `finding_binding_id_runtime_lookup_confirmed.md` -- binding-id == field-id
- `finding_native_binding_surface_439_across_19_modules.md` -- pattern overview
- `finding_lua_api_to_zone_opcode_systematic_xref.md` -- API↔opcode systematic

### Data Catalog

- `docs/data/ffxivtool_export_overview.md` -- 803-table catalog overview
- `docs/data/ffxivtool_table_catalog.csv` -- machine-readable catalog
- `docs/data/ffxivtool_table_catalog.md` -- human-readable catalog
- `docs/server/content_requirements/ffxivtool_import_plan.md` -- import plan

## 16. The bindWork Catalog (25+ binding IDs known)

```text
Binding ID    Field                                 Type
----------    -----                                 ----
0x3f2 (1010)  charaWork.parameterSave.hp[1]         u24 (predicted)
0x3f3 (1011)  charaWork.parameterSave.hpMax[1]      u24
0x3f4 (1012)  charaWork.parameterSave.state_mainSkillLevel  u24
0x7d2 (2002)  charaWork.battleSave.potencial        float (NM-sign-coded)
0xbbd (3005)  bazaar master flag (NEW discovery)
0xbbe (3006)  charaWork.property                    u32 (bitset)

Band ranges (full catalog has 25+ in these bands):
  1xxx   charaWork.parameterSave (hp/hpMax/mp/mpMax/state/level/...)
  2xxx   charaWork.battleSave (potencial, status, target, ...)
  3xxx   charaWork.property (bitsets, flags)
  4xxx   charaWork.statusSave (status effects)
  5xxx   npcWork.*
  100xxx PlayerBase additions
  200xxx Item-related
  300xxx Group-related
  400xxx World/zone-related
  500xxx Director/event-related

The READ side uses binding-id directly (compact 2-byte wire).
The WRITE side uses string paths (verbose ~30-byte wire).
This asymmetry saves ~80% bandwidth on the hot path.
```

## 17. The Lua Class System (engine internals)

```text
TWO-TABLE REGISTRY (engine+0x17c main + engine+0x204 pending):
  - Main map: finalized classes by name
  - Pending map: forward-declared (allows file load in any order)
  
DEFINITION FLOW:
  _defineClass("Child", "Parent") ->
    look up Parent (auto-create if not yet defined) ->
    if Parent finalized: ERROR ->
    if Parent pending: link Child to it, mark Child as ready

VTABLE INHERITANCE (CRITICAL):
  C++ classes have vtables baked at compile time.
  Lua-derived "Child" inherits Parent's vtable AS-IS.
  vtable[0x6c] = spawn ctor = called by _createActor("Child", ...)
  vtable[0xec] = WorkSync dispatcher

This is why 200+ pure-Lua classes can be spawned via _createActor:
they all defer to their nearest C++ ancestor's vtable[0x6c].
```

## 18. Class-Specific Record Sizes (EXE-confirmed)

```text
Class                          Size      Purpose
-----                          ----      -------
WorkPath instance              176 B     2 std::string + 2 shorts + flags
OnInitResumeChecker            16 B      vtable + scriptContext + actorRef + ready
WaitResumeChecker              40 B      vtable + 64-bit deadline + timer state
LoadDataResumeChecker          148 B     vtable + scope + tables + scratch
LoadDataFunctionEndCallback    40 B      vtable + ssd_owner + tables + callId + flag

opcode 0x12F outbound packet   56 B      sequence + WorkPath bytes
opcode 0x135 outbound packet   24 B      header + bindingId (4 bytes payload)
opcode 0x12d outbound packet   200 B     tagged container
opcode 0x12e outbound packet   104 B     RPC carrier

CommandUpdate record           0x118 B   (280 bytes)
BehaviorLogger listener        0x48 B    (72 bytes; separate from CommandUpdate)
```

## 19. Coverage Summary (As of 2026-05-27)

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
  Lua scripts ↔ EXE thunks         ✓ MAPPED (17 masters + 6 thunks)
  EXE async I/O ↔ CSV data         ✓ MAPPED (SpreadSheet pipeline)
  Lua scripts ↔ Wire opcodes       ✓ MAPPED (correlation findings)
  Lua scripts ↔ CSV data           ✓ MAPPED (132/164 critical)
  EXE binding storage ↔ Wire       ✓ MAPPED (binding-id == field-id)
```

## 20. What's Left

```text
HIGH-VALUE GAPS:
  - Inbound 0x12F handler not pinned (vtable walk needed at 0x0110fcf8)
  - 32 truly unmapped critical CSVs (likely in per-zone scripts)
  - ~125 of 625 useful CSVs (gear class variants)
  - Server S->C broadcast opcode (likely 0x130/131/132)
  - Per-zone scripts not yet swept (regionParam, zoneGroupParam,
    hamletDefScore, etc.)

MEDIUM-VALUE GAPS:
  - 3 sibling _updateWork thunks (Director/Item/Group) - confirm
    pattern uniformity
  - _parseTextCommand thunk (chat dispatch)
  - _appendMessagePool thunk (chat display)
  - _isInstanceOf thunk (RTTI walk)
  - vtable[0x6c] walk for sample classes (200+ named functions)
  - 8 remaining _wait* thunks (additional ResumeChecker subclasses)
  - LinkshellCommand family (system commands)
  - DesktopWidget main (687 KB Lua file)
  - charabaseclass_event.lua (444 lines)
  - charabaseclass_battle.lua (2027 lines, partial coverage)

LOW-VALUE / COSMETIC:
  - 2D map UI scripts (4 unmapped critical: 2Dmap_*)
  - Localization tables (text_*)
  - System debug tables
  - 100+ small gear class variants (acn200/300, blm0j1, ...)
```

## 21. Key Confirmed Facts (independent EXE validations)

```text
- binding id == on-wire field id (1:1 mapping; 3 independent
  EXE smoking-gun functions hardcoding 0xbbe/0x7d2/0x3f2)
- WorkPath struct = 176 bytes; 2 std::string + 2 shorts + flags
- Bit-packed binding storage at actor+0x214 (4 type tags: u8/u16/u24/u32)
- Storage class polymorphism via vtable+8 (read) +0x10 (alt)
- Wire opcode 0x12F = work-sync C->S (56-byte packet, Zone channel)
- Wire opcode 0x135 = subscribe-by-binding-id (24-byte, Zone channel)
- Inbound dispatch table at 0x00fdfb80 (~224 entries)
- Engine namespace: Component::Lua::GameEngine + 
  Application::Lua::Script::Client::Control
- vtable[0x6c] = polymorphic spawn ctor (every Lua-registered class)
- vtable[0xec] = WorkSync dispatcher pointer (per-class)
- ZoneClient global slot at engine+0x174ec
- 50+ item type predicates in ItemBaseClass_common (taxonomy complete)
- 7 jobs (15-19, 26-27) + 8 craft (DoH) + 4 gather (DoL incl. Shepherd)
- 1.x had GRAND COMPANY (not Free Company; FC came in ARR 2.0+)
- 1.x had NO player housing (the "Wards" are NPC trade districts)
- Materia + Bazaar existed in 1.x (precursor to ARR)
```

## 22. Speculative / Open Threads

```text
- Server-broadcast opcode (S->C binding-id push): 0x130/131/132 candidates
- Inbound 0x12F handler: vtable polymorphism via 0x0110fcf8
- The 8 predicted _wait* ResumeChecker subclasses (sizes TBD)
- Specific binding ids beyond catalog (5xxx NPC, larger ranges)
- WorkPath byte-exact wire format (text and binary variants)
- Per-zone CSV consumers (regionParam etc.)
- The 100+ Judge subclass-specific CSV bindings (if any)
```
