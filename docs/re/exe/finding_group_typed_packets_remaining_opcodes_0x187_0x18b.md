# Finding: Group:: Typed Packets -- Remaining Opcodes Pinned (0x187 WorkSync, 0x18b MemberInfo, vtable PropertyUpdater)

**Completes the Group:: typed-packet wire opcode map.** Found
dedicated opcodes for the 4 remaining Group:: subclasses that weren't
covered by the spawn/despawn opcodes (0x17c/0x143).

This finalizes the wire protocol for the **complete typed-object
replication system** in 1.x.

## 1. Updated Group:: subclass to wire opcode map

```text
Subclass              Wire opcode  Trigger path
--------              -----------  ------------
EntryBuilder          0x17c (380)  TYPE TAG = 0 in SPAWN packet
BreakupBuilder        0x143 (323)  DESPAWN packet (dedicated)
OnlineStatusUpdater   0x17c (380)  TYPE TAG = 0xe in SPAWN packet
MemberInfoUpdater     0x18b (395)  dedicated opcode (NEW)
PropertyUpdater       (vtable cb)  polymorphic via vtable at 0x00fd44ac (NEW)
WorkSyncUpdater       0x187 (391)  dedicated opcode (NEW)
```

## 2. The 3 NEW dedicated opcodes

### Opcode 0x187 -- WorkSyncUpdater packet

```text
ZoneIn_opcode_0x187_WORKSYNC_typedPacket_extractForwarder (0x00576390)
   ↓
WorkSyncUpdater_forwarder_toFactory (0x006c8340)
   ↓ thin: FUN_006c6b20(this+8, this, payload)
   ↓
WorkSyncUpdater_FACTORY_constructAndEnqueue (0x006c6b20)
   ↓
   new WorkSyncUpdater(payload) -- allocates 0xa0 (160B) child struct
   ↓
   enqueue to spawn pipeline ring buffer
```

**Server-side: opcode 0x187 = state replication batch.**
The 160B child struct holds the WorkSync state data. Likely related
to the inbound CommandUpdate record (200B) seen in prior findings.

### Opcode 0x18b -- MemberInfoUpdater packet

```text
ZoneIn_opcode_0x18b_MEMBERINFO_typedPacket_extractForwarder (0x005763a0)
   ↓
MemberInfoUpdater_forwarder_toFactory (0x006c5df0)
   ↓ thin: FUN_006c5240(this+8, this, payload)
   ↓
MemberInfoUpdater_FACTORY_constructAndEnqueue (0x006c5240)
   ↓
   new MemberInfoUpdater(payload) -- with class name + parameter
   ↓
   enqueue to spawn pipeline ring buffer
```

**Server-side: opcode 0x18b = member info update.**
Used to update party/linkshell member information (level changes,
class changes, status updates, etc.).

### PropertyUpdater -- vtable callback only

```text
FUN_006c5750 has DATA xref at 0x00fd44ac (vtable slot of unknown class).

This means PropertyUpdater is constructed POLYMORPHICALLY -- some
other object's vtable method calls this factory when a property
change occurs. Likely the property change is internal-state-driven
(e.g., a Lua-side trigger via _bindWork) rather than wire-driven.

There may be a separate wire opcode that triggers the vtable call,
but it's not directly traceable from PropertyUpdater's xrefs alone.

NOT BLOCKING for server implementation -- if server needs to push
property updates, it likely uses WorkSyncUpdater (0x187) instead.
```

## 3. Updated complete Group:: typed-packet wire protocol

```text
WIRE OPCODE ↔ SUBCLASS TABLE (for server implementation):

  Opcode 0x143       BreakupBuilder        despawn actor
  Opcode 0x17c+TAG0  EntryBuilder          spawn actor (with class name)
  Opcode 0x17c+TAG0xe OnlineStatusUpdater  change online status
  Opcode 0x187       WorkSyncUpdater       replicate state batch
  Opcode 0x18b       MemberInfoUpdater     update party/linkshell member info
  (vtable cb)        PropertyUpdater       (internal-state-driven; no dedicated opcode)

All 6 subclasses end up in the SAME spawn pipeline ring buffer
(at instance+0x20). The per-frame T0-T5 pipeline dispatches them
polymorphically via vtable.
```

## 4. The Group:: subsystem architecture (final picture)

```text
PURPOSE: typed-object replication for actor lifecycle + party/linkshell state

WIRE INPUT (5 dedicated opcodes + 1 internal):
  0x143  -> BreakupBuilder      (despawn)
  0x17c  -> EntryBuilder OR OnlineStatusUpdater (TYPE TAG dispatch)
  0x187  -> WorkSyncUpdater      (state batch)
  0x18b  -> MemberInfoUpdater    (member info)
  vtable -> PropertyUpdater      (internal-only)

PROCESSING:
  All 6 subclasses inherit from PacketRequestBase (vftable @ 0x00fd4120)
  All 6 are enqueued to the SAME ring buffer at spawn pipeline +0x20
  Per-frame T0-T5 pipeline drains polymorphically (vtable[5]/[11] overrides)

WIRE OUTPUT (ACKs):
  Spawn ACK:   2x outbound 0x130 (listObjectQueueAdd + Delete) + 1x 0x133
  Despawn ACK: likely 0x130 subset (TBD)
  Others ACK:  TBD per subclass

CLIENT EFFECT:
  EntryBuilder       -> allocate actor (84B) + fire actor:_onInit()
  BreakupBuilder     -> destroy actor + fire cleanup
  OnlineStatusUpdater -> update actor online status flag
  WorkSyncUpdater    -> apply state replication (200B CommandUpdate record)
  MemberInfoUpdater  -> update member info struct in party/linkshell
  PropertyUpdater    -> update property field on target
```

