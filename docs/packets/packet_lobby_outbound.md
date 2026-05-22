# Packet Spec: Lobby Outbound Wire Shape (8 opcodes)

Wire shape of the **eight** outbound IPC packets the client sends to
the lobby server during the 4-phase login flow plus chara-make and
sub-operations. Four come from
`LobbyLoginOperation_buildAndSendPacket` (`FUN_00da9880` — the main
switch on `step_type` for big request packets); four more come from
sibling helpers on the same `LobbyLoginOperation` (small ACK / sub-op
packets).

This is the **first concrete wire spec** for any of the three IPC
channels. The lobby outbound is fully pinned; the lobby inbound (the
`LobbyProtoDownCallbackInterface` concrete vtable) is still TBD.

Sources:

```text
EXE @ 0x00da9880  LobbyLoginOperation_buildAndSendPacket  (the switch)
EXE @ 0x00da2be0  IpcPacket_buildHeader                   (header primitive)
EXE @ 0x004e7750  IpcPacket_acquireSendSlot               (enqueue)
EXE @ 0x004e80b0  IpcPacket_finalizeAndSend               (commit + send)
EXE @ 0x00da4470 / 4330 / 4350 / 4490  "get packet body ptr" helpers
                                       (one per opcode-specific layout)

LobbyConnection (also pinned this pass):
EXE @ 0x00dab290  LobbyConnection_ctor                    (0xA8 bytes)
   vtable = RaptureChannelManager::vftable
   +0x008 inner socket/IPC wrapper (0x138 bytes)
   +0x088 flag
   +0x08c connection state (1=init, 3/4/5 during login)
   +0x090.. timing + RNG seed sub-struct
```

## All four packets share an outer 16-byte IPC envelope

Per `docs/packets/packet_frame_and_segment_header.md`, all IPC payload
travels inside segment-type 3 of a 16-byte-headered IPC segment. The
opcode listed below goes into the IPC subheader; the lobby
`IpcPacket_buildHeader(buf, opcode, payload_size, flags=0)` builds
that subheader.

The **payload sizes below are post-IPC-subheader bytes** — the body
shape after the framing layers documented elsewhere.

## Opcode 0x1F5 (501) — LOBBY_LOGIN_REQUEST (phase 1)

```text
size: 0x38 (56 bytes total payload)
trigger: doStartLobbyLogin -> LobbyLoginOperation_buildAndSendPacket case 0
emitted from: step_type == 0 (InitOperationStep)
expected server response: triggers onSuccessfulLobbyLogin (-> state 5)

layout:
  +0x00  uint32  session_id        (from LobbyClient+0x0c)
  +0x04  uint32  token_or_nonce    (from operation->step+0x08)
  +0x08  uint8[0x30]  zero-padded  (the 12 dwords 2..9 are all explicitly zeroed)
```

This is the **smallest** of the four — just session id + nonce. It's
the "ping the lobby with my pre-auth credentials and tell me to start"
packet.

## Opcode 0x05 — SERVICE_LOGIN_REQUEST (phase 2)

```text
size: 0xA0 (160 bytes total payload)
trigger: LobbyLoginOperation_buildAndSendPacket case 2
emitted from: step_type == 2 (ServiceLoginOperationStep)
expected server response: triggers onSuccessfulServiceLogin (4 list callbacks)

layout:
  +0x00  uint32  session_id        (from LobbyClient+0x0c)
  +0x04  uint32  (zero from memset)
  +0x08  uint16  zero              (explicit set)
  +0x0A  uint16  CLIENT_VERSION_A = 0x6E  (110 decimal -- patch revision?)
  +0x0C  uint16  CLIENT_VERSION_B = 0x1347 (4935 decimal -- build number?)
  +0x10  char[64]  account_name    (strncpy from connection_op+8; 64-byte max)
  +0x50  char[32]  credential_A    (strncpy from this+0x38; 32-byte max)
  +0x70  char[32]  credential_B    (strncpy from this+0x8c; 32-byte max)
```

Three string fields:

- `account_name` (64 bytes): the source is `operation->step+0x08`
  which holds the login parameter passed via `LobbyLoginOperation_ctor`.
- `credential_A` (32 bytes): the operation's `+0x38` field (one of the
  two credentials the LobbyLoginOperation stored at construction).
- `credential_B` (32 bytes): the operation's `+0x8c` field (the other).

Strings are not null-terminated within the buffer — `strncpy` with a
fixed N. Server-side decode must handle non-terminated.

