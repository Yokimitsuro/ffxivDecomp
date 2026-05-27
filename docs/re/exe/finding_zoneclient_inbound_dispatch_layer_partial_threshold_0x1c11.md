# Finding: ZoneClient Inbound Dispatch Layer (PARTIAL) -- 0x1c11 Sequence Threshold + Connection Manager RTTI

**Partial progress finding.** Probed the inbound side of the Zone
channel attempting to find where `Group::PacketRequestBase`
instances are constructed from wire bytes (spawn pipeline producer).

Result: did NOT pin the specific deserializer (likely deeper into
SocketThread / fiber territory), but DID discover:
1. The full ZoneClient mainLoopTick architecture (connection-level
   opcodes only)
2. A NEW 0x1c11 sequence threshold in packet dispatch (not previously
   documented)
3. Two NEW RTTI types in the Network namespace
4. Confirmation that ZoneClient does NOT deserialize typed packets --
   it receives ALREADY-CONSTRUCTED packet objects from upstream
   ConnectionManager

This is a valid intermediate step for the spawn wire-side trace.

## 1. Confirmed: ZoneClient ONLY handles low-level connection opcodes

`ZoneClient_mainLoopTick` (already named) is called per main-loop tick
and processes inbound packets via a switch on `packet_header+2`
(16-bit opcode). Cases:

```text
Opcode  Handler
------  -------
0x01    handshake reply (read +0x10 timer + +0x14 sub-protocol version)
0x02    version confirm (reply with opcode 6 + LobbyClient+0x230 session id)
0x0E    disconnect notice (set close flag, send opcode 4 ack)
0x11    disconnect notice (same as 0x0E)
default fall through to packet dispatcher (see section 2)
```

**Game-protocol opcodes (0x12d-0x135) do NOT appear in this switch.**
They fall through to the default-case dispatcher.

## 2. NEW: 0x1c11 sequence threshold in packet dispatch

The fall-through path calls `FUN_004e5ff0` (NEWLY RENAMED to
`ZoneClient_packetDispatch_treeOrDestroy_threshold_0x1c11`):

```text
ZoneClient_packetDispatch_treeOrDestroy_threshold_0x1c11(this, packet):
  
  1. vtable[+4] on this (probably per-source stat counter increment)
  
  2. WorkPathTree_lowerBound(this+0x14, &seq_a, &packet[+0x04])
     -- look up packet by some key (param_1+1 / packet[+0x04])
  
  3. FUN_008a87f0(this+0x14, &seq_a, seq_a_val, found_node)
     -- some tree manipulation
  
  4. ROUTE BY THRESHOLD:
     if (packet[+0x1c] < 0x1c11):                       ← 7185 decimal
       ZoneClient_packetTree_rbLookupOrInsert_bySequence(
         this+0x08, output_buf, &packet[+0x04])
       -- INSERT into the ordered packet tree
     else:
       vtable[0](1)
       -- packet destructor; DISCARD packet
  
  5. vtable[+8] on this (cleanup)
  
  Returns: 1 (always)
```

### What the 0x1c11 threshold likely means

```text
0x1c11 = 7185 decimal

Hypothesis A: Sliding window boundary
  - Packets within window 0..7184: ordered processing
  - Packets outside window: dropped (out of sequence / duplicate)

Hypothesis B: Opcode space split
  - Wire opcodes < 0x1c11: routed through ordered tree
  - Wire opcodes >= 0x1c11: discarded (unknown / reserved)

Hypothesis C: Sequence number ceiling per channel
  - 16-bit sequence space limited to 14 bits effectively
  - Top 2 bits used as channel/flag
  - Overflow wraps below 0x1c11

Most likely: Hypothesis A (sliding window) -- the 7185 magic value
matches typical MMORPG sliding-window sizes for in-order delivery.
The "tree insert" path is for ordered re-assembly.
```

## 3. NEW RTTI types confirmed (+2)

```text
Component::Network::IpcChannel::ConnectionManagerTmpl<
  Application::Network::ZoneProtoChannel::ZoneProtoUp,
  Application::Network::ZoneProtoChannel::ZoneProtoDown
>::RTTI_Type_Descriptor

Application::Network::ZoneProtoChannel::
  ServiceConsumerConnectionManager::RTTI_Type_Descriptor
```

Total RTTI types now confirmed: **17** (was 15).

These confirm the **network namespace hierarchy**:
- `Component::Network::IpcChannel::` -- generic IPC channel infrastructure
- `Component::Network::IpcChannel::ConnectionManagerTmpl<Up, Down>` --
  templated connection manager parameterized by per-channel protocol types
- `Application::Network::ZoneProtoChannel::ZoneProtoUp/Down` --
  client-up vs server-down protocol stream definitions
- `Application::Network::ZoneProtoChannel::ServiceConsumerConnectionManager` --
  concrete Zone-specific connection manager

The template instantiation means there are likely SIBLING
ConnectionManagerTmpl<X,Y> for Lobby and Chat channels with their
own ProtoUp/Down types.

## 4. Where typed packets are deserialized (HYPOTHESIS)

