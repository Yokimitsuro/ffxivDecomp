# Finding: NPC Dialog Protocol — `say`, `ask`, and the `askForEventMode` Primitive

Extends `finding_npc_event_system.md` with the complete client-side
dialog flow: the `say` channel ID, the variants of `ask` (basic,
restricted, extended, customize), and the unified
`desktopWidget:askForEventMode` primitive that all of them delegate
to.

Sources read:

```text
chara/npc/npcbaseclass_event.lua    921 lines
  getLimitedDistanceForTalk         line 4
  initForEventCommon                line 19-30
  startCliantTalkTurn               line 35-172
  startCliantTalkTurnNoWait         line 177-212
  waitCliantTalkTurn                line 217-222
  finishCliantTalkTurn              line 227-235
  normalTalkStep0                   line 240-310
  say                               line 312
  askRestrictChoices                line 386
  ask                               line 415
  askExtendWidget                   line 493
  askForCustomizeOption             line 514
```

## Talk Range Constant

```text
NpcBaseClass:getLimitedDistanceForTalk()  -> 7
```

The maximum distance (in game units, likely meters) for a player to
initiate Talk on an NPC. Server-side range checks should use this
value as the upper bound. Sit/Emote/Push interactions don't
explicitly declare a range; they probably inherit the same 7-unit
limit.

## `startCliantTalkTurn(self, mode, player)` — 8 modes (0-7)

Previously documented as modes 1-3. The actual mode space is 0-7:

```text
mode  source position            turn behavior          look behavior
----  ------------------------   -------------------    --------------------
 0    player position            no body turn           lockon player (weight 1)
 1    player position            full body turn if      lockon player (weight 1)
                                 angle > 1.047 rad
 2    player position            no body turn           lockon player (weight 0.25)
 3    explicit A3,A4,A5 coords   turn to coord          (no look)
 4    explicit A3,A4,A5 coords   no body turn           lookAtPosition(coords)
 5    player-position-MIRRORED   turn AWAY from player  (mirror; for chair etc)
 6    player-position-MIRRORED   no body turn           lookAtPosition(mirror)
 7    player position            no body turn (if angle  lockon player (weight 0.25)
                                 > 1.047)
```

The "MIRRORED" modes (5, 6) compute `npc_pos - (player_pos - npc_pos)`,
which is the point reflected through the NPC's own position. Used
for sit/relaxation animations where the NPC "settles in" away from
the player.

The 0.523 rad threshold (~30°) vs 1.047 rad (~60°) distinguishes
"just glance" from "turn whole body". So a player approaching from
slightly off-center gets head turn; from significantly off-center
gets full body turn.

## `say(npc, msg, ...)` — the NPC chat channel

```lua
NpcBaseClass:say(msg, ...)
  desktopWidget:showMessage(self, 38, msg, ...)
end
```

Channel **38** is the NPC dialog channel (confirmed; same as previous
finding). Variadic args are message-substitution parameters (player
name, item count, etc.).

Server implication: an NPC saying anything triggers a single
`desktopWidget:showMessage(actorId, 38, msgId, ...args)` call. The
server sends the actorId of the NPC, message id, and substitution
args; the client looks up the message text from `messageSheet`.

## `ask` family — 4 variants of the choice prompt

All four delegate to `desktopWidget:askForEventMode` with different
flag combinations. The unified primitive signature:

```text
desktopWidget:askForEventMode(
  self,              -- the calling actor (npc)
  npc,               -- the dialog source (usually same as self)
  msgId,             -- message id from messageSheet
  mode,              -- (1 for ask family) UI mode discriminator
  hideUI,            -- boolean: hide other UI elements during prompt
  allowCancel,       -- boolean: player can cancel (returns -3)
  choiceBaseId,      -- base message id for the choices
  choicesArray,      -- table of [choiceBaseId + i for enabled choices]
  ...varargs         -- additional rendering params
)
-> returns chosen index (or nil if cancelled)
```

### Variant 1: `ask(npc, msg, choiceBaseId, choiceCount, ...)`

The simplest variant. Computes choices = `[base+1, base+2, ..., base+count]`
and calls `askForEventMode(... mode=1, hideUI=false, allowCancel=false ...)`.

