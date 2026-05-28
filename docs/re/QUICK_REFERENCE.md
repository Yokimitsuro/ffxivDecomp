# Quick Reference: FFXIV 1.x Architecture Lookup Tables

**Single-page reference for the most-used facts** from the 187+
findings (80 EXE + 87 Lua + 13 correlation). Use this when you need a
fast lookup; refer to the named finding files for full context.

Last updated: 2026-05-28 +CONTENT (35-commit session). WIRE PROTOCOL
100% bidirectional + CONTENT MODEL mapped: work schemas (battle/event/
player/area/director), command flow, zone bootstrap, NPC talk-turn,
Director orchestration. KEY ARCHITECTURAL PRINCIPLE confirmed x4:
"content is client-side; server orchestrates state + triggers +
authorization". READY-TO-IMPLEMENT-SERVER milestone reached.

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

## 2. Disassembled Thunks (15) + Wire Opcodes

```text
Lua API                C++ thunk                          Address       Wire opcode
-------                ---------                          -------       -----------
_createActor           global_cpp_createActor_thunk       0x00709640    (none; coroutine)
_defineClass           global_cpp_defineClass_thunk       0x006dcc30    (none; local)
_wait                  ActorBase_cpp_wait_thunk           0x006dbcb0    (none; coroutine)
_getData (SSD)         SpreadSheet_cpp_getData_thunk      0x0070a720    (none; sync mem)
_loadKeyTemporarily    SpreadSheet_cpp_loadKey..._thunk   0x006f0840    (disk I/O async)
_updateWork (CharaBase) CharaBase_cpp_updateWork_thunk    0x006e7670    0x12F (56B Zone)
_updateWork (Director)  lua_updateWork_impl               0x006e85e0    0x12F (shared)
_updateWork (Item)      Lua_sendByteUshort..._via_0x132   0x006e2af0    0x132 (24B)
_updateWork (Group)     GroupBase_cpp_..._customDispatch  0x006e8890    0x133 (56B alt)
_parseTextCommand      DesktopWidget_cpp_parseText..._thunk 0x006fe2a0  (none; local parse)
_appendMessagePool     DesktopWidget_cpp_appendMessage... 0x006eced0    (queue-flushed)
_waitForTurning        CharaBase_cpp_waitForTurning_thunk 0x006e1700    (none; coroutine)
_waitForCharaSchedulerFinished                            0x006e4b40    (none; coroutine)
_waitForCharaSchedulerTutorialFinished                    0x006e6c20    (none; coroutine)
_waitForTargetTutorial                                    0x006e5710    (none; coroutine)
_waitForCameraTutorial                                    0x006e1c50    (none; coroutine)
_waitForItemSearchWidget                                  0x006e1b90    (none; coroutine)
_isInstanceOf          global_isInstanceOf_thunk_dualDispatch_   0x006ff210  (none; local; dual)
                        7rtti_plus_luaChain                                   7 RTTI fast-path + Lua chain
_canCreateActorByName  global_canCreateActorByName_thunk_        0x006ff1a0  (none; local)
                        creatabilityCheck                                     class registry + 3 tag check
```

### Class-system thunk family (4 complete; covers the entire Lua class API)

```text
Thunk                       Address         Bound name              Role
-----                       -------         ----------              ----
_defineClass                0x006e4d20      "_defineClass"          Register class into parent chain
_createActor                0x006e1700      "_createActor"          Instantiate via vtable[0x6c]
_isInstanceOf               0x006ff210      "_isInstanceOf"         Dual-dispatch type check
_canCreateActorByName       0x006ff1a0      "_canCreateActorByName" Creatability pre-check
```

### Inbound chat handlers (3 variants @ entries 35-37 of dispatch table)

```text
Entry  Handler                                          Variant
-----  -------                                          -------
35     ZoneIn_handler_chat_say_substitution_entry35     System/say with msg+sub params (0x40 buf)
36     ZoneIn_handler_chat_variant_C_tell               /TELL (sender +9, recipient +0x29, body +0x49)
37     ZoneIn_handler_chat_simple_entry37               Simple chat (1 name + flag byte)
```

### Inbound CommandUpdate (2 callback dispatchers)

```text
CommandUpdater_invokeLua_onUpdateWork_clipObj  @ 0x00773d90  simple (cutscene)
CommandUpdater_invokeLua_onUpdateWork_complex  @ 0x00773f10  filter+dispatcher+convert
Both fire Lua callback: actor:_onUpdateWork(struct, slot, idx0, idx1)
```

## 3. Wire Opcodes Confirmed

### Outbound (Zone channel, 9 opcodes 0x12d-0x135) -- FULLY MAPPED

```text
Opcode  Size    Handler / Purpose
------  ----    -----------------
0x12d   200B    PLAYER COMMAND (tagged container, CRC32 integrity)
                  PacketBuilder_opcode_0x12d_200B_tagged
                  - via _executeCommand -> vtable[0xa8] -> immediate/queued
                  - +0x24 = CRC32 of 128B payload (Sqex::Crypt::Crc32)
                  - +0x28 = discriminator, +0x49 = 128B command payload
                  - checksummed variants v1/v2 (0x0075e3a0/0x0075e510)
                  - also: ZoneOut_sendScriptError_opcode_0x12d (script err)
0x12e   104B    NAMED RPC (ResumeChecker-backed server calls)
                  Lua_send6argRpc_via_opcode_0x12e (single funnel)
                  - +0x10 = 1-byte method selector
                  - +0x19 = 64-byte param buffer
                  - paired with ~24 ResumeChecker types (request/response)
0x12f   56B     WorkSync update C->S (STRING-keyed path)
0x130   32B     list lifecycle ACK (spawn: queueAdd + delete pair)
0x131   24B     byte toggle
0x132   24B     Item _updateWork carrier (byte+ushort)
0x133   56B     WorkSync alt / spawn init ACK
0x134   40B     challenge/nonce
0x135   24B     Subscribe to bindingId

CHECKSUM ALGORITHM: standard CRC32 (poly 0xEDB88320, init/final
0xFFFFFFFF, slice-by-8). Transport integrity ONLY, NOT anti-cheat --
server must validate commands semantically. Trivially replicable.
```