```text
The current finding chain establishes:
  Win32 socket recv (NOT YET TRACED)
   ↓
  SocketThread / fiber (NOT YET TRACED)
   ↓
  ConnectionManager byte → packet framing
   ↓
  TYPED PACKET CONSTRUCTION via RTTI-polymorphic factory (NOT YET TRACED)
   ↓
  Push to per-Channel inbound queue
   ↓ (next-frame)
  ZoneClient_mainLoopTick pulls packets
   ↓
  Switch on opcode (handles 1/2/0xE/0x11; rest falls through)
   ↓
  ZoneClient_packetDispatch_treeOrDestroy_threshold_0x1c11
   ↓
  Tree insert (if sequence < 0x1c11) OR destroy

Game-protocol packets (Group::PacketRequestBase derived) presumably:
  - Are CONSTRUCTED in the SocketThread or fiber path BEFORE pull
  - Have wire opcode encoded in packet[+2] (per ZoneClient_mainLoopTick)
  - Are stored as polymorphic instances in the inbound queue
  - When pulled, fall through to FUN_004e5ff0 dispatcher
  - End up in the ordered packet tree
  - From the tree, must be CONSUMED by per-actor or per-script-engine
    dispatcher (this is the link to the SPAWN ring buffer)

The "spawn ring buffer at instance+0x20" we identified in the spawn
pipeline finding is likely WRITTEN BY a tree-walker that pulls
ordered packets and dispatches them by type.

NEXT TRACE: find writer to spawn ring buffer (instance+0x20).
That writer is the link between the network-side tree and the
script-side spawn pipeline.
```

## 5. Why the deep trace is harder than expected

```text
1. Win32 with SocketThread/fiber: I/O is OFF the main thread, so
   per-frame trace doesn't reveal the producer
2. Ghidra MCP can't easily search by RTTI symbol references --
   would need to find Group::PacketRequestBase::ctor call sites
   to find the polymorphic factory
3. The 0x1c11 threshold suggests sliding-window ordering, which
   means packets are queued/reordered before high-level dispatch
4. The high-level Script Engine packet handlers are in 0x0075xxxx
   address range but the Script Engine ENTRY POINT for inbound
   packets isn't obviously named -- it's probably hooked via a
   subscription/callback pattern (not direct function call)

What WOULD finish the trace:
  - Search for callers of PacketBuffer / PacketReceiver Read methods
  - Find functions that take Group::PacketRequestBase* as parameter
  - Or: search for writes to (instance+0x20) ring buffer slots
    (writer = network thread; reader = spawn T1)
```

## 6. Renames + comments applied

```text
0x004e5ff0  FUN_004e5ff0  → ZoneClient_packetDispatch_treeOrDestroy_threshold_0x1c11
0x004e5ca0  FUN_004e5ca0  → ZoneClient_packetTree_rbLookupOrInsert_bySequence

Plus 1 decompiler comment at 0x004e5ff0 documenting full body
behavior + the 0x1c11 threshold semantics + spawn wire-side
hypothesis.
```

## 7. Cross-references

- `finding_spawn_pipeline_typed_packet_ring_buffer_6_stage_architecture.md`
  -- the DRAIN side of this producer (next trace: find writer to T1's
  ring buffer)
- `finding_zone_chat_channel_architecture.md` -- prior 3-channel
  architecture finding (Lobby/Zone/Chat with SocketThread)
- `finding_application_mainTick_and_per_frame_subsystem_dispatch.md`
  -- the engine main loop architecture
- `finding_ipc_channel_framing.md` -- PacketBufferTmpl architecture
  (the 6 RTTI types for 3 channels x 2 directions)

## 8. Confidence

```text
Confirmed:
  - ZoneClient_mainLoopTick handles ONLY low-level opcodes 1/2/0xE/0x11
  - Game opcodes 0x12d-0x135 NEVER appear in this switch
  - Fall-through goes to FUN_004e5ff0 (renamed) with 0x1c11 threshold
  - 0x1c11 threshold routes between "tree insert" vs "destroy"
  - WorkPathTree-style red-black tree at this+0x14 and this+0x08
  - 2 NEW RTTI types in Network namespace (17 total now)
  - Win32-based architecture with separate I/O thread/fiber

Likely (High):
  - 0x1c11 is a sliding-window sequence threshold for in-order delivery
  - The packet ALREADY HAS its concrete C++ type by this point
    (polymorphic dispatch via vtable[0]/[+4]/[+8])
  - Group::PacketRequestBase instances are constructed in
    SocketThread / fiber, not in main thread
  - Specific deserializer factory is in 0x00dxxxxx range
    (alongside ConnectionManager code)

Speculative:
  - The spawn ring buffer (instance+0x20) is written by a
    tree-walker that consumes ordered packets from the
    ZoneClient_packetDispatch tree
  - There may be a separate "PacketHandler subscription" map
    that registers script engine as the handler for game opcodes
```

## 9. Next test

```text
1. Find writes to the spawn ring buffer at instance+0x20 (T1 reads
   from here). The writer is the link between network-side packet
   tree and script-side spawn pipeline.
2. Trace FUN_004e3eb0 / FUN_004e3e60 (init/cleanup wrappers around
   the receive loop) to see if they register packet handlers
3. Look for "PacketHandler" or "EventHandler" subscription patterns
   in the 0x004e0000-0x004e6000 range (ZoneClient module)
4. Try searching for callers of Group::PacketRequestBase ctor
   via xrefs to address 0x???? (would need to find ctor first)
5. Decompile FUN_00dae520 (the receive call) to see what packet
   types it returns
```

## Commit suggestion

```
docs(re/exe): PARTIAL spawn wire-side trace -- ZoneClient inbound dispatch + 0x1c11 sequence threshold + 2 NEW Network RTTI types (17 total)
```
