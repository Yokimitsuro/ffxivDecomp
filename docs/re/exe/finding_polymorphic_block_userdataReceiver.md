# Finding: Polymorphic Inbound Block Resolved -- UserDataReceiver Packet Class

Closes the 5-entry polymorphic block at inbound dispatch table
entries 22-26 by identifying the packet class (`UserDataReceiver`),
locating both its vtables, and reading vtable slots 21-25 to
identify per-slot semantics.

Key result: **the polymorphic block uses ONE class with 2 active
slots and 3 inherited no-op slots**. Opcodes 22, 25, 26 are reserved
no-ops; opcodes 23 and 24 do real work.

## Method

1. Traced from the polymorphic handler at entry 24 backward through
   the packet object's construction at `FUN_0089eed0` (called from
   entry 38 and from `FUN_007622e0`).
2. Read the disassembly of FUN_0089eed0 to extract the literal
   vtable pointer values:

   ```
   0089eefd: MOV [EDI], 0xfdf980      -- transient: CommandInterface::vftable
   0089ef19: MOV [EDI+8], 0x1057488   -- secondary subobject vtable
   0089ef1f: MOV [EDI], 0x10574a4     -- primary subobject vtable
   ```

3. Probed vtable slot data at each candidate address via
   `mcp__ghidra__get_xrefs_from`. Confirmed primary vtable @
   `0x010574a4` is the one used by the polymorphic dispatch
   (consistent with slot 22, 23 holding real functions; slots 21,
   24, 25 holding a shared no-op placeholder).

## Concrete identification

Per `FUN_0089eed0` (which constructs the packet for the inbound
data-packet path):

```text
Class:        Application::Lua::Script::Client::Command::Network::UserDataReceiver
Inherits:     Application::Lua::Script::Client::Command::CommandInterface
Object size:  0x24 bytes (per operator_new(0x24) in FUN_007622e0)
Vtables:
   primary    @ 0x010574a4   stored at object+0
   secondary  @ 0x01057488   stored at object+8

Allocation paths:
   1. Stack-allocated from FUN_00759e50 (entry 38, dataPacket)
   2. Heap-allocated from FUN_007622e0 -> queued at this+0x20
```

## Primary vtable slots 21-25 (the polymorphic block)

Inbound dispatch table entries 22-26 each invoke a different slot
of this vtable. The mapping is:

```text
DISPATCH    PRIMARY VTABLE    FUNCTION POINTER     SEMANTICS
ENTRY       SLOT (offset)
---------   ----------------  -------------------  -----------------------------------
   22        slot 21 (+0x54)   0x010574f8 -> 0x00776340   NO-OP (inherited from base)
   23        slot 22 (+0x58)   0x010574fc -> 0x008a2d50   APPEND payload to container (this+4)
   24        slot 23 (+0x5c)   0x01057500 -> 0x008a2b70   RESOLVE actor by id, store at this+0x18
   25        slot 24 (+0x60)   0x01057504 -> 0x00776340   NO-OP (inherited from base)
   26        slot 25 (+0x64)   0x01057508 -> 0x00776340   NO-OP (inherited from base)
```

So 3 of the 5 polymorphic opcodes (22, 25, 26) reach an INHERITED
no-op. Only opcodes 23 and 24 do real work for this packet class.

## Slot 22 (entry 23): "append payload"

```c
void UserDataReceiver_vtable_slot22_appendPayloadToContainer(this, packet) {
    PayloadEntry entry;
    FUN_004d3420(&entry, packet);                   // build from packet
    FUN_004d50d0((this + 4), &entry);               // insert into container at +4
    // cleanup if a tail object was built
}
```

So opcode 23 streams ONE payload entry into the packet's internal
container at `this+4` (a std::vector-like structure). This is
consistent with **multi-event payload accumulation**: the server
sends a sequence of opcode-23 events to push N entries into the
packet, then a final opcode commits/applies them.

