# Finding: Server-Notify Family (callServerOnX / doServerOnX) + Notice Authorization Model

**Maps the server-notify mechanism** — the family of `callServerOnX` /
`doServerOnX` bindings that send event-authorization requests to the
server. These are the wire-level basis of the "notice" system that
gates all content transitions (the server-authorization checkpoint
from the Director finding).

## 1. The server-notify family

```text
PlayerBase:
  _callServerOnCommand  registrar @ 0x0073f1d0  thunk @ LAB_006de680
  _doServerOnCommand    registrar @ 0x0073f320  thunk @ (sibling)

NpcBaseClass:
  _callServerOnTalk     registrar @ 0x00736fc0  thunk @ LAB_006e9520
  _callServerOnEmote    registrar @ 0x00737110  thunk @ LAB_006e95c0
  _callServerOnPush     registrar @ 0x00737260  thunk @ LAB_006e9660
  _doServerOnTalk       registrar @ 0x007373b0  thunk @ (sibling)
  _doServerOnEmote      registrar @ 0x00737500  thunk @ (sibling)
  _doServerOnPush       registrar @ 0x00737650  thunk @ (sibling)

Thunk addresses spaced 0xa0 (160B) apart -- COMDAT MFP thunk pattern.
```

**Two prefixes**:
- `callServerOnX` — request server processing of event X (async; sets
  up a wait/notice mode)
- `doServerOnX` — execute/commit server-side for event X

**Four event types**: Command (player actions), Talk/Emote/Push (NPC
interactions).

## 2. Thunk pattern (inferred from _executeCommand sibling)

```text
These thunks are in the same unanalyzed region as _executeCommand
(LAB_006de650), which was confirmed to be:
  MOV EAX, [ECX]          ; this->vtable
  MOV EAX, [EAX + 0xa8]   ; vtable slot
  JMP EAX                 ; tail-jump to concrete impl

callServerOnCommand (LAB_006de680) is 0x30 bytes after _executeCommand,
almost certainly the SAME vtable-thunk pattern at an adjacent slot
(likely vtable[0xac] or [0xb0]). The concrete impl flows through the
same command machinery -> wire opcode 0x12d (command, CRC32) or
0x12e (RPC).

(Definitive confirmation requires creating the functions in Ghidra +
reading the vtable slot, as was done for _executeCommand.)
```

## 3. The notice authorization model

```text
The "notice" system (from the Director finding) is built on top of
the server-notify family:

EVENT MODES (checked via player:_isEventPlaying(mode)):
  "emoteDefault8"   emote in progress
  "pushDefault"     push interaction
  "pushCommand"     push command
  "noticeEvent"     a server-acknowledged event in progress

NOTICE FLOW:
  1. Client initiates a server-gated event (quest accept, instance
     start, NPC talk with consequences)
  2. Client calls callServerOnX (Command/Talk/Emote/Push)
     -> sends request to server (via command/RPC wire)
  3. Client enters "noticeEvent" event mode (waits for server)
  4. Server validates:
     - ACCEPT -> server sends confirmation -> client proceeds
       (doServerOnX commits, event continues)
     - REJECT -> server sends rejection -> _onNoticeRejected fires
       -> _onEventCancel (closeAllOwnedContentWidget + resetFade)

This is how the server GATES content WITHOUT running it:
  - The content logic runs client-side (Director/NPC Lua)
  - At authorization checkpoints, the client asks the server
    (callServerOnX) and waits (noticeEvent mode)
  - The server's yes/no gates the transition
```

## 4. callServerOnCommand in context (getSystemCommand)

```text
getSystemCommand(player, ?, command, ...)              [player 1820]
   ↓ cmdId = command:getCommandId()
   ↓ if cmdId == 24105: try command:fire() locally; if handled, return
   ↓ _callServerOnCommand(?, command, ...)   <- SERVER NOTIFY
   ↓ if cmdId == 12014 (dismount): chocobo riding error handling
       -> worldMaster:notify(ridingError) + _executeCommand(dismount)

So system commands try a local fire() first, then fall back to
_callServerOnCommand for server processing. Matches the "try local,
fall back to server" pattern seen in the spawn RPC (FUN_00896f70).
```

## 5. NPC talk uses callServerOnTalk

```text
Per npcbaseclass.lua (lines 410, 432):
  NpcBaseClass:_onTalkEvent -> self:_callServerOnTalk(actor, args)

So when a player talks to an NPC with server-relevant consequences
(quest dialogue, shop transaction), the NPC's Lua calls
_callServerOnTalk to notify the server. The server processes the
interaction outcome and authorizes (or rejects) the result.

This completes the NPC interaction picture:
  - Dialogue/animation: client-side (say/ask/normalTalkStep0)
  - Server-relevant outcomes: _callServerOnTalk -> server notify
  - Server authorizes via the notice mechanism
```

## 6. Wire opcode (inferred)

```text
The server-notify family flows through the same Zone-channel command
machinery as _executeCommand. The most likely wire opcodes:
  - 0x12d (command, 200B, CRC32) for callServerOnCommand
  - 0x12e (RPC, 104B) for the notice request/response (paired with
    a ResumeChecker -- note ClientOrderEventWaitingResumeChecker exists)

The "ClientOrderEventWaitingResumeChecker" (from the ResumeChecker
correction finding) is likely the checker that suspends the script
while waiting for the server's notice response -- confirming the
notice = RPC-request + ResumeChecker-wait pattern.
```

## 7. Server-side requirements