### Inbound COMPLETE WIRE PROTOCOL (final, ~50 opcodes pinned)

```text
ACTOR LIFECYCLE:
  SPAWN:    0x17c TYPE_TAG 0     EntryBuilder         ~120B with class name
                    TYPE_TAG 0xe OnlineStatusUpdater  (same opcode, different tag)
  DESPAWN:  0x143                 BreakupBuilder       ~32B (id only)

GROUP:: TYPED PACKETS (8 subclasses, all wire-mapped):
  EntryBuilder         -> 0x17c (TYPE TAG 0)
  BreakupBuilder       -> 0x143
  OnlineStatusUpdater  -> 0x17c (TYPE TAG 0xe)
  MemberInfoUpdater    -> 0x18b
  WorkSyncUpdater      -> 0x187
  EntryLinkShellBuilder-> 0x188 (single) / 0x189 (batch)
  PropertyUpdater      -> internal via EntryLinkShellBuilder vtable[12]

PER-ACTOR 3x5 MATRIX (15 opcodes 0x148-0x156):
                  SINGLE     VARIABLE    FIXED-16   FIXED-32   FIXED-64
  TYPE A (112B):  0x148      0x149       0x14a      0x14b      0x14c
                  ACTION single/batch action results
  TYPE B (6B):    0x14d      0x14e       0x14f      0x150      0x151
                  STATUS icons (id + duration + flag)
  TYPE C (2B):    0x152      0x153       0x154      0x155      0x156
                  ID lists (action ids / hate list / targets)

ACTOR-BOUND VARIANTS (8 opcodes):
  0x146  ACTOR EVENT with context lookup
  0x16d  ACTOR EVENT byte payload
  0x16e  ACTOR EVENT with context lookup
  0x176  ACTOR EVENT simple payload
  0x18f  ACTOR TRIGGER no payload
  0x190  ACTOR EVENT with payload
  0x191  ACTOR PING (lookup + dispatch no args)
  (+ 0x148-0x156 above)

STATE EVENT CLUSTERS (10 opcodes):
  0x17a/0x17d/0x17e         session-gated state events (uint/uint64)
  0x17f-0x182               state events uint64 typeA/B/C/D
  0x183/0x184/0x185         uint to generic state variants

LARGE BATCH:
  0x18d                     Multi-record batch (up to 255 x 40B records)

SYSTEM / UI:
  0x193                     System error (22 codes: 16 slots + 6 specific)
  0x196                     Multi-field bit-packed (player status panel)
  0x1a3                     UI msgpool push uint
  0x198                     STRING UPDATE (rename/announcement)

MULTI-ENTITY STATE:
  0x186                     Multi-actor state set (12B per record)
  0x18a                     Bulk pair set (8B per entry)

WORKSYNC FIELD-LEVEL (lower):
  0x12F (56B)               WorkSync update (C->S string-keyed)
  0x132 (24B)               Item state notify
  0x133 (56B)               WorkSync alt / spawn init ACK

PER-ACTOR MESSAGE SYSTEM (opcodes 0x148-0x156):
  Routing: ALL 15 -> ActorMessageQueue_lookupOrCreate_perActorId_WorkPathTree
                       (red-black tree at this+0x10, queue per actor)
  TYPE A (0x148-0x14e): COMMANDS/ACTIONS
    constructor: FUN_007713xx family
    enqueue:     FUN_00764a30
    cleanup:     FUN_0076df10
  TYPE B (0x14f-0x156): EVENTS/STATE
    constructor: FUN_00768exx family
    enqueue:     FUN_00764b30
    cleanup:     FUN_007660c0

OPCODE 0x193 SYSTEM ERROR (22 codes):
  0x00-0x0F: 16 slot setters (error categories)
  0x10-0x12, 0x16: 4 specific error type setters
  0x13: BUILD LOCALIZED ERROR STRING (Japanese UTF-16 templates)
  0x14: System_broadcastSubsystem_preCancelHooks
  0x15: cancel hook cleanup
```

### Inbound GAME PROTOCOL (Zone channel; main dispatcher @ 0x004dc690; ~50+ opcodes) -- NEW

```text
Wire opcode  Handler                                  Purpose
-----------  -------                                  -------
SESSION OPCODES (LOW; 0x02-0x11):
  0x02       FUN_004d90c0+9980+dc5d0 chain            Session reauth
  0x03       FUN_004d8560 + 2x std::string            Login text push
  0x04       Complex disconnect cleanup chain         Logout
  0x05/0d/10 vtable[+0x24] dispatch                   Generic forward
  0x06       FUN_0081eb90                             ?
  0x07       Resync loop                              Reconnect resync
  0x08-0x0b  FUN_0081f090 bulk push (1/16/32/64)      Bulk state push
  0x0c       FUN_004bbb30 (short+byte)                ?
  0x0e/0x11  Disconnect notice variants
  0xca/0xcb  Session marker / cleanup

GAME PROTOCOL (HIGH; 0x143-0x1a8):
  0x143      DESPAWN -- BreakupBuilder construction   ACTOR DESPAWN PACKET ← !
  0x146      FUN_005764c0
  0x148-0x156 FUN_00576560-b80 (15 distinct)          Various bridges
  0x16d      FUN_005763c0 (byte payload)
  0x17a      FUN_005763b0 (uint payload)
  0x17c      SPAWN -- SpawnPipeline_FACTORY           ACTOR SPAWN PACKET ← !
  0x17d-0x186 FUN_005762c0-380 (10 distinct)          Various bridges
  0x187      WORKSYNC -- WorkSyncUpdater_FACTORY      STATE BATCH ← !
  0x188-0x18a FUN_00576360-380                        Various bridges
  0x18b      MEMBERINFO -- MemberInfoUpdater_FACTORY  MEMBER INFO UPDATE ← !
  0x18d      0x18d batch -- MULTI-RECORD BATCH        BATCH STATE PUSH ← !
  0x18f/0x190 FUN_00576c60/cd0                        ?
  0x191      FUN_00576d40
  0x193      FUN_00578c90 (3-arg)
  0x196      FUN_00576050
  0x198      FUN_00576150 (string)
  0x1a3      FUN_00576140

Default fallback: vtable[+0x24] on session at this+0x4e0

The 0-59 sub-opcode table @ 0x00fdfb80 is a SEPARATE inbound
dispatch mechanism for different sub-event types.
```

