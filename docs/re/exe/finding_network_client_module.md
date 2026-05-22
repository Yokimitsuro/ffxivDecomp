# Finding: `NetworkClientModule` Master Tick — Closes the Lobby↔Zone Handoff

While tracing the `RaptureLobbyCallback::vtable+0x2c` (the
zone-connect site) I found a **more important** function above it:
the `NetworkClientModule::tick` that owns both the LobbyClient and
the ZoneClient and drives the handoff between them. This closes the
remaining gap in the protocol stack documented so far.

Sources read / pinned this pass:

```text
EXE @ 0x004e30a0  NetworkClientModule_tick       master state machine, 6 states
EXE @ 0x004df0a0  LobbyClient_ctor                0x4A8 bytes
EXE @ 0x004df3d0  LobbyClient_teardownAndRelease
EXE @ 0x00da4950  LobbyClient_setupAndConnect
EXE @ 0x00dae3b0  ZoneClient_pumpConnectionState
EXE @ 0x004e11f0  LobbyClient_getReadinessField
EXE @ 0x004b3c50  NetworkModule_topLevelTick      (the parent tick)
EXE @ 0x004e3b90  ScalarTypeLoginParam_Utf8_flag2_ctor   (NOT the callback)
```

## NetworkClientModule master state machine

The NetworkClientModule is the singleton that owns BOTH the
LobbyClient and the ZoneClient. It ticks once per frame from the
application's network update path. Its master state field is at
`+0x250`:

```text
state 0 - IDLE / connect-requested
  if (this+0x2d0 trigger flag is set && this+0x240 LobbyClient is null):
    LobbyClient_ctor (FUN_004df0a0)             allocate 0x4A8 bytes
    LobbyClient_setupAndConnect (FUN_00da4950)  wire up + start TCP
    clear trigger flag

state 1 - LOBBY ACTIVE
  call FUN_004e2d00 (per-frame lobby sub-tick)
  if (this+0x24c "switch to zone" flag set):
    -> state 3
    -> tear down RaptureLobbyCallback (this+0x300)
    -> tear down LobbyClient (this+0x240) via LobbyClient_teardownAndRelease

state 2 / 3 - transient -> state 4

state 4 - ZONE STEADY
  ZoneClient_mainLoopTick (FUN_004e20a0)
  if (ready check via LobbyClient_getReadinessField passes
      && this+0x234 ZoneClient is populated):
    build outbound via FUN_004e3910
    ZoneClient_dispatchOutbound (FUN_004e0240)
    on success -> state 5

state 5 - LOBBY CLEANUP COMPLETE
  if (LobbyClient still alive):
    LobbyClient_teardownAndRelease (finally)
  ZoneClient_mainLoopTick (keep ticking the zone)
```

## NetworkClientModule field map

```text
+0x020/+0x024  configured lobby host + port (Utf8String) for state 0 connect
+0x234         ZoneClient*   (the active zone session; populated upstream
                              before state 4 reaches it)
+0x238         optional sub-channel client (chat?)
+0x240         LobbyClient*  (active lobby; created state 0, destroyed
                              state 1->3 or state 5)
+0x24c         "lobby finished, switch to zone" flag
+0x250         module state (0..5; the master state machine)
+0x254         Utf8String  (session token to inject during transition)
+0x2d0         "request connect to lobby" trigger flag
+0x2d8         trigger timestamp (debounce; 0x46 ticks between retries)
+0x2f0/+0x2f4/+0x2f8  credential triple passed to LobbyClient_setupAndConnect
+0x300         active sub-handler (RaptureLobbyCallback OR RaptureZoneCallback)
+0x308         timer / latency subsystem object (ticked via FUN_00d36d40)
+0x390..0x3A0  per-frame timing fields (last activity, RNG seed, etc.)
+0x398/+0x39c  last activity DWORD/uint32_high (for 0x3A8-tick timeout)
+0x3A8         reset interval (post-timeout, reset all timing fields)
```

## The complete client→server flow (finally end-to-end)

