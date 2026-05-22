# Finding: Lobby Login Flow — 4 Sequential Phases + 5 Chara-Make Operations

Map the FFXIV 1.x lobby flow end-to-end from the EXE side. This is the
piece that lets a compatible server accept the client's first
connection and walk it through authentication, character selection,
and world handoff.

Sources:

```text
EXE namespaces (RTTI-recovered, all under Application::Network::LobbyClient::*
unless noted):
  LobbyClientModule
  LobbyClientMixin
  LobbyLoginParam
  LobbyRequestCallback
  ScalarTypeLoginParam<Utf8String, flags 0/1/2>
  LobbyProtoDownDummyCallback
  Application::Network::LobbyProtoChannel::*
    LobbyProtoDownCallbackInterface
    ServiceConsumerConnectionManager
    LobbyCryptEngine
    ConsumerConnection
    LobbyProtoUpPacketBuilder / ClientPacketBuilder
  Application::Main::Menu::Bootup::RaptureLobbyCallback

EXE functions (renamed in this pass):
  FUN_00da55c0  LobbyClient_doStartLobbyLogin           (entry: begin login flow)
  FUN_00da4f80  LobbyClient_onSuccessfulLobbyLogin      (phase 1 ACK handler)
  FUN_00da5030  LobbyClient_onSuccessfulServiceLogin    (phase 2 ACK handler)
  FUN_00da5110  LobbyClient_onSuccessfulGameLogin       (phase 3 ACK handler)
  FUN_00da5190  LobbyClient_onSuccessfulCharaMake       (phase 4 -- optional)
  FUN_00da4f30  LobbyClient_CloseLobbyConnection
  FUN_00da5300  LobbyClient_gcCompletedOpsAndCheckActive
  FUN_00dad770  LobbyOperation_ctor                     (base class ctor)
  FUN_00dad750  LobbyRequestCallback_ctor               (callback base ctor)
  FUN_00da84c0  LobbyLoginOperation_ctor                (0xE0 bytes; inherits LobbyOperation)
  FUN_00da88e0  InitOperationStep_ctor                  (0x6c bytes; inherits LobbyRequestCallback)
  FUN_00da89f0  LobbyLoginOperationStep_ctor            (0xb8 bytes; inherits LobbyRequestCallback)

Configuration strings:
  0x00f90100 "net_lobby_port"               port override key
  0x00f90110 "lobby01.ffxiv.com"            default hostname
  0x00f90124 "net_lobby_host"               host override key
  0x00f90134 "net_debug_lobby_retry_count"  retry count override
  0x00f90150 "net_debug_lobby_retry_interval"
```

## Headline architecture

A successful FFXIV 1.x login is a **4-phase sequence**, each driven by
a different server response that triggers a different client-side
ACK handler. The handlers all live on the `LobbyClientMixin` class
and all share the same generic shape:

```text
log "LobbyClientMixin::onSuccessfulXxx:"
if connection alive:
    log "OK"
    invoke one or more vtable methods on the
    LobbyRequestCallback object stored in the
    stack-frame parameter (the "request" who initiated
    this phase)
else:
    log "NO"
```

The phases:

```text
1.  doStartLobbyLogin  ->  onSuccessfulLobbyLogin    set state to 5
                                                     (post-lobby-login)
2.                     ->  onSuccessfulServiceLogin  receive world list,
                                                     character list,
                                                     retainer list,
                                                     slot info
3.                     ->  onSuccessfulGameLogin     receive world-server
                                                     host/port and switch
                                                     over
4.  (optional)         ->  onSuccessfulCharaMake     chara-make op completed
                                                     (5 sub-types)
```

## Class hierarchy (RTTI-confirmed)