The two version uint16s are the **mandatory version handshake**: the
server MUST accept (0x6E, 0x1347) to let the flow progress. If you're
porting a server, hardcode acceptance of these values or reject with a
known error.

## Opcode 0x06 — GAME_LOGIN_REQUEST (phase 3)

```text
size: 0x1E0 (480 bytes total payload)
trigger: LobbyLoginOperation_buildAndSendPacket case 3
emitted from: step_type == 3 (GameLoginOperationStep)
expected server response: triggers onSuccessfulGameLogin (world handoff)

layout:
  +0x00  uint32  session_id        (from LobbyClient+0x0c)
  +0x04  uint32  zero
  +0x08  uint16  zero
  +0x0A  uint16  CLIENT_VERSION_A = 0x6E
  +0x0C  uint16  CLIENT_VERSION_B = 0x1347
  +0x10  char[0x180]  selected_blob (strncpy from connection_op+8; 384-byte max)
  +0x190 char[32]  credential_A     (strncpy from this+0x38)
  +0x1B0 char[32]  credential_B     (strncpy from this+0x8c)
  rest:  zero (the entire 0x1D0 body is memset to 0 before strncpy fills)
```

Same header shape as opcode 0x05, but with a **much larger string
field (384 bytes)** instead of 64. This carries the player's selection
from phase 2 — likely a concatenation of "(world id, character id,
selection metadata, world-server credentials)" the server returned in
the phase-2 lists.

Credentials A and B repeat from phase 2.

## Opcode 0x03 — small ACK (32 bytes)

```text
size: 0x20 (32 bytes)
emitted from: LobbyLoginOperation_sendAck32 (FUN_00daa070)
              bound to LobbyLoginOperation vtable slot at 0x01127fbc

layout:
  +0x00  uint32  session_id     (from LobbyClient+0xc)
  +0x08  uint8   sub_flag       (from this+0x3c)
  +0x09  uint8   const = 0x11   (always 17)
  +0x0C  uint32  step_token     (from this+0x38)
  rest:  zero
```

After this send, the operation's "next inbound opcode" pointer is set
to **0x0D** — i.e. the server is expected to respond with opcode 0x0D
on the LobbyProtoDown channel.

## Opcode 0x04 — small ACK (40 bytes)

```text
size: 0x28 (40 bytes)
emitted from: LobbyLoginOperation_sendAck40 (FUN_00daa740)
              bound to LobbyLoginOperation vtable slot at 0x01127fec

layout:
  +0x00  uint32  session_id      (from LobbyClient+0xc)
  +0x08  uint32  context_dword   (from (LobbyClient+0x8+0x14)+0xc)
  +0x10  uint8   context_byte    (from (LobbyClient+0x8+0x14)+0x8)
  rest:  zero
```

After this send, the "next inbound opcode" pointer is set to **0x0F**.

## Opcode 0x0B — PUT_CHARA_MAKE_DATA (480 bytes; streamed)

```text
size: 0x1E0 (480 bytes per chunk)
emitted from: LobbyLoginOperation_sendCharaMakeOrSubOp (FUN_00daa190)
              when operation_step->subtype == 0
              bound to LobbyLoginOperation vtable slot at 0x01127fd4
```

This is the **bulk chara-make data carrier**. Mode byte at +0x11 of
the payload selects:

```text
mode 0x01  NAME-only          : 400-byte block strncpy'd from step+0x6c
mode 0x02  FULL APPEARANCE    : 400-byte block from step+0xc0 via FUN_005a6f10,
                                CHUNKED LOOP -- one packet per chunk until the
                                source string is exhausted; high bit of mode byte
                                set on non-final chunks ((byte) | 0x80)
mode 0x06  RETAINER OP        : single packet, copies step+0xd byte to +0x72
other     generic
```

Shared header in every payload chunk:

```text
+0x00  uint32  session_id     (LobbyClient+0xc)
+0x10  uint8   mode           (1/2/6/other)
+0x08  uint32  field          (step+0x10)
+0x14  uint8   field          (step+0xc)
+0x0C  uint32  field          (step+0x14)
+0x12  uint16  field          (step+0xe)
+0x14  char[0x20] name        (32 B strncpy from step+0x18)
+0x34  ...     payload-specific (the 400-byte appearance for mode 2)
```

After (the last) send, the "next inbound opcode" pointer is set to
**0x0E**.

The chunked-loop behaviour for mode 2 means a full chara-make can
require **multiple wire packets** to deliver the appearance blob —
the server has to reassemble them by watching the high bit of the
mode byte.

## Opcode 0x0F — service-login sub-op (160 bytes)