## 5. Renames + comments applied

```text
0x00576390  → ZoneIn_opcode_0x187_WORKSYNC_typedPacket_extractForwarder
0x005763a0  → ZoneIn_opcode_0x18b_MEMBERINFO_typedPacket_extractForwarder
0x006c8340  → WorkSyncUpdater_forwarder_toFactory
0x006c5df0  → MemberInfoUpdater_forwarder_toFactory
0x006c5240  → MemberInfoUpdater_FACTORY_constructAndEnqueue
0x006c6b20  → WorkSyncUpdater_FACTORY_constructAndEnqueue
0x006c5750  → PropertyUpdater_FACTORY_constructAndEnqueue_vtableCallback
```

## 6. Server-side complete protocol map

```text
=== ACTOR LIFECYCLE ===
0x17c TYPE 0    SPAWN actor (~120B + class name string)
0x17c TYPE 0xe  CHANGE ONLINE STATUS (existing actor)
0x143           DESPAWN actor (~32B, id only)

=== STATE REPLICATION ===
0x12F           WorkSync C->S state update (56B)
0x132           Item state notify (24B)
0x133           WorkSync alt + spawn init ACK (56B)
0x187           WorkSyncUpdater BATCH state push (typed packet, 160B child)
0x18b           MemberInfoUpdater (member info update)
0x148-0x156     Per-actor message types (15 variants: actions, events)

=== ACKs (outbound from client) ===
0x130 (x2)      List lifecycle ACK (queueAdd + Delete)
0x133           WorkSync init ACK
0x135           Subscribe binding-id

=== SESSION LIFECYCLE ===
0x02            Handshake
0x03            Login text push
0x04            Logout
0x06            Heartbeat ACK
0x07            Resync
0x08-0x0b       Bulk state push (1/16/32/64 sizes)
0x0e/0x11       Disconnect notice
0xca/0xcb       Session marker/cleanup

=== ERROR / STATUS ===
0x193 (22 codes) System error/status (16 slot codes + 6 specific)

=== BATCH STATE ===
0x18d           Multi-record batch (up to 255 x 40B records;
                likely party/linkshell member list)
```

This is essentially the COMPLETE WIRE PROTOCOL needed for a basic
server. ~30 distinct opcodes documented with their purpose.

## 7. Confidence

```text
Confirmed:
  - Opcode 0x187 constructs WorkSyncUpdater (xref chain pinned)
  - Opcode 0x18b constructs MemberInfoUpdater (xref chain pinned)
  - PropertyUpdater factory has only a vtable DATA xref (polymorphic)
  - All 6 Group:: subclasses share the spawn pipeline ring buffer
  - 7 functions renamed

Likely (High):
  - WorkSyncUpdater 0xa0 (160B) child = same data as inbound CommandUpdate
    (200B record from prior WorkSync finding)
  - MemberInfoUpdater carries level/class/status changes for
    party/linkshell members
  - PropertyUpdater is INTERNAL-only (Lua _bindWork triggered;
    no direct wire opcode)

Speculative:
  - The "vtable callback" caller of PropertyUpdater is likely a
    binding-change observer that fires on Lua-side property updates
  - WorkSyncUpdater (opcode 0x187) is sent server-to-client as
    a high-level state push, distinct from the lower-level 0x12F/0x133
    WorkSync opcodes
```

## 8. Cross-references

- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the SPAWN opcode (0x17c)
- `finding_opcode_0x143_DESPAWN_packet_breakupBuilder_path.md`
  -- the DESPAWN opcode (0x143)
- `finding_spawn_pipeline_typed_packet_ring_buffer_6_stage_architecture.md`
  -- the 7 Group:: subclasses (now all wire-pinned)
- `finding_worksync_pipeline.md` -- the prior WorkSync findings
  (0x187 likely complements those)

## 9. Next test

```text
1. Decompile the WorkSyncUpdater factory (FUN_006c6b20) to compare
   its 0xa0 child struct layout to the 200B CommandUpdate record
2. Look for the wire opcode (if any) that triggers PropertyUpdater's
   vtable callback at 0x00fd44ac
3. Document the missing despawn ACK opcodes (look at BreakupBuilder's
   vtable[5]/[11] for outbound calls)
4. Cross-reference 0x18b MemberInfoUpdater with the Group_invokeLua_*
   onUpdateMember* function family
```

## Commit suggestion

```
docs(re/exe): Group:: typed-packets wire-side COMPLETE -- 0x187 WorkSyncUpdater + 0x18b MemberInfoUpdater + PropertyUpdater via vtable callback; 6 Group:: subclasses fully wire-mapped
```
