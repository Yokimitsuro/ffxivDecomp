# Finding: IPC Channel Architecture and Per-Channel Packet Framing

Identify the three protocol channels the client speaks (Lobby, Zone, Chat),
the templated packet-buffer machinery sitting between raw TCP bytes and the
per-channel packet handlers, and the function that pumps typed packets out
of the receive buffer.

## Targets

```text
FUN_00db6140  candidate: PacketBufferBase__tryGetNextPacket
FUN_00db6d20  candidate: PacketBufferTmpl<TChatProtoDown>__tryGetNextTyped
FUN_00db6590  candidate: PacketBufferTmpl<TChatProtoDown>__processOnePacket
FUN_00db67e0  candidate: PacketBufferTmpl<TChatProtoDown>__processAllPackets
FUN_00db5300  candidate: <channel>__handleOnePacket   (called per-packet)
FUN_00db4300  candidate: <channel>__onRecvEventLog    (debug log path)
```

## Evidence

### Three protocol channels with mirrored Up/Down builders

RTTI/vtable strings recovered from `.rdata` show the protocol layout:

```text
Component::Network::IpcChannel::PacketBufferBase
Component::Network::IpcChannel::PacketBufferTmpl<TLobbyProtoDown>
Component::Network::IpcChannel::PacketBufferTmpl<TZoneProtoDown>
Component::Network::IpcChannel::PacketBufferTmpl<TChatProtoDown>

Component::Network::IpcChannel::PacketBufferTmpl<TLobbyProtoUp>
Component::Network::IpcChannel::PacketBufferTmpl<TZoneProtoUp>
Component::Network::IpcChannel::PacketBufferTmpl<TChatProtoUp>

Application::Network::LobbyProtoChannel::ClientPacketBuilder
Application::Network::ZoneProtoChannel::ClientPacketBuilder
Application::Network::ChatProtoChannel::ClientPacketBuilder

Application::Network::LobbyProtoChannel::LobbyProtoUpPacketBuilder
Application::Network::ZoneProtoChannel::ZoneProtoUpPacketBuilder
Application::Network::ChatProtoChannel::ChatProtoUpPacketBuilder

Component::Network::IpcChannel::PacketDataBuilder<TXxxProtoUp>
```

This is a uniform shape: each of the three protocols has

- a `PacketBufferTmpl<TXxxProtoDown>` (incoming, server -> client)
- a `PacketBufferTmpl<TXxxProtoUp>`   (outgoing, client -> server)
- a `PacketDataBuilder<TXxxProtoUp>`  (typed packet builder)
- a `ClientPacketBuilder` (high-level builder used by gameplay code)
- a `XxxProtoUpPacketBuilder` (concrete builder)

`Up` and `Down` are the client-up / server-down halves of the protocol;
`Proto*` is the typed message family for that channel.

### Channels are independent TCP connections

`Lobby`, `Zone`, `Chat` are distinct `ProtoChannel` objects, each owning its
own `PacketBuffer*Down` (receive) and `PacketBuffer*Up` (send). The Socket
layer documented in `finding_net_event_loop.md` carries an `on_recv_tcp`
callback at `Socket+0x38`; the channel objects install themselves as the
context (`Socket+0x90`) and route bytes into their own `PacketBufferBase`.

### `tryGetNextPacket` shape

`FUN_00db6140` (called from the templated wrappers) is the base
`tryGetNextPacket(out_packet)`:

```text
1. EnterCriticalSection(this+0x60)
2. Iterate the pending-chunk list anchored at this+0x0c / this+0x10:
   a. for each entry whose vtable+0x0c "is_ready" returns true:
        - extract user data (entry[3]) and processor pointer (entry[4])
        - call processor->vtable+0x14 (entry[3])      ; per-packet dispatch
        - if this+0x78 secondary handler:
            call secondary->vtable+0x20 (entry[3])    ; e.g. Lua hook
        - call entry[4]->vtable+0x00 (1)              ; release
3. Iterate the list again and try to parse the head chunk:
        FUN_00db3880(this, out_packet, chunk_len, chunk_descriptor)
   On the first chunk where the parser fills out_packet[2] (segment data
   pointer) non-null, set `iVar3` and return true.
4. LeaveCriticalSection, return whether out_packet was populated.
```

Field layout that follows from this:

```text
PacketBufferBase (this):
  +0x08  primary packet processor*      ; vtable +0x14 = per-packet dispatch
  +0x0c  list head sentinel             ; head of pending-chunk doubly-linked list
  +0x10  list tail/iter                 ; ditto
  +0x18  ulonglong (timestamp?)         ; written via FUN_00da1c80
  +0x24  parsed_packet_count            ; incremented when parser succeeds
  +0x60  CRITICAL_SECTION (RTL)         ; covers list mutation
  +0x78  secondary packet processor*    ; vtable +0x20, +0x08, +0x10 used
```