```text
The server must handle the notify/notice family:

1. RECEIVE callServerOnX requests (Command/Talk/Emote/Push):
   - wire opcode 0x12d or 0x12e carrying the event + actor + params

2. VALIDATE the event server-side:
   - Command: can the player do this action?
   - Talk: is the NPC interaction allowed? quest state ok?
   - Emote/Push: positional/state validation

3. RESPOND (the authorization):
   - ACCEPT: confirmation -> client proceeds (wakes the
     ClientOrderEventWaitingResumeChecker)
   - REJECT: rejection -> client _onNoticeRejected -> event cancels

4. APPLY outcomes:
   - On accept: update quest/state, grant rewards, push WorkSync

This is the SERVER AUTHORIZATION CHECKPOINT. Every server-gated
content transition (quest accept/complete, instance start/clear,
trade confirm, etc.) flows through a callServerOnX -> notice ->
accept/reject cycle.
```

## 8. Confidence

```text
Confirmed:
  - 8 server-notify bindings (callServerOnCommand/Talk/Emote/Push +
    doServerOn variants)
  - Thunks in the unanalyzed region adjacent to _executeCommand
  - getSystemCommand uses _callServerOnCommand (try-local-first pattern)
  - NPC talk uses _callServerOnTalk (per npcbaseclass.lua 410/432)
  - 4 event modes incl. "noticeEvent" (via _isEventPlaying)
  - Notice flow: callServerOnX -> noticeEvent mode -> accept/_onNoticeRejected

Likely (High):
  - callServerOnX thunks are vtable-slot jumps (same pattern as
    _executeCommand vtable[0xa8])
  - Wire path is 0x12d (command) or 0x12e (RPC) -- same machinery
  - ClientOrderEventWaitingResumeChecker = the notice-wait checker
  - This is THE server-authorization mechanism for all gated content

Speculative:
  - call* = async request (sets notice mode), do* = commit/execute
  - Each event type (Command/Talk/Emote/Push) has its own vtable slot
  - The notice response opcode is an inbound variant that carries the
    sequence id to wake the ResumeChecker
```

## 9. WIRE PATH CONFIRMED (functions created + traced)

Both thunks created in Ghidra and traced end-to-end:

```text
callServerOnCommand:
  PlayerBase_callServerOnCommand_thunk_jmp_vtable_0xb4 (0x006de680)
    MOV EAX,[ECX]; MOV EAX,[EAX+0xb4]; JMP EAX  -- vtable[0xb4] slot 45
   -> MyPlayer_callServerOnCommand_impl_vtable0xb4_send_suspend (0x006e8b30)
      [extract command from Lua stack, lookup at this+0xfc]
   -> ServerNotify_send_via_0x12d_simple_128Bpayload (0x006e2fb0)
      -> ZoneOut_send_large_simple  == OPCODE 0x12d SIMPLE (no checksum)
   -> ServerNotify_createResumeChecker_atCmdSubsystem_0xf8 (0x00893380)
   -> CoroutineContext_pushResumeChecker  -- SUSPEND until server responds

callServerOnTalk:
  NpcBase_callServerOnTalk_extractArgs_sendNotify_suspend (0x006e9520)
   -> FUN_006e5c00 -> FUN_006e2e40 (talk notify send, sibling of 006e2fb0)
   -> same ResumeChecker suspend pattern

MyPlayer vtable confirmed:
  [42] 0xa8 = executeCommand (0x0070a010)         -> 0x12d CHECKSUMMED
  [45] 0xb4 = callServerOnCommand (0x006e8b30)    -> 0x12d SIMPLE
```

### KEY DISTINCTION: checksummed vs simple 0x12d

```text
  _executeCommand (player abilities)   -> 0x12d CHECKSUMMED (v1/v2, CRC32)
  callServerOnX  (system/event notify) -> 0x12d SIMPLE (no CRC)

Both are 0x12d / 200B tagged container with a 128-byte payload.
Player ABILITIES get anti-tamper CRC32; system/event NOTIFIES use the
simple variant. The discriminator byte at packet+0x28 distinguishes
the variants server-side.
```

### CONFIRMED notice flow (definitive)

```text
1. Client calls callServerOnX (event needs server authorization)
2. -> 0x12d SIMPLE packet sent to server (128B payload: event + actor + params)
3. -> ResumeChecker created (FUN_00893380 at cmd subsystem this+0xf8)
      + CoroutineContext_pushResumeChecker -> SCRIPT SUSPENDS
4. Server validates the event
5. Server response:
   - ACCEPT -> wakes the ResumeChecker -> script resumes -> event proceeds
   - REJECT -> _onNoticeRejected fires -> _onEventCancel (cleanup)

The ResumeChecker is almost certainly ClientOrderEventWaitingResumeChecker
(per the ResumeChecker correction finding) -- the notice-wait checker.
```

## 10. Cross-references

- `finding_directorbaseclass_content_orchestration_model.md` -- the
  notice system (noticeEvent / _onNoticeRejected) this implements
- `finding_executeCommand_outbound_path_CLOSED_0x12d_checksummed.md`
  -- the sibling thunk pattern + 0x12d command wire
- `finding_outbound_rpc_0x12e_format_plus_resumechecker_count_correction.md`
  -- the RPC path + ClientOrderEventWaitingResumeChecker
- `finding_npc_event_talk_turn_flow_client_side.md` -- NPC talk
  (_callServerOnTalk is the server-notify side)
- `finding_playerbaseclass_command_flow_and_player_module.md` --
  getSystemCommand + _onCommandEvent

## Commit suggestion

```
docs(re/correlation): server-notify family (callServerOnX/doServerOnX Command/Talk/Emote/Push) + notice authorization model -- the server-gating checkpoint for all content transitions
```
