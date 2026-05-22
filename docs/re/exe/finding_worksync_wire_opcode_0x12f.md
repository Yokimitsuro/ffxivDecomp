# Finding: Wire Opcode `0x12f` (303) — Work-Sync Update (Client → Server)

First **EXE-confirmed wire opcode** for the work-sync subsystem.
The Lua-side `_updateWork(structName, slotName, fieldIdx0, fieldIdx1)`
call translates to a fixed-format 56-byte packet sent via the Zone
channel.

Discovery date: 2026-05-23. Pinned during the EXE validation pass
following the binding-id-to-runtime-field-id confirmation.

## The Chain

```text
Lua call _updateWork(struct, slot, fieldOrIdx0, fieldOrIdx1)
   ↓
lua_updateWork_impl                          (FUN_006e85e0)
   ↓ extracts args from ExecuteParameters
   ↓ builds WorkPath via FUN_0070aa10 + FUN_0070aaa0
   ↓ calls WorkSync_dispatchOrEnqueue        (FUN_00767fc0)
   ↓
WorkSync_dispatchOrEnqueue                   (0x00767fc0)
   ↓ looks up local subscribers, dispatches
   ↓ enqueues for network via UpdateQueue_pushEntry
   ↓ OR calls WorkSync_serializePayloadAndSend (FUN_00767c00)
   ↓
WorkSync_serializePayloadAndSend             (0x00767c00)
   ↓ serializes the WorkPath via WorkPath_joinAsString (0x006cea20)
   ↓ memcpy the path bytes into a payload buffer
   ↓ calls WorkSync_buildAndSendPacket_opcode_0x12f
   ↓
WorkSync_buildAndSendPacket_opcode_0x12f     (0x0075e770)
   ↓ HARDCODES opcode=0x12f size=0x38
   ↓ packs sender + payload into 56-byte buffer
   ↓ calls Application_dispatchToZoneClient  (FUN_004d6d30)
   ↓
Application_dispatchToZoneClient             (0x004d6d30)
   ↓ fetches ZoneClient pointer from Application+0x174ec
   ↓ calls ZoneClient_dispatchOutbound       (already named)
   ↓
NETWORK SEND via Zone channel
```

## The Wire Constants

Hardcoded in `WorkSync_buildAndSendPacket_opcode_0x12f` at
0x0075e770:

```text
local_8e0[0] = 0x12f    -- wire opcode (303 decimal)
local_8e0[1] = 0x38     -- packet total size (56 bytes)
```

These are passed as a struct to `Application_dispatchToZoneClient`,
which forwards them to the Zone channel's segment builder.

## Packet Layout (deduced from local variable slots)

```text
offset   size    field
------   -----   ----------------------------------------
+0       4       sequence id / sender ref     (*param_1 from caller)
+4       16      WorkPath part 1              (memcpy from param_2+4)
+20      16      WorkPath part 2              (local_30 / zero-init)
+36      20      framing/padding              (gap to reach size 0x38)
TOTAL    56 bytes
```

The 32 bytes of WorkPath data are an **opaque** byte sequence. They
encode:

```text
WorkPath encoded fields (interpretation; not yet byte-mapped):
  - structName       e.g. "work" / "charaWork" / "playerWork"
  - slotCategory      e.g. "parameterSave" / "battleSave" / "eventTemp"
  - fieldIdx0         (0-based; was 1-based in Lua call, -1 adjustment)
  - fieldIdx1         (sub-index for nested arrays)
```

The actual byte format is built by `FUN_0070aa10` / `FUN_0070aaa0`
(WorkPath constructors); these were not decompiled in this pass.
Whatever the format, the server's job is to **walk the path,
resolve it to a binding-id internally, and apply the update**.

## Channel: Zone

Confirmed: `Application_dispatchToZoneClient` (0x004d6d30) fetches
the `ZoneClient` from global state at offset 0x174ec and forwards
to `ZoneClient_dispatchOutbound`. So opcode 0x12f goes over the
**Zone channel** (consistent with the prior framing finding —
`finding_ipc_channel_framing.md`).

## The Read/Write Asymmetry

Re-emphasizing the model:

```text
Direction          Format        Mechanism
-----------------  ----------    -----------------------------
CLIENT → SERVER     STRING path  _updateWork()/lua_updateWork_impl
                                  builds WorkPath with structName +
                                  slotCategory strings, fieldIdx0/1
                                  shorts. Server walks path.

SERVER → CLIENT     binding id   Server pushes "field X updated"
                                  with a UINT binding id (e.g. 0x3f2
                                  = 1010 = hp[1]) and the new value.
                                  Client uses Actor_readBindingUInt /
                                  Actor_readBindingBool /
                                  Actor_readBindingFloat which use
                                  the binding id as table key into
                                  actor+0x214.
```

The asymmetry makes sense:
- **Write side (input rare)**: Player UI toggles a flag, sends one
  string-based "set this thing" request. Bandwidth cost negligible
  because rare.
- **Read side (broadcast frequent)**: Every visible actor's HP
  ticks 3x/second. String paths would be wasteful; binding-id is
  compact (2 bytes vs ~30-50 bytes per path string).

So **two related but distinct wire formats** for the same conceptual
operation. The server needs both:
- A handler for opcode 0x12f (client write) that parses strings.
- A sender that pushes opcode <TBD> (server broadcast) with binding
  ids.

## What Server Needs to Implement

```text
INBOUND HANDLER (opcode 0x12f):
  Receive 56-byte packet on Zone channel
  Parse:
    +0   sequence/sender id
    +4   WorkPath bytes (32 bytes; format TBD)
  Walk the WorkPath to resolve (struct, slot, field_path)
  Optional: server-side validation
  Apply update to its world state for the actor
  Broadcast SERVER → CLIENT updates to all viewers
    (using the binding-id format, NOT echoing this opcode)

OUTBOUND BUILDER (binding-id format, opcode TBD):
  For each subscriber to the modified actor's field
    Build a (actorId, bindingId, value, type) packet
    Send via Zone channel
```

## Assessment

```text
Confirmed:
  - Wire opcode 0x12f (303) is the work-sync update packet from
    client to server.
  - Packet size is exactly 56 bytes (0x38).
  - Travels over Zone channel.
  - Payload includes a WorkPath struct (32 bytes) with the path
    encoded as strings + integer field indices.

Likely (High):
  - The WorkPath bytes at offset +4 and +20 are the path component
    strings + indices in a known format. Need to walk FUN_0070aa10
    + FUN_0070aaa0 to get the exact byte layout.
  - The 20-byte gap from +36 to +56 is reserved (zero-padded) for
    future expansion / forward compatibility.

Likely (Medium):
  - The server's broadcast format (server → client field updates)
    uses a different opcode -- probably consecutive to 0x12f
    (0x130? 0x131?). Need to grep for binding-id constants used in
    packet-build paths in the EXE inbound dispatch.
  - The sequence id at +0 is for client-side request tracking
    (response correlation, retry, etc.).

NOT YET CONFIRMED:
  - The exact WorkPath byte layout. Strings could be inline
    (length-prefixed UTF-8) or interned (hash references to a
    server-side string table).
  - The opcode for "server pushes binding-id update to client".
    Almost certainly exists but not yet pinned.
```

## Ghidra Annotations Made

```text
Renamed:
  0x0075e770  FUN_0075e770  ->  WorkSync_buildAndSendPacket_opcode_0x12f
  0x006cea20  FUN_006cea20  ->  WorkPath_joinAsString
  0x007838c0  FUN_007838c0  ->  UpdateQueue_pushEntry
  0x00767fc0  FUN_00767fc0  ->  WorkSync_dispatchOrEnqueue
  0x00767c00  FUN_00767c00  ->  WorkSync_serializePayloadAndSend
  0x004d6d30  FUN_004d6d30  ->  Application_dispatchToZoneClient

Decompiler comments added at:
  0x0075e770  (the wire constants + layout deduction)
  0x004d6d30  (the global ZoneClient slot at +0x174ec)
```

## Open Threads

```text
1. Decompile FUN_0070aa10 / FUN_0070aaa0 (WorkPath constructors) to
   recover the exact byte format of the 32-byte WorkPath payload.

2. Find the server-broadcast opcode. The PacketProcessor's
   "_onReceiveDataPacket" Lua handler walks an inbound packet and
   dispatches by type. The C++ side of that dispatch should have
   a switch on opcode that includes the "binding-id field update"
   case. Grep for the literal 0x12f or for callers that use
   Actor_readBindingUInt with a packet-derived bindingId.

3. The 20-byte tail of the 0x12f packet (offset +36 to +56) is
   unexplained. Either reserved/padding, or carries a per-packet
   type discriminator + payload value for SET operations
   (vs the path-only DELETE operation).
```
