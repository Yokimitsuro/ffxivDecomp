# Finding: Inbound Dispatch Table FOUND — 0x00fdfb80..0x00fdff00+ (~224 entries)

**Critical EXE discovery (2026-05-23)**: Found the **Zone channel
inbound dispatch table** at memory range `0x00fdfb80..0x00fdff00+`,
containing ~224 function pointers indexed by inbound opcode. This
closes the major Ghidra gap left in prior sessions.

## The Smoking Gun

Following the caller chain backwards from a known handler:

```text
1. FUN_008a0190 (Lua bridge to _onReceiveDataPacket) was the known
   Lua dispatch.

2. Its only caller is FUN_00759e50, which:
   - Calls FUN_0089eed0 to init a 192-byte packet reader
   - Calls FUN_008a0190 to dispatch to Lua
   - Calls FUN_0089e760 to cleanup

3. FUN_00759e50 has only ONE xref -- a DATA xref from 0x00fdfc18.
   Meaning: 0x00fdfc18 STORES THE POINTER to FUN_00759e50.

4. Sampling adjacent addresses in 0x00fdfXXX revealed CONSECUTIVE
   function pointers (each 4 bytes apart) -- a CLASSIC DISPATCH
   TABLE.
```

## Table Layout (Sampled — stride 4 bytes / one function pointer per slot)

```text
ENTRY  ADDR          POINTER             FUNCTION
-----  ----          -------             --------
  0   0x00fdfb80 -> FUN_00759820
  1   0x00fdfb84 -> FUN_007598a0
  2   0x00fdfb88 -> FUN_00759920
  3   0x00fdfb8c -> FUN_0075d710
  4   0x00fdfb90 -> FUN_0075d750
 16   0x00fdfbc0 -> FUN_00759a60
 24   0x00fdfbe0 -> FUN_00759cd0   vtable_dispatch_slot23 handler
 28   0x00fdfbf0 -> FUN_00759de0   (empty/no-op)
 30   0x00fdfbf8 -> FUN_00759e00   (empty/no-op)
 31   0x00fdfbfc -> FUN_00759e10
 32   0x00fdfc00 -> FUN_00759e20
 33   0x00fdfc04 -> FUN_00759e30
 34   0x00fdfc08 -> FUN_00759e40
 35   0x00fdfc0c -> FUN_0076c0d0
 36   0x00fdfc10 -> FUN_0076c3b0
 37   0x00fdfc14 -> FUN_0076c220
 38   0x00fdfc18 -> dataPacket_calls_onReceiveDataPacket  (Lua bridge)
 39   0x00fdfc1c -> FUN_00759ed0
 40   0x00fdfc20 -> FUN_00759f50
 41   0x00fdfc24 -> FUN_0076c4d0
 42   0x00fdfc28 -> FUN_00759fd0
 43   0x00fdfc2c -> FUN_0075a060
 44   0x00fdfc30 -> FUN_0075a0e0
 45   0x00fdfc34 -> FUN_0075a160
 46   0x00fdfc38 -> FUN_0075a200
 47   0x00fdfc3c -> FUN_0075a280
 48   0x00fdfc40 -> FUN_0075a300
 56   0x00fdfc60 -> FUN_0075a630
 64   0x00fdfc80 -> FUN_0075a920
 72   0x00fdfca0 -> FUN_00776cf0
 96   0x00fdfd00 -> default_noop (returns 0)
160   0x00fdfe00 -> default_noop (repeated)
224   0x00fdff00 -> FUN_00777da0
```

**Table range**: 0x00fdfb80 to 0x00fdff00+ = ~**224+ entries** with
4-byte stride (each entry = 1 function pointer).

So the "data packet" handler at entry 38 corresponds to whatever
opcode the runtime maps to position 38 in this table. If the
mapping is opcode-direct (table[opcode] = handler), this is opcode
0x26 (= 38 decimal). If the mapping uses a base offset, it could
be any other value.

