# Finding: Opcode 0x18d -- Session-Gated Multi-Record Batch State Push (up to 255 records of 40B)

**The most complex inbound opcode handler** in the 0x143-0x1a8 range.
Opcode 0x18d carries a **multi-record batch payload** — up to 255
records of 40 bytes each — gated by session readiness and dispatched
through a session-bound subsystem.

This is likely the wire format for **party member list update**,
**combat log batch**, or similar **multi-entity state push** that
needs atomic application.

## 1. The two-function handler

```text
ZoneIn_opcode_0x18d_sessionGated_bufferOrDirect_dispatch  (0x00575550)
   ↓ if session ready (FUN_00575400 check):
   ↓   forward directly to FUN_006c1570(this+0x18, header, payload)
   ↓ else:
   ↓   buffer for later processing (FUN_006bfce0 + FUN_00573f10)
   ↓
SessionBatch_processMultiRecord_count_in_payload_0xa4_40Bperrecord
   (0x0055cf70)
   ↓ called via session subsystem chain
```

## 2. Wire packet 0x18d format

```text
Payload layout (passed to FUN_0055cf70 as param_1):
  +0x00  uint32 field_a              header field 1
  +0x04  uint32 field_b              header field 2  
  +0x08  uint32 field_c              header field 3
  +0x0c  ?                           ?
  +0x10  ?                           ?
  +0x14  ?                           ?
  +0x18  record[0] starts here       40 bytes per record (10 dwords)
  ...    record[1], record[2], ...
  +0x294 BYTE = count                payload[+0xa4 dwords] = byte count
                                     (max 255 records due to byte width)

PER-RECORD LAYOUT (40 bytes = 10 dwords):
  field[-2]   used    record id?
  field[-1]   skipped reserved/padding?
  field[ 0]   used    primary value
  field[ 1]   used    secondary value
  field[ 2]   skipped reserved/padding?
  field[ 3]   used    tertiary value
  field[ 4]   used    quaternary value
  field[ 5]   used    quinary value
  field[6-9]  ?       remaining 4 dwords -- unclear use

Per record, 6 of 10 dwords are extracted into a destination
slot of stride 30 bytes (FUN_0055cf70 copies into this+0x2c+(N*0x1e)).
```

## 3. Processing flow

```c
SessionBatch_processMultiRecord(this, payload, callback_target):
  // copy header fields
  this[+0x08] = payload[0]
  this[+0x0c] = payload[1]
  this[+0x10] = payload[2]
  
  // read count
  count = payload[0xa4] (byte)
  this[+0x14] = count
  
  // process each record
  for (N = 0; N < count; N++):
    record_src = payload + 6 + (N * 10)        // 40-byte stride source
    record_dst = this + 0x2c + (N * 0x1e)       // 30-byte stride dest
    
    copy 6 dwords from record_src to record_dst (with reordering)
    
    FUN_00573fc0(callback_target, &record_dst, ...)   // per-record callback
  
  // set multi-record flag
  if (this[+0x798] == 0):
    this[+0x798] = (count > 1)
  
  // notify downstream
  notify_target = FUN_004d7620(session)
  if (notify_target):
    FUN_00671400(notify_target, this)
```

## 4. Semantics (inferred from architecture)

```text
Session-gated handling suggests state that's only valid in an
established session context.

Multi-record batch (up to 255 records) at 40 bytes each is consistent
with bulk pushes during:
  
  PARTY MEMBER LIST UPDATE:
    - Typical party: 1-8 members
    - Each member record: id + name hash + level + class + position + ...
    - 6 dwords (24 bytes) ≈ enough for compact member state
    
  COMBAT LOG BATCH:
    - Multiple events at once (damage, heal, miss, etc.)
    - 24 bytes per event ≈ (source, target, action, value, flags, time)
    
  QUEST LOG BATCH UPDATE:
    - All active quest states at once
    - 24 bytes per quest ≈ (id, progress, vars, flags)
    
  INVENTORY BATCH:
    - Multiple items pushed together
    - Probably uses different opcode (per ItemBase finding)
  
  LINKSHELL MEMBER LIST:
    - Similar to party but larger membership (up to 64-128)

Most likely candidate based on:
  - Session gating (works only after login complete)
  - 6-dword stride (compact per-entry)
  - Single-batch dispatch (atomic update)
  - Up to 255 entries (fits 100+ entities)

→ PARTY MEMBER LIST or LINKSHELL MEMBER LIST is most probable.

Server-side: should batch member updates into 0x18d packets rather
than sending individual updates per member.
```

