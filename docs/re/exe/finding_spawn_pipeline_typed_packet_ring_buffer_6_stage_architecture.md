# Finding: Actor Spawn Pipeline -- 6-Stage Typed-Packet Ring-Buffer Architecture (Group::PacketRequestBase)

**Bridges class system to wire protocol.** Actor spawn in 1.x is
NOT a simple wire opcode -- it's a **typed packet object system**
in the `Group::PacketRequestBase` polymorphic hierarchy, processed
through a 6-stage pipeline from per-tick pump to actor allocation.

Discovered while probing how the spawn opcode reaches `_createActor`.
**Adds 2 NEW RTTI types** in the `Group::` namespace, bringing the
confirmed RTTI count from 9 to 11.

## 1. The 6 pipeline stages

```text
Stage  Function                                                  Address
-----  --------                                                  -------
T0     SpawnPipeline_T0_perTickPump_processQueue                 0x006cdd20
T1     SpawnPipeline_T1_ringBufferConsumer_castEntryBuilderBase  0x006cda80
T2     SpawnPipeline_T2_orchestrate_listObject_emits_0x130_pair  0x006cd8e0
T3     SpawnPipeline_T3_dispatch2plusN_actorsList                0x006db9a0
T4     SpawnPipeline_T4_buildAndDispatchToAllocator              0x006cbc90
T5     SpawnPipeline_T5_allocateActor_84B_invokeOnInit_ackVia_0x133  0x006c8cf0
```

## 2. End-to-end flow

```text
WIRE INBOUND (typed packet via Group hierarchy)
   │
   │ Server pushes Group::PacketRequestBase serialized payload
   │ (wire opcode likely 0x12d tagged container — needs verification)
   │
   ▼
T0: SpawnPipeline_T0_perTickPump_processQueue
   │
   │ Called per game tick when this+0x2c (queue size) > 0
   │ AND this+0xea (busy flag) == 0
   │
   │ Resolves head-of-queue PacketRequestBase via FUN_006ced30,
   │ extracts vtable[+0x4] (instance pointer) for each of 2 slots,
   │ then forwards to T1 if both ready.
   │
   │ Sets busy flag (+0xea) = 1 during processing, clears on completion
   │ to allow next tick to process more
   │
   ▼
T1: SpawnPipeline_T1_ringBufferConsumer_castEntryBuilderBase
   │
   │ Ring buffer read with wraparound:
   │   capacity = this+0x24 (e.g., 8 slots)
   │   head     = this+0x28 (advances on consume)
   │   size     = this+0x2c (decrements on consume)
   │   storage  = this+0x20 → array of 4-byte ptrs
   │
   │ For each entry (up to 2 per tick):
   │   1. ___RTDynamicCast(entry, 0,
   │        Group::PacketRequestBase::RTTI,    ← SOURCE
   │        Group::EntryBuilderBase::RTTI,     ← TARGET
   │        0)
   │   2. Extract piVar5[4]/[5] = actor id pair (+0x10/+0x14)
   │   3. Call vtable[+0x38] → "getBuildData" → build payload ptr
   │   4. Free wrapper, keep build data
   │
   ▼
T2: SpawnPipeline_T2_orchestrate_listObject_emits_0x130_pair
   │
   │ For each of the 2 actor slots:
   │   - Validate via FUN_006c1460 (registry lookup + +0x25 != 0x0f)
   │   - If validation passes: forward as-is
   │   - Else: FUN_006da630 normalizes to null
   │
   │ Then:
   │   1. Build local list object via FUN_006da9d0
   │   2. Lua_listObjectQueueAdd_sends_0x130_variantA    ← OUT 0x130
   │   3. FUN_006db050 (additional setup)
   │   4. FUN_006db1d0 (additional setup)
   │   5. Lua_listObjectDelete_sends_0x130_variantA      ← OUT 0x130
   │   6. T3 dispatch
   │
   ▼
T3: SpawnPipeline_T3_dispatch2plusN_actorsList
   │
   │ Processes up to 2+N actor slots:
   │   - slot A (param_1[4] / param_1[0xb])
   │   - slot B (param_1[5] / param_1[0xc])
   │   - additional array iteration from param_1[0xe]..[0xf]
   │
   │ For each actor:
   │   if slot has NO existing instance:
   │     - if no override callback: skip
   │     - else: FUN_006c04e0 (override path)
   │   else if no override callback:
   │     - T4 dispatch
   │   else:
   │     - FUN_006cd7d0 (custom build path with override)
   │
   ▼
T4: SpawnPipeline_T4_buildAndDispatchToAllocator
   │
   │ 1. Lookup actor class info via FUN_006d03c0 (registry)
   │ 2. If class has any work fields (+0x14/0x18/0x1c/0x20 > 0):
   │      - operator_new(0x48) for "WorkRecord" (72 bytes)
   │      - FUN_006cb4c0 initializes work record
   │ 3. T5 dispatch with actor build data + optional work record
   │
   ▼
T5: SpawnPipeline_T5_allocateActor_84B_invokeOnInit_ackVia_0x133
   │
   │ 1. operator_new(0x54) = 84 bytes for ACTOR INSTANCE
   │ 2. FUN_006c83d0 = actor ctor
   │ 3. Store at this+0xa0 (actor instance pointer)
   │ 4. FUN_00ccc590 builds reverse lookup index
   │ 5. Clean up old instance at this+0x9c (if exists)
   │ 6. Actor_invokeLua_onInit(...)              ← T3 lifecycle callback fires
   │ 7. Set actor[+0x50] = 1 (active flag)
   │ 8. Set actor[+0x4c] based on +0x18 condition (1 or 2)
   │ 9. If +0x18 != 0:
   │      WorkSyncAlt_serializePayloadAndSend_opcode_0x133  ← OUT 0x133 ACK
   │
   ▼
LUA: actor:onInit() callback runs
LUA: actor is now LIVE and visible to script
```

