# Packet Spec: Lobby Outbound Wire Shape (4 opcodes)

Wire shape of the four outbound IPC packets the client sends to the
lobby server during the 4-phase login flow. Extracted from
`LobbyLoginOperation_buildAndSendPacket` (`FUN_00da9880`) — a single
function with a switch on `step_type` (0/2/3/4) that emits all four.

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
FUN_00da9880  LobbyLoginOperation_buildAndSendPacket
FUN_00da2be0  IpcPacket_buildHeader
FUN_004e7750  IpcPacket_acquireSendSlot
FUN_004e80b0  IpcPacket_finalizeAndSend
FUN_00da45b0  LobbyClient_ensureConnection
FUN_00da54d0  LobbyClient_queueLoginOperation
FUN_00da4790  InitOperationStep_kick
FUN_00da7040  LobbyLoginOperationStep_kick
FUN_00dab290  LobbyConnection_ctor
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

## Assessment

```text
Confirmed:
  - Four outbound IPC opcodes on the lobby channel: 0x1F5 (LobbyLogin),
    0x05 (ServiceLogin), 0x06 (GameLogin), 0x1F6 (CharaMake).
  - Payload sizes: 56 / 160 / 480 / 120 bytes (the body part inside
    the segment-3 IPC).
  - All four share a session_id at +0x00 from LobbyClient+0x0c.
  - Phase 2 and 3 carry the version handshake constants 0x6E and
    0x1347 at fixed offsets +0x0A and +0x0C.
  - Two credentials (A 32 bytes, B 32 bytes) are sent in phases 2 and
    3, both copied via strncpy from LobbyLoginOperation+0x38 / +0x8c.
  - After each successful send, LobbyConnection+0x8c flips to state 4
    until the matching onSuccessfulXxxLogin handler moves it on.

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
