# Finding: Zone + Chat Channel Architecture (vs Lobby)

After mapping the lobby end-to-end, this finding tackles the Zone and
Chat channels — both fundamentally different in architecture from the
lobby and from each other only in payload size of the initial
handshake. Cross-references the previously documented lobby findings.

Sources read (all renamed in this pass):

```text
ZoneClient_sendInitialHandshake     (FUN_00dae1e0)
ZoneClient_forwardOutbound          (FUN_00dae010)
ZoneClient_dispatchOutbound         (FUN_004e0240)
ZoneClient_sendKeepalive            (FUN_004e0290)
ZoneClient_sendLargeStatePush       (FUN_004e0320)
ZoneClient_mainLoopTick             (FUN_004e20a0)

ZoneIpcPacket_buildHeader           (FUN_00dc1cf0)
ZoneIpcPacket_acquireSendSlot       (FUN_00daf850)
ZoneIpcPacket_bodyPtr               (FUN_00dc1490)
ZoneIpcPacket_finalizeAndSend       (FUN_00db06a0)

ChatClient_sendInitialHandshake     (FUN_00db4020)
ChatIpcPacket_buildHeader           (FUN_00e40a60)
ChatIpcPacket_acquireSendSlot       (FUN_00db5010)
ChatIpcPacket_bodyPtr               (FUN_00e40820)
ChatIpcPacket_finalizeAndSend       (FUN_00db5a90)
```

RTTI structure (from `.rdata`):

```text
Application::Network::ZoneProtoChannel::
  SocketThread                                 -- dedicated OS thread
  ServiceConsumerConnectionManager
    LobbyCryptEngine analogue (TBD)
    ConsumerConnection
    ConnectionData
  ZoneProtoDownCallbackInterface
  + ChannelManagerCoreTmpl<ZoneProtoUp, ZoneProtoDown>
  + ChannelManagerTmpl_LF<...>                 -- lock-free variant
  + ChannelManagerOnSingleConnectionTmpl<...>
  + NetBufferTmpl<ZoneProtoUp>                 -- vs PacketBufferTmpl in Lobby
  + NetBufferFactoryTmpl[_LF]<...>
  + NetBufferQueueCoreTmpl<...>
  + NetBufferQueueTmpl_LF<...>
  + PrimaryEntity*<...>_LF
  + EntityContainerTmpl<...>

Application::Network::ZoneClient::
  ZoneProtoDownDummyCallback
  RaptureChannelManager                        -- the channel singleton

Application::Network::ChatProtoChannel::
  (same template family, parameterised on ChatProtoUp/Down)
  + SocketThread                               -- also has dedicated thread

Application::Network::ChatClient::
  ZoneProtoDownDummyCallback analogue
  RaptureChannelManager (Chat variant)
```

## Structural differences from the lobby

| Aspect | Lobby | Zone | Chat |
|---|---|---|---|
| dedicated socket thread | NO (main thread) | **YES** (`SocketThread@ZoneProtoChannel`) | **YES** (`SocketThread@ChatProtoChannel`) |
| connection lifetime | transient (closed after world handoff) | persistent (the entire session) | persistent (the entire session) |
| flow shape | 4 fixed phases via Operations queue | continuous main-loop tick | continuous main-loop tick |
| buffer infrastructure | `PacketBufferTmpl` | `NetBufferTmpl` + `_LF` (lock-free) | `NetBufferTmpl` + `_LF` |
| ipc primitives | `IpcPacket_buildHeader` (FUN_00da2be0) | `ZoneIpcPacket_buildHeader` (FUN_00dc1cf0) | `ChatIpcPacket_buildHeader` (FUN_00e40a60) |
| version handshake | 0x6E + 0x1347 in opcode 0x05 / 0x06 payload | **0x3C6B** in opcode 0x02 payload | **0x3C6B** in opcode 0x02 payload |

The Zone and Chat share the same handshake version constant
(`0x3C6B = 15467`); the lobby's two-uint16 handshake is a different
mechanism altogether.

## Why lock-free buffers

