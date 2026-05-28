# Finding: playerbaseclass.lua -- Command Flow (Lua→0x12d), Timing-Combo Inbound, + Player Module Inventory

**Deep-dive into the player-specific Lua module** (uy9l5s89r57y9rr.lua,
3020 lines, ~75 functions). Maps the **client-side command flow**
that feeds the outbound wire command (0x12d), the **inbound timing-
combo handler** (server→client combo prompts), and the full
player-module surface.

This is the Lua counterpart to charabaseclass + the bridge between
UI/input and the wire command path.

## 1. The command flow (Lua → wire 0x12d)

```text
command(commandObj, params...)                          [line 1978]
   ↓ 1. burst check: if playerWork.commandBurstBlocker set -> REJECT
   ↓    (EXCEPT command ids 12017 / 12009 which bypass -- cancel/menu)
   ↓ 2. getCommandName(commandObj) -> dispatch flag
   ↓    if flag != "commandRequest": check _canExecuteCommand(flag)
   ↓ 3. commandObj:canFire(player, params...) -> validate
   ↓ returns canFire result

_onCommandRequest(commandObj, params...)                [line 1911]
   ↓ 1. LENGTH GUARD: if #arg2(string) + #arg3(string) > 50 -> REJECT
   ↓ 2. canCommand(commandObj, params...) validation
   ↓ 3. if OK:
   ↓      name = getCommandName(commandObj)
   ↓      _executeCommand(name, commandObj, params...)  <- WIRE SEND (0x12d)
   ↓      if name == "commandRequest": recordRequestInformation()
   ↓      playerWork.commandBurstBlocker = 1             <- RATE LIMIT
   ↓ returns execute result

canCommand(commandObj, flag)                            [line 2027]
   ↓ if flag in {commandForced/Default/Weak/Content/JudgeMode}:
   ↓    desktopWidget:closeAllEventModeWidget()
   ↓ if flag in {widgetCreate/macroRequest}:
   ↓    processCancelCommandAboutWidget(flag)
```

### Key client-side gating mechanisms

```text
1. commandBurstBlocker (playerWork field):
   - Set to 1 after EVERY command -> blocks subsequent commands
   - Bypass list: command ids 12017, 12009 (cancel / menu actions)
   - Cleared elsewhere (likely on server response or per-tick)
   - CLIENT-SIDE ANTI-SPAM (advisory; server must still validate)

2. 50-char combined string limit:
   - #arg2 + #arg3 string lengths must be <= 50
   - Prevents oversized command payloads (chat-in-command injection?)

3. Command-type widget cleanup:
   - Combat commands close event-mode widgets
   - UI commands cancel pending widget operations

SERVER NOTE: these are CLIENT-SIDE conveniences. A modified client
could bypass them. The server MUST independently validate every
command (the CRC32 in 0x12d is only integrity, not auth).
```

## 2. Inbound timing-combo handler (_onReceiveTimingPacket)

The server→client side of the timing-command combo system (from
the battle finding):

```text
_onReceiveTimingPacket(player, timingType, successFlag)  [line 1502]
   ↓ areaMaster = player:_getCurrentAreaMaster()
   ↓ if areaMaster:isInstanceRaid():
   ↓   if timingType == 5:
   ↓     cmd = _getStaticActor(24301)   -- raid timing command
   ↓     name = getCommandName(cmd)
   ↓     if successFlag: _executeCommand(name, cmd, 30004, 5, 1)  -- success
   ↓     else:           _executeCommand(name, cmd, 30004, 5, 2)  -- fail
   ↓   return
   ↓ if timingType == 1:
   ↓   if successFlag:
   ↓     cmd = searchReadyCommand(22004)   -- ready combo command
   ↓     ... execute follow-up
```

**FLOW**: server detects a combo timing window → sends timing packet
(wire opcode for timing) → client's `_onReceiveTimingPacket` fires →
client AUTO-EXECUTES the appropriate follow-up command (via the same
_executeCommand → 0x12d path).

So the combo loop is:
```text
1. Server sets timingCommandFlag (WorkSync) -> client shows prompt
2. Player presses timing command (27xxx) -> 0x12d to server
3. Server validates timing -> sends timing packet (success/fail)
4. _onReceiveTimingPacket -> client auto-executes result command
   (30004 for raid, 22004-ready for normal)
```

Command IDs in the timing flow:
```text
24301  raid timing command (static actor)
30004  raid timing follow-up (sub 5, mode 1=success / 2=fail)
22004  ready combo command (type 1 timing)
24312  stand-up command (from _onMoveAtSit)
```

## 3. Inbound wire-message handlers (player-targeted callbacks)

The player module implements these `_on*` callbacks (fired by the
inbound wire dispatch -> CommandUpdater -> Lua):

```text
_onInit                    actor spawn complete (T3 lifecycle)
_onUpdateWork              WorkSync state update applied
_onReceiveDataPacket       generic 192B data packet
_onReceiveTimingPacket     combo timing (section 2)
_onTouch                   touch/interact event
_onMoveAtSit               sit movement -> auto stand (cmd 24312)
_onLoginEvent              login sequence event
_onReceiveLimitAddicted    limit break / addiction state
_onReceiveAchievementId    achievement unlock -> showAchievementPopup
_onReceiveAchievementRate  achievement progress -> processReceiveAchievementRate
_onCommandEvent            command-as-event dispatch
_onCommandCancel           server cancelled a command -> widget cleanup
_onCommandRejected         server rejected a command
_onChocoboRentalRide / _onChocoboWarpRide / _onGetGoobbue  mount events
_onPreEvent / _onPostEvent / _onPreCommand / _onPostCommand  hooks
```

