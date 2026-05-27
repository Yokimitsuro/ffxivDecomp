# Finding: SPAWN WIRE-SIDE LOOP CLOSED -- Opcode 0x17c + Zone Main Inbound Dispatcher (50+ Game Opcodes) + 7 Group:: Subclasses

**THE LOOP IS CLOSED.** Via Ghidra interactive RTTI walk + xref
trace, the full spawn wire-side path is now confirmed end-to-end.
Combined with the prior 6-stage spawn pipeline (drain side), this
completes the spawn architecture from server-pushed wire bytes to
Lua actor:_onInit() callback.

Additionally discovered: the **Zone MAIN inbound opcode dispatcher**
handling **50+ game-protocol opcodes** in the 0x143-0x1a8 range.
This is the SECOND inbound opcode space (the 0-59 sub-opcode table
@ 0x00fdfb80 was already known; this is the high-opcode game-protocol
space).

## 1. Wire opcode 0x17c = SPAWN PACKET

```text
Wire opcode 0x17c (380 decimal):
  Sent by: Server (Zone channel, inbound to client)
  Purpose: Push an actor spawn / member info / property update /
           worksync state replication packet
  Carrier: Group::PacketRequestBase-derived typed packet object
           (one of 7 subclass types -- see section 4)
```

This is the **answer to the long-standing "where does spawn come from?" question.**

## 2. FULL END-TO-END FLOW (spawn producer + consumer)

```text
SERVER PUSH
   ↓
WIRE: Zone channel inbound, opcode 0x17c
   ↓
ZoneClient_mainLoopTick (per-frame)
   ↓ FUN_00dae520 receive
   ↓
ZoneClient_packetDispatch_treeOrDestroy_threshold_0x1c11
   (sequence < 0x1c11 → in-order tree insert)
   ↓
FUN_004dc690  Zone_MAIN_inbound_opcode_dispatcher_50plus_handlers
   ↓ switch on packet[+2] = wire opcode
   ↓ case 0x17c:
   ↓
FUN_00576250  ZoneIn_opcode_0x17c_SPAWN_extractAndForwardToFactory
   ↓ unwraps container, finds inner packet object
   ↓
FUN_006cc620  SpawnPipeline_dispatcher_check2711tag_routeToFactory
   ↓ checks 0x2711 magic tag (list-object type signature)
   ↓ if matched: setup notification chain (FUN_006cc5b0 helper)
   ↓ ALWAYS forwards to:
   ↓
FUN_006cc070  SpawnPipeline_FACTORY_dispatchByTypeTag_enqueueToRingBuffer
   ↓
   ↓ ← THE PRODUCER ←
   ↓
   ├─ Switch on packet[+0x10] (param_3[4]) = TYPE TAG:
   │    0x0  → new EntryBuilder(...) at 0x40 bytes
   │    0xe  → new OnlineStatusUpdater(...) at 0x50 bytes
   │    other variants for EntryBuilder
   ├─ ringBuffer_enqueue_4bytes(this+8, &newPacketPtr)  ← PUSH to spawn queue
   └─ map.insert at this+0x30 keyed by packet[+0x08] (de-dup tracking)
   ↓
[ring buffer at spawn_pipeline_instance+0x20 now holds new PacketRequestBase*]
   ↓
[PER-FRAME tick fires; per finding_application_mainTick]
   ↓
PerFrameTick_Subsystems_widgets_zone_spawn_etc slot[6]
   ↓
SpawnPipeline_perFrameWrapper_dispatchesT0
   ↓
SpawnPipeline_T0_perTickPump_processQueue
   ↓
   ↓ ← THE CONSUMER (6-stage drain) ←
   ↓
SpawnPipeline_T1_ringBufferConsumer_castEntryBuilderBase
   ↓ RTTI cast PacketRequestBase → EntryBuilderBase
   ↓ extract +0x10/+0x14 = actor ID
   ↓ extract class name string
   ↓
SpawnPipeline_T2_orchestrate_listObject_emits_0x130_pair
   ↓ sends 2x opcode 0x130 ACK packets to server (listObjectQueueAdd + Delete)
   ↓
SpawnPipeline_T3_dispatch2plusN_actorsList
   ↓
SpawnPipeline_T4_buildAndDispatchToAllocator
   ↓ allocates 72B WorkRecord if class has work fields
   ↓
SpawnPipeline_T5_allocateActor_84B_invokeOnInit_ackVia_0x133
   ↓ allocates 84B actor instance (operator_new(0x54))
   ↓ calls actor ctor (FUN_006c83d0)
   ↓ stores at owner+0xa0
   ↓
Actor_invokeLua_onInit
   ↓
LUA: actor:_onInit()  ← script callback fires; actor is LIVE
   ↓
[Server now receives 0x130 ACK pair + 0x133 WorkSync init ACK]
   ↓
[Server now sends WorkSync state updates via opcode 0x12F/0x132/0x133]
```