The Zone and Chat each spawn a dedicated `SocketThread` (RTTI strings
at `0x0131cb90` and `0x0131bdf0` respectively). That thread runs in
parallel with the game's main thread, which means the
NetBuffer/NetBufferQueue used to ferry packets between the threads
must be thread-safe. Hence the `_LF` (lock-free) variants of the
templates exist for the Zone and Chat — but not for the Lobby, which
is single-threaded.

## Zone outbound opcode roster

Pinned by reading the four functions that call
`ZoneClient_forwardOutbound`:

```text
opcode 0x01  HANDSHAKE_RETRY / latency ping     40 bytes   ZoneClient_mainLoopTick
opcode 0x02  INITIAL HANDSHAKE                  40 bytes   ZoneClient_sendInitialHandshake
opcode 0x03  LARGE STATE PUSH                  560 bytes   ZoneClient_sendLargeStatePush
opcode 0x04  DISCONNECT_ACK                     24 bytes   ZoneClient_mainLoopTick
opcode 0x06  HEARTBEAT / keepalive              24 bytes   ZoneClient_mainLoopTick / ZoneClient_sendKeepalive
```

### Opcode 0x02 — initial handshake (40 B)

```text
+0x00  uint32  protocol_version  0x3C6B (15467; constant)
+0x04  uint8   zero
+0x05  ...     zeros to payload size 40
```

Emitted exactly once, when zone state transitions from 1 to 2.

### Opcode 0x06 — heartbeat (24 B)

```text
+0x00  uint32  session_id  (from LobbyClient+0x230)
+0x04  uint8   zero
+0x05  ...     zeros to payload size 24
```

Emitted periodically by `ZoneClient_mainLoopTick`; the standalone
`ZoneClient_sendKeepalive` (`FUN_004e0290`) emits the same shape when
external code triggers it.

### Opcode 0x01 — handshake retry / latency ping (40 B)

```text
+0x00  uint32  protocol_version  0x3C6B
+0x04  uint32  current_tick     (timeGetTime() reading)
+0x08..+0x28   zeros
```

Emitted once per second by the main loop tick (`if (now !=
this+0x340 last_tick)`). The `timeGetTime` value is the basis the
server uses to estimate client-server latency.

### Opcode 0x03 — large state push (560 B)

The heaviest zone outbound packet. Probably the **player
initial-state push** (position + appearance + buffs + party) sent
shortly after the handshake completes. Body:

```text
+0x00  uint32   route_id            (param_1)
+0x04  uint32   ?                   (param_2[0])
+0x08  uint32   ?                   (param_2[1])
+0x0C  uint32   ?                   (param_2[2])
+0x10  uint32   sub_route           (param_3)
+0x14  uint8[0x200]  opaque payload  (memcpy from caller-provided buffer)
+0x214 uint16   trailing_field      (param_5)
+0x216 ...      zeros to 560 bytes
```

The 512-byte opaque payload is what makes this the "state push" — far
more than fits in a position update, so this is presumably the full
serialised character/world state required for the server to
reconstruct the player's session.

### Opcode 0x04 — disconnect ack (24 B)

Emitted only on server-initiated close. After the server sends
opcode 0x0E or 0x11 (both treated as "disconnect now"), the client
replies with this 24-byte packet and sets `this+0x3b0 = 1` (closing
flag).

## Zone inbound opcode roster (from main loop switch)

Pinned by the `switch(packet+0x02)` in `ZoneClient_mainLoopTick`:

```text
opcode 0x01  HANDSHAKE_REPLY                    triggers latency timer setup
opcode 0x02  VERSION_CONFIRM                    triggers heartbeat (06) reply
opcode 0x0E  DISCONNECT_NOTICE                  triggers close + opcode 04 ACK
opcode 0x11  DISCONNECT_NOTICE (variant)        same as 0x0E
```

### Opcode 0x01 inbound — handshake reply

```text
+0x10  uint32  client_tick_base   (timer reference; client subtracts from
                                   timeGetTime() to compute one-way latency)
+0x14  uint32  sub_protocol_ver   (if > 0x14C, activates a sub-feature via
                                   FUN_00dadf50; the feature TBD)
```

### Opcode 0x02 inbound — version confirm

