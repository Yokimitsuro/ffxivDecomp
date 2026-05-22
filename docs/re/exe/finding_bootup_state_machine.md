# Finding: Bootup State Machine + How the Lobby Login Is Triggered

While trying to locate the `RaptureLobbyCallback::vtable+0x2c`
(`onGameLogin_switchToWorld`) callsite — i.e. *the* function that
opens the zone connection — I traced the upstream chain instead and
found the **bootup state machine** that drives the entire pre-game
flow. The zone-connect handoff sits inside one of its states.

Sources read / pinned this pass:

```text
EXE @ 0x006b0220  Bootup_stateMachineTick      (>1000 lines; ~58 states)
EXE @ 0x004e0690  LobbyClient_proxyStartA      (case 0x1B + 0x25 entry)
EXE @ 0x004e0790  LobbyClient_proxyStartB      (alternative entry; no callers)
EXE @ 0x00da47e0  (small ctor of callback wrapper; sets this+0xc from
                   vtable+0x04 result on the RaptureLobbyCallback)
EXE @ 0x00da4660  (LobbyClient "is-ready-to-login" gate)
```

## Bootup state machine shape

`Bootup_stateMachineTick` (`FUN_006b0220`) is a massive function that
ticks once per game frame and steps the pre-game flow through ~58
discrete states. Key fields on its parent object (`param_1`):

```text
param_1[-0xC]      parent ApplicationContext (read repeatedly)
param_1[7]         the network client module (LobbyClient parent)
param_1[9]/[0xB]/[0xC]   widget/UI subsystem pointers
param_1[0x11]      currentBootupState (the state enum, 0..0x3A)
param_1[0x12]      per-state context object (caller-provided)
param_1[0x13]      length of the context object's serialised form
param_1[0x14]      pending state push
param_1[0x53/0x54] last GetTickCount() for frame-time tracking
param_1[0x55/0x56] accumulator
param_1[0x6DE]     sub-state counter within the active state
param_1[0x6DF]     secondary sub-state counter
param_1[0x6EA]     callback object pointer
param_1[0x6FD]     "advance to next state on next tick" flag
param_1[0x71B]     bitfield of UI-init flags (bits 0, 1, 2, 3)
param_1[0x232..]   lobby-related state (decoded from previous findings)
param_1[0x6FF..]   appearance preview objects (chara make)
```

## Key states (the boot-to-world flow)