```text
LobbyOperation                                      base class for "a command to the lobby server"
  +0x00 vftable
  +0x08 LobbyClient*   parent / owner
  +0x0c id field
  +0x10 status = 1     initial = "pending"
  +0x18 ?              embedded substructure (FUN_00d353f0 init)
  +0x30/+0x34 context dwords
└─ LobbyLoginOperation                              total 0xE0 bytes; the persistent op that survives across phases 2 and 3
     +0x38 Utf8String  credential A
     +0x8c Utf8String  credential B

LobbyRequestCallback                                base class for "the request-side observer"
  +0x00 vftable        (the LobbyRequestCallback vtable documented below)
├─ InitOperationStep                                total 0x6c bytes; first of the setup pair
│    +0x04 step_type = 0
│    +0x08 context dword
│    +0x0c flag byte
│    +0x10 Utf8String  (endpoint or handshake blob)
│    +0x54 uint16      derived from string + 0x15
│    +0x68/+0x69 byte flags
└─ LobbyLoginOperationStep                          total 0xb8 bytes; second of the setup pair
     +0x04 step_type = 1
     +0x08 context dword
     +0x0c flag byte
     +0x10..+0x54  data via FUN_00da8390 (Utf8String + derived field)
```

The class graph shows **two unrelated hierarchies** for the lobby flow:

- **Operations** (`LobbyOperation` / `LobbyLoginOperation`) are the
  client-side wrappers around a server command. They live in queues on
  the `LobbyClient` and carry the per-attempt state (credentials,
  status, retry counter).
- **Callbacks** (`LobbyRequestCallback` / `InitOperationStep` /
  `LobbyLoginOperationStep`) are the observer-side objects that
  receive the four-phase ACKs. They live alongside the Operation and
  hold per-step transient state.

The `LobbyRequestCallback` *base* vtable is what the four
`onSuccessful*` handlers invoke — i.e. the table mapped in the
"LobbyRequestCallback vtable (consolidated)" section below. Concrete
subclasses (the two OperationSteps) override the relevant slots.

## Operation queues on `LobbyClient`

```text
LobbyClient+0x044  "setup queue"          drained when there is no live
                                          connection. Holds the
                                          (InitOperationStep, LobbyLoginOperationStep)
                                          pair that drives the segment-9 /
                                          segment-10 encryption handshake
                                          plus the initial auth.

LobbyClient+0x1a8  "login queue"          drained when the connection is
                                          already in state 3/4/5. Holds
                                          LobbyLoginOperation objects, one
                                          per login attempt. Each persistent
                                          op carries the flow across phases
                                          1..3 of one full login attempt.

LobbyClient+0x1b0  "active op head"       set when a queue head is currently
                                          being processed (used by
                                          gcCompletedOpsAndCheckActive to
                                          decide whether to clean up).
```

## Phase 0: `doStartLobbyLogin` — kick the login flow

```c
LobbyClient_doStartLobbyLogin(this, cred1, cred2, loginParams, _, errorNotifyCb)

  // freshness check: if >900 s (15 min) since last activity, force-close
  if (time() - this->lastActivityTs[+0x28] > 900) {
    LobbyClient_CloseLobbyConnection(this);
  }

  // capture credentials into Utf8String fields
  this->credentialA[+0xb0]  = cred2;
  this->credentialB[+0x104] = sysCfg("???");  // pulled from a system config blob

  state = this->connection[+8]->state[+0x8c];

  if (state in {3, 4, 5} && isReadyToLogin(this)) {
    log "doStartLobbyLogin";
    this->loginAttemptCounter[+0x18]++;
    // queue a 0xE0-byte LoginOperationStep on this->loginOpQueue[+0x1a8]
    op = new LobbyLoginOperationStep(this, attemptCounter, errorNotifyCb,
                                     this[+0x330], loginParams, cred1);
    enqueue(this->loginOpQueue[+0x1a8], op);
    return true;
  }

  // otherwise (no connection yet, or connection in wrong state)
  log "doResetConnection";
  this->connectionState[+0x40] = 0;
  // queue setup pair on this->setupOpQueue[+0x44]:
  setupA = new SetupOpA(this[+0x54]);          // 0x6c bytes
  setupB = new SetupOpB(this->credentialA);    // 0xb8 bytes
  enqueue(this->setupOpQueue[+0x44], setupA);
  enqueue(this->setupOpQueue[+0x44], setupB);
  return setupA->kick();                       // vtable+0x58 on first op
```

So:

- The lobby session state machine has at least state values **3, 4,
  5** (pre-login / login-in-progress / post-lobby-login).
- A fresh session always boots through a **two-step setup pair** (the
  0x6c + 0xb8 ops); only then does it queue the actual login op
  (0xE0 bytes).
- A staleness gate of 900 seconds forces a clean reconnect.

## Phase 1: `onSuccessfulLobbyLogin` (initial auth)

