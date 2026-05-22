# Packet Spec: Lobby Inbound Wire Shape (9 opcodes)

Wire shape of the **inbound** IPC packets the lobby server sends to
the client. Closes the loop with `packet_lobby_outbound.md`.

Sources (all renamed in this pass):

```text
FUN_00da9ec0  LobbyClient_dispatchInbound_LobbyLogin    (phase 1)
FUN_00daa9f0  LobbyClient_dispatchInbound_ServiceLogin  (phase 2)
FUN_00daa950  LobbyClient_dispatchInbound_GameLogin     (phase 3)
FUN_00daac30  LobbyClient_dispatchInbound_CharaMake     (phase 4)

Payload decoders (one per inbound packet variant):
FUN_00da4b80  LobbyClient_decode_LobbyLoginPayload      (opcode 0x0C)
FUN_00da76b0  LobbyClient_decode_ServiceLoginPayload    (opcode 0x0D)
FUN_00da6320  LobbyClient_decode_WorldList              (opcode 0x15)
FUN_00da4c20  LobbyClient_decode_CharacterList          (opcode 0x16)
FUN_00da4d80  LobbyClient_decode_RetainerList           (opcode 0x17)
FUN_00da64b0  LobbyClient_decode_GameLoginPayload       (opcode 0x0F)
FUN_00da79d0  LobbyClient_decode_CharaMakePayload       (opcode 0x0E)
```

## Headline result — every inbound opcode the lobby uses

```text
opcode  phase         purpose
------  ------------  ----------------------------------------------------
0x0C     1            session/count payload that completes phase 1
0x1F5    1            auth response carrying frontend+ticket
                      (SAME opcode value as the outbound request; the
                       channel is bidirectional with this id)
0x0D     2            "all lists delivered" completion signal for service login
0x15     2            WORLD LIST                  (logged "WLD_SEQ:" / "WLD_Count:")
0x16     2            CHARACTER LIST              (logged "CHR_SEQ:" / "CHR_Count:")
0x17     2 + 4        RETAINER LIST               (re-emitted during chara-make)
0x0F     3            game-login payload (world server host/port)
                      (SAME opcode value as outbound 0x0F sub-op; different
                       payload schema)
0x10     4            game-handoff confirmation
                      (triggers vtable+0x48 with two payload pointers)
0x0E     4            chara-make response, with sub-op id at +0x1a (1-based):
                        1 Reserve, 2 Make, 3 Rename, 4 Delete,
                        6 RenameRetainer (op 5 reserved; not emitted)
```

So the LobbyProtoDown channel has **9 distinct opcodes** the client
handles. Anything else lands in the dispatcher's `default` branch and
moves the connection state to value 4 silently (no error packet sent
back to the server).

## Phase 1 dispatcher (`FUN_00da9ec0`)

Handles **two inbound opcodes** for the LobbyLogin phase:

### Opcode 0x1F5 — bidirectional auth response

```text
size: variable (at least 0x1d bytes used; full size in segment header)

payload reads:
  +0x14  uint32  ticket_seq        (logged "Ticket: <n>")
  +0x18  uint32  some_field        (param_4 in handler signature)
  +0x1a  uint16  frontend_id       (logged "Frontend: <n>")
  +0x1c  uint8   auth_success      (non-zero => proceed)

if (auth_success != 0 && some_field != 0):
    log "OnSuccessfulLobbyLogin"
    invoke LobbyClient_onSuccessfulLobbyLogin
```

### Opcode 0x0C — session/count payload

```text
size: variable

dispatcher reads:
  +0x10  payload_root        -> passed to LobbyClient_decode_LobbyLoginPayload

dispatcher logs:
  "SEQ: <unaff_ESI>"           sequence number (in register, from prior log call)
  "Count: <unaff_EBX>"         count value

if decoder returns 0:
    invoke LobbyClient_onSuccessfulLobbyLogin
```

So phase 1 can complete via **either** the 0x1F5 path (single packet
with ticket data) or the 0x0C path (session payload after a separate
ticket exchange). The OR makes the server protocol flexible.