```lua
function NpcBaseClass:ask(msg, choiceBaseId, choiceCount, ...)
  choices = build_choices(choiceBaseId, choiceCount)
  return desktopWidget:askForEventMode(self, self, msg, 1, false, false,
                                        choiceBaseId, choices, ...)
end
```

### Variant 2: `askRestrictChoices(npc, msg, choiceBaseId, ...enabledFlags)`

Same as `ask` but the trailing variadic args are **booleans** that
gate which choices appear. Only choices with `true` flag are added to
the choicesArray. Used when some menu options are conditionally
available.

```lua
function NpcBaseClass:askRestrictChoices(msg, choiceBaseId, ...flags)
  choices = {}
  for i, flag in ipairs(flags):
    if flag == true: append(choices, choiceBaseId + i)
  return desktopWidget:askForEventMode(self, self, msg, 1, false, false,
                                        choiceBaseId, choices, ...extras)
end
```

### Variant 3: `askExtendWidget(npc, msg, choiceBaseId, choiceCount, mode, modeParam, ...)`

Takes a `mode` arg 0-3 that encodes the `(hideUI, allowCancel)` flag
combo:

```text
mode  hideUI  allowCancel
----  ------  -----------
 0    false   false
 1    false   true
 2    true    false
 3    true    true
```

So `mode` becomes a compact 2-bit flag pair. The `modeParam` (A5_2)
is the value passed as the `mode` arg to `askForEventMode` (instead
of the constant 1 used by `ask`).

### Variant 4: `askForCustomizeOption(...)`

7-arg variant for character customization screens. Passes its args
directly through to `askForEventMode` with no transformation. Used
when the calling code already knows the exact `askForEventMode`
signature.

## The Talk Turn Protocol (full sequence)

For a typical Talk interaction:

```text
1. Player presses interact on NPC.
2. Client sends _callServerOnTalk(npc, player) -- the request goes
   server-side.
3. Server validates: is player in range (<7 units)? Is NPC available?
4. Server sends _onTalkEvent(npc, player, scriptParams).
5. Client runs NpcBase:_onTalkEvent:
   - desktopWidget:isEventLockonCameraEnable()? -> if so, set lockon
     target to NPC.
   - _callServerOnTalk(npc, player) ... (re-call into server-side
     script)
   - _setLockonTarget(nil) -> clear lockon
   - desktopWidget:cancelAllTarget() -> clear any target indicators
6. The NPC's server-side dialog script runs:
   a. startCliantTalkTurn(mode, player) -- yield wait for animation
   b. say(msgId) -- yield to show message
   c. ask(msgId, choiceBase, count) -- yield for player choice
   d. ... -- branching logic based on choice
   e. finishCliantTalkTurn() -- restore NPC facing
7. _onEventCancel fires for cleanup, both sides.
```

## Server implication for NPC dialog implementation

A server implementing NPC dialog needs to handle:

```text
inbound from client:
  TalkRequest(npcActorId, playerActorId)       -- on player interact
  TalkResponse(choiceIndex)                     -- on player choosing option
  TalkCancel(npcActorId)                        -- on player escape/move-out
  EmoteRequest/EmoteResponse/EmoteCancel        -- parallel set
  PushRequest/PushResponse/PushCancel           -- parallel set

outbound to client:
  TalkEvent(npcActorId, scriptId, scriptParams) -- accepts request
  TalkRejected(npcActorId, reasonId)            -- rejects request
  showMessage(npcActorId, channel=38, msgId,
              ...args)                          -- "say" output
  askForEventMode(npcActorId, msgId, mode,
                  hideUI, allowCancel,
                  choiceBase, choices,
                  ...args)                      -- "ask" output
  CharaScheduler(npcActorId, schedulerId)       -- animation
  ClientTurnStart(npcActorId, mode, playerActorId)  -- turn animation
  ClientTurnFinish(npcActorId)                  -- restore facing
  EventCancel(npcActorId)                       -- abort
```

The dialog state machine is entirely **server-side**: the server
walks through say/ask/animation calls and waits for client responses.
The client's role is purely UI rendering plus input collection.

## Talk-Turn Mode-to-Use-Case Mapping