```text
size: 0xA0 (160 bytes)
emitted from: LobbyLoginOperation_sendCharaMakeOrSubOp (FUN_00daa190)
              when operation_step->subtype == 1
              same Ghidra function as opcode 0x0B but a different branch

layout:
  +0x00  uint32  session_id     (LobbyClient+0xc)
  +0x10  uint8[0x20]  block_a   (memcpy 32 B from step+0x18 onwards)
  +0x30  uint8[0x60]  block_b   (memcpy 96 B from step+0x38 onwards)
  rest:  zero
```

After this send, the "next inbound opcode" pointer is set to **0x10**.

This appears to be a **service-login follow-up packet** the client
sends in response to a server hint. The 32+96-byte blocks have no
strncpy markers (they're raw memcpy), so they probably carry binary
data (e.g. a server-issued session-extension token).

## Opcode 0x1F6 (502) — CHARA_MAKE_REQUEST (phase 4, optional)

```text
size: 0x78 (120 bytes total payload)
trigger: LobbyLoginOperation_buildAndSendPacket case 4
emitted from: step_type == 4 (LobbyCharaOperationStep)
expected server response: triggers onSuccessfulCharaMake (one of 5 ops)

layout:
  +0x00  uint32  session_id        (from LobbyClient+0x0c)
  +0x04  uint32  op_token          (from connection_op+8)
  +0x08  uint8[0x20] zeros
  +0x28  char[64]  chara_name      (strncpy from local_64; 64-byte max)
  rest: filled by FUN_005a5650/FUN_005a3fb0/FUN_005a4010/FUN_005a3fe0
       and FUN_005a7730 -- structured chara-make payload (appearance,
       birthday, etc.) -- exact field map TBD by reading those helpers.
```

The chara-make payload is the **most complex** — it embeds a
structured "character creation" record built by five helper functions.
Each helper writes into a different stack region (`auStack_9c`,
`auStack_74`, `local_64`, `aiStack_54`) that ends up packed into the
payload. The op-code in `OperationStep->step_type` (1/2/3/4/6) tells
the server which sub-operation the request is for. Op 5 is reserved
(see `finding_lobby_flow.md`).

## Common send sequence

```c
IpcPacket_buildHeader(&stack_pkt, opcode, payload_size, 0);
slot = IpcPacket_acquireSendSlot(connection, &stack_pkt);
if (slot != 0) {
    body = FUN_00da4xxx(&stack_pkt);  // packet-specific body pointer
    fill_body(body);
    IpcPacket_finalizeAndSend(connection, &stack_pkt, 0);
    log("Send Packet : <opcode>");
    if (connection->inner != NULL) {
        connection->inner->state[+0x8c] = 4;   // login in progress
    }
}
IpcPacket_releaseSlot(slot);  // FUN_00da2b30
```

After every successful send, **`LobbyConnection+0x8c` (the inner
socket state) is set to 4**. The handler `onSuccessfulXxxLogin` (any
of phases 1..4) is responsible for advancing it back to 5 on the
positive response. So the state cycle is:

```text
  1 (init) -> 3 (connecting) -> 4 (login pending) -> 5 (login OK)
                                  ^                    |
                                  +--- another send ---+
```

## Pinned EXE primitives (renamed in Ghidra)

```text
Main packet builders / send primitives
  FUN_00da9880  LobbyLoginOperation_buildAndSendPacket (switch: 0x1F5/0x05/0x06/0x1F6)
  FUN_00daa070  LobbyLoginOperation_sendAck32          (0x03)
  FUN_00daa740  LobbyLoginOperation_sendAck40          (0x04)
  FUN_00daa190  LobbyLoginOperation_sendCharaMakeOrSubOp (0x0B / 0x0F)
  FUN_00da2be0  IpcPacket_buildHeader
  FUN_004e7750  IpcPacket_acquireSendSlot
  FUN_004e80b0  IpcPacket_finalizeAndSend

Inbound step handlers (server -> client step ACKs)
  FUN_00da5410  LobbyLoginOperationStep_onLobbyLogin   (sets step->done flag)

Connection management
  FUN_00da45b0  LobbyClient_ensureConnection           (allocates LobbyConnection if needed)
  FUN_00da54d0  LobbyClient_queueLoginOperation        (queues another LobbyLoginOperation)
  FUN_00da4790  InitOperationStep_kick                 (kicks via LobbyClient_ensureConnection)
  FUN_00da7040  LobbyLoginOperationStep_kick           (kicks via LobbyClient_queueLoginOperation)
  FUN_00dab290  LobbyConnection_ctor                   (0xA8 bytes; RaptureChannelManager subclass)
```

## Operation-step subclass roster (RTTI-confirmed)

The lobby has SIX OperationStep types — bigger than first thought:

```text
OperationStep                base class (RTTI at 0x0131a1c8)
  InitOperationStep          step_type 0  (RTTI 0x0131a4a8; ctor 0x00da88e0)
  LobbyLoginOperationStep    step_type 1  (RTTI 0x0131a500; ctor 0x00da89f0)
  ServiceLoginOperationStep  step_type 2  (RTTI 0x0131a558; ctor TBD)
  GameLoginOperationStep     step_type 3  (RTTI 0x0131a5b8; ctor TBD)
  LobbyCharaOperationStep    step_type 4  (RTTI 0x0131a610; ctor TBD)
```

The step_type values 0..4 line up with the switch cases in
`LobbyLoginOperation_buildAndSendPacket`, **except**: case 0 is
LobbyLogin (step_type 0 from InitOperationStep_ctor)
not "Init". So either:

- The earlier guess that InitOperationStep does the encryption-init
  segment is wrong, and the Init step actually emits the
  LOBBY_LOGIN_REQUEST (opcode 0x1F5), OR
- A separate code path handles the encryption-init segment outside of
  `LobbyLoginOperation_buildAndSendPacket`.

Likelier explanation (High confidence): `LobbyLoginOperation_buildAndSendPacket`
is only the **post-encryption application** layer. The segment-9 /
segment-10 encryption handshake is handled by the **LobbyCryptEngine**
documented earlier, *before* the LobbyLoginOperation packets ever
appear on the wire. So:

```text
TCP connect
  |
  |--(segment 9 ENCRYPTION_INIT)----------> server   (LobbyCryptEngine)
  <--(segment 10 ENCRYPTION_RESPONSE)------
  |
  |--(segment 3 opcode 0x1F5 56 bytes)----> server   (case 0)
  <--                                      server triggers onSuccessfulLobbyLogin
  |
  |--(segment 3 opcode 0x05  160 bytes)---> server   (case 2)
  <--                                      server triggers onSuccessfulServiceLogin
  |
  |--(segment 3 opcode 0x06  480 bytes)---> server   (case 3)
  <--                                      server triggers onSuccessfulGameLogin
  |--(optional segment 3 opcode 0x1F6 120 bytes) (case 4) for chara-make
  |
  TCP teardown; switch to world server
```

## Inbound side (server -> client) — partial

Each operation step has a small per-step inbound handler that fires
when the matching server response arrives. The first one is now
pinned:

```text
LobbyLoginOperationStep::onLobbyLogin  (FUN_00da5410)
  -> just sets step->done_flag (+0xd) = 1 and logs.
```

The full inbound handler chain is:

```text
server packet on LobbyProtoDown
  -> ProtoChannel_dispatchPacketById (the std::map<id, Handler> from
     finding_packet_dispatch_by_id.md)
  -> a per-opcode handler that:
       1. updates step->done_flag (via the per-step handler like
          LobbyLoginOperationStep_onLobbyLogin)
       2. eventually invokes LobbyClientMixin::onSuccessfulXxxLogin
          (which raises the LobbyConnection state and calls the
          LobbyRequestCallback vtable slots documented in
          finding_lobby_flow.md)
```

The intermediate dispatch table (opcode -> handler addr) for the
LobbyProtoDown opcodes is **TBD**. From the outbound-side "next
expected inbound opcode" markers seen in this pass, the inbound
opcodes we can predict are:

```text
After client sends ...        expected server reply opcode
0x03 small ACK                0x0D
0x04 small ACK                0x0F  (note: same value as outbound!)
0x0B chara-make data          0x0E
0x0F service sub-op           0x10
```

So the LobbyProtoDown opcode space includes at least {0x0D, 0x0E,
0x0F, 0x10}, plus the still-unidentified opcodes that trigger the
four `onSuccessfulXxx` handlers.

## Assessment

```text
Confirmed:
  - EIGHT outbound IPC opcodes on the lobby channel (up from four).
    Main request packets:
      0x1F5 LobbyLogin       (56 B)
      0x05  ServiceLogin    (160 B)
      0x06  GameLogin       (480 B)
      0x1F6 CharaMake       (120 B)
    Sub-operation / ACK packets:
      0x03  small ACK         (32 B)
      0x04  small ACK         (40 B)
      0x0B  PutCharaMakeData (480 B; chunked stream)
      0x0F  service sub-op   (160 B)
  - All eight share a session_id at +0x00 from LobbyClient+0x0c.
  - Phase 2 and 3 carry the version handshake constants 0x6E and
    0x1347 at fixed offsets +0x0A and +0x0C.
  - Two credentials (A 32 bytes, B 32 bytes) are sent in phases 2 and
    3, both copied via strncpy from LobbyLoginOperation+0x38 / +0x8c.
  - After each successful send, LobbyConnection+0x8c flips to state 4
    until the matching onSuccessfulXxxLogin handler moves it on.
  - The chara-make PutData (opcode 0x0B) is a CHUNKED stream: mode
    byte (+0x10) has its high bit set on non-final chunks; server
    must reassemble.

Likely (High):
  - LobbyConnection IS the network manager: RaptureChannelManager
    subclass with a 0x138-byte inner object that wraps the actual
    socket + framing.
  - The encryption-init / response segments (types 9/10) are emitted
    by LobbyCryptEngine on connection setup and are NOT part of the
    LobbyLoginOperation switch. So the application-layer opcodes
    start at 0x1F5; the cryptography happens earlier, transparently.
  - There are SIX OperationStep subclasses RTTI-confirmed
    (OperationStep + Init + LobbyLogin + ServiceLogin + GameLogin +
    LobbyChara). The earlier finding only had three; this pass adds
    ServiceLogin, GameLogin and LobbyChara.

Likely (Medium):
  - The clientVersion handshake (0x6E, 0x1347) decodes as the patch
    revision and build number of FFXIV 1.x. 4935 (0x1347) is a build
    number in the 1.23 patch family.
  - The 384-byte selected_blob in GAME_LOGIN_REQUEST carries the
    (world-id, character-id, session-key) tuple the player picked
    from the phase-2 lists, plus per-world session credentials the
    server returned. The strncpy origin (operation+0x8) is reused
    from phase 2, so it might be a TEXTUAL representation
    concatenated by the server.

Speculative:
  - The five helpers used in chara-make (FUN_005a5650 etc.) are
    serialisers for: appearance, voice, birthday/guardian, starting
    town, and starting class. This matches the 1.x character
    creation UI. Direct verification requires reading those helpers.

Next test:
  - Decompile the five chara-make helper functions to extract the
    exact appearance/voice/birthday/town/class field layout. That
    closes the chara-make wire spec entirely.
  - Find the constructors for ServiceLoginOperationStep,
    GameLoginOperationStep, LobbyCharaOperationStep -- their layouts
    will pin the rest of the operation->step+0x08 token shape.
  - Identify the LobbyProtoDownCallbackInterface concrete vtable to
    pin the *inbound* opcode-to-handler mapping (server -> client).
    The four onSuccessfulXxx handlers we have are LobbyClientMixin
    methods invoked indirectly via LobbyRequestCallback vtable; the
    LobbyProtoDownCallbackInterface vtable is the lower-level recv
    callback that decides which onSuccessfulXxx to invoke.

Commit suggestion:
  docs(packets): pin lobby outbound wire shape (4 opcodes)
```

## Server implication

A minimal compatible lobby server now has a concrete wire spec to
implement:

1. **Accept segment-9 / segment-10 encryption handshake** first;
   the application layer doesn't start until this completes.
2. **Receive opcode 0x1F5** (56-byte body). Read session_id and
   token_or_nonce from +0x00/+0x04. Respond with a packet that the
   client recognises as "lobby login OK", flipping
   `LobbyConnection->state` to 5 via the onSuccessfulLobbyLogin path.
3. **Receive opcode 0x05** (160-byte body). Read account_name,
   credential_A, credential_B. Confirm the version (0x6E, 0x1347)
   matches. Respond with phase-2 payloads: world list, character
   list, retainer list, slot/identity info (offsets at
   LobbyClient+0x1c0..0x200 per `finding_lobby_flow.md`).
4. **Receive opcode 0x06** (480-byte body). Read the 384-byte
   selection blob (the world+character pick) and the credentials.
   Respond with world-server host/port via the onSuccessfulGameLogin
   path.
5. **Optionally receive opcode 0x1F6** (120-byte body). Read the
   chara-make payload (chara_name + appearance/voice/birthday/town/
   class blob — TBD). Respond with a chara-make op-code response
   (1/2/3/4/6 per `finding_lobby_flow.md`).
6. **String fields are not null-terminated**: use strncpy semantics
   to extract. Max lengths are 64 (account_name, chara_name), 32
   (credentials), 384 (game-login blob).
7. **Version handshake**: reject or warn if the client's 0x0A/0x0C
   fields don't match the expected pair. For 1.23b, the expected
   values are 0x6E / 0x1347.