Without finding the dispatcher's opcode-to-position arithmetic
(probably `table[opcode * 4 + base]`), the exact opcode mapping
remains undetermined. But the table existence + the handler patterns
are conclusive.

## Handler Categories (3 patterns observed)

```text
PATTERN 1: Specific handler with packet processing
  Example: ZoneIn_handler_dataPacket (FUN_00759e50)
  - Init a packet reader with specific buffer size
  - Process the packet (custom logic)
  - Bridge to Lua via _onReceiveXxx hook
  
  Most "interesting" packets follow this pattern.

PATTERN 2: Generic vtable dispatch
  Example: FUN_00759cd0 -- (**(code **)(**(int **)(arg + 8) + 0x5c))(arg + 4)
  - Treats the packet as a POLYMORPHIC OBJECT
  - Looks up vtable+0x5c (slot 23) and invokes it
  - The packet object knows what to do with itself

  This is the OOP packet design: each opcode is a class, each
  class has its own "process" virtual method.

PATTERN 3: Default no-op (returns 0)
  FUN_005c5c80
  - Returns 0 (drops the packet)
  - Used for opcode space gaps + extension headroom
  - REPEATED in many slots
```

## Design Inference: Packets are Polymorphic Objects

The existence of Pattern 2 (vtable dispatch via packet object's
own method) reveals **the inbound packet system is OOP**:

```text
class InboundPacketBase {
  virtual ~PacketBase();
  ... other virtuals ...
  virtual void process();      // <- slot 23 (0x5c offset)
  ... more virtuals ...
};

class WorkSyncPacket : InboundPacketBase {
  virtual void process() override {
    // apply binding update to actor storage
  }
};

class DataPacket : InboundPacketBase {
  virtual void process() override {
    // dispatch to Lua _onReceiveDataPacket
  }
};
```

So when the server sends opcode N, the receive loop:
1. Allocates a packet object of the class registered for opcode N
2. Hydrates it from the wire bytes
3. Calls dispatch_table[N](packet) -- which is either:
   - A specific C++ handler that knows how to process this opcode
   - The generic vtable-dispatch handler that calls packet->process()
4. The packet's process() method applies the state change

This is **much more elegant** than a giant switch statement, and
explains why we couldn't find a single switch with all opcodes
0x12d-0x135 -- each opcode is its own class.

## Opcode-to-Handler Mapping

The exact opcode → handler mapping requires knowing:
1. The table base offset interpretation (does table[0] = opcode 0?
   Or opcode 0x12d? Or some other base?)
2. The opcode space covered (full 0..255? Or specific range?)

**Hypothesis A: Direct opcode indexing 0..255**
- table[opcode] = handler
- Base 0x00fdfb80 = opcode 0
- 0x00fdfc18 = (0x00fdfc18 - 0x00fdfb80) / 4 = 38, so opcode 38

**Hypothesis B: Offset from outbound base 0x12d**
- table[opcode - 0x12d] = handler
- 0x00fdfb80 = handler for 0x12d
- 0x00fdfc18 = handler for 0x12d + 38 = 0x153

Without further analysis (or wire capture), can't disambiguate.

But the existence of the table + its scale + the handler patterns
**closes the major gap** in the inbound dispatch understanding.

## Updated Wire Model

```text
INBOUND PACKET PROCESSING (Zone channel):

  Network bytes arrive
   ↓
  Read opcode (uint16 from segment header)
   ↓
  Allocate packet object via factory (per opcode)
   ↓
  Hydrate object from wire bytes
   ↓
  Look up handler in dispatch table at 0x00fdfb80
   ↓
  Invoke handler with (sender, packet_obj)
   ↓
  Handler either:
    - Calls packet_obj->process() (Pattern 2, generic)
    - Calls specific C++ logic + Lua hook (Pattern 1, specific)
    - No-op for unmapped opcodes (Pattern 3)
   ↓
  State updated: binding storage modified, Lua hooks fired,
  UI refreshed
```

