# Finding: npcbaseclass_event.lua -- NPC Talk-Turn Flow (client-side content; server triggers + tracks state)

**Maps the NPC interaction / event execution flow** — how talking to
an NPC runs. Confirms the key architectural principle: **NPC dialogue,
animation, and choices are CLIENT-SIDE Lua**. The server's role is to
TRIGGER events and TRACK state, not to send dialogue.

This is the same pattern as zone-CSV-is-client-local (prior finding):
static content lives on the client; the server orchestrates state.

npcbaseclass_event.lua = 921 lines, 21 functions.

## 1. The talk-turn system (client↔server dialog coordination)

```text
"CliantTalkTurn" (sic -- typo for ClientTalkTurn) = the turn-taking
that coordinates an NPC conversation:

startCliantTalkTurn(self, mode, targetPlayer)          [177]
   - Get player position; compute NPC orientation toward player
   - mode 1: full look-at + _turnDir if angle > 1.047 rad (~60°)
   - mode 2: partial look-at (weight 0.5)
   - mode 3: no turn
   -> NPC faces the player who initiated talk

startCliantTalkTurnNoWait(self)                        [217]
   -> _waitForTurning (ResumeChecker yield -- waits for turn anim)

waitCliantTalkTurn(self)                               [224]
   -> (yields the script coroutine while turn completes)

finishCliantTalkTurn(self)                             [240]
   -> _turnBack + _cancelLookAt (NPC returns to original facing)
```

The talk-turn uses the **_waitForTurning ResumeChecker** — the NPC
script yields while the turn animation plays, then resumes. This is
the async pattern applied to conversation pacing.

## 2. Standard talk entry (normalTalkStep0)

```text
normalTalkStep0(self, msgId, params, animType, ...)    [247]
   ↓ 1. Play talk gesture via _runCharaScheduler(animId):
   ↓      animType 0 -> 403087360 (default gesture)
   ↓      animType 1 -> 403066880
   ↓      animType 2 -> 403070976
   ↓      animType 3 -> 403075072
   ↓      animType 4 -> 403079168
   ↓      animType 5 -> 403083264
   ↓      animType 6 -> 403087360 (same as 0)
   ↓      animType 7 -> 403091456
   ↓      animType 8 -> 403095552
   ↓      (IDs step by 0x1000; base 403066880 = 0x18062000)
   ↓ 2. desktopWidget:showMessage(npc, channel=38, msgId, params)
   ↓      channel 38 = NPC dialog (matches chat-channel finding)
```

So a talk step = play a gesture animation + show a dialogue message.
The animType picks the NPC's body language (nod, point, ponder, etc.).

## 3. Dialogue + choice functions

```text
say(self, msgId, msgParam, ...)                        [312]
   - Builds a parameterized message with variadic substitution params
   - Variable-length param collection loop (select-based)
   - Displays NPC dialogue (msgId -> localized text from CSV client-side)

ask(self, ...)                                         [415]
askRestrictChoices(self, ...)                          [386]
askExtendWidget(self, ...)                             [493]
askForCustomizeOption(self, ...)                       [514]
   - Present choice prompts; return the player's selection
   - The selection is what the script branches on (and what the
     server learns if it needs the outcome)

switchEvent(self, ...)                                 [801]
   - Switch to a different event mid-conversation
```

## 4. NPC gesture / utility functions

```text
getLimitedDistanceForTalk      interaction range check
lookAtPosition                 NPC looks at a world position
doSalute                       salute gesture (rank-based?)
isUpperRank                    rank comparison (GC/social)
isMapMarkerVisibleForTalkable  map marker for talkable NPCs
getMapMarkerTypeForTalkable    marker type
isContentsInAsk                content-gating in ask prompts
initForEvent / initForEventCommon  event setup
```

## 5. The client-side content principle (CONFIRMED AGAIN)