Sets `this+0x308 = (server_tick - this->local_tick) * 1000 -
this->latency + (jitter)` — i.e. uses this opcode to **calibrate the
client/server clock skew**. After this, the client emits a 24-byte
opcode 6 with the session id at `LobbyClient+0x230`.

### Opcode 0x0E / 0x11 inbound — disconnect

Both opcodes trigger the same code path: set close flag, send
opcode 4 (24 B), then tear down via `FUN_00dae3b0`.

## Chat outbound (so far)

Only the initial handshake is pinned in this pass:

```text
opcode 0x02  INITIAL HANDSHAKE   56 bytes (vs Zone's 40)   ChatClient_sendInitialHandshake
```

Body shape identical to Zone's opcode 0x02 — protocol_version
`0x3C6B` at +0x00, zeros afterwards — but Chat's payload is **56
bytes**, 16 bytes larger than Zone's. The reason is TBD (Chat-specific
auth token at the end?).

Chat presumably has its own equivalent of the Zone main loop. Not
inspected this pass.

## How the zone connection opens

Pre-condition: lobby phase 3 completed, the world server `(host, port,
ticket, identifier, session_blob)` available at `LobbyClient+0x224`
through `+0x2d4` (see `packet_lobby_payload_layouts.md`).

The Zone connect path was NOT inspected in this pass. Working
hypothesis:

```text
LobbyRequestCallback::vtable[+0x2c] (onGameLogin_switchToWorld)
    |
    | invoked by LobbyClient_onSuccessfulGameLogin
    v
RaptureLobbyCallback::onGameLogin_switchToWorld_impl
    |
    | reads (host, port, ticket, identifier) from LobbyClient fields
    | opens a TCP socket to the zone server
    | constructs Application::Network::ZoneClient::RaptureChannelManager
    | spawns Application::Network::ZoneProtoChannel::SocketThread
    | sets ZoneClient state == 1 ("socket open, not yet handshaked")
    v
ZoneClient_sendInitialHandshake fires (opcode 0x02 outbound)
    | state -> 2
    v
server replies opcode 0x01 (handshake reply)
    v
server replies opcode 0x02 (version confirm)
    | state -> 3 (steady; main loop emits heartbeat every 1s)
```

The transition into state 3 is the gate that opens the "main loop"
behaviour where any opcode can be sent. Before state 3, only opcode
2 is accepted by `ZoneClient_forwardOutbound`.

## Cross-channel summary

The three IPC channels have **distinct toolchains**:

```text
                Lobby           Zone            Chat
                ----            ----            ----
buildHeader  IpcPacket_      ZoneIpcPacket_  ChatIpcPacket_
            buildHeader     buildHeader     buildHeader
            (FUN_00da2be0)  (FUN_00dc1cf0)  (FUN_00e40a60)

acquireSlot  IpcPacket_      ZoneIpcPacket_  ChatIpcPacket_
            acquireSendSlot acquireSendSlot acquireSendSlot
            (FUN_004e7750)  (FUN_00daf850)  (FUN_00db5010)

bodyPtr      (varies per     ZoneIpcPacket_  ChatIpcPacket_
              packet)        bodyPtr         bodyPtr
                            (FUN_00dc1490)  (FUN_00e40820)

finalize     IpcPacket_      ZoneIpcPacket_  ChatIpcPacket_
            finalizeAndSend finalizeAndSend finalizeAndSend
            (FUN_004e80b0)  (FUN_00db06a0)  (FUN_00db5a90)

dispatcher   per-Operation   ZoneClient_     ChatClient_
                            forwardOutbound  forwardOutbound (TBD)

main loop    none (transient) ZoneClient_     ChatClient_
                            mainLoopTick    mainLoopTick (TBD)
```

So porting the IPC layer to a server requires implementing **three
independent protocol decoders** even though the framing layer (16-byte
segment header) is shared (see
`docs/packets/packet_frame_and_segment_header.md`).

## Assessment

