# Packet Spec: Outer Frame and Segment Header

Document the wire-format of an FFXIV 1.x IPC frame as parsed by the client,
including the segment type enum and the fixed sizes the client enforces.

## Source

Reverse engineered from the segment parser:

```text
FUN_00db35e0  candidate: PacketBufferBase__parseSegment
FUN_00db3880  candidate: PacketBufferBase__parseChunk    (caller, switch on segment_type)
```

This is the inner switch that converts a byte buffer into one segment;
called from `tryGetNextPacket` (see `docs/re/exe/finding_ipc_channel_framing.md`).

## Frame structure (Down direction — server -> client)

The client parses an incoming "frame" as:

```text
+-----------------------------------+
| Frame header (>= 16 bytes)        |  -- exact field layout TBD; only frame_size
|   ...                             |     was used by the segment loop
|   uint16  frame_size       @ +0x04|     (matches *(ushort*)(buf+4))
+-----------------------------------+
| Segment[0]  (16-byte header + payload, length self-describing)
| Segment[1]  ...
| ...
+-----------------------------------+
```

The client tracks two cursors on the buffer object that holds the frame:

```text
buffer->buffer_ptr   (this+0x08)
buffer->frame_size   (this+0x0c)   uint16, taken from *(ushort*)(buf+4)
buffer->cursor       (this+0x0e)   uint16, starts at 0x10 (post header)
```

Initial sanity gate inside `parseSegment`:

```c
if (frame_size_cached < 0x10) return 0;          // refuse runts
if (frame_size_cached < *(uint16*)(buf+4)) return 0;
buffer->frame_size = *(uint16*)(buf+4);          // adopt header value
if (buffer->cursor == 0) buffer->cursor = 0x10;  // skip the 16-byte frame header
```

So the **frame header is exactly 16 bytes**, and `*(uint16*)(buf+4)` is the
total frame length (header + all segments).

## Segment header (16 bytes, copied verbatim into the out-packet)

For each segment, the parser copies 16 bytes starting at `buf+cursor`
into `out_packet[2..5]` (four dwords) and then reads two key fields:

```text
offset  size  field                     C type   notes
------  ----  ------------------------  -------  -----------------------------
+0x00   2     segment_size              uint16   total bytes of THIS segment
                                                 (header + payload)
+0x02   ?     ?
+0x04   4     source_actor_id_or_sess   uint32   copied into out_packet[3]
+0x08   4     target_actor_id_or_sess   uint32   copied into out_packet[4]
+0x0A   2     segment_type              uint16   switch key (see below)
+0x0C   4     ?                         uint32   copied into out_packet[5]
+0x10   ...   payload                   bytes    segment_size - 0x10 bytes
```

Notes:

- The parser reads `segment_size` as `*(ushort*)((int)param_2 + 0)` after
  the 16-byte copy. With the 16 bytes laid out as four little-endian dwords,
  this puts `segment_size` at offset 0 of the segment header. (Confidence:
  High; this is what the parser dereferences.)
- The byte at `(int)param_2 + 10` — i.e. byte 0x0a — is treated as the
  switch discriminant `segment_type`. (Confidence: High; this is the
  literal expression in the decompile.)
- The parser checks `segment_size + cursor <= frame_size` before consuming —
  truncated segments cause the buffer to be reset.

## Segment-type enum (with fixed-size enforcement)

Switch on `segment_type` inside `parseSegment` (FUN_00db35e0):

```text
type  symbolic (candidate)              fixed segment_size   payload size
----  -------------------------------   ------------------   ---------------
0x01  SESSION_INIT_1                    0x38 (56)            0x28 (40 bytes)
0x02  SESSION_INIT_2                    0x38 (56)            0x28 (40 bytes)
0x03  IPC                               variable              segment_size - 0x10
                                        (any > 0x10)         (game packet payload)
0x07  KEEPALIVE                         0x18 (24)            8 bytes
0x08  KEEPALIVE_RESPONSE                0x18 (24)            8 bytes
0x09  ENCRYPTION_INIT                   0x278 (632)          0x268 (616 bytes)
0x0A  ENCRYPTION_RESPONSE               0x290 (656)          0x280 (640 bytes)
other unknown                           consumed and skipped via cursor advance
```

Key behaviour by type:

- **Types 1, 2, 9, 10**: pure copy-into-out_packet, no payload dispatch.
  These are handshake / session / encryption packets — the client absorbs
  the whole segment as a fixed-size record. `out_packet[2..]` is then
  consumed by higher-level Channel code via the per-channel handler at
  `vtable+0x1c` (see below).
- **Type 3 (IPC)**: the payload-carrying segment.
  - Allocates a `0x238`-byte packet object via `FUN_00db3430(this_00, 0x238, 0)`
    where `this_00` is fetched via `(**(code **)(*param_1 + 0x40))()` — the
    channel's packet pool.
  - Copies `source_id`, `target_id` from segment header into
    `packet[+0x14], packet[+0x18]`.
  - `memcpy(packet[+0x24], buf+cursor+0x10, segment_size - 0x10)` —
    payload is placed at packet offset `+0x24`.
  - `packet[+0x20] = segment_size - 0x10` — payload length.
  - If `param_3` (the channel handler) is non-null:
    `(*(code*)(*param_3 + 0x1c))(source_id, payload_ptr, payload_len);`
    — this is the **IPC payload dispatch into the channel** at
    vtable slot **+0x1c**.
  - Returns the allocated packet pointer.
- **Types 7, 8 (keepalive)**: copy 24-byte segment header into out_packet,
  advance cursor. No payload dispatch. Matches the MeteorReborn log
  hypothesis (`op=0x0001 len=24` — but see below; the `0x0001` was the
  *log's own* opcode label, not segment_type; segment_type at offset
  +0x0a equals 7 or 8 for those frames).

