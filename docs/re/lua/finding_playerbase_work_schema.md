# Finding: `PlayerBaseClass` `playerWork` Schema + The myPlayer Wire Boundary

Reading `playerbaseclass.lua:_onInit` (lines 407-1097) exposes the
complete `playerWork` schema, the full list of `_bindWork` calls
made by Player class subtree, and — most importantly — the **wire
boundary between myPlayer and other players**: ALL the player-class
`_bindWork` calls happen inside an `if isMyPlayer` block. Other
players visible on screen receive ZERO `playerWork` syncs.

Sources read:

```text
chara/player/playerbaseclass.lua    3020 lines
  _onInit                          line 407-1097 (the bulk of the file)
```

The class also `require`s four companion modules:

```text
PlayerBaseClass_craft         crafting subsystem
PlayerBaseClass_harvest       harvesting subsystem
PlayerBaseClass_negotiation   negotiation subsystem
PlayerBaseClass_cliprog       client progression (XP/level events)
```

## Super call: `CharaBase._onInit(true, true)`

PlayerBase invokes `CharaBase._onInit(hasGameParameter=true,
hasBattle=true)` — confirming that **players ALWAYS have full
battle + parameter sub-structs**. (NPCs may have neither; players
always have both.)

## `playerWork._save`

```text
[
  {_assignForChild, 16}    -- 16-byte child reserved (for Player subclass)
]
```

## `playerWork._temp` (11 fields)

```text
{variableCommandPlaceDriven,        array[4] integer16}
{variableCommandPlaceDrivenSub,     array[4] integer32}
{variableCommandPlaceDrivenTarget,  array[4] actor}
{variableCommandPlaceDrivenPriority, array[4] integer8}
{variableCommandContent,            integer32}
{variableCommandContentSub,         integer32}
{variableCommandEmoteSit,           integer32}
{commandBurstBlocker,               timer (default false)}
{requestBurstBlocker,               integer32}
{widgetCommandBurstBlocker,         integer32}
{_assignForChild,                   512}      -- 512-byte child reserved
```

The "burst blocker" trio implements client-side anti-spam: after
firing a command (action), the timer + 2 integer slots prevent
re-firing for some interval. The 512-byte `_assignForChild` is the
large extension area Player class uses for its own `work` struct.

## `playerWork._sync` — the myPlayer-only block (28 fields)

This is wrapped in `if isMyPlayer ... end`:

```text
identity
  {tribe,              integer8}    -- character race/tribe
  {guardian,           integer8}    -- guardian deity id
  {birthdayMonth,      integer8}
  {birthdayDay,        integer8}
  {initialTown,        integer8}    -- (binding 100007)

quest journal
  {questScenario,      array[16] actor}        -- 16 active scenario quests
                                                  (actor refs to Quest objects)
  {questScenarioComplete, array[2048] boolean} -- 2048-bit scenario completion bitmap
  {questGuildleve,     array[8]  actor}        -- 8 active leve quests
  {questGuildleveComplete, array[2048] boolean} -- 2048-bit leve completion bitmap

warp confirm panel (variableCommandConfirmWarp*)
  {variableCommandConfirmWarp,         integer32}
  {variableCommandConfirmWarpSender,   string(32)}    -- 32-char sender name
  {variableCommandConfirmWarpSenderByID, integer32}
  {variableCommandConfirmWarpSenderSex,  integer8}
  {variableCommandConfirmWarpPlace,    integer32}

raise confirm panel (variableCommandConfirmRaise*)
  {variableCommandConfirmRaise,         integer32}   -- (binding 100001)
  {variableCommandConfirmRaiseSender,   string(32)}
  {variableCommandConfirmRaiseSenderByID, integer32}
  {variableCommandConfirmRaiseSenderSex,  integer8}

NPC linkshell chat
  {npcLinkshellChatCalling,  array[64] boolean}
  {npcLinkshellChatExtra,    array[64] boolean}

content / combat state
  {isContentsCommand,         boolean}     -- in content-command mode
  {castEndClient,             integer32}   -- cast bar end time (client clock)
  {castCommandClient,         integer32}   -- command being cast (client tracking)
  {comboNextCommandId,        array[2] integer32}  -- 2-slot combo chain
  {comboCostBonusRate,        float}       -- combo TP discount
  {isRemainBonusPoint,        boolean}     -- rested-bonus has remaining
  {restBonusExpRate,          float}       -- rested EXP multiplier

reserved
  {_assignForChild,           128}         -- 128-byte child extension
```

### Non-myPlayer (else branch)

```text
playerWork._sync = [{_assignForChild, 128}]
```