```c
LobbyClient_onSuccessfulLobbyLogin(this, [stackArg] requestCb)
  log "LobbyClientMixin::onSuccessfulLobbyLogin:";
  if (this->connection[+8] == 0) { log "NO"; return; }
  this->connection->state[+0x8c] = 5;          // move to post-lobby-login
  log "OK";
  if (requestCb != null) {
    requestCb->vtable[+0x10]();                // "lobby login OK"
    requestCb->vtable[+0x14](this[+0x1c0]);    // pass session blob
  }
```

After this handler runs, the LobbyClient is **state 5**. The server
must have:

- Sent something that the LobbyConnection's RecvCallback recognised
  as "lobby auth OK" (the wire packet shape is in segment-3 IPC; the
  exact opcode is in the LobbyProtoDown union — TBD).
- Pre-populated `this+0x1c0` with whatever session blob the client
  needs to keep for the rest of the flow (~16 bytes by stride
  inference; likely a session token + identity).

## Phase 2: `onSuccessfulServiceLogin` (lists)

```c
LobbyClient_onSuccessfulServiceLogin(this, [stackArg] requestCb)
  log "LobbyClientMixin::onSuccessfulServiceLogin:";
  if (this->connection[+8] == 0) { log "NO"; return; }
  log "OK";
  if (requestCb != null) {
    requestCb->vtable[+0x20](this[+0x1d0]);                       // world list
    requestCb->vtable[+0x24](this[+0x1d0], this[+0x1e0]);          // char list
    requestCb->vtable[+0x28](this[+0x20], this[+0x1d0],
                             this[+0x1e0], this[+0x1f0]);          // retainer list
    requestCb->vtable[+0x1c](this[+0x20], this[+0x1d0],
                             this[+0x1e0], this[+0x1f0],
                             this[+0x200]);                        // "all done"
  }
```

Field map (high confidence by stride and field reuse across calls):

```text
this+0x020   session key / token         (uint32, set during phase 1)
this+0x1c0   lobby session blob          (~16 bytes)
this+0x1d0   world list                  (16 bytes header, array body)
this+0x1e0   character list              (16 bytes header, array body)
this+0x1f0   retainer list               (16 bytes header, array body)
this+0x200   slot/identity info          (~16 bytes)
```