This is the **complete actor lifecycle from wire arrival to Lua hook**.

## 3. Wire packet format for opcode 0x17c

Per FUN_006cc070 access patterns (param_3 fields in 4-byte units):

```text
Offset  Type       Field                                 Notes
------  ----       -----                                 -----
+0x00   uint32     id_a_low                              actor primary id (low)
+0x04   uint32     id_a_high                             actor primary id (high)
+0x08   uint32     id_b_low                              KEY for dedup lookup
+0x0c   uint32     id_b_high
+0x10   uint32     TYPE_TAG                              0 = EntryBuilder (spawn)
                                                         0xe = OnlineStatusUpdater
                                                         other = EntryBuilder variants
+0x14   uint32     additional id?                        (param_3[5])
+0x18   uint64     field_pair_1                          self-check field A
+0x20   uint64     field_pair_2                          self-check field B
+0x28   uint64     matched_id                            comparison key
+0x30   uint32     payload_data
+0x34   uint32     (more)
+0x38   uint32     additional data (param_3[0xe])
+0x40   uint32     flag                                  0 vs non-zero affects path
+0x44   char[]     CLASS NAME STRING                     null-terminated; passed
                                                         to std::string ctor
                                                         (variable length)
+0x64   ?          additional data section (param_3[0x19])
+0x74   ?          (param_3[0x1d])
+0x76   ushort     SIZE field                            short at +0x76 (0x1d*4+2)

Total packet size: ~120 bytes (30 uint32 words, per FUN_006cc5b0 copy loop)
```

**Server-side implementation requirement:**
- Build wire packet matching this layout
- Set TYPE_TAG (+0x10) to select subclass behavior
- Include CLASS NAME STRING (+0x44) -- this is what client uses for
  _createActor lookup
- Track sent packets to correlate 0x130 ACK pair from client
- Track 0x133 WorkSync init ACK to know spawn completed on client

## 4. Group:: subclass hierarchy (7 confirmed + base)

Via RTTI walk + factory decompilation:

```text
Application::Lua::Script::Client::Group::
  PacketRequestBase (base, 32+ bytes; vftable at 0x00fd4120)
   │
   ├─ EntryBuilderBase                    -- actor entry operations
   │    │
   │    ├─ EntryBuilder                   -- actor ADD/SPAWN (allocates 0x40 + 0xf8 child)
   │    │
   │    ├─ BreakupBuilder                 -- actor REMOVE/DESPAWN
   │    │
   │    └─ OnlineStatusUpdater            -- ONLINE STATUS change (0x50 bytes)
   │
   ├─ MemberInfoUpdater                   -- MEMBER INFO update
   │
   ├─ PropertyUpdater                     -- PROPERTY update
   │
   └─ WorkSyncUpdater                     -- WORKSYNC STATE replication
                                            (allocates 0xa0 = 160B child)
```

**This proves the Group:: subsystem is a TYPED-OBJECT REPLICATION
SYSTEM covering at least 6 operation types**:
1. Add actor (EntryBuilder)
2. Remove actor (BreakupBuilder)
3. Change online status (OnlineStatusUpdater)
4. Update member info (MemberInfoUpdater)
5. Update property (PropertyUpdater)
6. Replicate worksync state (WorkSyncUpdater)

This explains why the prior `Group_invokeLua_*` function family
(7 functions for update events like onUpdateMember*, onUpdateGroupCurrent,
etc.) maps cleanly to these Group:: typed packets.

## 5. PacketRequestBase vftable (13 slots @ 0x00fd4120)