```text
state  purpose                                            calls into
-----  -------------------------------------------------  ----------------------------
0      idle / unused
1      warmup. Allocates 3 sub-objects (0x3C0, 0x3D0,     FUN_00885dc0 / FUN_0088c810
       0x860 bytes) and stores them at +0x6FF / +0x702 /  / FUN_0088b070
       +0x703. Several UI vtable +0x24 init calls.
2      title menu. Sets visibility + waits for user.      FUN_0055c8e0
3      bg/effect ready check                              FUN_00686ee0
4      enter "bg_effect" mode                             FUN_00686e30
5      enter "wsw_rtas1f" mode                            FUN_00686e30
6      close widget                                       FUN_0055c280
7      audio cue                                          FUN_006aa990
8      generic "show widget + wait for tick 0x14D"
9      tick-driven wait
0xA    similar wait variant
0xB    yet another wait
0xC    show with ticks 0x14D
0xD    set flag bytes via FUN_006a9b20
0xE    same as 0xD with different arg
0xF    chara-creation widget multi-step (per-character record)
0x10   FUN_004d6F40 mode toggle
0x11   FUN_004d6F00 mode toggle
0x12   wait until FUN_004d70f0 returns truthy
0x13   wait via FUN_004d6FE0
0x14   wait via FUN_004d7030
0x15   wait via FUN_004d7070
0x16   wait via FUN_004d70b0
0x17   set widget select state
0x18   confirm via vtable + advance
0x19   release widget
0x1A   release + wait for transition
0x1B   HTTPS GET to "secure.square-enix.com" auth server.
       Calls FUN_004e0690 (LobbyClient_proxyStartA) with
       a credential token.
0x1C   alternate auth path that opens HTTPS direct to
       "secure.square-enix.com" -- the *first* network
       contact the client makes.
0x1D   poll auth response
0x1E   set bootup error code (0xC351 / 0x3A99 etc.)
0x1F   set yet another error
0x20   load auth response payload
0x21   FUN_006ad410 (clear auth context)
0x22   widget control (camera modes 0..5)
0x23   trigger character select widget; emits cmd 0x29
       (retainer-related) via FUN_004dfb20.
0x24   no-op
0x25   *** START LOBBY LOGIN ***
       Calls FUN_004e0690 (LobbyClient_proxyStartA).
       Calls FUN_004e1eb0 (lobby HTTPS bridge) on initial
       state 0; transitions sub-state on responses.
0x26   character select main widget open. Inputs
       come back through this+0x1056.
0x27   character pre-create config push
0x28   character pre-create save
0x29   character delete
0x2A   queue drain (pop everything from +0x17/+0x18)
0x2B   *** WORLD LIST iteration ***
       For each of 24 entries, calls FUN_006aece0 to
       process. Sets +0xCD3 = 1 on completion.
0x2C   *** CHARACTER LIST iteration ***
       For each of 16 entries (with 4-tuple inner),
       extracts character details into +0xD22-region
       slots. Sets +0xD62 = 1 on completion.
0x2D   *** RETAINER LIST iteration ***
       For each retainer (16x2 records), calls
       FUN_006B4E50 to allocate 0x29 slots and copies
       0x29 dwords each. Sets +0xEA5 = 1 on completion.
0x2E   character page select. Per-character 22 dword
       records into +0xfcc / +0x100f. Each invocation
       reads from a different page via param_1[0xebb].
0x2F   gear/feature flags load (8 zero-init dwords).
0x30   chara-appearance config push (step 0..10).
0x31   chara-name input (step 0..1).
0x32   chara-name additional step (step 0..5).
0x33   16 fixed appearance slots written (each 12 B).
0x34   chara-style commit. Computes derived appearance
       values into +0x59..+0x6A.
0x35   final chara-create commit; new 0x1D0-byte object
       at +0x6DD.
0x36   set flag +0x6FD = 1
0x37   clear flag +0x6FD = 0
0x39   *** LOGOUT / TEARDOWN ***
       Closes all widgets, sets UI flags, calls
       FUN_006A9600(self, 0x15) to push state 0x15.
0x3A   clear 10 dword slots starting at +0x73.
```

### Two states that ARE the network entry points

```text
case 0x1B   HTTPS GET to "secure.square-enix.com" — the AUTH server
case 0x25   "doStartLobbyLogin" — the LOBBY login proper
```

Both go through `FUN_004e0690 = LobbyClient_proxyStartA`. The
distinction is what state of `param_1[0x6DE]` they pass:

- case 0x1B → asks the auth server for a session ticket
- case 0x25 → uses the ticket from 0x1B to start the actual lobby
  login flow documented in `finding_lobby_flow.md`

## The proxy + callback registration

`LobbyClient_proxyStartA` (`FUN_004e0690`) is what the Bootup state
machine invokes. It:

```c
LobbyClient_proxyStartA(this, callback_obj, cred1, cred2, cred3)
  if (this->lobbyClient[+0x240] != null
      && LobbyClient_isReadyToLogin(this->lobbyClient)) {
    // wrap callback_obj into a local frame
    FUN_004e3b90(local_frame, callback_obj);
    // attempt registration
    if (FUN_00da47e0(this->lobbyClient, local_frame)) {
      // success: kick the login
      LobbyClient_doStartLobbyLogin(this->lobbyClient,
                                    cred1, cred2, cred3, ...);
    }
    cleanup(local_frame);
  }
```

The `callback_obj` parameter is **the RaptureLobbyCallback instance**
(the one whose vtable+0x2c we want to find for the zone-connect step).
It is created by the Bootup module before invoking this proxy; the
instantiation site is **inside the Bootup state machine** at case
0x1B / 0x25, where the local stack frame is built and `param_1`-style
args are read out of the bootup context.

Tracking the exact construction will require reading `FUN_004e3b90`
(callback frame builder) and walking it back to the Bootup case
that pushes the callback's vtable address — which is the gate for the
zone-connect step.

## Why this matters

The chain we now have for "client → world server" is:

```text
Bootup_stateMachineTick (state 0x25)
  -> LobbyClient_proxyStartA
       -> LobbyClient_doStartLobbyLogin
            -> ... (lobby phases 1..3, see finding_lobby_flow.md)
            -> server replies opcode 0x0F (game-login payload)
                 -> LobbyClient_decode_GameLoginPayload writes host/port/ticket
                 -> LobbyClient_onSuccessfulGameLogin
                      -> requestCb->vtable[+0x30] onGameLogin_worldInfo()
                      -> requestCb->vtable[+0x2c] onGameLogin_switchToWorld()
                                                  ^^^^ THIS is the zone-connect site
                                                  (the RaptureLobbyCallback impl
                                                  TBD; instantiated somewhere in
                                                  Bootup state 0x1B/0x25 setup)
```

Once `vtable+0x2c` is identified, the rest of the zone-connect path
is straightforward:

1. Read world server (host, port, ticket, identifier, session_blob)
   from `LobbyClient+0x224..+0x2d4`.
2. Construct `Application::Network::ZoneClient::RaptureChannelManager`.
3. Spawn `Application::Network::ZoneProtoChannel::SocketThread`.
4. Send `ZoneClient_sendInitialHandshake` (opcode 0x02; documented in
   `finding_zone_chat_channel_architecture.md`).

The remaining unknown is which **specific function** implements
`RaptureLobbyCallback::vtable[+0x2c]`. That requires reading
`FUN_004e3b90` (the callback frame builder) to identify the
RaptureLobbyCallback's concrete vtable address.

## Assessment

```text
Confirmed:
  - Bootup_stateMachineTick at FUN_006b0220 drives ~58 states from
    title screen through character select.
  - State 0x1B is the auth server HTTPS handshake (secure.square-enix.com).
  - State 0x25 is the "doStartLobbyLogin" entry; both states go
    through LobbyClient_proxyStartA.
  - The callback object passed in to LobbyClient_proxyStartA is the
    RaptureLobbyCallback (matches RTTI at 0x012d7550); it is
    instantiated inside the Bootup module, not in the lobby.

Likely (High):
  - The RaptureLobbyCallback concrete vtable lives in .rdata at an
    address that FUN_004e3b90 (callback frame builder) writes into
    a local. Identifying that address gives the vtable+0x2c slot
    that is the zone-connect implementation.
  - States 0x2B / 0x2C / 0x2D are where the bootup module READS the
    world / character / retainer lists (already populated in
    LobbyClient+0x1d0..+0x200 by the lobby decoders) and renders
    them in the menu. State 0x2E loads the per-character pages.

Likely (Medium):
  - State 0x25's sub-states (param_1[0x6DE] 0 -> 1 -> 0x1BC -> end)
    track the lobby phase progression: 0 = "send phase 1", 1 =
    "send phase 2 + chara-make if needed", 0x1BC = "ready for
    phase 3 / world handoff".
  - State 0x36/0x37 are bracket states that pause the state machine
    while a sub-flow runs (the +0x6FD flag tells outer state to
    auto-advance).

Speculative:
  - State 0x29 (chara-delete) might block until the server confirms
    via the chara-make response (opcode 0x0E op 4) before clearing
    local state.

Next test:
  - Decompile FUN_004e3b90 -- the callback frame builder. This is
    where the RaptureLobbyCallback vtable address is loaded into a
    stack local. From that address, read slot +0x2c to find the
    zone-connect function.
  - Cross-reference Bootup state 0x25 against finding_lobby_flow.md
    sub-state machine (LobbyConnection.state = 3/4/5).

Commit suggestion:
  docs(re/exe): pin Bootup state machine; lobby-login entry via state 0x25
```

## Server implication

The Bootup state machine is **client-internal** — it has no direct
server contract. But it pins **where the four credential fields come
from** (the three string fields documented in `finding_lobby_flow.md`
and the auth ticket from secure.square-enix.com). A test server
operator who wants to bypass the auth server (state 0x1B) and inject
credentials directly needs to:

1. Patch state 0x1B to no-op or accept any auth ticket.
2. Patch state 0x25 to use hard-coded credentials.
3. Direct DNS / hosts override of `lobby01.ffxiv.com` and
   `secure.square-enix.com` to point at the test server.

None of these require protocol changes; they're build-time
substitutions on the client side.
