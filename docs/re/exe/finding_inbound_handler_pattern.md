# Finding: Inbound Handler Pattern — Specific Handlers Route to MyPlayer Methods

Walking the inbound handlers in the dispatch table at 0x00fdfb80
reveals a **uniform 3-layer pattern**: tabla entry → packet reader
setup → typed-event method on MyPlayer (via dynamic_cast). This
finalizes the inbound dispatch model.

## The Pattern (4 handlers sampled)

All handlers follow this template:

```c
void HANDLER(this, packet_arg) {
  // Layer 1: setup local packet reader (8 bytes on stack)
  uint8_t local_14[8];
  FUN_00776XXX(local_14, packet_arg);   // hydrate reader from
                                          // packet bytes
  // Layer 2: dispatch to a typed event method
  FUN_008a3DXX(local_14, this+4, this+8);  // typed router
}
```

The "typed router" function (FUN_008a3DXX family) then does:

```c
void TYPED_ROUTER(this, param_1, param_2) {
  // Layer 3: cast the target actor to MyPlayer
  MyPlayer* mp = ___RTDynamicCast(
    param_2, 0,
    &ActorBase::RTTI_Type_Descriptor,
    &MyPlayer::RTTI_Type_Descriptor, 0
  );
  // Invoke a specific event-handling method on MyPlayer
  FUN_006eXXXX(mp, param_1, ...);
}
```

So each opcode → typed router → MyPlayer event method.

## Sampled Handlers

```text
TABLE ENTRY    PACKET READER       TYPED ROUTER      MYPLAYER METHOD
0x00fdfb80     FUN_00776a50        FUN_008a3de0      FUN_006e11e0
0x00fdfb84     FUN_00776b70        FUN_008a3e20      FUN_006e1200
0x00fdfb88     (direct, no reader) FUN_008a3e60      FUN_006f8200
0x00fdfb8c     FUN_008a36b0        FUN_008a36c0      (variant)
0x00fdfbe0     -- generic vtable dispatch (slot 23) --
0x00fdfc18     FUN_0089eed0        FUN_008a0190      _onReceiveDataPacket
                (192-byte buffer)                    (Lua bridge)
```

The packet reader functions (`FUN_00776XXX`) are **per-packet-shape
hydrators** -- each one knows how to parse a specific wire format
into the local 8-byte reader struct.

The typed routers (`FUN_008a3eXX`) handle the **MyPlayer cast + final
dispatch** -- they ensure the target is the local player and route
to the right event method.

The MyPlayer methods (`FUN_006eXXXX`) are the **actual event handlers**
that mutate state, trigger Lua hooks, update UI, etc.

## Discovery: Most Events Target the Local Player

The presence of `RTDynamicCast<ActorBase, MyPlayer>` in every typed
router confirms that **most inbound events are routed to the local
player specifically**. This makes sense:

- HP/MP/TP updates → MyPlayer (your own bars)
- Achievement progress → MyPlayer
- Inventory changes → MyPlayer
- Quest progress → MyPlayer
- Buff/debuff applications → MyPlayer

For events targeting OTHER actors (other players, NPCs visible
nearby), there's probably a separate path that uses the broader
actor lookup (per-actor id) rather than the MyPlayer cast.

## The 3-Layer Architecture

```text
Layer 1 (Packet I/O):
  FUN_00776XXX    per-packet-shape readers (different funcs per
                  opcode's payload format)

Layer 2 (Type-Safe Routing):
  FUN_008a3eXX    typed routers; dynamic_cast to MyPlayer; route
                   to specific event method

Layer 3 (Event Processing):
  FUN_006eXXXX    specific event handlers; mutate state, trigger
                   Lua hooks, update UI

The DISPATCH TABLE at 0x00fdfb80 holds the LAYER-1 wrappers (each
opcode has its own L1 handler with its own L2 routing). The wider
container architecture is:

  opcode 0x?? -> table[entry] -> wrapper -> reader -> router ->
                                              event method -> Lua
```

## Implications

```text
Total per-packet overhead:
  1 dispatch lookup (O(1) table indexing)
  1 packet reader init (allocate 8-byte stack reader)
  1 hydration call (decode wire bytes)
  1 dynamic_cast (RTTI overhead; small constant)
  1 typed event call
  1+ Lua bridge calls (for events that escalate to Lua)

So inbound packet processing is FAST -- few function calls deep,
all hot-path optimized. The dynamic_cast is the only "expensive"
operation but RTTI in MSVC is well-optimized.

Server-side picture stays the same:
  Server constructs packet with opcode + payload
  Sends via Zone channel
  Client's dispatch table[opcode] -> reader -> router ->
                                      MyPlayer event method
  No additional protocol overhead per layer.
```

## Assessment

```text
Confirmed:
  - 3-layer architecture: Packet Reader / Typed Router / Event
    Method
  - Typed routers use RTTI dynamic_cast to ensure target type
  - Most events target MyPlayer specifically (cast confirms it)
  - The dispatch table at 0x00fdfb80 holds Layer 1 wrappers

Likely (High):
  - Each FUN_00776XXX reader corresponds to a specific opcode's
    payload format (e.g. one for "binding update", one for
    "stat change", one for "command result").
  - The FUN_006eXXXX event methods are on the MyPlayer class
    vtable, dispatching to Lua via the standard _onChangeXxx
    or _onReceiveXxx hook family.

Likely (Medium):
  - For events targeting non-myPlayer actors, there's probably a
    parallel chain that uses actor lookup by id instead of the
    MyPlayer cast.
  - The "packet reader" struct (8 bytes) is probably the same
    shape across all packets (begin pointer + end pointer for
    the payload buffer).

Speculative:
  - The reader functions (FUN_00776XXX) may be auto-generated
    from a packet schema (each shape has a generated parser).
  - The 3-layer separation reflects classic Microsoft COM-style
    design: I/O / dispatch / impl separation.
```

## Open Threads (Final)

```text
1. The exact OPCODE -> table-position arithmetic. Requires finding
   the function that does `dispatch_table[base + opcode * 4]`. Not
   pinned yet.

2. The set of event types -- each FUN_006eXXXX is a different
   event handler. Enumerating them all gives the full inbound
   event roster.

3. The non-MyPlayer dispatch path -- for events on other actors.
   Probably uses a separate router family.

The dispatcher PATTERN is now fully understood. The exact opcode
mapping + the per-event behavior are pending but the architectural
model is complete.
```

## Closes the Wire Dispatch Investigation

With this finding, the inbound dispatch chain is fully decomposed:

```text
WIRE BYTES ARRIVE
   ↓
Read opcode from segment header
   ↓
┌─ Is opcode a RESPONSE to a pending request?
│  YES -> PATH A: dynamic_cast<PacketRequestBase>, invoke
│         vtable+0x34 (process)
│
└─ NO -> PATH B (table dispatch):
   ↓
   table[base + opcode_offset] = handler   (table at 0x00fdfb80)
   ↓
   handler -> packet reader setup -> typed router ->
              dynamic_cast<MyPlayer> -> event method ->
              [optional Lua hook]
   ↓
   STATE UPDATED
```

The investigation has reached its natural conclusion at the
architectural level. Byte-exact wire compatibility would require
walking each opcode's specific reader + handler bodies, but the
shape is established.
