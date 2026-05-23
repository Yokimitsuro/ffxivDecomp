# Finding: Complete Zone Channel Outbound Opcode Roster

Massive opcode discovery. By tracing all callers of
`Application_dispatchToZoneClient` (the function that fetches the
`ZoneClient` from Application+0x174ec and forwards to
`ZoneClient_dispatchOutbound`), the **complete set of application-
layer outbound opcodes** on the Zone channel is now mapped.

Date: 2026-05-23. Discovered after walking the `_updateWork` wire
chain.

## The Opcode Roster (application-layer over Zone)

```text
opcode   size    function name                                    notes
------   -----   ---------------------------------------------    --------------------
0x12d    200B    ZoneOut_sendScriptError_opcode_0x12d            client script error
                 (FUN_0076e270)                                   report; chunked at 0x80 B
0x12e    104B    ZoneOut_send_opcode_0x12e_104B                  64 bytes variable payload
                 (FUN_0075e670)                                   + 16 dwords of param_5
0x12f    56B     WorkSync_buildAndSendPacket_opcode_0x12f        WORK-SYNC UPDATE (the
                 (0x0075e770)                                     string-path-based field
                                                                  write -- documented in
                                                                  finding_worksync_wire_
                                                                  opcode_0x12f.md)
0x130    32B     ZoneOut_send_opcode_0x130_32B_variantA          2 dword args + 2 zero
                 (FUN_0075e860)                                   pads
                 ZoneOut_send_opcode_0x130_32B_variantB
                 (FUN_0075e8d0)                                   alt variant with extra
                                                                  payload (param_1 extends)
0x131    24B     ZoneOut_send_opcode_0x131_24B_byte              single byte payload at
                 (FUN_0075ea50)                                   +8
0x132    24B     ZoneOut_send_opcode_0x132_24B_byteUshort        byte + ushort payload
                 (FUN_0075eac0)
0x133    56B     ZoneOut_send_opcode_0x133_56B                   SIMILAR shape to 0x12f
                 (FUN_0075e950)                                   (same 56B size + 32B
                                                                  variable payload).
                                                                  Likely the WRITE
                                                                  COUNTERPART or a
                                                                  related write opcode.
0x134    40B     ZoneOut_send_opcode_0x134_40B_withNonce         40 bytes with random
                 (FUN_0075eba0)                                   15-char mixed-case
                                                                  nonce + hash via
                                                                  FUN_00d3aae0. CHALLENGE
                                                                  / ANTI-TAMPER packet.
0x135    24B     ZoneOut_send_opcode_0x135_24B_dword             single dword payload
                 (FUN_0075ecd0)
```

## The "Large Checksummed" Family

Four functions build large packets (~2208 bytes per local_940 buffer)
using `FUN_00776760` (likely the packet builder) and `FUN_00d3aae0`
(hash/checksum). Each uses a different INBOUND opcode (set by the
builder, not hardcoded in the caller):

```text
ZoneOut_send_large_simple              @ 0x0075e1c0   no checksum hash
ZoneOut_send_large_checksummed_v1      @ 0x0075e3a0   with FUN_00d3ab60+aae0 hash
ZoneOut_send_large_checksummed_v2      @ 0x0075e510   variant of v1
ZoneOut_send_large_checksummed_v3      @ 0x0075e230   variant of v1 with byte cond
```

These probably correspond to:
- World state initial push (~2 KB compressed per actor)
- Inventory bulk push
- Quest journal full sync
- Other "large initial data load" packets

The exact opcodes for these are encoded inside `FUN_00776760` and
need further analysis. The pattern suggests opcodes in the 0x1XX or
0x2XX range with the same general 2 KB payload.

## Cross-Reference with Segment-Level Opcodes

The opcodes 0x12d-0x135 are application-layer (inside segment type 3
IPC). For comparison, the segment-level opcodes (from
`ZoneClient_mainLoopTick`):

```text
segment opcode  purpose
--------------  --------------------------------------
0x01            handshake / latency ping (40 B)
0x02            initial handshake (40 B)
0x03            large state push (560 B)
0x04            disconnect ack (24 B)
0x06            heartbeat (24 B; session id payload)
0x0e / 0x11     disconnect notice
```

So the wire stack has two layers:
- **Segment-level opcodes** (0x01-0x11): protocol housekeeping
- **Application-level opcodes** (0x12d-0x135): game state mutations

## Implications for Server