## Phase 2 dispatcher (`FUN_00daa9f0`)

Switch over **four opcodes**. The flow in normal operation:

```text
server sends 0x15 (WORLD LIST)    -> decode into LobbyClient+0x1d0
server sends 0x16 (CHARACTER LIST) -> decode into LobbyClient+0x1e0
server sends 0x17 (RETAINER LIST)  -> decode into LobbyClient+0x1f0
server sends 0x0D ("all done")    -> decode + onSuccessfulServiceLogin
                                       (which fires the 4 vtable callbacks
                                        +0x1c, +0x20, +0x24, +0x28)
```

The completion opcode 0x0D is what triggers
`LobbyClient_onSuccessfulServiceLogin`. Each list opcode just decodes
into the per-list buffer at its slot in `LobbyClient`; the server
must send all three lists *before* the 0x0D to keep the order
consistent with the four-callback ordering in
`finding_lobby_flow.md`.

## Phase 3 dispatcher (`FUN_00daa950`)

Accepts **only opcode 0x0F**. Decoder
`LobbyClient_decode_GameLoginPayload` reads the world server host
and port (and presumably a transient session token) from the payload
at packet+0x10. On success, invokes
`LobbyClient_onSuccessfulGameLogin` — which fires the two vtable
callbacks (+0x30 worldInfo, +0x2c switchToWorld) documented in
`finding_lobby_flow.md`.

Phase 3 is **single-packet**: only one inbound message completes the
phase. There's no separate "world list confirmation" or similar.

## Phase 4 dispatcher (`FUN_00daac30`)

Three opcodes routed by the chara-make dispatcher:

### Opcode 0x0E — chara-make response

Switch on **sub-op id at +0x1a (uint16)**, converted to (id - 1):

```text
+0x1a value   subop      decoder call                                  callback slot
1             Reserve    decode_CharaMakePayload + onSuccessfulCharaMake  +0x34
2             Make       same                                              +0x38
3             Rename     same                                              +0x40
4             Delete     same                                              +0x3c
5             (reserved; default -> no-op)
6             RenameRtnr inline: log "CALL onRenameRetainerName";          +0x44
                          invoke this->callback+0x44 directly
```

Note: op 6 (RenameRetainer) is **handled inline** rather than via the
generic onSuccessfulCharaMake handler. The inline path doesn't go
through the LobbyClientMixin layer at all.

### Opcode 0x10 — game-handoff confirmation

```text
LobbyClient_dispatchInbound_CharaMake:
  if opcode == 0x10:
    if (this->connection != null && this->callback != null):
        this->callback->vtable[+0x48](connection+0x74, connection+0x80)
```

This invokes a callback slot **not previously seen** in the
LobbyRequestCallback vtable (+0x48 is past the chara-make slots at
+0x34..+0x44). Likely the "world server is reachable, ready to switch"
confirmation that the server sends *after* the game-login response
(opcode 0x0F) was acknowledged.

### Opcode 0x17 — retainer list (replay during chara-make)

Same decoder as phase 2 (`LobbyClient_decode_RetainerList`). The
server may re-emit the retainer list during a chara-make operation
that changes retainer state.

## State machine implied by inbound + outbound

```text
TCP / encryption handshake (LobbyCryptEngine; segments 9 + 10)
    |
    v
client sends 0x1F5 -> server replies 0x1F5 (or 0x0C)
    => LobbyConnection.state = 5 ; phase 1 done
    |
    v
client sends 0x05   -> server sends 0x15 (world list)
                                  0x16 (char list)
                                  0x17 (retainer list)
                                  0x0D (completion)
    => phase 2 done; LobbyClient+0x1d0..+0x200 populated
    |
    v
client sends 0x06   -> server replies 0x0F (world server info)
    => phase 3 done; world handoff starts
    |
    v
(optional) client sends 0x1F6 / 0x0B / 0x0F (sub-ops)
            -> server replies 0x0E (chara-make ack) or 0x17 (retainer list)
                                  0x10 (game-handoff confirm)
```