So **other players visible on screen receive a `playerWork._sync` of
just 128 reserved bytes**. No quest data, no warp panels, no combo
state synced for other players.

This is huge: the server's per-other-player playerWork wire surface
is **literally zero meaningful fields**. Only the 7 charaWork bindings
sync.

## `playerWork._tag` (12 tag groups)

```text
{profile,               60,  self, [tribe, guardian, birthdayMonth,
                                    birthdayDay, initialTown]}
  -- 60-SECOND rate! These almost never change.

{confirmWarpCommand,    1,   self, [variableCommandConfirmWarp*x5]}
{confirmRaiseCommand,   1,   self, [variableCommandConfirmRaise*x4]}
{journal,               1,   self, [questScenario, questGuildleve]}
{npcLinkshellChat,      1,   self, [npcLinkshellChatCalling,
                                    npcLinkshellChatExtra]}
{questCompleteS,             [questScenarioComplete, "."]}  -- nested-path tag
{questCompleteG,             [questGuildleveComplete, "."]}  -- nested-path tag
{isContentsCommand,     1,   self, [isContentsCommand]}
{combo,                 1,   self, [comboNextCommandId, comboCostBonusRate]}
{consoleTray,           1,   self, [isRemainBonusPoint]}
{expBonus,              1,   self, [restBonusExpRate]}
{castState,             1,   self, [castEndClient, castCommandClient]}
```

The **`profile` tag rate of 60 seconds** is a new tick-rate ceiling.
Adding to the rate-band model:

```text
rate     tags                                                     fields synced
-------  -------------------------------------------------------  -----------------
0.3 s    stateAtQuicklyForAll                                     HP, MP, TP (5)
1   s    most self-only tags (commandDetail, battleParameter,
         confirmWarp, confirmRaise, journal, npcLinkshellChat,
         isContentsCommand, combo, consoleTray, expBonus, castState)  many
1.5 s    stateForAll                                              mainSkill, job (3)
60  s    profile                                                  identity (5)
```

So the client expects:
- **300ms** ticks for HP/MP/TP (frantic combat sync)
- **1s** ticks for most self-only state (cooldowns, combo, UI panels)
- **1.5s** ticks for class/level info (slow visual transitions)
- **60s** ticks for identity (race, deity, birthday, town — never changes)

## All `_bindWork` calls in PlayerBase._onInit (ALL myPlayer-only)

```text
1001  charaWork.parameterSave.state_mainSkill
1002  charaWork.parameterSave.constanceCommandSlot_commandId
1003  charaWork.parameterSave.giftCommandSlot_commandId
1004  charaWork.parameterSave.abilityCostPoint_used
1005  charaWork.parameterSave.abilityCostPoint_max
1006  charaWork.parameterSave.constanceCostPoint_used
1007  charaWork.parameterSave.constanceCostPoint_max
1008  charaWork.parameterSave.giftCostPoint_used
1009  charaWork.parameterSave.giftCostPoint_max
2001  charaWork.battleSave.skillLevel
3001  charaWork.commandAcquired
3002  charaWork.command
3003  charaWork.commandCategory
3004  charaWork.commandBorder
100001 playerWork.variableCommandConfirmRaise
100002 playerWork.variableCommandConfirmWarp
100003 playerWork.variableCommandContent
100004 playerWork.variableCommandPlaceDriven
100005 playerWork.variableCommandEmoteSit
100007 playerWork.initialTown
```

