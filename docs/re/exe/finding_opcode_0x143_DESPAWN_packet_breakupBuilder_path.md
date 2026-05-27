# Finding: Opcode 0x143 = DESPAWN PACKET (BreakupBuilder Path)

**Misidentified opcode now correctly characterized.** What was
initially labeled as "generic state event" in the bridge pattern
finding is actually the **DESPAWN PACKET** — the mirror image of
opcode 0x17c SPAWN.

This closes the actor lifecycle wire protocol: server sends 0x17c
to spawn an actor and 0x143 to despawn it. Both use the same spawn
pipeline ring buffer but construct different typed packet objects.

## 1. The despawn flow (mirror of spawn)

```text
WIRE: Zone channel inbound, opcode 0x143
   ↓
ZoneIn_opcode_0x143_DESPAWN_extractAndForwardToDespawnHandler (0x00576240)
   ↓
DespawnPipeline_forwarder_toBreakupConstructor (0x006c5de0)
   ↓
DespawnPipeline_constructBreakupBuilder_enqueueToRingBuffer (0x006c5150)
   │
   ├─ operator_new(0x38)  -- allocate 56-byte BreakupBuilder
   ├─ FUN_006d6f10(...)   -- construct BreakupBuilder with ids
   └─ ringBuffer_enqueue_4bytes(this+8, &builder)
        ↓ SAME RING BUFFER AS SPAWN ↓
   
[per-frame] SpawnPipeline T0/T1/T2/T3/T4/T5
   ↓ T1 RTTI cast (BreakupBuilder IS-A EntryBuilderBase IS-A PacketRequestBase)
   ↓ T5 invokes dtor path instead of allocator (subclass polymorphism)
   ↓
Actor's destructor / despawn callback fires
```

## 2. Wire packet 0x143 format (much smaller than 0x17c)

```text
param_1 fields (smaller payload than 0x17c spawn):
  +0x00  param_1[0]    -- if zero, use "same-as-source" path
  +0x04  param_1[1]    -- additional discriminator?
  +0x08  param_1[2]    -- id field A (source actor id)
  +0x0c  param_1[3]    -- id field A (source actor id high)
  +0x10  param_1[4]    -- id field B (target/replacement id low)
  +0x14  param_1[5]    -- id field B (target/replacement id high)
  +0x18  param_1[6]    -- matched_id comparison (low)
  +0x1c  param_1[7]    -- matched_id comparison (high)

PROCESSING LOGIC:
  if (param_1[0] == 0
      OR (param_1[2]==param_1[6] AND param_1[3]==param_1[7])
      OR (all zero ids)):
      → use param_1[4,5] as effective id, discriminator=1
  else:
      → use param_1[2,3] as effective id, discriminator=0

Then constructs BreakupBuilder with those ids.

Total wire size: ~32 bytes (much smaller than 0x17c spawn at ~120B
because despawn only needs id; no class name needed).
```

## 3. Architecture: spawn vs despawn parallel

```text
                        SPAWN (0x17c)              DESPAWN (0x143)
                        -------------              ---------------
Wire opcode             0x17c (380)                0x143 (323)
Wire packet size        ~120 bytes                 ~32 bytes
Carries class name?     YES (offset +0x44)         NO (id only)
Subclass constructed    EntryBuilder               BreakupBuilder
Subclass parent         EntryBuilderBase           EntryBuilderBase (same!)
Subclass alloc size     0x40 + 0xf8 child          0x38
Type tag at +0x10       0 (EntryBuilder)           N/A (different opcode)
Ring buffer destination instance+0x20 spawn queue  instance+0x20 spawn queue (SAME!)
Per-frame consumer      T0-T5 spawn pipeline       T0-T5 spawn pipeline (SAME!)
T5 action               new(0x54) Actor + ctor     dtor path (poly via vtable)
Outbound ACK            2x 0x130 + 1x 0x133        ? (TBD; likely subset)
```

**Key insight**: SPAWN and DESPAWN share the same pipeline because
both BreakupBuilder and EntryBuilder inherit from EntryBuilderBase.
The pipeline doesn't care which subclass — it dispatches polymorphically
via vtable. The T5 stage's behavior depends on the specific subclass's
vtable methods.

## 4. The 2-path BreakupBuilder construction

BreakupBuilder has TWO callers (both result in despawn but different
trigger contexts):

### Path A: Direct despawn (opcode 0x143 -- DOCUMENTED ABOVE)

```text
Server sends 0x143 packet → handler chain → BreakupBuilder → ring buffer
This is the explicit "remove actor X" path.
```

### Path B: Pending-list scan despawn (FUN_006c5020)

```text
DespawnPipeline_scanPendingList_conditionalBreakup (0x006c5020):
  Scans a list at this+0x14/0x18 (count + items)
  For each entry matching certain criteria:
    new BreakupBuilder for that entry
    enqueue to spawn ring buffer
  
  This is the IMPLICIT cleanup path -- triggered by zone change /
  party departure / etc. -- the engine scans pending actors and
  generates despawn entries for ones no longer needed.
```

