# Finding: Per-Channel Packet Dispatch by ID (map lookup, not a switch table)

Identify how the client routes a parsed IPC packet to its per-handler code.
This is the step that follows the segment parser
(`docs/packets/packet_frame_and_segment_header.md`) and is the place where
the protocol's "opcode space" is enforced on the client side.

## Targets

```text
FUN_00db5300  candidate: ProtoChannel__dispatchPacketById
FUN_004e4b40  candidate: stl_map_find_or_redblack_helper   (used as map.find)
FUN_004e4ba0  candidate: stl_map_iter_value
FUN_00db3430  candidate: PacketPool__alloc                 (allocates 0x238 packet object)
```

## Evidence

### Shape of FUN_00db5300

Decompile (paraphrased — comments are mine):

```c
void __thiscall FUN_00db5300(ProtoChannel *this, uint packet_handle)
{
    PacketObject *pkt = *(PacketObject **)(packet_handle + 8);
    uint  payload_or_body  = pkt ? *(uint *)((char*)pkt + 0x14) : 0;
    uint  dispatch_id      = pkt ? *(uint *)((char*)pkt + 0x18) : 0;

    if (payload_or_body == 0 || dispatch_id == 0) {
        // UNKNOWN-PACKET FALLBACK
        Unknown *u = (**(...)(this->vtable_034 + 8))(this, this->arg_028, this->arg_028);
        (**(...)(this->vtable_0 + 0x60))(u, packet_handle);
        if (u) (**(...)*u)(1);   // release
        return;
    }

    // LOOKUP IN MAP KEYED BY dispatch_id
    Iter it = FUN_004e4b40(this, &dispatch_id);     // map.find(dispatch_id)
    if (it != 0) {
        Handler *h = FUN_004e4ba0(it);              // iter -> value
        if (h->func != 0) {
            (**(...)( *(int *)(h->func) + 4 ))(h, packet_handle);   // virtual dispatch
        }
    }
}
```

Key observations:

- **There is no jump table and no `switch` on the opcode.** Dispatch is a
  map lookup keyed on the dword at packet-object offset `+0x18`, which is
  the value the segment parser stored from the segment header field at
  segment offset `+0x08` (see frame/segment doc).
- The map's value is a "handler object" pointer; the handler has its own
  vtable, and the dispatch invokes vtable slot `+0x04`.
- The lookup helper pair `FUN_004e4b40 / FUN_004e4ba0` is structurally
  identical to MSVC STL's red-black-tree `_Tree::_Lbound` /
  `_Tree::_Mynod`-style helpers used for `std::map`/`std::set`. This is
  consistent with the SE codebase's heavy use of `std::map<uint, Handler*>`
  for registries.
- On lookup miss or null body, the call falls through to an
  "unknown packet" handler reachable through `this->vtable_034 + 8` and
  then `this->vtable_0 + 0x60`. This is the same code path that produces
  the `"Get Unkown Packet "` / `"END: Get Unkown Packet"` strings
  observed in `.rdata` at `0x01127d48` and `0x01127d8c` — the typo
  ("Unkown") is the binary's own and is diagnostic.

### Call-site population

`FUN_00db5300` has at least 15 direct callsites at:

```text
00dacb20  00dacc10  00dacd70  00daceb0  00dacff0  00dad130
00db11d0  00db12c0  00db1420
... (full list available via xrefs)
```

The dense cluster around `0x00daxxxx` is consistent with one
`processOnePacket` per protocol channel times several entrypoints
(blocking/non-blocking/buffered/etc.) — i.e. each channel's
`processPacket` and `processAllPackets` ends up calling the same
`dispatchPacketById` once it has a parsed packet in hand. Not all
clusters were traced.

### Relationship to the segment parser

From `finding_ipc_channel_framing.md` and the segment doc:

- The segment parser (`FUN_00db35e0`) allocates a 0x238-byte packet object
  via `FUN_00db3430` for IPC segments and fills:
  - packet `+0x14` = segment-header `source` field
  - packet `+0x18` = segment-header `target` field
  - packet `+0x20` = payload length
  - packet `+0x24` = payload bytes