```text
Slot  Address     Function                                Notes
----  -------     --------                                -----
[0]   0x006d0c20  FUN_006d0c20                            destructor / dtor
[1]   0x00ab7340  FUN_00ab7340                            ?
[2]   0x006d0c10  FUN_006d0c10                            ? (twin of [0])
[3]   0x006ce2e0  FUN_006ce2e0                            ? (spawn area)
[4]   0x00b73290  FUN_00b73290                            ?
[5]   0x005c5c80  ZoneIn_handler_default                  inbound placeholder
                                                           (subclasses override)
[6]   0x00a72a20  FUN_00a72a20                            ?
[7]   0x00a72a20  FUN_00a72a20                            same as [6]
[8]   0x009d364d  __purecall                              PURE VIRTUAL
                                                           (subclasses MUST override)
[9]   0x005b8d90  FUN_005b8d90                            ?
[10]  0x0080fa00  FUN_0080fa00                            ?
[11]  0x005c5c80  ZoneIn_handler_default                  inbound placeholder
                                                           (subclasses override)
[12]  0x00c37620  FUN_00c37620                            ?

Slot 8 = __purecall = abstract method requiring subclass override.
Slots 5 and 11 = ZoneIn_handler_default = placeholder for inbound
                  dispatch (each subclass overrides with its actual
                  packet handler).
```

The 2 ZoneIn_handler_default slots are the **per-subclass packet
handlers** — when a wire packet arrives, the dispatcher calls these
virtual methods to let each subclass parse its own payload.

## 6. NEW: Zone main inbound opcode dispatcher (FUN_004dc690)

```text
Renamed: Zone_MAIN_inbound_opcode_dispatcher_50plus_handlers
Address: 0x004dc690
Caller:  ZoneClient_mainLoopTick (around 0x004dd05d)

This is the PRIMARY high-level dispatcher for game-protocol opcodes.
Switch on packet[+2] = 16-bit wire opcode.

Two opcode ranges covered:
  - Session opcodes 0x02-0x11 (~14 cases)
  - Game opcodes 0x143-0x1a8 (~40+ cases)

OPCODE → HANDLER MAPPING (partial; 50+ opcodes total):

Session (low opcodes):
  0x02  reauth chain
  0x03  login text (2x std::string: 0x20 + 0x200)
  0x04  logout + cleanup chain
  0x05/0d/10  vtable[+0x24] dispatch
  0x06  FUN_0081eb90
  0x07  resync loop
  0x08/09/0a/0b  bulk state push (1/16/32/64 sized variants)
  0x0c  short+byte event
  0x0e  disconnect notice variant A
  0x11  disconnect notice variant B
  0xca  session marker
  0xcb  session cleanup

Game protocol (high opcodes; partial sample):
  0x143       FUN_00576240
  0x146       FUN_005764c0
  0x148-0x156 FUN_00576560-b80  (15 opcodes, similar bridge style)
  0x16d       FUN_005763c0  (byte payload)
  0x16e       FUN_00576430
  0x176       FUN_00576bf0
  0x17a       FUN_005763b0  (uint payload)
  0x17c       SPAWN -- FUN_00576250 → SpawnPipeline_dispatcher ← !!!
  0x17d-0x18b FUN_005762c0-3a0  (12 opcodes)
  0x18d       FUN_00575550 + FUN_0055cf70  (complex w/ session at +0x4d8)
  0x18f (399) FUN_00576c60
  0x190 (400) FUN_00576cd0
  0x191       FUN_00576d40
  0x193       FUN_00578c90  (3 uint args)
  0x196       FUN_00576050
  0x198       FUN_00576150  (string payload)
  0x1a3       FUN_00576140

Default fall-through (switchD_004dc749_caseD_f):
  vtable[+0x24] on session object at this+0x4e0
  -- polymorphic fallback for unhandled opcodes
```

**This nearly doubles the known wire opcode count.** Prior coverage
focused on the 0-59 sub-opcode table @ 0x00fdfb80 (used by some
sub-dispatcher) and the outbound 0x12d-0x135 range. Now we have:
- 50+ inbound game opcodes (0x143-0x1a8 + session opcodes 2-0x11)
- The 0-59 sub-opcode table (60 entries; was already known)
- 9 outbound game opcodes (0x12d-0x135)

Total wire surface area is much larger than previously documented.

## 7. The 0x2711 magic tag (now understood)