### Inbound SUB-OPCODE table (Zone channel, table @ 0x00fdfb80, ~224 entries)

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

## 4. Async / Coroutine Pattern (ResumeChecker FULL INVENTORY)

```text
Base interfaces:
  Component::Lua::GameEngine::ResumeCheckerInterface       (script yields)
  Component::Lua::GameEngine::FunctionEndCallbackInterface  (I/O completion)

~24 ResumeChecker subclasses (RTTI-string enumerated; was 11 documented).
The async yield pattern is ~2x more pervasive than first mapped. Full
list in finding_outbound_rpc_0x12e_format_plus_resumechecker_count_correction.md.
Categories: 6 async I/O, 3 RPC-backed (CreateStaticActor/CreateClientItem/
GetString), 3 animation, 3 scheduler, 3 tutorial, 6 core/misc.
RPC-backed checkers pair with outbound 0x12e RPC (request/response halves).

11 of those CONFIRMED with sizes (original inventory; universal yield pattern):
#   Subclass                                              Size    Lua API / role
-   --------                                              ----    --------------
1   OnInitResumeChecker                                    16 B   _createActor
2   WaitResumeChecker                                      40 B   _wait
3   LoadDataResumeChecker                                 148 B   _loadKeyTemporarily
4   AppendMessageResumeChecker                             12 B   _appendMessagePool
5   WaitForTurningResumeChecker                             8 B   _waitForTurning
6   WaitForCharaSchedulerFinishedResumeChecker             12 B   _waitForCharaSchedulerFinished
7   s_WaitForCharaSchedulerTutorialFinishedResumeChecker   12 B   _waitForCharaSchedulerTutorialFinished
8   TargetTutorialResumeChecker                            12 B   _waitForTargetTutorial
9   s_CameraTutorialResumeChecker                           8 B   _waitForCameraTutorial
10  s_ItemSearchWidgetResumeChecker                         8 B   _waitForItemSearchWidget
11  LpbLoader::ResumeChecker                              ~120 B  ENGINE-INTERNAL (LPB bytecode loader)

[possible 12th: HamletDefenseScoreResumeChecker for Director
 _waitForHamletDefenseScore -- target @ 0x006dcb00 is DATA label
 (Ghidra didn't auto-detect as function)]

SIZE DISTRIBUTION:
   8 B (3 subclasses): minimal (vtable + 1 context ptr)
  12 B (4):            small (vtable + ref + state)
  16 B (1):            OnInit (scriptCtx + actorRef + flag)
  40 B (1):            Wait (64-bit deadline + timer state)
 148 B (1):            LoadData (diskJobId + refs + flags)

Size correlates with READINESS CHECK STATE complexity.

Known FunctionEndCallback subclasses:
  LoadDataFunctionEndCallback   40 B    SSD async loads completion

Coroutine context API:
  CoroutineContext_isTrackingEnabled   FUN_00cd27d0
  CoroutineContext_pushResumeChecker   FUN_00cd2860
  CoroutineContext_pushEndCallback     FUN_00cd28c0
  CoroutineContext_findPendingCallback FUN_00cd2630
  ScriptCoroutineKey_construct         FUN_00713f80

UNIVERSAL THUNK PATTERN (5 steps; same for all 10):
  1. Extract args from Lua stack
  2. Setup wait target (varies per checker)
  3. Allocate subclass via operator_new(size)
  4. Construct via XResumeChecker_ctor
  5. CoroutineContext_pushResumeChecker (script yields)
```

## 5. WorkSync State Replication (FULLY MAPPED end-to-end ~95%)

### 4 _updateWork thunks, 3 distinct wire opcodes (CORRECTED)

```text
Class       Thunk                                       Opcode   Size   Predictive
-----       -----                                       ------   ----   ----------
CharaBase   CharaBase_cpp_updateWork_thunk @ 0x006e7670  0x12F   56 B   YES
Director    lua_updateWork_impl @ 0x006e85e0             0x12F   56 B   YES
Item        Lua_sendByteUshort..._via_0x132 @ 0x006e2af0 0x132   24 B   NO (state notify)
GroupBase   GroupBase_cpp_..._customDispatch @ 0x006e8890 0x133  56 B   NO (group authoritative)
```

**Important**: pattern is NOT uniform. The 4 share the Lua API name
`_updateWork` but use DIFFERENT thunks and wire opcodes. Per-class
binding name is OVERLOADED via master registrars.

### C -> S (full pipeline; CharaBase/Director path)

```text
Lua: actor:_updateWork("category", "field", subIdx, listIdx)
 -> WorkPath built (2-4 components, 176 bytes per instance)
 -> WorkSync_dispatchOrEnqueue (FUN_00767fc0)
 -> Look up in actor's red-black tree (WorkPathTree_lowerBound)
 -> If sync-flag SET (entry+0x29): predictive apply via UpdateQueue
 -> Always: WorkSync_serializePayloadAndSend (FUN_00767c00)
 -> Wire: opcode 0x12F, 56-byte packet, STRING payload
```

### S -> C (7-LEVEL INBOUND CHAIN)

```text
LEVEL 0  Wire packet (opcode 0x12F/0x132/0x133)
LEVEL 1  Zone inbound dispatcher (table @ 0x00fdfb80)
LEVEL 2  Lua-bound dispatch: FUN_006e17e0 (full) / FUN_006e1f70 (simple)
LEVEL 3  Per-class WorkSync dispatcher (vtable[0xec])
LEVEL 4  Packet entry: FUN_00775890/00775a30 -> FUN_00775180
LEVEL 5  Byte parser: 4-mode variable-length encoding
LEVEL 6  Per-record processor FUN_00774220 (alloc 200B CommandUpdate record)
LEVEL 7  CommandUpdater_invokeLua_onUpdateWork_clipObj/complex
         -> Lua callback: actor:_onUpdateWork(struct, slot, idx0, idx1)
```

