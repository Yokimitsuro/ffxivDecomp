# Finding: Packet Dispatch Chain — RTTI + PacketRequest Correlation

Documents the additional EXE pieces of the inbound dispatch chain
discovered while searching for the opcode→handler arithmetic. The
chain involves RTTI-based dynamic_cast checks + PacketRequest
correlation (matching server responses to client-side pending
requests).

## RTTI Class Hierarchy Discovered

```text
String at 0x012bf788:
  .?AVPacketRequestBase@Group@Client@Script@Lua@Application@@

String at 0x012bf980:
  .?AVPacketProcessor@Group@Client@Script@Lua@Application@@

String at 0x012bf790:
  .?AVPacketRequestBase@Group@Client@Script@Lua@Application@@
  (alternate symbol)

PacketBufferTmpl strings (per-channel + direction):
  0126a268  PacketBufferTmpl<TLobbyProtoDown, ...>   inbound lobby
  0126a320  PacketBufferTmpl<TZoneProtoDown, ...>    inbound zone
  0126a398  PacketBufferTmpl<TChatProtoDown, ...>    inbound chat
  0126a2e0  PacketBufferBase                         common base
  01318ed8  PacketBufferTmpl<TLobbyProtoUp, ...>     outbound lobby
  0131dca0  PacketBufferTmpl<TZoneProtoUp, ...>      outbound zone
  01322fc0  PacketBufferTmpl<TChatProtoUp, ...>      outbound chat
```

So the network layer has **6 PacketBufferTmpl specializations**
(per channel × direction), plus the common base. The Inbound zone
class `PacketBufferTmpl<TZoneProtoDown>` is the one we care about
for inbound dispatch.

## Dynamic Cast Chain — Request Correlation

`FUN_006c05e0` performs **request-by-id lookup**:

```c
function lookupPacketRequest(this, param_1):
  // Walks an internal container (ring buffer / hash table)
  for each entry in this.container:
    if entry.field_0x10 == *param_1 and entry.field_0x14 == param_1[1]:
      // Found match on (id_low, id_high) -- 8-byte composite key
      casted = dynamic_cast<PacketRequestBase>(entry,
                                                 EntryBuilderBase);
      if casted:
        result = (*casted->vtable[0x34])();  // slot 13: process
        return result
  return 0
```

So:
- The container holds `EntryBuilderBase` objects
- We dynamic_cast to `PacketRequestBase` if applicable
- The matching key is an 8-byte composite (probably request_id +
  sequence_number)
- vtable+0x34 (slot 13) of PacketRequestBase is "process" / "fulfill"

This is **the client-side request tracking system**: when client
sends a request, it stores a PacketRequest in this container; when
server responds, the response is correlated by id and the request's
process() method is invoked.

## Caller Chain

```text
FUN_006c05e0  lookupPacketRequest_byId
  ↑ called by ↑
FUN_006c3630  (higher dispatcher; checks hash table first,
                falls back to linear scan via FUN_006c05e0)
  ↑ called by ↑
FUN_006c37e0  (another wrapper)
  ↑ called by ↑
... (continues into the higher network stack)
```

`FUN_006c3630` first tries a fast hash lookup (`FUN_006d1020`) and
falls back to the linear scan if not found. Standard request
correlation pattern.

## The Two-Path Inbound Dispatch

The inbound packet processing now appears to have **two parallel
paths**:

```text
PATH A: REQUEST/RESPONSE (Pending Request Correlation)
  - Client previously sent a request via _executeCommand / etc.
  - PacketRequest stored in container with id
  - Server responds with id
  - Inbound dispatcher correlates id -> PacketRequest
  - PacketRequest's process() method (vtable+0x34) fires
  - Used for: command results, query responses, sync acknowledgments

PATH B: PUSH (Server-Initiated Events)
  - Server pushes state change unilaterally (no pending request)
  - Inbound dispatcher looks up handler in table at 0x00fdfb80
  - Handler runs (specific or vtable-dispatch on packet object)
  - Used for: actor sync updates, NPC actions, chat messages
```