## 5. Server implementation priority

```text
PRIORITY: HIGH

Implementation needed for:
  - Initial party formation push (zone enter while in party)
  - Party member join/leave events (atomic re-push)
  - Linkshell login member list
  - Any other multi-entity batch the server tracks

Without 0x18d, client won't see:
  - Party list in UI (no members visible)
  - Linkshell roster (offline state)
  - Possibly: combat log entries that batch
```

## 6. Renames + comments applied

```text
0x00575550  FUN_00575550  → ZoneIn_opcode_0x18d_sessionGated_bufferOrDirect_dispatch
0x0055cf70  FUN_0055cf70  → SessionBatch_processMultiRecord_count_in_payload_0xa4_40Bperrecord

Plus decompiler comment at 0x0055cf70 documenting full layout +
processing flow.
```

## 7. ALSO documented: opcode 0x193 internals (SYSTEM ERROR/STATUS)

While decompiling related handlers, the internals of opcode 0x193
(system error/status dispatcher) became clearer:

```text
The 22 codes of opcode 0x193 dispatch to:

  Codes 0x00-0x0F (16 codes):
    FUN_0075f3e0(this[+4]+0x10c, code, value)
    -- Writes value to ARRAY SLOT [code] in error array
    -- Different slots probably encode different error categories:
       0x00 = login/auth error
       0x01 = world full
       0x02 = action denied
       0x03 = inventory full
       0x04 = ... etc. (16 slots = 16 error categories)
  
  Code 0x10: FUN_0075d210 → stores at this+0x10 (specific error setter)
  Code 0x11: FUN_0075d230 → stores at this+0x14 (variant 2)
  Code 0x12: FUN_0075d250 → stores at this+0x18 (variant 3)
  
  Code 0x13: BUILD LOCALIZED ERROR STRING using UTF-16 templates
             (Japanese phrase fragments), call message pool to display
  
  Code 0x14: System_broadcastSubsystem_preCancelHooks
             (already-named -- cancel pending subsystem operations)
  
  Code 0x15: FUN_00576020 (cancel hook cleanup if certain conditions)
  
  Code 0x16: FUN_0075d270 → stores at this+0x1c (variant 4)
```

So opcode 0x193 is the **SYSTEM ERROR/STATUS RESPONSE CHANNEL**:
- 16-slot error array for categorized errors
- 4 specific error type setters (codes 0x10-0x12, 0x16)
- 1 localized string builder (code 0x13)
- 2 cancel-hook triggers (codes 0x14, 0x15)

Server uses this to push:
- Login/auth failures
- Action rejections
- World status (full, maintenance)
- Localized server messages
- Cancel requests to client subsystems

**Server implementation priority for 0x193: HIGH** — needed for any
server response that can't be silently accepted (errors, rejections,
system notifications).

## 8. Confidence

```text
Confirmed:
  - FUN_00575550 is opcode 0x18d handler (xref'd from Zone main dispatcher)
  - FUN_0055cf70 is the batch multi-record processor
  - 40 bytes per record (10 dwords) × up to 255 records
  - Session-gated dispatch (buffer if not ready, forward if ready)
  - 6 of 10 dwords per record extracted to 30-byte destination stride
  - Per-record callback via FUN_00573fc0
  - 0x193 has 22 codes total (16 slot-indexed + 6 specific actions)

Likely (High):
  - 0x18d carries PARTY MEMBER LIST or LINKSHELL MEMBER LIST batches
  - 16 error slots in 0x193 each map to specific error categories
  - The 6-dword-per-record format encodes compact entity state
    (id + name_hash + 4 status fields)

Speculative:
  - The 4 skipped dwords per record (record[-1], [2], [6-9]) might be
    server-internal tracking fields stripped before send
  - Code 0x13 of 0x193 displays Japanese-localized error templates
    (UTF-16 strings "k0W0~0W0_0" pattern observed)
```

## 9. Cross-references

- `finding_zone_inbound_game_opcodes_0x143_0x1a8_bridge_pattern.md`
  -- the parent finding for the opcode range
- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the main inbound dispatcher
- `finding_appendMessagePool_thunk_command_updater_dispatch.md`
  -- the message pool that 0x193 code 0x13 writes to

## Commit suggestion

```
docs(re/exe): opcode 0x18d = session-gated multi-record batch state push (up to 255x40B records) + 0x193 internals (22 codes: 16 error slots + 6 specific actions)
```