### Apply path (4 BitPacked WRITERS to actor+0x214)

```text
BitPacked_writeByte_type1     0x00d11d30
BitPacked_writeShort_type2    0x00d11e90
BitPacked_writeUint24_type3   0x00d11fd0
BitPacked_writeUint32_type4   0x00d12080
BindingStorage_writeField_lowLevel_byBindingId  0x00ce44d0
```

### 4-mode variable-length packet encoding (explains asymmetric protocol)

```text
binding-id mode  : 5 bytes/field (S->C compact; hot broadcast path)
string-keyed mode: ~30 bytes/component (C->S verbose paths)
short payload    : (tag - DAT_00fe059b) bytes
large payload    : (tag - DAT_00fe05a1) bytes
~95% bandwidth saving for compact mode
```

### 2 record types

```text
Outbound CommandUpdate:  280B (0x118) via CommandUpdater_allocAndEnqueueRecord
Inbound  CommandUpdate:  200B (0xc8)  via FUN_00768260 (inbound CTOR)
  Inner buffer 2 sizes: 160B compact / 768B extended (many-field broadcasts)
```

### Lua API SYMMETRIC round-trip

```text
Lua passes 1-based -> outbound -1 = 0-based wire
Wire 0-based -> inbound +1 = 1-based Lua callback
Script receives SAME values it sent (round-trip preservation PROVEN)
```

### C -> S subscribe

```text
Lua: queryBinding(bindingId)
Wire: opcode 0x135, 24-byte packet
```

### ECHO behavior

Inbound parser CONDITIONALLY calls outbound serializer for client
prediction reconciliation when server pushes authoritative value.

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

## 13a. Spawn Pipeline FULL END-TO-END (CLOSED 2026-05-28)

```text
SPAWN ARCHITECTURE: typed-packet replication via Group:: hierarchy.
Wire opcode 0x17c carries Group::PacketRequestBase-derived packets.

FULL FLOW (server packet -> Lua actor:_onInit):

  SERVER pushes opcode 0x17c (Zone channel, ~120 byte packet)
   ↓
  Zone_MAIN_inbound_opcode_dispatcher_50plus_handlers (0x004dc690)
   ↓ case 0x17c:
  ZoneIn_opcode_0x17c_SPAWN_extractAndForwardToFactory (0x00576250)
   ↓
  SpawnPipeline_dispatcher_check2711tag_routeToFactory (0x006cc620)
   ↓ checks 0x2711 list-object signature
  SpawnPipeline_FACTORY_dispatchByTypeTag_enqueueToRingBuffer (0x006cc070)
   ↓ TYPE TAG at packet[+0x10] selects subclass:
   │   0   -> EntryBuilder (spawn)
   │   0xe -> OnlineStatusUpdater
   │   ... -> other Group:: subclasses
   ↓ ringBuffer_enqueue_4bytes(instance+0x20, &newPacket)
   ↓
  [PER-FRAME tick fires]
   ↓
  SpawnPipeline_perFrameWrapper_dispatchesT0 (slot[6] of PerFrameTick)
   ↓
  T0  SpawnPipeline_T0_perTickPump_processQueue           0x006cdd20
  T1  SpawnPipeline_T1_ringBufferConsumer (RTTI cast)     0x006cda80
  T2  SpawnPipeline_T2_orchestrate (sends 2x 0x130 ACKs)  0x006cd8e0
  T3  SpawnPipeline_T3_dispatch2plusN_actorsList          0x006db9a0
  T4  SpawnPipeline_T4_buildAndDispatchToAllocator        0x006cbc90
  T5  SpawnPipeline_T5_allocateActor_84B + 0x133 ACK      0x006c8cf0
   ↓
  Actor_invokeLua_onInit
   ↓
  LUA: actor:_onInit() -- script callback fires; actor LIVE

WIRE PACKET 0x17c LAYOUT (~120 bytes):
  +0x00  id_a (8B)            actor primary id
  +0x08  id_b (8B)            dedup key (server tracks)
  +0x10  TYPE_TAG (4B)        0=EntryBuilder, 0xe=OnlineStatusUpdater, ...
  +0x18  field_pair_1 (8B)    self-check
  +0x20  field_pair_2 (8B)    self-check fallback
  +0x28  matched_id (8B)      comparison key
  +0x30  payload_data
  +0x40  flag (4B)
  +0x44  CLASS NAME STRING    null-terminated; used by _createActor
  +0x76  size (short)

OUTBOUND ACKs per spawn (server tracks these):
  2x opcode 0x130 (32B each): listObjectQueueAdd + Delete
     payload: (resolver_id, primary_id) = same 2 IDs server sent
  1x opcode 0x133 (56B): WorkSync init ACK
     fires from T5 after actor:_onInit() completes

SIZES:
  Actor instance:  84 bytes (0x54) via operator_new in T5
  WorkRecord:      72 bytes (0x48) in T4 if class has work fields
  Wire packet:     ~120 bytes

7 GROUP:: SUBCLASSES (typed-packet hierarchy):
  PacketRequestBase (base; vftable @ 0x00fd4120, 13 slots)
    EntryBuilderBase
      EntryBuilder         spawn (alloc 0xf8 child)
      BreakupBuilder       despawn
      OnlineStatusUpdater  status change (alloc 0x50)
    MemberInfoUpdater      member info update
    PropertyUpdater        property update
    WorkSyncUpdater        worksync state (alloc 0xa0 = 160B)

THE 0x2711 MAGIC: list-object spawn signature checked at
SpawnPipeline_dispatcher_check2711tag. Triggers notification chain
setup before factory dispatch.

SERVER-SIDE COMPLETE PROTOCOL:
  1. Send opcode 0x17c with packet
  2. Wait for 2x 0x130 ACK (list lifecycle)
  3. Wait for 1x 0x133 ACK (WorkSync init complete)
  4. Now push state updates via 0x12F/0x132/0x133
```

## 13b. Application Main Loop + Per-Frame Tick (15 SLOTS COMPLETE)