## 3. NEW RTTI types discovered (+2)

```text
NEW (from this finding):
  - Application::Lua::Script::Client::Group::PacketRequestBase::RTTI_Type_Descriptor
  - Application::Lua::Script::Client::Group::EntryBuilderBase::RTTI_Type_Descriptor

Prior 9 + 2 = 11 RTTI types now confirmed:
  - Component::Lua::GameEngine::LuaControl
  - Component::Lua::GameEngine::ResumeCheckerInterface
  - Component::Lua::GameEngine::FunctionEndCallbackInterface
  - Component::Lua::GameEngine::LpbLoader::ResumeChecker
  - Application::Lua::Script::Client::Control::ActorBase
  - Application::Lua::Script::Client::Control::CharaBase
  - Application::Lua::Script::Client::Control::PlayerBase
  - Application::Lua::Script::Client::Control::NpcBase
  - Application::Lua::Script::Client::Control::AreaBase
  - Application::Lua::Script::Client::Control::DirectorBase
  - Application::Lua::Script::Client::Control::DesktopWidget
  - Application::Lua::Script::Client::Control::WorldMaster
  - Application::Lua::Script::Client::Control::MyPlayer (per prior chat finding)
  - Application::Lua::Script::Client::Group::PacketRequestBase            ← NEW
  - Application::Lua::Script::Client::Group::EntryBuilderBase             ← NEW

That's 15 confirmed RTTI types.

NEW NAMESPACE: Application::Lua::Script::Client::Group:: -- distinct
from Application::Lua::Script::Client::Control:: -- this is where
the "typed packet" infrastructure lives (PacketRequestBase root +
subclass hierarchy for different packet types).

This explains the "Group_invokeLua_*" function naming pattern from
the search -- those Group thunks are members of this same namespace
that interacts with party/lobby/group state.
```

## 4. Spawn architecture rationale

### Why typed packets instead of opcodes?

```text
A simple opcode approach would be:
  opcode 0xSPAWN + actor_id + class_name + position + ...

But 1.x uses POLYMORPHIC typed packets:
  Group::PacketRequestBase
    ├─ EntryBuilderBase (actor spawn)
    ├─ <other subclasses likely exist>
    └─ ...

Benefits:
1. EXTENSIBILITY: new packet types add new subclasses without
   changing wire opcodes
2. RTTI DISPATCH: receiver doesn't switch on opcode; uses
   ___RTDynamicCast to determine packet handling
3. SERIALIZATION: each subclass owns its own serialize/deserialize
   (via vtable methods at +0x38, etc.)
4. SHARED INFRA: ring buffer queue + per-tick pump is REUSED for
   all packet types, not just actor spawn
```

### Why the ring buffer?

```text
Spawn is EXPENSIVE: actor allocation, Lua callback dispatch, work
record setup, list-object protocol with 2 outbound 0x130 packets,
plus T3 ACK via 0x133.

Per-tick pump processes only 2 entries max per tick to avoid:
- Long frame stalls (spawn storm at zone enter)
- Reentrancy issues (busy flag +0xea prevents recursion)
- Lua side overload (each onInit can yield via ResumeChecker)

This means a zone with 50+ actors spawns over 25+ frames at 60Hz =
~400ms ramp-up. Visible as the gradual "fade-in" you see when
loading a zone in 1.x.
```

### The 0x130 outbound pair (queueAdd + delete)

```text
T2 sends 2 outbound 0x130 packets per spawn:
  1. Lua_listObjectQueueAdd_sends_0x130_variantA  -- adds to client's
                                                     actor list
  2. Lua_listObjectDelete_sends_0x130_variantA    -- removes from
                                                     pending-spawn queue

This is the CLIENT TELLING SERVER about spawn state transitions:
  - "I'm adding this actor to my active list"
  - "I'm removing this entry from my pending queue"

Server uses these to track:
  - Per-client actor visibility (subscription model)
  - Spawn ack/nack (if server pushed a spawn but client never adds,
    something's wrong)

Then T5 sends additional 0x133 ACK for the per-actor WorkSync init.
```