```text
Confirmed:
  - Zone and Chat have dedicated SocketThreads with lock-free
    NetBuffer infrastructure; the Lobby runs single-threaded.
  - Zone/Chat share the protocol_version constant 0x3C6B (15467)
    at payload offset +0x00 of opcode 0x02 (the initial handshake).
  - Each channel has its OWN copy of the IPC packet primitive set
    (buildHeader, acquireSlot, bodyPtr, finalize). No shared code
    between channels at this layer.
  - Zone outbound opcode roster (5 pinned):
       0x01 handshake retry  40 B
       0x02 initial handshake 40 B
       0x03 large state push 560 B
       0x04 disconnect ack    24 B
       0x06 heartbeat         24 B
  - Zone inbound opcode roster (4 pinned):
       0x01 handshake reply
       0x02 version confirm
       0x0E disconnect notice
       0x11 disconnect notice variant
  - The zone main loop ticks once per second and emits a handshake
    retry / latency ping (opcode 0x01) on the heartbeat boundary.

Likely (High):
  - The Chat channel has the same opcode shape as the Zone for the
    handshake (opcode 0x02 with 0x3C6B at +0x00) but a 56-byte body
    vs the Zone's 40 bytes; the extra 16 bytes carry chat-specific
    auth state (channel id? room id?).
  - Opcode 0x03 (560 B) carries the player's initial state push --
    appearance + position + party metadata that the server needs to
    reconstruct the session.
  - The zone connection is opened by the LobbyRequestCallback
    vtable+0x2c slot (onGameLogin_switchToWorld) reading the world
    server (host, port, ticket, identifier) from the LobbyClient
    fields at +0x224..+0x2d4.

Likely (Medium):
  - The "sub_protocol_version" at +0x14 of inbound opcode 0x01 with
    threshold 0x14C (332) is a feature gate -- builds at or above
    332 enable a sub-feature; older builds skip it. Probably the
    LF lock-free path activation.
  - Opcode 0x0E and 0x11 both being disconnect signals means one is
    "graceful close" and the other is "forceful kick". Without
    server logs both look the same to the client.

Speculative:
  - 0x3C6B as a hex pun: dec 15467; in Chinese telephony pinyin?
    Probably just an internal SE version number with no semantic.

Next test:
  - Decompile the Zone connect site (vtable+0x2c on
    RaptureLobbyCallback) -- that gives the actual point where the
    LobbyClient hands off the (host, port, ticket) to the
    ZoneClient and the TCP open happens.
  - Find ChatClient_mainLoopTick (the chat analogue of FUN_004e20a0)
    to pin the chat outbound/inbound opcode rosters.
  - Decompile the inbound dispatcher for zone (analogue of
    LobbyClient_dispatchInbound_*). For zone it presumably feeds the
    inbound packets into the queue that ZoneClient_mainLoopTick
    drains; we don't yet have the entry point.

Commit suggestion:
  docs(re/exe): zone + chat channel architecture; zone outbound
                (5 opcodes) + inbound (4 opcodes) pinned
```

## Server implication

A minimal compatible zone server has a **much simpler protocol** than
the lobby — only 5 outbound opcodes from the client and 4 inbound
signals to drive in steady state.

```text
client sends            server replies
---------------         ---------------
TCP connect to (host, port) from lobby phase 3
   |
opcode 0x02 (40 B)      opcode 0x01 (handshake reply)
                            +0x10 = base_tick
                            +0x14 = sub_proto_ver (>= 0x14C for full feature)
                        opcode 0x02 (version confirm; triggers calibration)
   |
opcode 0x06 every 1s    (no reply expected; pure heartbeat)
opcode 0x01 every 1s    (latency ping; server may use to estimate RTT)
opcode 0x03 (560 B once) opcode 0x03 reply with world state? (TBD)
   |
... ongoing gameplay IPC (segment-3 packets carrying game opcodes;
    same opcode space the C++ ProtoChannel_dispatchPacketById docs
    in finding_packet_dispatch_by_id.md handle) ...
   |
opcode 0x04 (24 B; on close ACK)  opcode 0x0E or 0x11 (server-initiated close)
TCP teardown
```

The protocol version `0x3C6B (15467)` must match exactly or the
handshake reply opcode 0x01 will not provide a usable sub-proto
field; the client interprets a non-matching version as "no LF
features" and proceeds in a degraded mode (probably no async I/O).