## Cross-check against observed log

```text
[Zone] RECV src=0x00000006 tgt=0x00000006 op=0x0001 len=24 hex=49B2FC1B...
```

- `len=24` matches a type-7/8 KEEPALIVE segment exactly (0x18 = 24 bytes).
- `src=0x00000006 tgt=0x00000006` matches the segment header fields at
  +0x04 and +0x08 (both copied from the same id when the keepalive is
  self-addressed).
- `op=0x0001` is **not** segment_type 1; in this log it is almost
  certainly a higher-level Sapphire-style label assigned by the test
  server. The actual on-wire `segment_type` byte at +0x0a should be
  `0x07` (echo request) or `0x08` (echo reply).
- `hex=49B2FC1B 00000000 00000000...` — the leading dword `0x1BFCB249`
  (little-endian) is the first uint32 of the segment payload (8 bytes
  total after the 16-byte header). Likely a client tick / timestamp the
  server is expected to echo back unchanged.

## Out-packet structure (filled by parseSegment)

The `out_packet` allocated for an IPC segment (size 0x238):

```text
+0x00 - +0x13  vtable + bookkeeping (template type pointer at param_2[2])
+0x14          source_actor_or_session_id   (uint32, from segment +0x04)
+0x18          target_actor_or_session_id   (uint32, from segment +0x08)
+0x1C - +0x23  ?  (param_2[6..7], not always set)
+0x20          payload_length               (uint32)
+0x24          payload_ptr                  (uint8*, points into pool)
... (rest of 0x238 bytes: packet pool / typed payload area)
```

For non-IPC segments (types 1/2/7/8/9/10), the same `out_packet` is reused
but the parser simply does a `memcpy` of the 16-byte segment header into
`out_packet[2..5]` and bumps the cursor. There is no payload pointer
publication — the channel handler at `vtable+0x1c` does not run for those
types in this code path. Higher-level channel code consumes those
segments differently.

## Assessment

```text
Confirmed:
  - Frame header is 16 bytes; *(uint16*)(buf+4) is the full frame size.
  - Segment header is 16 bytes; segment_size at +0x00; segment_type at
    +0x0a; source/target at +0x04, +0x08; one extra dword at +0x0c.
  - Segment types 1, 2, 7, 8, 9, 10 are recognised with **fixed**
    segment sizes that the parser actively validates against.
  - Segment type 3 is the IPC payload carrier and is the only type that
    triggers the channel handler at vtable+0x1c with
    (source_id, payload_ptr, payload_len).
  - Payload offset in an IPC packet object is +0x24; payload length is
    at +0x20; copy is performed by memcpy.

Likely (High):
  - Type 1/2 are SESSION_INIT halves, Type 7/8 are KEEPALIVE request/reply,
    Type 9/10 are ENCRYPTION_INIT/RESPONSE. Matches the canonical FFXIV
    1.x segment-type enum widely known from Sapphire-style 1.0 server
    reverse work, and the fixed sizes (0x38 / 0x18 / 0x278 / 0x290)
    match published references.
  - The `0x1BFCB249` first-dword of the observed keepalive payload is a
    client tick value the server is expected to echo.

Likely (Medium):
  - Frame header still has 12 bytes of unaccounted fields before
    +0x04..+0x06 (which holds frame_size). The slot layout
    (magic/seq/timestamp) is consistent with known 1.x frame headers but
    has not been verified from this binary yet.

Speculative:
  - That all three channels (Lobby, Zone, Chat) share this exact frame
    layout. Strongly suggested by the shared PacketBufferBase, but not
    yet confirmed against channel-specific code paths.

Next test:
  - Decompile FUN_00db6140's caller chain on the Lobby and Zone sides
    (find PacketBufferTmpl<TLobbyProtoDown>/TZoneProtoDown vtable users)
    to confirm frame layout is identical.
  - Decompile FUN_00db3430 (the packet allocator at size 0x238) to learn
    the rest of the packet-object layout — fields above +0x24 likely
    include opcode / IPC subtype that maps to the per-channel handler.
  - Confirm the segment_type values 0x07/0x08 by examining the response
    builder on the Up side (look for type-7/8 emits in
    XxxProtoUpPacketBuilder calls).

Commit suggestion:
  docs(packets): document FFXIV 1.x frame + segment header and the seg type enum
```

## Server implication

- A compatible server must construct frames with a **16-byte frame
  header** containing the total frame length at offset +0x04, followed by
  one or more segments.
- Each segment must use a **16-byte header** with:
  - `segment_size` at +0x00 (uint16, total including header)
  - `source_id` at +0x04
  - `target_id` at +0x08
  - `segment_type` at +0x0a (uint16, low byte is the switch)
  - one extra dword at +0x0c (purpose TBD, often zero in 1.x)
- Handshake / encryption / keepalive segments MUST be sent at the exact
  fixed sizes the client enforces; otherwise the parser silently resets the
  buffer and drops the entire frame.
- Game packets travel only inside `segment_type = 3` (IPC). The server
  must put the actual IPC payload (with its own opcode header) starting
  at byte +0x10 of the segment.
- To pass keepalive: when the client sends a type-0x07 KEEPALIVE with an
  8-byte payload, reply with a type-0x08 KEEPALIVE_RESPONSE echoing the
  first dword unchanged.
- For session start, the server is expected to deliver type-1 and type-2
  SESSION_INIT segments (0x38 each) and the two encryption segments
  (0x278 + 0x290) before any IPC traffic.