These map to the inbound opcodes documented in the wire findings
(0x148-0x156 per-actor, achievement opcodes 0x53-0x56, etc.).

## 4. Player module function inventory (~75 functions)

### Character identity (creation data)
```text
isPlayer, isValidName, getTribe, getNation, getGuardian, getBirthday,
getInitialTown, isMale, isFemale
```

### Grand Company progression
```text
isPrebelongGrandCompany, getGrandCompanyRank, getGrandCompanyRankLinear,
getGrandCompanySealMax, getGrandCompanyNeedSealNextRank,
getGrandCompanySealCount
```

### NPC Linkshell (NPC-issued linkshells)
```text
hasNpcLinkshell, isNpcLinkshellChatCalling,
getNpcLinkshellChatLinkshellLength
(complements the player Linkshell system from prior finding)
```

### Command system (the core)
```text
command, canCommand, _onCommandRequest, _onCommandEvent,
_onCommandCancel, _onCommandRejected, delegateCommand, getSystemCommand,
getCommandName (in sibling), _executeCommand (native binding)
setPlaceDrivenCommandVariation, resetPlaceDrivenCommandVariation,
setContentCommandVariation, setEmoteSitCommandVariation,
commandAboutDebug, commandAboutWidget, isCommandAboutWidgetPlaying,
cancelCommandAboutWidget, processCancelCommandAboutWidget
```

### Quest tracking
```text
getScenarioQuest, getScenarioQuestLength, getGuildleveQuest,
getGuildleveQuestLength, updateQuestComplete, processUpdateQuestComplete,
isQuestComplete, setQuestContentsCommandPermitFlag,
getQuestContentsCommandPermitFlag
```

### Combat / cast
```text
getComboInformation, getCastCommand, getCastEndTime, getWarpRecastTime,
searchReadyCommand, _onReceiveLimitAddicted
```

### Misc
```text
getRestBonusExpRate, isAcquiredAdditionalCommand, getGiftCountInformation,
getOtherClassAbilityCountInformation, isRemainBonusPoint,
canRequestInformation, recordRequestInformation, isEventPlaying,
postMapOpen, checkSameItemCatalogId, decodeTimingPacketInformation
```

## 5. Server-side requirements

```text
COMMAND HANDLING:
  - Receive 0x12d command (validate CRC32 optionally)
  - Server-side validate (client's commandBurstBlocker / 50-char /
    canCommand are advisory only)
  - On reject: trigger client _onCommandRejected (inbound)
  - On cancel: trigger client _onCommandCancel
  - Respect command ids 12017/12009 as always-allowed (cancel/menu)

TIMING COMBOS:
  - Set timingCommandFlag (WorkSync) on combo window
  - Receive player's timing command (27xxx) via 0x12d
  - Send timing packet (type + success flag) -> client auto-resolves
    * raid: type 5 -> client executes 30004
    * normal: type 1 -> client executes 22004-ready

PLAYER STATE TO PROVIDE:
  - Character creation: tribe/nation/guardian/birthday/town/sex
  - Grand Company: rank/seal/progression
  - Quest: scenario + guildleve quest lists + completion flags
  - Achievement: id unlocks + progress rates (popup triggers)

LOGIN: _onLoginEvent fires the login sequence (server pushes login event)
```

## 6. Confidence

```text
Confirmed:
  - command flow: command -> canCommand -> _onCommandRequest ->
    _executeCommand -> wire 0x12d
  - commandBurstBlocker anti-spam (bypass 12017/12009)
  - 50-char combined string limit
  - _onReceiveTimingPacket auto-executes follow-up combo commands
  - ~75 player functions enumerated by role
  - Player implements ~18 _on* inbound wire callbacks
  - Timing command ids: 24301/30004/22004/24312

Likely (High):
  - commandBurstBlocker cleared on server command response / per-tick
  - Grand Company is the 1.x social/rank progression (3 GCs)
  - NPC linkshells are quest/faction auto-grants
  - Achievement popups driven by inbound opcodes 0x53-0x56

Speculative:
  - cmd 12017/12009 = cancel + main-menu (always allowed during burst)
  - The 50-char limit prevents command-arg-based chat injection
  - Place/content/emote command variations swap command sets by context
```

## 7. Cross-references

- `finding_executeCommand_outbound_path_CLOSED_0x12d_checksummed.md`
  -- the wire side that command() feeds (0x12d)
- `finding_charabaseclass_battle_schema_and_timing_commands.md`
  -- the timingCommandFlag combos (this is the inbound resolution)
- `finding_per_actor_messages_COMPLETE_15_opcodes_3x5_matrix.md`
  -- the inbound action results these callbacks consume
- `finding_company_group_freecompany.md` -- Grand Company system
- `finding_linkshell_subsystem_inventory.md` -- NPC linkshell complement

## 8. Next test

```text
1. Read getCommandName + _canExecuteCommand (sibling files) for the
   command-name resolution
2. Read playerbaseclass_negotiation (_w53vq19q1vw subfile) -- the
   negotiationFlag mechanic
3. Read playerbaseclass_work (_nvsz subfile) -- player work schema
4. Map command variation system (place/content/emote) to command sets
5. Trace _onLoginEvent -> full login sequence
```

## Commit suggestion

```
docs(re/lua): playerbaseclass.lua -- command flow (command->canCommand->_executeCommand->0x12d) + inbound timing-combo handler + ~75 fn inventory + 18 _on* wire callbacks
```