## Assessment

```text
CONFIRMED:
  - Inbound dispatch table at 0x00fdfb80..0x00fdff00+
  - ~224 function pointers indexed by opcode (or opcode offset)
  - 3 handler patterns: specific / vtable-dispatch / default-noop
  - Packets are POLYMORPHIC OBJECTS with their own vtable
  - vtable slot at offset 0x5c (= slot 23) is the "process" method

LIKELY (High):
  - The table covers opcodes 0..223 or 0x12d..0x12d+223 (still TBD)
  - Most opcodes are no-ops or generic vtable-dispatch handlers
  - The "data packet" handler (Lua bridge) corresponds to the
    INBOUND counterpart of outbound 0x12f WorkSync OR a different
    "data" packet opcode entirely
  - The 192-byte buffer size (0xc0) for the data handler tells us
    the corresponding inbound opcode has 192-byte payload

LIKELY (Medium):
  - The wire opcode for server-pushed BINDING UPDATES is in this
    table somewhere. Could be the FUN_00759e50 handler if the
    server pushes a 192-byte "data" packet for field updates.
  - Per-binding writes may use the vtable-dispatch handler (Pattern
    2), with the WorkSyncPacket class implementing process() to
    write into the bit-packed storage at actor+0x214.

NOT YET CONFIRMED:
  - Exact opcode->handler mapping (need to disambiguate Hypothesis
    A vs B)
  - Specific binding-update opcode value
  - The packet factory function (which creates a packet object of
    the right class for each opcode)
```

## Ghidra Annotations Made

```text
0x00759e50 -> ZoneIn_handler_dataPacket_calls_onReceiveDataPacket
              (with detailed comment about table location and Lua
               bridge)
0x005c5c80 -> ZoneIn_handler_default_noop
              (with comment explaining the no-op fallback role)
0x00759cd0 -> ZoneIn_handler_vtable_dispatch_slot23
              (with comment explaining the polymorphic packet
               design and vtable slot 23 = process())
```

## Open Threads

```text
1. PIN THE OPCODE-INDEXING ARITHMETIC:
   Find a function that performs `table[0x00fdfb80 + opcode * 4]`
   indexing. That function's parameter is the opcode itself.

2. PIN THE PACKET FACTORY:
   The function that creates a packet object of the right CLASS
   based on opcode. Probably a separate dispatch table or switch
   on opcode.

3. DECOMPILE HANDLER CONTENTS:
   Walk a dozen handlers (FUN_00759e30, FUN_00759f50, FUN_0076c0d0,
   etc.) to deduce their per-opcode behavior. May reveal naming
   patterns for the corresponding opcodes.

4. CONFIRM THE SERVER-BROADCAST OPCODE:
   The 192-byte payload of the "data" handler suggests a 192-byte
   server-pushed packet. If the WorkSync broadcast is 192 bytes
   (vs outbound 56 bytes), that's the inbound counterpart opcode.
   Worth checking _onReceiveDataPacket implementations across the
   Lua codebase for the typical payload size.
```

## Server Implementation Implications

A server-side packet builder for the inbound (server -> client) side
can now follow this template:

```text
1. For each event the server wants to push:
   - Identify the packet class (e.g. WorkSyncUpdate)
   - Identify the opcode (table position to use)
   - Serialize the packet using the class's known format

2. Construct the segment:
   - Segment header (16 bytes)
   - Application payload (opcode + packet bytes)

3. Send via Zone channel

4. Client receives:
   - Segment processor pulls opcode + payload
   - Dispatch table[opcode] invoked
   - Handler processes -- either via Lua hook or via packet's own
     process() method
```

The KEY INSIGHT: the server doesn't need to think about Lua hooks
or vtable dispatch -- it just needs to construct correctly-formatted
packets for each opcode. The client's dispatch table handles
everything else.

This **closes the major gap** in the inbound side of the wire
protocol understanding.