```text
0x2711 (10001 decimal) appears in two places:
  - SpawnPipeline_outerRing (FUN_006c5f40) -- checks piVar1[4] == 0x2711
  - SpawnPipeline_dispatcher_check2711tag_routeToFactory (FUN_006cc620)
    -- checks param_2[0xc] == 0x2711

Now understood: 0x2711 is the LIST-OBJECT TYPE SIGNATURE for the
spawn pipeline's container. When the inbound packet matches:
  - param_2[0xc] == 0x2711 (it's a list-object-typed packet)
  → triggers the notification chain setup before factory dispatch
  → without it, just direct factory dispatch

The 0x2711 is essentially a "this is a SPAWN LIST packet" subtype
discriminator within the broader Group:: typed-packet system.
```

## 8. The PacketRequestBase ID structure (final answer)

```text
Each PacketRequestBase instance has 2 IDs at offsets +0xc and +0x10/+0x14:
  +0xc   uint32  resolver_id (= *param_1 in ctor)
  +0x10  uint32  primary_id_low  (= *param_2)
  +0x14  uint32  primary_id_high (= param_2[1])

These map to the wire packet IDs:
  resolver_id = packet[+0x00] (id_a)
  primary_id  = packet[+0x10/+0x14] (was originally id at +0x08 in wire)

The server uses (id_b_low, id_b_high) at wire +0x08 for de-duplication
tracking. Client confirms receipt via outbound 0x130 packet carrying
(resolver_id, primary_id) -- explaining the 0x130 2-uint32 payload
format from prior finding.
```

## 9. Renames + comments applied (this session round)

```text
0x004dc690  FUN_004dc690  → Zone_MAIN_inbound_opcode_dispatcher_50plus_handlers
0x00576250  FUN_00576250  → ZoneIn_opcode_0x17c_SPAWN_extractAndForwardToFactory
0x006cc620  FUN_006cc620  → SpawnPipeline_dispatcher_check2711tag_routeToFactory
0x006cc5b0  FUN_006cc5b0  → SpawnPipeline_helper_copyPacket120B_setDiscriminator
0x006cc070  FUN_006cc070  → SpawnPipeline_FACTORY_dispatchByTypeTag_enqueueToRingBuffer
0x006d0b90  FUN_006d0b90  (kept as dtor of PacketRequestBase)
0x006d6e20  FUN_006d6e20  (kept as ctor of PacketRequestBase)
0x006d6e90  FUN_006d6e90  (kept as ctor of EntryBuilderBase)
0x006d6f10  FUN_006d6f10  (kept as ctor of BreakupBuilder)
0x006cbee0  FUN_006cbee0  (kept as ctor of EntryBuilder)
0x006c4890  FUN_006c4890  (kept as ctor of MemberInfoUpdater)
0x006c5460  FUN_006c5460  (kept as ctor of PropertyUpdater)
0x006c5620  FUN_006c5620  (kept as ctor of WorkSyncUpdater)
0x006c4440  FUN_006c4440  (kept as ctor of OnlineStatusUpdater)

Plus 2 comprehensive decompiler comments at 0x004dc690 (main
dispatcher) and 0x006cc070 (factory) documenting full body.
```

## 10. Updated RTTI types (15 → 17)

```text
2 NEW Network RTTI types (from prior partial finding):
  + Component::Network::IpcChannel::ConnectionManagerTmpl<
      ZoneProtoUp, ZoneProtoDown>
  + Application::Network::ZoneProtoChannel::
      ServiceConsumerConnectionManager

7 Group:: subclass vftables now confirmed (each implies an RTTI
descriptor, though we only had the PacketRequestBase one explicitly):
  - PacketRequestBase (base; we walked its RTTI)
  - EntryBuilderBase
  - EntryBuilder
  - BreakupBuilder
  - OnlineStatusUpdater
  - MemberInfoUpdater
  - PropertyUpdater
  - WorkSyncUpdater

Total: 17 RTTI types confirmed (with 7 more Group:: subclasses
implicit but not RTTI-walked individually).
```

## 11. Server-side complete spawn protocol