`PacketBufferTmpl<T>` (derived):

```text
+0x00  vtable (PacketBufferTmpl<TXxxProtoDown>::vftable)
+0x08  back-pointer to PacketBufferBase (this+8 -> the buffer above)
+0x38  internal queue head ptr
+0x3c  internal queue iter
+0x40  internal queue count
```

`FUN_00db6d20` is the typed `tryGetNextPacket(out)`: it first drains the
template's own queue (`this+0x38..0x40`); if empty, delegates to
`FUN_00db6140` on the underlying `PacketBufferBase` via `this+0x08`.

### `processAllPackets` and `processOnePacket`

`FUN_00db6590` (one packet) and `FUN_00db67e0` (drain all) wrap
`tryGetNextPacket` and for each populated packet call:

```text
FUN_00db5300(channel, &out_packet)     ; channel-specific handler
FUN_004e6080(out_packet[2]->vtable, out_packet)   ; release packet
```

`FUN_00db5300` is therefore the channel-specific per-packet handler —
the natural place where `ChatProto::onPacket(...) / ZoneProto::onPacket(...)
/ LobbyProto::onPacket(...)` would dispatch by message id. Decompiled
samples seen so far all reference the `ChatProtoDown` vtable in their
locals; analogous instantiations exist for Lobby and Zone but were not
yet located.

### Debug receive logging

`FUN_00db4300` is a debug variant: it constructs a `PacketBufferTmpl
<TChatProtoDown>` on the stack, drains one packet via the same path, then
emits the string `"receieve packet... Event on #<n>"` (typo preserved
from the binary) followed by a number to the log stream at `DAT_01363d30`.
The number is derived from a member pointed to by `this+0x88` — likely an
event id / packet id resolved through `FUN_004e4b40 / FUN_004e4ba0`.

This confirms that "Event on #<n>" is the client's own designator for
incoming packets at the channel layer, which is useful for correlating
client logs against a packet stream.

## Assessment

```text
Confirmed:
  - The client speaks exactly three IPC channels: Lobby, Zone, Chat. Each
    is an independent connection with mirrored Up/Down packet buffers and
    builders, all under Application::Network::*ProtoChannel.
  - PacketBufferBase is the generic per-channel receive accumulator and is
    where bytes from a Socket get framed.
  - tryGetNextPacket is the boundary between byte-stream and per-channel
    typed packet handler.
  - Per-packet dispatch is virtual; the primary processor (PacketBufferBase
    +0x08) gets vtable+0x14 called per ready chunk.

Likely (High):
  - FUN_00db5300 is the per-channel "handle this packet" function. Renaming
    candidates exist for it under each channel.
  - The secondary processor at PacketBufferBase+0x78 is the Lua bridge:
    matches "Lua::Script::Client::Group::PacketProcessor" RTTI seen earlier,
    and is consulted only after the primary processor has run.

Likely (Medium):
  - The "Event on #<n>" string in FUN_00db4300 is a packet/event id; this
    becomes high confidence once the n source is decoded to a known
    enum/string table.

Speculative:
  - That all three channels use the same FUN_00db5300; more likely each
    has its own template-instantiated copy. The Lobby/Zone variants live at
    different addresses to be discovered.

Next test:
  - Decompile FUN_00db5300 to see whether it switches on packet
    type/opcode or simply forwards to vtable+0x14.
  - Identify the Lobby and Zone equivalents of FUN_00db4300 / FUN_00db6590
    / FUN_00db67e0 by looking for the matching PacketBufferTmpl vtables in
    .rdata (TLobbyProtoDown / TZoneProtoDown).
  - Find what installs Socket+0x38 = ProtoChannel::onRecv to bind the
    Socket layer to the right PacketBuffer.

Commit suggestion:
  docs(re/exe): document IPC channel framing and tryGetNextPacket
```

## Server implication

- A compatible server must serve **three independent TCP connections** per
  game session (Lobby, Zone, Chat). They are not multiplexed onto a single
  socket.
- Each channel deserialises into typed packets independently, so opcode
  spaces are per-channel, not global. A given opcode value can mean
  different things on Lobby vs Zone vs Chat.
- Pacing of server -> client bytes is irrelevant to framing: the
  per-channel `PacketBufferBase` will buffer partial frames across recv()
  calls and only fire the channel handler when a complete segment is
  available.
- Channel handlers run under a critical section per channel — the server
  may send packets back-to-back without worrying about client-side
  reentry within one channel, but inter-channel ordering is not enforced
  by the client.