- `tryGetNextPacket` (`FUN_00db6140`) yields that packet via
  `out_packet[2]`, and `processOnePacket` (e.g. `FUN_00db6590`) then calls
  `FUN_00db5300(channel, out_packet)`.

So the field at packet `+0x18` — the **dispatch key** here — is the same
dword the segment header carries at its offset `+0x08`. That dword is
what the previous finding called `target_actor_or_session_id`, but its
behavioural role on the client side is: **the key the channel uses to
pick a registered handler.**

This forces a re-reading of the segment-header field at `+0x08`. On the
client receive side it is treated as a **dispatch id** (handler-table
key), not as an entity-id semantic. The same dword may also serve as an
addressed entity on other paths, but the on-receive dispatch path keys
on it directly.

### What a "handler" looks like

The matched value pointer is fetched via `piVar3[9]` (offset 0x24 inside
the std::map node — consistent with the standard MSVC red-black-tree
layout where the value is at +0x24 of `_Tree_node`). The handler
object's vtable slot `+0x04` is the per-packet entry point and is called
as `(handler, packet)`.

This means **every individual opcode/event the channel cares about is
registered as its own handler object at runtime.** It is not a compile-
time function-pointer table. Adding a new opcode on the server side will
not provoke any client-side reaction unless the client has previously
registered a matching handler under that key.

## Assessment

```text
Confirmed:
  - FUN_00db5300 is the channel's "given a packet handle, run the
    registered handler" function.
  - Dispatch is performed by std::map<uint, Handler*>-style lookup, not a
    switch or jump table. The key is the dword at packet object +0x18.
  - The miss path leads to the "Get Unkown Packet" debug strings;
    unknown ids do not crash the client.

Likely (High):
  - The dispatch key at packet +0x18 corresponds to segment-header
    offset +0x08; this is the same field the previous finding labelled
    `target_id`. On the receive path the client treats it as the
    handler-table key.
  - FUN_004e4b40/FUN_004e4ba0 are the std::map find/value helpers and
    will appear in many other dispatch tables across the binary.

Likely (Medium):
  - There is one std::map per channel (Lobby / Zone / Chat) holding the
    full set of registered handlers for that channel. The 15+ callsites
    of FUN_00db5300 are channel-specific processOnePacket wrappers
    around the same dispatch.

Speculative:
  - That the dispatch key uniquely identifies a "message id" rather than
    an addressed entity. Strong client-side behavioural evidence (it is
    used as a map key) but the binary may also use it as an entity id
    on other paths (e.g. when sending). Confirming the duality requires
    looking at the outbound side.

Next test:
  - Find where the std::map at `ProtoChannel::this` is populated. That
    will yield the full per-channel handler registry (all the
    "opcodes" the client recognises). Look for code that builds a node
    and inserts it; in MSVC STL this typically goes through a
    `_Tree::insert` helper near 0x004e4xxx.
  - Decompile one or two callers from the FUN_00db5300 cluster
    (e.g. FUN_00dacb20) to confirm the per-channel processOnePacket
    pattern and pick up channel identity.
  - Cross-check the dispatch key against an outbound packet build to
    determine whether it doubles as an entity id or is purely a
    handler-table key on the wire.

Commit suggestion:
  docs(re/exe): document IPC packet dispatch via std::map<id, Handler*>
```

## Server implication

- A compatible server cannot pick an arbitrary opcode value and expect
  the client to react to it. Only opcode values pre-registered in the
  per-channel handler map will trigger client behaviour; everything else
  silently hits the "Unkown Packet" path.
- Because the client uses **the segment-header field at +0x08** as the
  handler-table key, the server must place the intended dispatch id in
  that field, not inside the IPC payload at +0x10. This is the opposite
  of the modern (2.x+) FFXIV design and matches what is observable in
  the 1.x wire traffic.
- For an early-bring-up server, the practical recipe is:
  - finish the handshake (segment types 1, 2, 9, 10) — see
    `docs/packets/packet_frame_and_segment_header.md`
  - reply to keepalive (segment type 7 -> 8)
  - send any IPC packet (segment type 3) with the dispatch id of one
    known-registered handler; observe whether the client reacts (state
    change, log line, response packet) to confirm the registry mapping
  - iterate to discover the registered id set without needing to
    decompile the entire registration code first