For a server, the outbound opcodes a CLIENT can send are now
ENUMERATED. The server only needs to implement handlers for these
~13 opcodes:

```text
Mandatory for basic gameplay:
  0x12f  work-sync update (string path-based)
  0x130  short state changes (2 dwords)
  0x131  byte payload (toggle-style action?)
  0x132  byte + ushort (compound state)
  0x133  56-byte payload (similar to 0x12f)

Diagnostic / nice-to-have:
  0x12d  script error report (200B chunked; useful for debug logs)
  0x12e  104-byte payload
  0x134  challenge/nonce (anti-tamper; can be no-op'd)
  0x135  dword payload

Bulk transfer (server -> client; opcode discovered inside builder):
  ZoneOut_send_large_*  (~2 KB packets; initial state push)
```

## Assessment

```text
Confirmed:
  - 13+ application-layer outbound opcodes identified in the Zone
    channel (0x12d-0x135 range plus the "large" family).
  - All hardcode their opcode + size in a local struct passed to
    Application_dispatchToZoneClient.
  - Sizes range from 24 bytes (small state toggles) to 2 KB
    (bulk state push).
  - The 0x134 packet includes a random 15-char nonce + hash --
    anti-tamper / challenge mechanism.
  - The 0x12d packet is CHUNKED: long error messages split into
    multiple 200B packets, each sent separately.

Likely (High):
  - The opcode range 0x12d-0x135 is the "GameState" outbound
    family. Other ranges (0x100-0x12c, 0x136+) probably hold other
    subsystems (chat, social, etc.).
  - The "large checksummed" family is for initial state loads
    (zone enter, inventory full sync). Opcodes embedded in
    FUN_00776760.
  - The 0x12e and 0x133 packets (104B and 56B with variable
    payload) are LIKELY the OPPOSITE DIRECTION of common requests
    -- e.g. client sends 0x12f (action request), client also sends
    0x133 with the result of completing the action.

Likely (Medium):
  - The 0x130/0x131/0x132 packets are micro-events like equipment
    swap, weapon toggle, sit-down. Their tiny size suggests they
    just signal a state change without carrying much data.
  - The 0x134 anti-tamper packet probably runs periodically (every
    N seconds) to verify the client hasn't been spoofed.

NOT YET CONFIRMED:
  - The INBOUND opcode space (server -> client) -- not yet mapped.
  - The exact semantics of each opcode (what action/state each
    triggers). Would require tracing back to which Lua function
    calls each sender.
  - The hash algorithm in FUN_00d3aae0 used by 0x134 -- likely
    MD5 or CRC-32.
```

## Ghidra Annotations Made

13 functions renamed with their opcode + size:

```text
0x0076e270  ZoneOut_sendScriptError_opcode_0x12d
0x0075e670  ZoneOut_send_opcode_0x12e_104B
0x0075e860  ZoneOut_send_opcode_0x130_32B_variantA
0x0075e8d0  ZoneOut_send_opcode_0x130_32B_variantB
0x0075e950  ZoneOut_send_opcode_0x133_56B
0x0075ea50  ZoneOut_send_opcode_0x131_24B_byte
0x0075eac0  ZoneOut_send_opcode_0x132_24B_byteUshort
0x0075eba0  ZoneOut_send_opcode_0x134_40B_withNonce
0x0075ecd0  ZoneOut_send_opcode_0x135_24B_dword
0x0075e1c0  ZoneOut_send_large_simple
0x0075e3a0  ZoneOut_send_large_checksummed_v1
0x0075e510  ZoneOut_send_large_checksummed_v2
0x0075e230  ZoneOut_send_large_checksummed_v3
```

## Open Threads

```text
1. Decompile FUN_00776760 to recover the opcode + size for the
   "large checksummed" family. Probably 4 distinct opcodes for
   the v1/v2/v3 variants.

2. Find the CALLERS of each ZoneOut_send_opcode_0x12X function --
   they reveal which Lua/game action triggers each opcode. E.g.
   the caller of 0x131 (byte payload) probably maps to a specific
   "toggle X" Lua command.

3. The INBOUND opcode space (server -> client packets, including
   the field-update broadcast counterpart to 0x12f) is still
   completely unmapped. Strategy: examine the inbound receive
   loop in ZoneClient_mainLoopTick to find the application-layer
   dispatcher.

4. The 0x12d "ScriptError" chunked report is a great DEBUGGING
   target -- if reproduced server-side, the server can capture
   client-side Lua exceptions for debugging during integration.
```