```text
NPC dialogue/animation/choices are CLIENT-SIDE Lua scripts:
  - say() takes a msgId -> client resolves to localized text from CSVs
  - normalTalkStep0 plays animations via local CharaScheduler
  - ask() shows choices via local widgets; returns selection locally
  - The entire conversation script runs in the client's Lua VM

SERVER ROLE (minimal):
  1. TRIGGER the event: "player X talked to NPC Y" -> client runs
     NPC Y's event Lua script locally
  2. RECEIVE outcomes: if the conversation has server-relevant choices
     (accept quest, buy item, etc.), the client sends the result back
     (via command 0x12d or RPC 0x12e)
  3. TRACK state: quest progress, flags, inventory changes
  4. The server NEVER sends dialogue text -- it's all client-local

This MIRRORS the zone-CSV insight:
  - Zone geometry/data: client-local
  - NPC dialogue/animation: client-local
  - Quest scripts: client-local (server tracks completion flags)
  - SERVER = state authority + event triggers + actor population

IMPLICATION: a 1.x server is dramatically simpler than a "send
everything" model. The client is a rich content engine; the server
is a state/trigger orchestrator. This is why the wire protocol is
so compact (binding-ids, msgIds, command-ids -- not text/geometry).
```

## 6. Event trigger flow (inferred end-to-end)

```text
1. Player walks up to NPC (within getLimitedDistanceForTalk)
2. Player presses interact -> command (0x12d) "talk to NPC Y"
3. Server validates + triggers event -> sends event-start to client
   (likely via command-event or a per-actor message)
4. CLIENT runs NPC Y's event Lua script:
   - startCliantTalkTurn (NPC faces player, _waitForTurning yield)
   - normalTalkStep0 / say (gesture + dialogue, channel 38)
   - ask (choices) -> player selects
   - on server-relevant choice: send result (0x12d / 0x12e)
   - finishCliantTalkTurn (NPC turns back)
5. Server updates quest/state based on choices
6. Server may push state updates (WorkSync) reflecting outcomes
```

## 7. Confidence

```text
Confirmed:
  - Talk-turn system: start/wait/finish with _waitForTurning yield
  - normalTalkStep0: animType -> CharaScheduler gesture id + showMessage
  - Channel 38 = NPC dialog (consistent with chat findings)
  - 9 talk gesture animation IDs (403066880-403095552, step 0x1000)
  - say = variadic parameterized message builder
  - ask family (4 variants) for choice prompts
  - 21 functions enumerated

Likely (High):
  - NPC dialogue/animation/choices are ENTIRELY client-side Lua
  - Server triggers events + receives choice outcomes + tracks state
  - Server never sends dialogue text (msgIds resolve client-side)
  - The compact wire protocol is a direct consequence of this design

Speculative:
  - The animType -> gesture mapping is per-NPC-personality
  - askForCustomizeOption is for character customization NPCs
  - switchEvent enables multi-stage conversations / branching quests
```

## 8. Cross-references

- `finding_npc_dialog_protocol.md` -- prior say/ask family finding
- `finding_areabaseclass_zone_bootstrap_sequence.md` -- the parallel
  "zone CSVs are client-local" insight
- `finding_playerbaseclass_command_flow_and_player_module.md` -- the
  command path that triggers NPC interaction
- `finding_worldmaster_complete.md` -- channel 38 = NPC dialog routing
- `finding_wait_thunk_universal_resume_checker_confirmed.md` --
  _waitForTurning ResumeChecker used in talk turns

## 9. Next test

```text
1. Read the rest of say/ask (choice return handling)
2. Read a concrete director/event script (61s57qvs dir) to see a full
   quest/event orchestration
3. Map the event-start trigger wire path (how server starts an event)
4. Read npcbaseclass.lua main (623 lines) for NPC spawn/AI hooks
5. Trace askForCustomizeOption -> character customization flow
```

## Commit suggestion

```
docs(re/lua): npcbaseclass_event.lua -- NPC talk-turn flow (client-side content); server triggers events + tracks state, never sends dialogue; channel 38; 9 gesture anim IDs
```