```text
Win32 message loop (outer)
   ↓
Application_mainTick_perFrame_eventLoopAndSubsystems  @ 0x004da680
   ↓ (3 startup gates: +0x4a8, +0x17444, +0x174dc)
PerFrameTick_Subsystems_widgets_zone_spawn_etc        @ 0x00578970
   ↓
[15 SUBSYSTEM SLOTS, all characterized]

PERFRAMETICK SUBSYSTEM SLOT MAP (FINAL):
  [0]   Engine state container
  [1]   Secondary state container (+0x110 and +0x114 child subsystems)
  [2]   Widget LIFECYCLE pump (state machine)
  [3]   Widget ANIMATION + state tick
  [4]   Widget LOAD MGR (message 0xde)
  [5]   SPREADSHEET CSV PRELOADER (4 CSVs: worldMasterLogCategory,
        command [with ID filters], achievement, hamletDefScore)
  [6]   SPAWN PIPELINE (perFrameWrapper -> T0)               CONFIRMED
  [7]   INBOUND WORKSYNC PUMP complex (32/tick)              NEW
  [8]   INBOUND WORKSYNC PUMP simple (32/tick)               NEW
  [9]   Widget thunk
  [10]  TIMEOUT MONITOR (900-frame / 15-sec threshold)
  [11]  COMPOUND widget tick (2 sub-dispatchers)             NEW
  [12]  DEAD SESSION CLEANUP TICK (GC zombie sessions)       NEW
  [1+0x110]  PLAYER MODE STATE TICKER (3 bindings + ref)     NEW
  [1+0x114]  WIDGET CONTAINER CHILD NOTIFIER                 NEW
  [0xd] Pluggable polymorphic (vtable[+8])

THROUGHPUT CAPACITY:
  - 2 WorkSync pumps x 32/tick = 64 state updates/frame
  - At 60Hz: ~3840 state updates/sec peak
  - Spawn pipeline: 2 actors/frame = 120 spawns/sec
  - 50-actor zone ramp: ~417ms (fade-in at zone enter)

EXPLAINS THE 2-PER-FRAME SPAWN RATE:
  - T1 reads 2 entries per call
  - perFrameWrapper calls T1 once per frame
  - At 60 Hz: 120 spawn/sec max -> 50-actor zone = ~417ms ramp
  - At 30 Hz: 60 spawn/sec max -> 833ms ramp
  - This IS the "fade-in" at zone enter in 1.x

INPUT EVENT ENCODING (32-bit packed at this+0x17828):
  Bits 0xe0000000  Event tag (0xc0 = routed dispatch)
  Bits 0x0e000000  Subsystem ID (4 bits; 3 known: 0/1/2)
  Bits 0x00ffffff  Payload (24 bits)

  Tag 0xc0 routes to DAT_01336b60 + (subsys_id * 24) handler table.
```

## 13c. RTTI Types Confirmed (17 base + 7 Group:: subclasses = 24 total)

```text
NAMESPACE: Component::Lua::GameEngine::
  - LuaControl::RTTI_Type_Descriptor                    (universal source)
  - ResumeCheckerInterface::vftable                     (async base)
  - FunctionEndCallbackInterface::vftable               (I/O base)
  - LpbLoader::ResumeChecker::vftable                   (LPB loader)

NAMESPACE: Application::Lua::Script::Client::Control::
  - ActorBase                                           (universal supertype)
  - CharaBase
  - PlayerBase
  - MyPlayer
  - NpcBase
  - AreaBase
  - DirectorBase
  - DesktopWidget
  - WorldMaster

NAMESPACE: Component::Network::IpcChannel::             (NEW; networking)
  - ConnectionManagerTmpl<ZoneProtoUp, ZoneProtoDown>

NAMESPACE: Application::Network::ZoneProtoChannel::    (NEW; networking)
  - ServiceConsumerConnectionManager

NAMESPACE: Application::Lua::Script::Client::Group::   (typed packets)
  - PacketRequestBase           (base; vftable @ 0x00fd4120)
  - EntryBuilderBase            (subclass for entry ops)
  - EntryBuilder                (concrete: actor spawn)
  - BreakupBuilder              (concrete: actor despawn)
  - OnlineStatusUpdater         (concrete: online status)
  - MemberInfoUpdater           (concrete: member info)
  - PropertyUpdater             (concrete: property change)
  - WorkSyncUpdater             (concrete: worksync state, 160B child)

Used by:
  - _isInstanceOf (6 Control:: types in hardcoded fast-path; ActorBase
    short-circuited to TRUE because universal)
  - SpawnPipeline T1 (Group:: packet hierarchy RTTI cast to EntryBuilderBase)
  - SpawnPipeline_FACTORY (TYPE TAG -> Group:: subclass dispatch)
  - ZoneClient_pumpConnectionState (Network types)
  - Various other ___RTDynamicCast call sites
```

## 13d. THE ARCHITECTURAL PRINCIPLE (client-side content) -- confirmed x4

```text
"CONTENT IS CLIENT-SIDE; SERVER ORCHESTRATES STATE + TRIGGERS + AUTH"

CLIENT-LOCAL (client already has it; server never sends):
  - Zone geometry/data (CSVs loaded by areabaseclass _onInit)
  - NPC dialogue/animation/choices (npcbaseclass_event say/ask)
  - Combat formulas + stat tables (charabaseclass getMagicAttack etc.)
  - Content orchestration logic (Director event scripts)

SERVER AUTHORITY (minimal):
  - TRIGGERS: spawn actors/directors (0x17c) by class name
  - STATE: WorkSync replication (battleSave/eventSave/director._sync)
  - AUTHORIZATION: notices (noticeEvent -> accept / _onNoticeRejected),
    command validation (semantic), reward grants
  - Never sends content (text/geometry/logic)

WHY: explains the compact wire protocol (ids/flags not content),
the feasibility of a server (orchestrator not engine), and the
extensive client Lua (it IS the game logic).

Confirmed across 4 independent layers: zone / NPC / combat / director.
```

## 13e. Work Schemas (server-replicable state)