Combining all the findings so far:

```text
[Bootup_stateMachineTick state 0x1B]
   |
   | HTTPS GET to secure.square-enix.com -> ticket
   v
[Bootup_stateMachineTick state 0x25]
   |
   | Sets NetworkClientModule+0x2d0 = trigger flag
   | Provides (host, cred1, cred2, ticket) at +0x020/0x2f0
   v
[NetworkClientModule_tick state 0]
   |
   | LobbyClient_ctor (allocate 0x4A8 bytes)
   | LobbyClient_setupAndConnect (host, flags, port)
   |    -> LobbyClient_ensureConnection
   |       -> LobbyConnection_ctor (0xA8 bytes)
   |          -> opens TCP socket
   v
[NetworkClientModule_tick state 1 -- LOBBY ACTIVE]
   |
   | FUN_004e2d00 (lobby sub-tick) drives the four-phase login:
   |   - segment 9 / segment 10 encryption handshake
   |   - opcode 0x1F5 (lobby login) -> reply 0x1F5 or 0x0C
   |   - opcode 0x05  (service login) -> 0x15+0x16+0x17+0x0D (lists)
   |   - opcode 0x06  (game login) -> 0x0F (world server info)
   |       -> LobbyClient_decode_GameLoginPayload writes
   |          host/port/ticket to LobbyClient+0x224..+0x2d4
   |       -> LobbyClient_onSuccessfulGameLogin
   |          -> requestCb->vtable[+0x30] onGameLogin_worldInfo
   |          -> requestCb->vtable[+0x2c] onGameLogin_switchToWorld
   |             -> [RaptureLobbyCallback::switchToWorld_impl]
   |                INSTANTIATES the ZoneProtoChannel::
   |                ServiceConsumerConnectionManager with
   |                the world server (host, port, ticket).
   |                Spawns SocketThread@ZoneProtoChannel.
   |                Stores resulting ZoneClient* at NetworkModule+0x234.
   |                Sets NetworkModule+0x24c = "switch to zone" flag.
   v
[NetworkClientModule_tick state 1 transitions to state 3 -> 4]
   |
   | Tears down LobbyClient (the +0x240 slot) -- the lobby TCP socket
   | is closed; the lobby callback at +0x300 is released.
   v
[NetworkClientModule_tick state 4 -- ZONE STEADY]
   |
   | ZoneClient_mainLoopTick (FUN_004e20a0) drives the persistent
   | zone session:
   |   - emits opcode 0x02 handshake at state 1
   |   - emits opcode 0x01 latency ping every 1 s
   |   - emits opcode 0x06 heartbeat
   |   - dispatches inbound packets via the LobbyProtoDown / ZoneProtoDown
   |     callback chain
   |
   | ZoneClient_dispatchOutbound (FUN_004e0240) routes any pending
   | outbound packet through ZoneClient_forwardOutbound.
   v
[NetworkClientModule_tick state 5 -- LOBBY FULLY TORN DOWN]
   |
   | LobbyClient_teardownAndRelease completes any leftover cleanup.
   | Steady-state from here is repeated ZoneClient_mainLoopTick calls.
   v
[gameplay packets flow on the Zone channel; the lobby socket is dead]
```

## The one remaining hole

The `RaptureLobbyCallback::switchToWorld_impl` (the implementation of
the `vtable+0x2c` callback that does the actual zone-connect) is
still **not pinpointed at its concrete address**. From this pass I
now know:

- The callback at `NetworkClientModule+0x300` is the
  `RaptureLobbyCallback` instance.
- It is allocated inside the Bootup state machine state 0x1B/0x25
  setup path, before `LobbyClient_proxyStartA` is invoked.
- When it executes its `vtable+0x2c`, it must:
  1. Read world host/port/ticket from LobbyClient+0x224..+0x2d4.
  2. Construct the `ZoneProtoChannel::ServiceConsumerConnectionManager`
     (with the SocketThread for the dedicated thread).
  3. Push the resulting ZoneClient pointer into
     NetworkClientModule+0x234.
  4. Set NetworkClientModule+0x24c = 1 (the "switch to zone" flag).