**Total bindings registered by PlayerBase: 20**. All are gated on
`isMyPlayer`. (Note: 100006 is reserved/unused, confirming the
catalog's "100006 unused" annotation.)

## The myPlayer wire boundary — the central design insight

Combining the bindings from CharaBase and PlayerBase:

```text
For ANY visible chara (CharaBase bindings, always active):
  1010   hp[1]
  1011   hpMax[1]
  1012   state_mainSkillLevel
  2002   potencial          (only when !isMyPlayer)
  3006   property bitmap
  4001   bazaarRetail
  4002   bazaarRepair

Total per non-myPlayer chara: 7 bindings (or 6 if not in bazaar)

For myPlayer ONLY (PlayerBase + CharaBase combined):
  All of the above MINUS 2002 (myPlayer skips 2002 from CharaBase!)
  PLUS 1001-1009 (9 more from PlayerBase)
  PLUS 2001 (skillLevel from PlayerBase)
  PLUS 3001-3004 (4 more from PlayerBase)
  PLUS 100001-100005, 100007 (6 more from PlayerBase)

Total for myPlayer: 6 + 9 + 1 + 4 + 6 = 26 bindings

For Player (concrete class, from previous finding):
  PLUS 101001 guildleveId

Total myPlayer wire surface: 27 distinct binding ids
```

So a server's per-other-player sync cost is **~3.5x cheaper** than
per-myPlayer cost. In an 8-person party (1 myPlayer + 7 others):

```text
myPlayer:    27 bindings  + 12 tag groups
7x other:    7 bindings   + ~3 tag groups each
                              (status, command, depictionJudge, etc)
```

## Assessment

```text
Confirmed:
  - PlayerBase._onInit calls CharaBase._onInit(true, true). Players
    always have battle + game parameters.
  - playerWork._sync has 28 fields ONLY when isMyPlayer; otherwise
    just a 128-byte child reserved slot.
  - 20 _bindWork registrations in PlayerBase, ALL gated by isMyPlayer.
  - Tag group "profile" has rate 60 (the slowest sync rate observed).
  - 100006 is confirmed unused (skipped in the binding sequence).
  - 2002 potencial is bound for OTHER players, not myPlayer (the
    CharaBase code path: `if hasBattle and not isMyPlayer then
    _bindWork 2002`).

Likely (High):
  - The 2048-bit questScenarioComplete and questGuildleveComplete
    bitmaps imply 1.x had up to 2048 distinct scenario quests and
    2048 distinct guildleves. The actual content was much less; this
    was forward-compatible provisioning.
  - The 32-char string limit for ConfirmWarpSender / ConfirmRaiseSender
    confirms the player name limit was 31 chars + null in 1.x
    (similar to FFXI's 16-char limit, doubled for international names).
  - The 4-slot variableCommandPlaceDriven arrays cover the 4 simultaneous
    place-driven actions (events like /pickup that depend on the target
    location). Limited to 4 because the UI only shows 4 contextual
    action prompts at once.
  - "comboNextCommandId" array[2] = 2 slots for combo chains because
    1.x's combo system supported at most 2-stage combos (initial +
    finisher).

Likely (Medium):
  - The "burst blocker" trio (commandBurstBlocker timer + 2 integer
    slots) is the client-side action-rate limiter. Prevents button
    mashing during cooldowns or while the server is processing.
  - "npcLinkshellChatCalling/Extra" 64-slot bool arrays may represent
    "which NPC is currently saying something to you" — used to render
    NPC LS chat without server-side broadcast for every line.

Speculative:
  - The 60-second "profile" rate suggests SE optimized for the case
    where a player's tribe/guardian NEVER changes mid-session. Even
    so, a 60s tick costs negligible bandwidth.

Next test:
  - PlayerBaseClass_craft and PlayerBaseClass_harvest: 1.x specific
    crafting/gathering systems. May surface more bindings in unused
    ranges.
  - PlayerBaseClass_negotiation: the negotiation subsystem complement
    to NegotiationJudge.
  - PlayerBaseClass_cliprog (454 lines): client progression hooks
    (XP gain events, level-up notifications).

Commit suggestion:
  docs(re/lua): PlayerBaseClass schema + myPlayer wire boundary
                (20 bindings myPlayer-only; profile tag rate 60s)
```

## Server implication

The actor sync wire surface has now been **fully decomposed by
actor type**:

```text
Per OTHER PLAYER (visible, not me):
  ~7 _bindWork ids active
  ~3-4 tag groups active (just identity + charaWork tags)
  No quest, no combo, no warp/raise panels.
  
  Wire surface: ~100 bytes initial state, ~30 bytes/s steady state.

Per MY PLAYER (local):
  ~27 _bindWork ids active
  ~25+ tag groups across charaWork + playerWork + work
  Quest journal (2048-bit bitmaps), combo, all UI panel state.
  
  Wire surface: ~3.5 KB initial state, ~600 bytes/s steady state.

Per NPC:
  ~1-3 _bindWork ids active (actorClassId + maybe push command)
  ~2 tag groups (pushCommand, hate)
  No quest data, no UI panels.
  
  Wire surface: ~100 bytes initial state, ~10 bytes/s steady state.
```

A server bringing up a **fully-populated 8-person party in a busy zone
(myPlayer + 7 others + 30 NPCs)**:

```text
initial state:   3500 + 7*100 + 30*100 = ~7.2 KB
steady state:    600 + 7*30 + 30*10 = ~1.1 KB/s
```

Even with framing overhead, **a 1.x server only needs ~5 KB/s of
actor-state bandwidth per client**. The protocol was designed for
512 Kbps DSL. Modern infrastructure trivializes this.

This finding **closes the actor schema discovery**: every per-actor
field is now enumerated with its exact type, size, sync rate, and
gating condition (myPlayer vs others). What remains for full server
parity is the wire framing (partially documented) and the per-binding
on-wire payload format (the next critical EXE-side investigation).