```text
BATTLE (charabaseclass initBattleSync):
  battleSave (persistent): potencial(float), physicalLevel(i16),
    physicalExp(i32), skillLevel/Cap/Point[52], negotiationFlag[2]
  battleTemp (transient): castGauge_speed[2], timingCommandFlag[4],
    generalParameter[35] (28 synced indices 4-19,24-35 + 7 local 1-3,20-23)
  Sync groups: battleStateForSelf (self), timingCommand, battleParameter

EVENT (charabaseclass initEventSyncWork):
  eventSave (persistent): bazaar (player shop), bazaarTax(i8), repairType(i8)
  eventTemp (transient): linkshellIcon[4], bazaarRetail/Repair/Materia(bool)

AREA (areabaseclass):
  areaWork._temp: actorNumber(i16), isInstanceRaid(bool),
    isEntranceDesion(bool), _assignForChild[64]
  8 zone-type prefixes: Fld/Dgn/Twn/Btl/Tes/Evt/Shp/Ofc

DIRECTOR (DirectorBaseClass):
  work._temp (local) + work._sync (replicated) + work._tag (sync group)
  updateSyncWork -> _updateWork (rate-limited by canRequestInformation)

COMMAND FLOW (playerbaseclass):
  command -> canCommand -> _onCommandRequest -> _executeCommand -> 0x12d
  Gating: commandBurstBlocker (bypass cmd 12017/12009), 50-char limit
  Timing combos: timingCommandFlag set -> player 27xxx -> server timing
    packet -> _onReceiveTimingPacket auto-executes follow-up (30004/22004)
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

### EXE Architecture (2026-05-28 OUTBOUND batch -- newest)

- `finding_command_checksum_is_standard_crc32.md` -- 0x12d CRC32 (Sqex::Crypt::Crc32); transport integrity not anti-cheat; WIRE PROTOCOL 100% MAPPED
- `finding_executeCommand_outbound_path_CLOSED_0x12d_checksummed.md` -- player command path: _executeCommand vtable[0xa8] -> 0x12d checksummed
- `finding_outbound_rpc_0x12e_format_plus_resumechecker_count_correction.md` -- 0x12e RPC format (104B) + ResumeChecker ~24 correction

### EXE Architecture (2026-05-28 SESSION FINAL -- 24 commits)

- `finding_perFrameTick_subsystems_COMPLETE_15_slots_characterized.md` -- ALL 15 PerFrameTick slots characterized + 5 wire variants + 4 new bindings
- `finding_zone_inbound_opcodes_COVERAGE_COMPLETE.md` -- 95% non-fallback opcode coverage in 0x143-0x1a8
- `finding_misc_game_opcodes_0x186_0x18a_0x191_0x196_0x198_characterized.md` -- 5 misc opcodes
- `finding_linkshell_wire_opcodes_0x188_0x189_CLOSED.md` -- LINKSHELL wire-side + PropertyUpdater mystery solved
- `finding_linkshell_subsystem_inventory.md` -- Linkshell Lua inventory + 8th Group:: subclass discovery
- `finding_per_actor_messages_COMPLETE_15_opcodes_3x5_matrix.md` -- 3x5 matrix (15 opcodes)
- `finding_per_actor_message_constructors_semantized.md` -- per-actor msg construction patterns
- `finding_opcode_0x18d_session_batch_multi_record_state_push.md` -- 0x18d batch + 0x193 internals
- `finding_opcode_0x143_DESPAWN_packet_breakupBuilder_path.md` -- DESPAWN
- `finding_group_typed_packets_remaining_opcodes_0x187_0x18b.md` -- 0x187 + 0x18b
- `finding_zone_inbound_game_opcodes_0x143_0x1a8_bridge_pattern.md` -- 50+ game opcodes
- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md` -- SPAWN wire-side
- `finding_zoneclient_inbound_dispatch_layer_partial_threshold_0x1c11.md` -- 0x1c11 threshold
- `finding_application_mainTick_and_per_frame_subsystem_dispatch.md` -- CAPSTONE main loop
- `finding_spawn_pipeline_typed_packet_ring_buffer_6_stage_architecture.md` -- SPAWN T0-T5
- `finding_isInstanceOf_thunk_dual_dispatch_rtti_plus_luachain.md` -- _isInstanceOf dual dispatch
- `finding_canCreateActorByName_thunk_creatability_check.md` -- class system thunk family complete

### EXE Architecture (2026-05-27 session findings)

- `finding_smallmodules_inventory_closed_17_masters.md` -- the 17-master inventory
- `finding_createActor_thunk_async_actor_factory.md` -- async actor creation
- `finding_defineClass_thunk_class_registration_loop.md` -- class registry
- `finding_wait_thunk_universal_resume_checker_confirmed.md` -- async pattern
- `finding_updateWork_thunk_worksync_state_replication.md` -- WorkSync end-to-end
- `finding_worksync_inbound_writers_pinned.md` -- 4 BitPacked writers
- `finding_spreadsheet_thunks_exe_data_bridge.md` -- EXE-Data bridge
- `finding_inbound_dispatch_table_found.md` -- 224-slot inbound table
- `finding_resumechecker_11th_subclass_LpbLoader_plus_vtable_methodology.md` -- 11th ResumeChecker + RTTI methodology

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

### Lua Architecture (2026-05-28 CONTENT batch -- newest)

- `finding_directorbaseclass_content_orchestration_model.md` -- Director content engine: _sync state + notice authorization (client-side-content x4)
- `finding_npc_event_talk_turn_flow_client_side.md` -- NPC talk-turn flow; dialogue is client-side; channel 38
- `finding_areabaseclass_zone_bootstrap_sequence.md` -- zone bootstrap; zone CSVs client-local; 8 zone-type prefixes
- `finding_playerbaseclass_command_flow_and_player_module.md` -- command flow (-> 0x12d) + timing-combo inbound + 18 _on* callbacks
- `finding_charabaseclass_battle_schema_and_timing_commands.md` -- battle/event WorkSync schemas + timing-command combos

### Lua Architecture (prior session)

- `finding_desktopwidget_connector_main_orchestrator_architecture.md` -- DesktopWidget connector (26,564 lines, 255 methods, 13 subsystems)

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