So opcodes 0x12d-0x135 (the outbound roster) may CORRESPOND to a
RESPONSE pattern via Path A, while genuine server-pushed events
use Path B with the table at 0x00fdfb80.

## Updated Wire Model

```text
WIRE INBOUND PROCESSING:

  Packet arrives on Zone channel
   ↓
  PacketBufferTmpl<TZoneProtoDown> handles the receive
   ↓
  Extracts opcode from segment header (offset +2, uint16)
   ↓
  ┌─ Is this a RESPONSE to a pending request?
  │  YES -> Path A:
  │   - Look up by (id_low, id_high) in PacketRequest container
  │   - Found? dynamic_cast<PacketRequestBase>, call vtable[0x34]
  │   - Done.
  │
  └─ NO -> Path B:
   - Look up handler in dispatch table[0x00fdfb80 + offset]
   - Invoke handler:
     - Specific handler (e.g. dataPacket): custom logic + Lua bridge
     - Vtable-dispatch handler: call packet->vtable[0x5c] (process)
     - Default no-op: drop the packet
```

## Assessment

```text
Confirmed:
  - 6 PacketBufferTmpl specializations exist (3 channels × 2
    directions).
  - PacketRequestBase + EntryBuilderBase are RTTI-confirmed classes
    in the request correlation system.
  - PacketRequest correlation uses 8-byte composite key (id_low +
    id_high).
  - vtable slot 0x34 (slot 13) of PacketRequestBase = "process" /
    "fulfill" virtual method.
  - Two-path inbound dispatch: response correlation (Path A) +
    push handler table (Path B).

Likely (High):
  - The outbound opcodes 0x12d-0x135 send requests that get
    correlated via Path A. The corresponding server responses
    also use these opcodes (or paired response opcodes) but
    delivered via PacketRequest fulfillment, not the dispatch
    table.
  - The 0x12f outbound (WorkSync write request) gets a paired
    response via PacketRequest -- the server may NOT broadcast
    the change back to subscribers via the same packet opcode.
  - Path B (dispatch table) is for fire-and-forget server pushes:
    HP updates, chat messages, NPC say events, etc. The 224-entry
    table covers these.

Likely (Medium):
  - The high-level dispatcher (FUN_006c3630 and above) routes
    between Path A and Path B based on opcode classification or
    presence in the request container.
  - The 0x10-byte stride between consecutive PacketRequest container
    entries (this+0x14) suggests each entry is ~16-32 bytes
    including request id + state + result buffer.

Not Yet Determined:
  - The exact opcode -> handler arithmetic for the dispatch table
  - The relationship between Path A request IDs and the wire
    opcode space
  - Whether the same wire opcode can serve both Path A (response)
    and Path B (push) at different times
```

## Implications for Server Implementation

A server now has two distinct response modes:

```text
RESPONSE MODE (Path A):
  When server responds to a client request:
    Build response packet with the original request's id
      (client side will correlate via PacketRequest container)
    Send via Zone channel

PUSH MODE (Path B):
  When server initiates a state change broadcast:
    Build packet with appropriate push opcode
    Send via Zone channel
    Client's dispatch table[opcode] handles it
```

The server doesn't need to know which path is used — both go
through the Zone channel. The CLIENT decides path A vs B based on
whether the opcode/id matches a pending request.

## Open Threads

```text
1. PACKET FACTORY:
   The function that allocates a packet object of the right class
   based on opcode. Still TBD. Without it, the exact opcode ->
   class mapping is unknown.

2. PATH SPLIT DETECTION:
   The condition that routes a packet between Path A (correlation)
   and Path B (table dispatch). Probably checks if the opcode
   appears in the request container's pending-id set.

3. OPCODE-TO-TABLE-POSITION ARITHMETIC:
   The exact formula table[0x00fdfb80 + f(opcode)*4] -- the f()
   may be opcode-direct, opcode-minus-base, or opcode-from-class-id.
```