## 5. Server implications

```text
WIRE PROTOCOL: Server must implement the typed packet system:
  - Wire opcode (likely 0x12d tagged container) carries serialized
    Group::PacketRequestBase derivatives
  - Each subclass has its own serialization format
  - Per-actor spawn payload includes:
    * actor id (+0x10/+0x14 = 64-bit?)
    * class name (string)
    * build data (per-subclass payload)

SERVER-SIDE STATE:
  - Per-client "pending spawn queue" mirroring client's ring buffer
  - Wait for client's 0x130 queueAdd ACK before marking spawn confirmed
  - Wait for client's 0x133 T5 ACK before sending state updates
  - Respect client's 2-per-tick spawn rate (don't flood)

REVERSE ENGINEERING NEXT:
  - Decompile FUN_006d03c0 to learn class registry layout
  - Decompile FUN_006cb4c0 to learn WorkRecord init (72 bytes)
  - Find Group::PacketRequestBase wire deserialization
  - Find sibling EntryBuilderBase subclasses (despawn? state update?)
```

## 6. Renames + comments applied

```text
0x006c8cf0  FUN_006c8cf0   → SpawnPipeline_T5_allocateActor_84B_invokeOnInit_ackVia_0x133
0x006cbc90  FUN_006cbc90   → SpawnPipeline_T4_buildAndDispatchToAllocator
0x006db9a0  FUN_006db9a0   → SpawnPipeline_T3_dispatch2plusN_actorsList
0x006cd8e0  FUN_006cd8e0   → SpawnPipeline_T2_orchestrate_listObject_emits_0x130_pair
0x006cda80  FUN_006cda80   → SpawnPipeline_T1_ringBufferConsumer_castEntryBuilderBase
0x006cdd20  FUN_006cdd20   → SpawnPipeline_T0_perTickPump_processQueue
```

Plus decompiler comment at 0x006cda80 documenting the RTTI cast +
ring buffer mechanics + new RTTI namespace discovery.

## 7. Cross-references

- `finding_createActor_thunk_async_actor_factory.md` -- the Lua side
  (now we know what wire path triggers it indirectly via T5)
- `finding_isInstanceOf_thunk_dual_dispatch_rtti_plus_luachain.md` --
  RTTI walk that this finding extends (+2 new types)
- `finding_canCreateActorByName_thunk_creatability_check.md` -- the
  Lua-side spawn precondition check
- `finding_actor_lifecycle_T0_T3.md` -- T3 (onInit) is what T5 fires here
- `finding_inbound_chat_handlers_3_variants_decompiled.md` --
  3-channel architecture (Chat / Zone / Lobby)
- `finding_worksync_pipeline.md` -- T5 ACK via 0x133 is part of this

## 8. Confidence

```text
Confirmed:
  - 6-stage pipeline T0→T5 with confirmed call chain
  - Stage T5 allocates 84 bytes per actor
  - Stage T5 fires Actor_invokeLua_onInit (T3 lifecycle callback)
  - Stage T5 sends WorkSync ACK via opcode 0x133
  - Stage T2 sends 2 outbound 0x130 packets (queueAdd + delete)
  - Stage T1 RTTI-casts to Group::EntryBuilderBase
  - 2 NEW RTTI types: PacketRequestBase + EntryBuilderBase in
    Group:: namespace
  - Ring buffer at this+0x20 with head/size/capacity at +0x24/0x28/0x2c
  - Busy flag at +0xea prevents reentrant pump
  - Per-tick pump processes at most 2 entries per call
  - All 6 functions renamed + 1 decompiler comment added

Likely (High):
  - Inbound wire opcode is 0x12d (tagged container) — needs verification
  - Group:: namespace has additional packet subclasses (despawn,
    state update, ...)
  - The 0x130 outbound pair is a "spawn ack" pattern visible to server
  - Server-side actor visibility model uses these ACKs

Speculative:
  - The 84-byte actor size is the C++ instance size (Lua state may
    add more on top)
  - The 72-byte WorkRecord holds per-actor WorkSync state
  - The 2-per-tick rate may be tunable per zone density
```

## 9. Next test

```text
1. Find Group::PacketRequestBase wire deserialization entry point
   (likely called from a Zone inbound dispatch table slot for
   opcode 0x12d or similar tagged container)
2. Enumerate all Group::PacketRequestBase subclasses via vtable scan
   (other packet types beyond actor spawn)
3. Decompile FUN_006cb4c0 to document the 72-byte WorkRecord layout
4. Trace how server-side spawn packet construction would work
   (mirror the EntryBuilderBase format)
5. Verify opcode 0x12d carries Group:: packets (or identify alt opcode)
```

## Commit suggestion

```
docs(re/exe): SPAWN PIPELINE 6-stage architecture -- Group::PacketRequestBase typed-packet ring-buffer + 2 new RTTI types (15 total confirmed)
```