Band ranges (full catalog has 29+ in these bands; 7Axxx + C00xxx NEW):
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
  7Axxx  PLAYER MODE state (NEW: 0x7a121/22/23 -- combat/event/cutscene mode)
  C00xxx Mode/state root refs (NEW: 0xc0000024 = mode root)

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

CLASS SYSTEM THUNK FAMILY (4 complete -- covers entire Lua class API):
  _defineClass            (0x006e4d20)  Registers class
  _createActor            (0x006e1700)  Instantiates via vtable[0x6c]
  _isInstanceOf           (0x006ff210)  DUAL DISPATCH (7 RTTI fast-path
                                         + Lua chain walk fallback)
  _canCreateActorByName   (0x006ff1a0)  Creatability pre-check
                                         (3 non-creatable category tags)

_isInstanceOf HOT-PATH (7 hardcoded C++ class names):
  ActorBaseClass    -> TRUE unconditionally (universal supertype)
  CharaBaseClass    -> ___RTDynamicCast
  PlayerBaseClass   -> ___RTDynamicCast
  NpcBaseClass      -> ___RTDynamicCast
  AreaBaseClass     -> ___RTDynamicCast
  DirectorBaseClass -> ___RTDynamicCast
  DesktopWidget     -> ___RTDynamicCast

  ALL ___RTDynamicCast calls use LuaControl as SOURCE -- proves the
  invariant that every Lua-passable instance derives from LuaControl.

DYNAMIC FALLBACK (any other class name):
  - Resolve name -> classId via LuaClass_resolveOrRegisterClassByName
  - Walk instance+0xc chain comparing +0x54 against classId
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

## 19. Coverage Summary (As of 2026-05-28 SESSION FINAL)

```text
FINDINGS:                196+ total
  EXE-side:               83+
  Lua-side:               93
  Correlation:            13

CONTENT MODEL: client-side content + server orchestration (x4 confirmed)
  Work schemas: battle/event/player/area/director (server-replicable)
  Flows: command->0x12d, spawn, zone bootstrap, NPC talk-turn, director
WIRE PROTOCOL: 100% MAPPED both directions (server-ready)
  OUTBOUND: 0x12d command (CRC32), 0x12e RPC, 0x12f-0x135 state, chat
  INBOUND: ~95% non-fallback opcodes + all semantic categories
  ALGORITHMS recovered: CRC32, 4-mode WorkSync encoding, binding-id==field-id

EXE NATIVE SURFACE:     ~344 _cpp bindings + ~62 pure-Lua wrappers
  Located in masters:    409 registrar slots (100%)
  ~30 engine-internals discovered (NOT in _u.lua)
  Coverage:              ~100% of native binding surface

THUNKS DISASSEMBLED:      17+ (master primitives + 8 _wait* + class system)
  - 4 architectural (createActor, defineClass, wait, getData)
  - 1 async I/O (loadKeyTemporarily)
  - 2 class system NEW (_isInstanceOf dual dispatch, _canCreateActorByName)

WIRE OPCODES (massively expanded):
  Outbound (Zone): 9 named (0x12d-0x135) + chat opcodes
  Inbound MAIN game protocol: 50+ opcodes (0x143-0x1a8 range)
    + KEY: opcode 0x17c = SPAWN PACKET (Group::PacketRequestBase)
    + KEY: opcode 0x143 = DESPAWN PACKET (BreakupBuilder)
    + KEY: opcode 0x187 = WORKSYNC BATCH (WorkSyncUpdater)
    + KEY: opcode 0x18b = MEMBER INFO UPDATE (MemberInfoUpdater)
    + KEY: opcode 0x18d = MULTI-RECORD BATCH (255 x 40B records)
    + KEY: opcode 0x193 = SYSTEM ERROR/STATUS (22 codes)
    + 15 opcodes 0x148-0x156 = per-actor message system
  Inbound session opcodes: ~14 (0x02-0x11)
  Inbound sub-opcode table: 60 entries @ 0x00fdfb80
  Total inbound: ~120+ opcodes pinned with ~6 SEMANTICALLY NAMED
  - 4 _updateWork (CharaBase, Director, Item, GroupBase)
  - 2 chat (parseTextCommand, appendMessagePool)
  - 6 _wait* siblings (Turning, CharaSchedFin x2, Tutorial x3)

RESUMECHECKER SUBCLASSES: ~24 (RTTI-enumerated; was 11 confirmed)
  11 with confirmed sizes; +13 more from RTTI strings
  RPC-backed (3) pair with outbound 0x12e RPC request/response

RTTI TYPES CONFIRMED: 25 total (17 base + 8 Group:: subclasses)
  4 in Component::Lua::GameEngine::
  9 in Application::Lua::Script::Client::Control::
  2 in Component::Network::IpcChannel:: / Application::Network::*
  9 in Application::Lua::Script::Client::Group::
    (PacketRequestBase + EntryBuilderBase + EntryBuilder +
     BreakupBuilder + OnlineStatusUpdater + MemberInfoUpdater +
     PropertyUpdater + WorkSyncUpdater + EntryLinkShellBuilder)
  
  ALL 8 GROUP:: SUBCLASSES NOW WIRE-MAPPED:
    EntryBuilder -> 0x17c TAG0       BreakupBuilder -> 0x143
    OnlineStatusUpdater -> 0x17c TAG0xe   MemberInfoUpdater -> 0x18b
    WorkSyncUpdater -> 0x187          EntryLinkShellBuilder -> 0x188/0x189
    PropertyUpdater -> vtable[12] of EntryLinkShellBuilder (INTERNAL)

WIRE OPCODES PINNED:
  Outbound: 7 named (0x12d-0x135) + chat opcodes
  Inbound:  ~3 chat handlers + ~218 dispatch table slots
  WorkSync FULL bidirectional path (7-level inbound chain)

DATA CATALOG:            803 CSV tables
  Lua-accessible critical: 132 of 132 (100%) -- 32 are engine-internal
  Useful mapped:         ~371 of 625 (estimate; via _loadTextData)
  Total unique mapped:   ~503 of 803 (62.6%)

3-AXIS BRIDGE STATUS:
  Lua scripts ↔ EXE thunks         ✓ MAPPED (17 masters + 17 thunks)
  EXE async I/O ↔ CSV data         ✓ MAPPED (SpreadSheet pipeline)
  Lua scripts ↔ Wire opcodes       ✓ MAPPED (correlation findings)
  Lua scripts ↔ CSV data           ✓ MAPPED (132/132 Lua-accessible critical)
  EXE binding storage ↔ Wire       ✓ MAPPED (binding-id == field-id)
  WorkSync end-to-end              ✓ MAPPED ~95% (entry table slot TBD)
  Chat loop end-to-end             ✓ MAPPED 100% (parse + dispatch + 3 inbound)
  Class registration loop          ✓ MAPPED 100% (4-thunk family complete)
  Actor lifecycle T0-T3            ✓ MAPPED 100%
  ResumeChecker hierarchy          ✓ MAPPED 11 confirmed (was 10)
  SPAWN PIPELINE end-to-end        ✓ MAPPED 100% PROD->CONS->LUA  CLOSED
    - producer side: opcode 0x17c -> dispatcher -> factory
    - consumer side: 6-stage T0-T5 + ACKs (0x130 x2 + 0x133)
  Main loop architecture           ✓ MAPPED 100% (2-level tick)
  DesktopWidget UI orchestrator    ✓ MAPPED (13 subsystems, 255 m)
  Zone game-protocol opcodes       ✓ MAPPED 50+ opcodes (0x143-0x1a8) NEW
  Network connection layer         ⚙ PARTIAL (RTTI types pinned; thread TBD)
```