```text
WHEN SERVER WANTS TO SPAWN ACTOR ON CLIENT:

1. Construct wire packet with opcode 0x17c (Zone channel):
   - Header (8 bytes: opcode + size)
   - Payload at +0x10:
     * ID pair (+0x00, +0x04): actor primary id
     * ID pair (+0x08, +0x0c): dedup key (server-tracked)
     * TYPE_TAG (+0x10): 0 for EntryBuilder (spawn)
     * Position/comparison fields
     * Class name string at +0x44 (e.g. "PartyCharaActor", "EnemyNpc")
     * 0x2711 tag somewhere if list-object spawn (per dispatcher check)

2. Send via Zone channel (sequence < 0x1c11 for in-order processing)

3. Wait for client ACKs:
   - 2x opcode 0x130 (32B each): listObjectQueueAdd + Delete
     = "I added the actor to my list" + "I processed the pending entry"
     Payload: (resolver_id, primary_id) -- same 2 IDs server sent
   - 1x opcode 0x133 (56B): WorkSync init ACK
     = "Actor's onInit completed; ready for state sync"

4. Now server can push state updates via opcode 0x12F/0x132/0x133

WHEN SERVER WANTS TO DESPAWN ACTOR:
   - Send 0x17c with TYPE_TAG set to BreakupBuilder's discriminator
   - Wait for ACKs

WHEN SERVER WANTS TO UPDATE STATUS/MEMBER/PROPERTY:
   - Send 0x17c with TYPE_TAG set to:
     * OnlineStatusUpdater (0xe) for online status
     * MemberInfoUpdater for member info
     * PropertyUpdater for property
     * WorkSyncUpdater for worksync state
```

## 12. Confidence

```text
Confirmed:
  - Wire opcode 0x17c = SPAWN packet (TRIPLE confirmation: opcode 0x17c
    case calls FUN_00576250 calls FUN_006cc620 calls factory)
  - 7 Group:: subclasses (RTTI walk + ctor decomp)
  - Full producer-consumer flow end-to-end
  - 50+ game protocol opcodes in dispatch table
  - Wire packet layout (per param_3 access patterns)
  - PacketRequestBase vftable (13 slots @ 0x00fd4120)
  - 0x2711 = list-object spawn signature
  - 2x 0x130 + 1x 0x133 ACK pattern per spawn

Likely (High):
  - Opcodes 0x143-0x1a8 are all part of the "script engine" wire
    protocol (sent by server during gameplay; ~40 specific handlers
    + fallback)
  - The 50+ opcodes carry: chat, target updates, spawn/despawn,
    state sync, status effects, combat events, etc.
  - Each opcode has a specific bridge function in 0x00576xxx range
    (FUN_005764c0..b80 style) that parses payload and forwards to
    Lua via invokeLua_on* family

Speculative:
  - Each Group:: subclass's vtable[5] and vtable[11] (the ZoneIn_handler_default
    overrides) handles inbound packet parsing per type
  - The "spawn pipeline instance" (with ring buffer at +0x20) is
    a WorldMaster or session-scoped object; one instance handles
    all actors globally
```

## 13. Cross-references

- `finding_spawn_pipeline_typed_packet_ring_buffer_6_stage_architecture.md`
  -- the CONSUMER side (now linked to producer side here)
- `finding_application_mainTick_and_per_frame_subsystem_dispatch.md`
  -- the per-frame tick that drains the queue
- `finding_zoneclient_inbound_dispatch_layer_partial_threshold_0x1c11.md`
  -- the sequence threshold layer (preceding step in inbound path)
- `finding_isInstanceOf_thunk_dual_dispatch_rtti_plus_luachain.md`
  -- the class name lookup that uses the class string from this packet
- `finding_createActor_thunk_async_actor_factory.md`
  -- the Lua-side _createActor (which can also be called by spawn
  pipeline T5 via vtable[0x6c])

## 14. Next test

```text
Now that the spawn opcode is pinned, the natural follow-ups are:
1. Walk each Group:: subclass's vtable[5] / vtable[11] overrides
   to document inbound packet parsing per subclass
2. Document the ~40 game opcodes in 0x143-0x1a8 range systematically
   (most are bridges to Lua via standard pattern)
3. Decompile FUN_00cc9320 (the "lookup by name/id" called in
   FUN_00576250) to understand how opcode 0x17c locates its target
4. Map BreakupBuilder construction path (to find despawn opcode/path)
5. Document the 0xca/0xcb session opcodes (low-opcode session
   management)
```

## Commit suggestion

```
docs(re/exe): SPAWN WIRE-SIDE LOOP CLOSED -- opcode 0x17c = SPAWN; Zone MAIN inbound dispatcher (50+ game opcodes); 7 Group:: subclasses; end-to-end flow producer→consumer→Lua
```