```text
mode  typical use case
----  -----------------------------------------------------------
 0    initial greet: lockon player but don't turn body (NPC already
      facing the player from idle posture)
 1    NPC across the room turns to you and engages
 2    NPC already engaged in current animation, just looks at you
      briefly (head only, weight 0.25)
 3    NPC turns to a specific spot in the world (not the player)
 4    NPC looks at a spot but doesn't turn body
 5    NPC turns AWAY from player (sit on chair, climb up ladder, etc.)
 6    NPC looks away from player (focused on something else)
 7    NPC re-engages mid-dialog with brief glance (lockon weight 0.25)
```

## Assessment

```text
Confirmed:
  - Talk range constant is 7 game units (probably meters).
  - startCliantTalkTurn has 8 modes (0-7), not the 1-3 previously
    documented.
  - "Cliant" is a SE typo (should be Client); preserved verbatim
    throughout the codebase.
  - desktopWidget channel 38 is the NPC dialog channel.
  - desktopWidget:askForEventMode is the unified primitive for ALL
    choice prompts (basic, restricted, extended, customize). Its
    signature is exactly 9 args: (caller, source, msgId, mode, hideUI,
    allowCancel, choiceBase, choicesArray, ...extras).
  - The 4 ask variants are syntactic sugar over different flag combos
    of askForEventMode.

Likely (High):
  - The 7-unit Talk range is metric (meters). 1.x used a metric world
    grid; 1 unit = 1 meter.
  - The "MIRRORED" modes (5, 6) for talk-turn are specifically for
    sit/relax animations where the NPC seats themselves opposite the
    player (e.g. tavern chairs facing the bar away from the patron).
  - The mode-2 head-only glance with weight 0.25 is for follower
    NPCs already in another animation (carrying boxes, sweeping the
    floor) that briefly acknowledge the player without breaking
    their current pose.

Likely (Medium):
  - askForCustomizeOption is used by the character-creation NPCs at
    new-character spawn (race / class selection). The 7-arg shape
    suggests it passes hairstyle / face / eye-color options directly.
  - The askRestrictChoices variant supports up to 11 conditional
    choices (the variadic loops up to L23_2 = arg 11). 1.x menus
    rarely exceeded 8 options visually.

Speculative:
  - The choice index transform (choiceBase + index) means message
    ids for choices are CONSECUTIVE in messageSheet. So "Yes/No" at
    base 1000 means msgId 1001 = "Yes", 1002 = "No". Easy to layout
    in the sheet.
  - The -3 cancel code (mentioned in finding_npc_event_system.md)
    surfaces from askForEventMode when allowCancel=true and the
    player escapes the menu.

Next test:
  - Find the C++ side of desktopWidget:askForEventMode. Most likely
    a Lua callback that pushes a SHOW_DIALOG packet and yields. Trace
    via the Ghidra string "askForEventMode" or via the parent
    function for desktopWidget's Lua bindings.
  - Read npcbaseclass_cliprog.lua (and other cliprog files) for the
    client-progression event hooks (XP gain, level-up) that fire from
    NPC dialog flows.

Commit suggestion:
  docs(re/lua): NPC dialog protocol -- say (channel 38), ask family,
                askForEventMode primitive, 8-mode talk-turn
```

## Server implication

The minimum-viable NPC interaction implementation needs:

1. **Receive TalkRequest** -> validate range (<7 units) and NPC
   availability -> respond with TalkEvent or TalkRejected.
2. **Run the dialog script** server-side, walking through:
   - Animation: send ClientTurnStart with mode 0-7.
   - Wait for animation: server keeps state; client may send a
     "turn done" ack or the server times out after the animation.
   - say: send `showMessage(npcId, 38, msgId, ...args)`.
   - ask: send `askForEventMode(...)` and wait for player's choice
     response.
   - Branch on choice; loop.
   - finishCliantTalkTurn: send ClientTurnFinish.
3. **Handle the chara scheduler** by sending `runCharaScheduler
   (npcId, schedulerId)` whenever the dialog wants the NPC to play
   an emote (the 0x18098000-base ID space from the previous finding).
4. **Send EventCancel** when the player cancels or moves out of range.

This is a **stateful protocol** (server holds dialog state until the
player responds or cancels). Total state per active dialog: ~32 bytes
(npc id, current step id, last choice). 1.x supported probably
hundreds of simultaneous dialogs server-wide; cheap.