## 20. What's Left

```text
SMALL REMAINING GAPS (~3%):
  - 12th ResumeChecker (HamletDefenseScoreResumeChecker) -- target
    at 0x006dcb00 is DATA label; Ghidra didn't auto-detect function
  - Exact Zone inbound table slot that triggers FUN_006e17e0
    (currently known to be multiplexed via _onReceiveDataPacket entry 38)
  - Symbolic names for 3 byte-tag constants (DAT_00fe059b/05a0/05a1)
  - Chat channel IDs (32/33/38/40) -> specific outbound wire opcodes
  - vtable[0x6c] walk for 5-10 sample classes (200+ mechanical naming)
  - SPAWN wire-side: wire opcode that produces PacketRequestBase
    instances (likely 0x12d tagged container; needs network I/O thread trace)
  - 10 unmapped subsystems in PerFrameTick (slots [7-9], [11-12], 1+0x110/+0x114, 0xd)

MEDIUM-VALUE GAPS:
  - LinkshellCommand family (system commands)
  - charabaseclass_event.lua (444 lines)
  - charabaseclass_battle.lua (2027 lines, partial coverage)
  - desktopwidget_itemdetail.lua (10,687 lines)
  - equipwidget.lua (10,072 lines)
  - retaineritemlistwidget.lua (9,654 lines)
  - ~125 of 625 useful CSVs (gear class variants)

CONFIRMED ENGINE-INTERNAL (no Lua surface; not a gap):
  - 32 critical CSVs loaded by C++ (regionParam, 2Dmap_*, etc.)
  - These are CLIENT-LOCAL, not server-pushed

RESOLVED IN 2026-05-28 SESSION:
  ✓ _isInstanceOf thunk (RTTI walk implementation) -- DONE; DUAL DISPATCH
  ✓ _canCreateActorByName -- DONE; 4-thunk class family complete
  ✓ DesktopWidget main 687 KB Lua file -- DONE; 13 subsystems, 255 methods
  ✓ Spawn pipeline 6-stage architecture (T0-T5) -- DONE; +2 RTTI types
  ✓ Application main tick + per-frame dispatch -- DONE; CAPSTONE
  ✓ 11th ResumeChecker (LpbLoader::ResumeChecker) -- DONE
  ✓ Subsystem[10] (timeout monitor 900-frame threshold) -- DONE
  ✓ SPAWN WIRE OPCODE PINNED: 0x17c -- DONE; via Ghidra RTTI walk
  ✓ 7 Group:: subclasses (EntryBuilder/BreakupBuilder/Online/Member/
    Property/WorkSyncUpdater) -- DONE
  ✓ Zone MAIN inbound opcode dispatcher 50+ game opcodes -- DONE
  ✓ Full spawn protocol producer->consumer->Lua -- DONE; CAPSTONE
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
- 15 RTTI types confirmed (LuaControl is universal SOURCE for all dynamic casts)
- 2 NEW namespaces beyond Control:: -- Group::PacketRequestBase /
  EntryBuilderBase (typed-packet hierarchy for spawn)
- Actor spawn = 84 bytes (operator_new in T5); WorkRecord = 72 bytes (T4)
- Spawn rate = 2/frame -> at 60Hz = 120 spawn/sec -> 50-actor zone = ~417ms ramp
- Application main loop is FUN_004da680 (Win32 message loop entry)
- PerFrameTick (FUN_00578970) dispatches 15+ subsystem ticks per frame
- Spawn pipeline occupies subsystem slot[6] of PerFrameTick
- Subsystem slot[10] = timeout monitor (900-frame / 15-sec threshold)
- 32-bit packed input events at engine+0x17828 (3-bit tag + 4-bit subsys + 24-bit payload)
- WIRE OPCODE 0x17c = SPAWN PACKET (Group::PacketRequestBase typed packets)
- Zone MAIN inbound dispatcher at FUN_004dc690 (50+ game opcodes 0x143-0x1a8)
- 7 Group:: subclasses for typed-packet replication (spawn/despawn/status/member/property/worksync)
- 0x2711 = list-object spawn signature (PacketRequestBase discriminator)
- PacketRequestBase vftable @ 0x00fd4120 (13 slots; subclasses override [5]/[11] = inbound handlers)
- Spawn ACK pattern: 2x outbound 0x130 (queueAdd + delete) + 1x outbound 0x133 (init complete)
- Wire packet 0x17c is ~120 bytes including class name string at +0x44
- 0x1c11 sequence threshold (FUN_004e5ff0) routes between in-order tree vs discard
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