## Slot 23 (entry 24): "resolve target actor"

```c
void UserDataReceiver_vtable_slot23_resolveActorIntoField0x18(this, packet) {
    int *resolved = FUN_00cc9320(&packet, *packet); // resolve actor by id
    *(int *)(this + 0x18) = *resolved;              // store at +0x18
    FUN_00cc9330();                                  // cleanup
}
```

So opcode 24 sets the packet's "target actor" field (at +0x18) by
resolving an actor id from the payload via the standard
`FUN_00cc9320 / FUN_00cc9330` actor lookup pair (already used in
many other handlers).

## Object field layout (inferred)

```text
UserDataReceiver layout (0x24 bytes total):
  +0x00 (4B): primary vtable pointer        (=  0x010574a4)
  +0x04 (?):  payload container start       (std::vector-like)
       ...   (continues to +0x14)
  +0x08 (4B): secondary vtable pointer      (= 0x01057488)
                (overlaps with the container -- MSVC multi-inheritance
                 sometimes interleaves; the secondary vtable pointer
                 is at +8 from the subobject base)
  +0x10 (1B): dispatch mode byte (0/1/2/0xff)  -- used by FUN_0089fbf0
  +0x14 (4B): target actor reference (resolved)
  +0x18 (4B): target actor pointer (filled by slot 23)
  +0x1a (1B): channel/sub-id byte
  +0x18 (2B): ushort id (per FUN_0089fbf0)
  +0x1c (?):  ...
  +0x20 (4B): packet container head ptr (per FUN_007622e0:
                FUN_007945a0(this+0x20, packet))
```

These offsets are inferred from method bodies; field layout still
needs full verification.

## Why the polymorphic block has 3 no-ops

The base class (CommandInterface) defines ~25+ virtual methods. Each
derived class overrides only the ones it cares about. For
UserDataReceiver:

- It overrides slot 22 (its packet-specific "append entry") and slot
  23 (its packet-specific "resolve target").
- It does NOT override slots 21, 24, 25.
- Those slots stay as the base's `FUN_00776340` (empty function).

So inbound opcodes 22, 25, 26 — when dispatched to a
UserDataReceiver packet — do nothing. They might do something for
OTHER packet classes if any other class overrides those slots. But
the data-packet inbound channel only constructs UserDataReceiver
objects, so for this channel those opcodes are effectively NO-OP.

## Implications for server

```text
For server implementation of the polymorphic block (entries 22-26):

  Required:    entries 23 and 24 -- must send them as part of any
               complex multi-event sequence (e.g. command result push
               with payload chunks).

  Optional:    entries 22, 25, 26 -- can be sent but have no client
               effect on UserDataReceiver packets. May be useful for
               other packet types in the future.

Sequence example (server pushes a command result to a target actor):
  1. send entry 24 (resolve_target_actor) with target_actor_id
  2. send entry 23 (append_payload_entry) N times with payload chunks
  3. send a "commit/apply" opcode (TBD - possibly entry 25 or another
     non-polymorphic opcode that reads from this+0x18 and this+4)
```

## Secondary vtable @ 0x01057488

Probed slots show:
- 0x010574e0 (slot 22 of secondary): `FUN_008a2ac0` -- destructor variant 1
- 0x010574e4 (slot 23 of secondary): `FUN_0089fbf0` -- COMPLEX MULTI-MODE DISPATCHER
- 0x010574ec (slot 25 of secondary): `FUN_008a2c90` -- destructor variant 2

The secondary vtable holds the MSVC "scalar deleting destructor" and
"vector deleting destructor" plus a complex dispatch function
`FUN_0089fbf0` (which is also the router for non-polymorphic dispatch
table entry 42).

`FUN_0089fbf0` has a 4-way switch on `*(byte *)(this+0x10)`:

```text
case 0:    dynamic_cast<CharaBase>(actor) + FUN_00771f50/00772050
case 1:    ID-based dispatch via FUN_008a1510 + FUN_007721b0
case 2:    name-based dispatch via FUN_008a15b0 + FUN_00772560
case 0xff: broadcast/all dispatch via FUN_00772650 or FUN_00771f50
```

This 4-way dispatch on a "mode byte" at +0x10 suggests UserDataReceiver
is a **multi-target packet**:

- mode 0: target is a specific CharaBase actor
- mode 1: target is a numeric id
- mode 2: target is a name string
- mode 0xff: target is broadcast (all-or-self)

So a single UserDataReceiver packet can dispatch a payload to any
of 4 target kinds depending on its mode byte. This is consistent
with the FFXIV 1.x model of "tell/say/yell/system" type targeting.

## Annotations made in Ghidra

```text
RENAMES:
  - 0x008a2d50 -> UserDataReceiver_vtable_slot22_appendPayloadToContainer
  - 0x008a2b70 -> UserDataReceiver_vtable_slot23_resolveActorIntoField0x18
  - 0x00776340 -> UserDataReceiver_vtable_noop_inherited

COMMENTS (multi-line, with vtable layout and cross-references):
  - 0x008a2d50 (slot 22 behavior + multi-event payload accumulation)
  - 0x008a2b70 (slot 23 behavior + actor resolve pair)
  - 0x00776340 (no-op + which slots reuse it)
```

## Confidence

```text
Confirmed:
  - UserDataReceiver is the concrete packet class for the inbound
    dispatch (verified by reading FUN_0089eed0 disassembly).
  - It has TWO vtables (multi-inheritance): primary @ 0x010574a4 and
    secondary @ 0x01057488. Object size 0x24.
  - Primary vtable slots 21-25 have been read: 21/24/25 = no-op,
    22 = append-payload, 23 = resolve-actor.
  - 3 of the 5 polymorphic opcodes (22, 25, 26) are NO-OP for this
    packet class.

Likely (High):
  - The packet accumulates state across multiple opcodes received
    in sequence: opcode 24 sets target, opcode 23 appends payload
    chunks, then a final opcode applies.
  - The "complex multi-mode dispatcher" at FUN_0089fbf0 (secondary
    vtable slot 23) is the SAME router used by non-polymorphic entry
    42 -- confirming the cross-system reuse.

Likely (Medium):
  - The 4 dispatch modes (0/1/2/0xff) in FUN_0089fbf0 mirror the
    4 chat variants A/B/C/D. UserDataReceiver may be the underlying
    inbound packet shape for ALL chat messages (with the mode byte
    selecting the target kind).

Speculative:
  - Slot 21/24/25 may be overridden by OTHER inbound packet classes
    in the same channel (e.g. a separate "RawDataReceiver" or
    "BinaryReceiver" might use those slots). Confirming requires
    finding other classes that share the dispatch table.
```

## Coverage update

```text
Active opcodes named:           24 (+2 from this round: 23 + 24)
Active opcodes characterized:    5 (polymorphic block; 3 of 5 confirmed
                                     as no-op for UserDataReceiver)
Active opcodes via family:      48 total active
Coverage %:                     50% NAMED, 100% FAMILY-CLASSIFIED
```

## Next test

- Inspect `FUN_0089fbf0` (the multi-mode dispatcher) call paths to
  confirm whether the 4 modes correspond to chat A/B/C/D variants.
- Walk FUN_004d3420 / FUN_004d50d0 to characterize the "payload entry"
  data structure inserted via slot 22.
- Look for OTHER packet classes whose vtables include FUN_00776340
  AND override slot 21/24/25 — that would explain when opcodes
  22/25/26 actually do something.
- Walk the destructor functions (FUN_008a2ac0 -> FUN_0089fb50 and
  FUN_008a2c90 -> FUN_008a2c20) to read the field destruction order;
  this gives a definitive object field layout.

## Commit suggestion

```
docs(re/exe): resolve polymorphic inbound block to UserDataReceiver packet class
```