The concrete vtable address could be located by:

- Finding the constant in `.rdata` that the Bootup module loads
  into the RaptureLobbyCallback's `*this`, OR
- Reading `FUN_004e0690::LobbyClient_proxyStartA` more carefully
  (the caller stack frame may push the callback's vtable address as
  part of the registration into FUN_00da47e0).

This is the natural next probe but is **not blocking** for a
server-side bring-up: the four phases of lobby login + the zone
opcode set + the zone connection field layouts are all already
pinned end-to-end.

## Assessment

```text
Confirmed:
  - NetworkClientModule_tick is the master state machine; field map
    above pins ~18 named offsets.
  - 6 states (0..5) drive the full lifecycle from "no connection
    yet" through "lobby active" to "zone steady, lobby torn down".
  - LobbyClient_ctor allocates 0x4A8 bytes (a single big object;
    includes the 0x224..+0x2d4 world-handoff slots, the credential
    Utf8Strings at +0xb0/+0x104, the list std::vectors at +0x1c0
    through +0x200, and the operation queues).
  - LobbyClient_setupAndConnect is the wiring function called from
    state 0 right after the ctor.
  - ZoneClient_pumpConnectionState maps the underlying
    ConnectionManagerTmpl state onto the ZoneClient state +0x8c.
  - LobbyClient_getReadinessField is the gate in state 4 that
    decides when the dispatcher can run.

Likely (High):
  - The "switch to zone" flag at +0x24c is set BY the
    RaptureLobbyCallback's vtable+0x2c implementation when the world
    server connection is established. The lobby cleanup at state 1
    -> 3 -> 4 is a consequence.
  - The ZoneClient is INSTANTIATED inside RaptureLobbyCallback's
    vtable+0x2c -- NOT inside the NetworkClientModule. That keeps
    the module agnostic of when the zone session opens.

Likely (Medium):
  - The two byte flags at LobbyClient+0xac/+0xad passed to
    LobbyClient_setupAndConnect are: +0xac = "use encryption" (1
    if crypto required), +0xad = "use compression" (1 if
    available).
  - State 2 being a fallthrough to state 4 suggests the original
    design had a separate "negotiating zone" state that was later
    merged.

Speculative:
  - 0x4A8 (1192 bytes) for LobbyClient_ctor includes a 256-byte
    region for cryptographic state plus the various Utf8String slots
    and the std::vector headers; the rest is the operation queues.

Next test:
  - Find the RaptureLobbyCallback concrete vtable address in
    .rdata and decompile its +0x2c slot. With the
    NetworkClientModule field map (this finding) and the lobby/zone
    architecture finding, the +0x2c implementation should be a
    short function: read the host/port from LobbyClient, allocate a
    ConnectionManager, push the result into
    NetworkClientModule+0x234, raise +0x24c flag.

Commit suggestion:
  docs(re/exe): pin NetworkClientModule master tick; closes lobby<->zone
                handoff flow
```

## Server implication (final state)

The end-to-end protocol stack from client to world server is now
documented from byte-level wire on through application-level state
machines. A server that implements:

1. The lobby outbound opcodes (4 main + 4 sub-ops; see
   `packet_lobby_outbound.md`)
2. The lobby inbound opcodes (9 total; see `packet_lobby_inbound.md`)
3. The lobby inbound payload layouts at byte level (see
   `packet_lobby_payload_layouts.md`)
4. The zone outbound + inbound rosters (5 + 4 opcodes; see
   `finding_zone_chat_channel_architecture.md`)
5. The Bootup state machine bypass for the auth server (see
   `finding_bootup_state_machine.md`)

...has everything needed to fully accept a 1.23b client connection
through to world steady state. The remaining pieces (game-side IPC
opcodes inside segment-3 packets, the actual gameplay protocol) are
documented at the structural level in
`finding_packet_dispatch_by_id.md` and live above this layer.