The server therefore must, in phase 2, push **four pieces of data**:
the world list (worlds the player can pick), the character list (the
player's existing characters, possibly filtered by world), the
retainer list (the player's retainers), and a slot/identity block.

The callback `+0x1c` ("all done") fires after the three list
callbacks and is the cue for the menu to start rendering.

## Phase 3: `onSuccessfulGameLogin` (world handoff)

```c
LobbyClient_onSuccessfulGameLogin(this, [stackArg] requestCb)
  log "LobbyClientMixin::onSuccessfulGameLogin:";
  if (this->connection[+8] == 0) { log "NO"; return; }
  log "OK - ";
  if (requestCb != null) {
    requestCb->vtable[+0x30]();   // world-server info (host/port etc.)
    requestCb->vtable[+0x2c]();   // switch-to-world trigger
  }
```

Two-step shape: first deliver the world-server info, then trigger the
switch. The vtable methods at +0x30 and +0x2c don't show args here
because both are no-arg in the decompile, but they almost certainly
read off fixed offsets in `this` that the recv path filled in. The
expected slots: `this+0x?` holds the world server `(host, port)` and
a transient session key the world server uses to re-authenticate.

After +0x2c the **lobby socket can be torn down**; the client is now
talking to the world server.

## Phase 4: `onSuccessfulCharaMake` (chara-make ops, optional)

```c
LobbyClient_onSuccessfulCharaMake(this, [stackArg1] opCode, [stackArg2] requestCb)
  log "LobbyClientMixin::onSuccessfulCharaMake:";
  if (this->connection[+8] == 0) {
    log "NO"; return;
  }
  log "OK";
  if (requestCb != null) {
    switch (opCode) {
      case 1: log "CALL onReserveCharacterName";  requestCb->vtable[+0x34](); break;
      case 2: log "CALL onMakeCharacter";          requestCb->vtable[+0x38](); break;
      case 3: log "CALL onRenameCharacterName";    requestCb->vtable[+0x40](); break;
      case 4: log "CALL onDeleteCharacterName";    requestCb->vtable[+0x3c](); break;
      case 5: // (no callback)                                                  break;
      case 6: log "CALL onRenameRetainerName";     requestCb->vtable[+0x44](); break;
    }
  }
```

The five operations the server can confirm:

```text
opCode  op                          callback slot
------  --------------------------- -------------
  1     ReserveCharacterName        vtable+0x34
  2     MakeCharacter               vtable+0x38
  3     RenameCharacterName         vtable+0x40
  4     DeleteCharacterName         vtable+0x3c
  5     (reserved -- no callback)
  6     RenameRetainerName          vtable+0x44
```

So a server's "chara-make response" packet must carry one of these
six op-codes (1..6, with 5 reserved). The client uses the op-code to
pick the right callback. Op-codes 5 and any higher are silently
dropped.

The chara-make phase is **optional** — only invoked if the player
chose to create / rename / delete a character or retainer. Most
session-flow logins skip phase 4 entirely and proceed directly from
phase 2 (character list) to phase 3 (game login) once the player
picks an existing character.

## The `LobbyRequestCallback` vtable (consolidated)

Pulled from all four phase handlers:

```text
slot   purpose                                  args
-----  ---------------------------------------  -----------------------------------
+0x10  onLobbyLogin_ack                         (no args)
+0x14  onLobbyLogin_sessionBlob                 (sessionBlob*)
+0x1c  onServiceLogin_complete                  (sessionKey, worldList, charList,
                                                 retainerList, slotInfo)
+0x20  onServiceLogin_worldList                 (worldList*)
+0x24  onServiceLogin_charList                  (worldList*, charList*)
+0x28  onServiceLogin_retainerList              (sessionKey, worldList, charList,
                                                 retainerList)
+0x2c  onGameLogin_switchToWorld                (no args; read world from this)
+0x30  onGameLogin_worldInfo                    (no args; read world from this)
+0x34  onReserveCharacterName_done              (no args)
+0x38  onMakeCharacter_done                     (no args)
+0x3c  onDeleteCharacterName_done               (no args)
+0x40  onRenameCharacterName_done               (no args)
+0x44  onRenameRetainerName_done                (no args)
```

This is **the contract a server needs to satisfy** for the menu to
progress through the full flow.

## Operational logs (for diagnosis)

Strings that appear in the operation path:

```text
LobbyClientMixin::onSuccessfulLobbyLogin:        phase 1 ACK
LobbyClientMixin::onSuccessfulServiceLogin:      phase 2 ACK
LobbyClientMixin::onSuccessfulGameLogin:         phase 3 ACK
LobbyClientMixin::onSuccessfulCharaMake:         phase 4 ACK
doStartLobbyLogin                                phase 0 entry
doResetConnection                                phase 0 reset path
OnSuccessfulLobbyLogin                           ?
LobbyLoginOperationStep::onLobbyLogin            operation-step internal log
LobbyChannelManager::onAcceptConnection!!        TCP accept ok
LobbyChannelManager::onSetupConnection!!         setup pair completed
LobbyChannelManager::onNewChannel!!              channel registered
CloseLobbyConnection                             close path
Remove LobbyOperation                            operation cleanup
```

A bringing-up server with debug builds will see exactly this set of
logs as the handshake progresses; absence of any log line pinpoints
where the protocol diverged.

## Assessment

```text
Confirmed:
  - Login is a strict 4-phase sequence on the LobbyClient side. Each
    phase has its own ACK handler on LobbyClientMixin and progresses
    the LobbyConnection state.
  - LobbyConnection state value 5 = "post-lobby-login, ready for
    service-login".
  - The LobbyRequestCallback vtable has at least 13 named slots
    (table above). Each is invoked by exactly one of the four ACK
    handlers.
  - The chara-make phase has 5 distinct sub-operations (1=Reserve,
    2=Make, 3=Rename, 4=Delete, 6=RenameRetainer; 5 reserved).
  - A 900-second inactivity timeout forces a reconnect on the next
    doStartLobbyLogin.

Likely (High):
  - Phase 1 carries authentication credentials (cred1 + cred2 in
    doStartLobbyLogin). The "ScalarTypeLoginParam<Utf8String> flags
    0/1/2" RTTI strings indicate THREE typed credentials are passed
    in via the LoginParam class; the two we see in this function are
    only the first two.
  - The server's response packets for each phase carry a
    well-defined payload that maps 1:1 to the offsets at this+0x020,
    +0x1c0, +0x1d0, +0x1e0, +0x1f0, +0x200. The "service login"
    payload is the heaviest (4 lists + identity), perhaps ~512 bytes.

Likely (Medium):
  - The two-step setup pair (0x6c + 0xb8) is the LobbyCryptEngine
    handshake -- segment types 9 (ENCRYPTION_INIT, 0x278) and 10
    (ENCRYPTION_RESPONSE, 0x290) documented in the segment-frame
    finding. Each step constructs one of those segments.
  - The post-phase-3 switch-over does NOT require a graceful
    teardown of the lobby socket; the client tears it down once the
    world socket is alive. A test server can leave the lobby socket
    open on its side and let it timeout.

Speculative:
  - That opCode 5 in chara-make is reserved for "MoveCharacter
    between worlds", a feature SE never landed in 1.x.
  - That this+0x330 (passed to LobbyLoginOperationStep ctor) is a
    pre-computed challenge-response token derived from
    cred1/cred2/the crypt key.

Next test:
  - DONE: FUN_00da4f30 is the close path -- it just clears
    LobbyClient+0x08 (the connection ptr) after invoking
    connection->vtable[0] (release).
  - DONE: FUN_00da5300 is not "isReadyToLogin"; it is
    gcCompletedOpsAndCheckActive -- it walks LobbyClient+0x1a8 (the
    login queue), removes completed ops, and returns true if the
    queue is still active. It runs AFTER the state check, not before
    it.
  - DONE: the three operation-step constructors are now named and
    their layouts documented. The actual wire-payload writers are
    deeper: in the step's vtable+0x58 ("kick"), which builds and
    sends via a LobbyProtoUpPacketBuilder. Pinning those is the next
    real step.
  - PENDING: identify the LobbyProtoDownCallbackInterface vtable in
    .rdata (RTTI at 0x0131a0d0) -- finds which concrete functions
    populate slots +0x10..+0x44 of the LobbyRequestCallback for
    incoming packets.
  - PENDING: decompile InitOperationStep::vtable[0x58] (the "kick")
    to see exactly which segment-9 ENCRYPTION_INIT bytes the client
    sends first.

Commit suggestion:
  docs(re/exe): document lobby login flow (4 phases + chara-make)
```

## Server implication (consolidated)

A minimal compatible lobby server has to:

1. **Accept TCP** on the configured port. Default hostname is
   `lobby01.ffxiv.com`; client override via `net_lobby_host` /
   `net_lobby_port`. The latter must be in the live system config or
   the registry; for a test server, point `net_lobby_host` at
   localhost.
2. **Negotiate encryption** by sending the segment-type-9
   `ENCRYPTION_INIT` (0x278 bytes) and accepting the client's
   segment-type-10 `ENCRYPTION_RESPONSE` (0x290 bytes). The
   `LobbyCryptEngine` handles the symmetric key derivation.
3. **Phase 1 (LobbyLogin)**: receive the client's credential packet
   (containing the three `ScalarTypeLoginParam<Utf8String>` strings:
   flags 0/1/2), validate, respond with a "lobby auth OK" packet
   that carries the session blob the client will store at +0x1c0.
4. **Phase 2 (ServiceLogin)**: receive the client's "give me my
   lists" request, respond with four payloads: world list, character
   list, retainer list, slot info (the offsets at this+0x1d0,
   +0x1e0, +0x1f0, +0x200). The session key at this+0x20 is set by
   one of these.
5. **Phase 3 (GameLogin)**: receive the client's "I picked this
   character/world" request, respond with the world server's host,
   port and a transient session token. After this the client tears
   down the lobby socket.
6. **(Optional) Phase 4 (CharaMake)**: receive a chara-make op
   request (Reserve / Make / Rename / Delete / RenameRetainer),
   process, respond with the matching op-code in [1..4, 6].
   Op-code 5 must not be used.
7. **Keep retries reasonable**: the client has tunable
   `net_debug_lobby_retry_count` / `net_debug_lobby_retry_interval`.
   For a test server, infinite retries are typical.
8. **The 900-second freshness timeout** means a long-idle client
   will silently reconnect; don't rely on a single TCP connection
   surviving across menu activity.