The lobby socket can be torn down after the client sees the
appropriate phase-3 (0x0F) completion path. The world server
connection is established in parallel and the client switches over.

## Assessment

```text
Confirmed:
  - 9 inbound opcodes on the lobby channel: 0x0C, 0x0D, 0x0E, 0x0F,
    0x10, 0x15, 0x16, 0x17, 0x1F5.
  - The world / character / retainer lists are sent as separate
    opcodes (0x15 / 0x16 / 0x17) followed by an explicit completion
    opcode (0x0D).
  - Opcode 0x1F5 is BIDIRECTIONAL — same id for the client's
    initial request and the server's auth response. The same
    handler function namespace covers both sides.
  - Opcode 0x0F is shared between the inbound game-login response
    and the outbound service-login sub-op (different payload
    schemas; the channel direction disambiguates).
  - Chara-make sub-op ids on the wire are 1-based (1..6, with 5
    reserved); the dispatcher uses (id - 1) as the switch index.
  - Op 6 (RenameRetainer) bypasses the LobbyClientMixin handler and
    invokes the callback's slot +0x44 directly from the dispatcher.

Likely (High):
  - All four phase dispatchers are slots in the same
    LobbyProtoDownCallbackInterface vtable. Each opcode is routed
    server-side by the IPC channel's std::map<id, Handler> before
    these specific functions are invoked.
  - Opcode 0x10's callback target (vtable+0x48 on a callback object
    that wasn't seen before) means the LobbyRequestCallback vtable
    extends past the chara-make slots; +0x48 is the
    "world-handoff-confirmed" slot.

Likely (Medium):
  - 0x0C and 0x1F5 in phase 1 are alternate completion paths to
    accommodate different SE backend authentication flows
    (account-server vs ticket-server). The Frontend field at +0x1a
    of opcode 0x1F5 might select which world server cluster the
    player belongs to.

Speculative:
  - The "SEQ" log values come from a register the dispatchers expect
    the caller to have already loaded; that suggests the LobbyProto
    framing adds a per-packet sequence number that the receive path
    threads through into the dispatcher. The std::map dispatcher in
    finding_packet_dispatch_by_id.md may be the source.

Next test:
  - Decompile the seven decoder functions (FUN_00da4b80, FUN_00da76b0,
    FUN_00da6320, FUN_00da4c20, FUN_00da4d80, FUN_00da64b0,
    FUN_00da79d0) to extract the exact payload field layouts for each
    inbound opcode. Sizes and offsets there pin the wire shape
    completely.
  - Find the std::map<opcode, dispatcher> table inside the
    LobbyProtoDownCallbackInterface vtable. That confirms each of
    the 4 dispatchers' opcode -> vtable-slot binding.

Commit suggestion:
  docs(packets): pin lobby inbound wire (9 opcodes; full bidirectional map)
```

## Server implication (consolidated, both directions)

The lobby flow now has a **complete opcode roster**. A test server
implementing the lobby needs to:

```text
client says           server replies
------------          --------------
0x1F5 (56 B)          0x1F5 (auth response; ticket + frontend) OR
                      0x0C  (session payload + count)
   => after this, the client expects LobbyConnection.state = 5

0x05  (160 B)         0x15  WORLD LIST
                      0x16  CHARACTER LIST
                      0x17  RETAINER LIST
                      0x0D  service-login completion
   => after 0x0D, the client expects the four list-callback methods
      to fire in onSuccessfulServiceLogin order

0x06  (480 B)         0x0F  world server host/port
   => after this, the client begins teardown of the lobby socket and
      opens a TCP socket to the new server

(chara-make path)
0x1F6 (120 B)         0x0E  with sub-op id at +0x1a (1..4 or 6)
0x0B (480 B, chunked) 0x0E  (one per chunk?)
0x0F  (sub-op 160 B)  0x10  (game-handoff confirmation)
```

Field offsets, lengths and other per-decoder details are still TBD
until the seven decoder functions are decompiled (next pass).