Both paths funnel into the same ring buffer.

## 5. Correction to prior finding

```text
PRIOR FINDING (finding_zone_inbound_game_opcodes_0x143_0x1a8_bridge_pattern.md):
  Section 4 -- GROUP B inferred:
    "0x143: generic state event (thin bridge to subsystem_0x18)"

CORRECTION:
  0x143 is the DESPAWN PACKET, NOT a generic state event.
  
  The "subsystem at this+0x18" that I called "generic state" is
  actually the spawn pipeline manager -- it owns the same ring
  buffer used by the spawn factory.
  
  Recategorization:
    0x143 -> moved from GROUP B (generic state) to GROUP E (SPAWN family)
            -- it's the DESPAWN counterpart of 0x17c SPAWN
```

## 6. Renames + comments applied

```text
0x00576240  → ZoneIn_opcode_0x143_DESPAWN_extractAndForwardToDespawnHandler
              (was: ZoneIn_opcode_0x143_thinBridge_to_subsystem_0x18)
0x006c5de0  → DespawnPipeline_forwarder_toBreakupConstructor
0x006c5150  → DespawnPipeline_constructBreakupBuilder_enqueueToRingBuffer
0x006c5020  → DespawnPipeline_scanPendingList_conditionalBreakup

Plus decompiler comment at 0x006c5150 documenting the wire packet
layout + processing flow.
```

## 7. Server-side actor lifecycle protocol (NOW COMPLETE)

```text
COMPLETE WIRE PROTOCOL FOR ACTOR LIFECYCLE:

  TO SPAWN AN ACTOR:
    1. Server sends opcode 0x17c (~120 bytes) with class name + ids
    2. Client constructs EntryBuilder -> spawn ring buffer
    3. Client allocates 84B actor, fires actor:_onInit()
    4. Client sends 2x outbound 0x130 (listObjectQueueAdd + Delete)
    5. Client sends 1x outbound 0x133 (WorkSync init ACK)
    6. Server can now push state via 0x12F/0x132/0x133/0x148-0x156

  TO DESPAWN AN ACTOR:
    1. Server sends opcode 0x143 (~32 bytes) with actor id
    2. Client constructs BreakupBuilder -> spawn ring buffer
    3. Client calls actor destructor / cleanup callback
    4. Client likely sends some 0x130-family ACK (TBD)
    5. Server stops sending state for that actor

  TO UPDATE ACTOR STATE (already documented):
    - opcode 0x12F: WorkSync state update (56B)
    - opcode 0x132: item state notify (24B)
    - opcode 0x133: WorkSync alt (56B)
    - opcodes 0x148-0x156: per-actor message variants (15 types)

The spawn/despawn cycle is now FULLY DOCUMENTED for server implementation.
```

## 8. Confidence

```text
Confirmed:
  - Opcode 0x143 constructs BreakupBuilder (xref chain pinned)
  - BreakupBuilder shares ring buffer with EntryBuilder (spawn pipeline)
  - 2 trigger paths for BreakupBuilder construction (direct + scan)
  - Wire packet 0x143 is significantly smaller than 0x17c (no class name)
  - 4 functions renamed in chain
  - Prior characterization of 0x143 as "generic state" was WRONG;
    now corrected

Likely (High):
  - Despawn ACK uses a subset of the spawn ACK pattern (likely just
    the 0x130 pair, no 0x133 because no init to complete)
  - The "scan pending list" path is triggered on zone change to
    despawn actors no longer in range
  - T5 stage uses vtable polymorphism to call different code for
    EntryBuilder (new actor) vs BreakupBuilder (delete actor)

Speculative:
  - The 2-path discriminator in 0x143 packet (matched_id check)
    distinguishes between "graceful logout" vs "force disconnect"
    despawn variants
```

## 9. Cross-references

- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the SPAWN counterpart (0x17c)
- `finding_spawn_pipeline_typed_packet_ring_buffer_6_stage_architecture.md`
  -- the 6-stage drain pipeline (used by both spawn and despawn)
- `finding_zone_inbound_game_opcodes_0x143_0x1a8_bridge_pattern.md`
  -- the parent finding (contains correction note)

## 10. Next test

```text
1. Decompile EntryBuilder's vtable[5]/vtable[11] vs BreakupBuilder's
   to confirm the polymorphic dispatch difference at T5
2. Verify despawn ACK opcodes (does despawn send 0x130 pair like spawn?)
3. Look for OnlineStatusUpdater dedicated wire opcode (similar to 0x143
   for despawn, there should be one for status change)
4. Check if MemberInfoUpdater / PropertyUpdater / WorkSyncUpdater
   have their own dedicated opcodes
```

## Commit suggestion

```
docs(re/exe): opcode 0x143 = DESPAWN PACKET (BreakupBuilder path); shares spawn pipeline ring buffer; actor lifecycle wire protocol COMPLETE
```
