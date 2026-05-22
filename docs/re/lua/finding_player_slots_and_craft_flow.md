# Finding: `PlayerBaseClass` Module Slots + Crafting Lives Under `command/game/`, Not Under Player

Read of the deciphered `chara/player/playerbaseclass*` files plus the
`command/game/craftcommand.lua` and `widget/craftprogresswidget.lua`
modules that actually carry the crafting flow in the 1.23b build.

Sources read (deciphered paths):

```text
chara/player/playerbaseclass.lua            (69 KB, base + require()s)
chara/player/playerbaseclass_u.lua          (17.8 KB, native bindings table)
chara/player/playerbaseclass_work.lua       (7.2 KB, playerWork schema)
chara/player/playerbaseclass_cliprog.lua    (4.0 KB, "cliprog" sub-module)
chara/player/playerbaseclass_craft.lua          (18 B, EMPTY stub)
chara/player/playerbaseclass_harvest.lua        (18 B, EMPTY stub)
chara/player/playerbaseclass_negotiation.lua    (18 B, EMPTY stub)
command/game/craftcommand.lua               (~1 KB, thin override)
widget/craftprogresswidget.lua              (CraftProgressWidget.work schema)
```

## Headline result

`PlayerBaseClass` reserves four sub-module slots (`_craft`, `_harvest`,
`_negotiation`, `_cliprog`) that are loaded at the top of
`playerbaseclass.lua` via:

```lua
require("/Chara/Player/PlayerBaseClass_craft")
require("/Chara/Player/PlayerBaseClass_harvest")
require("/Chara/Player/PlayerBaseClass_negotiation")
require("/Chara/Player/PlayerBaseClass_cliprog")
```

**Three of the four (`_craft`, `_harvest`, `_negotiation`) are empty
stubs of 18 bytes** — just the standard Lua 5.1 chunk header with no
body. Only `_cliprog` (4 KB) has real content.

This means: in 1.23b the crafting / harvest / negotiation **systems are
not modular extensions of the Player actor.** Their logic lives
elsewhere. Concretely:

- **Crafting** is implemented as a *command* (`CraftCommand`) and a
  *widget* (`CraftProgressWidget`), not as a player module.
- **Harvest** is similarly externalised (the dedicated dir was
  `61s57qvs/29so5rq...` -> `director/harvest*`).
- **Negotiation** is externalised under `widget/...negotiation*` and a
  zone master (`area/zone/zonemasternegotiationtest`).

The empty stubs are evidence that SE *intended* to modularise these
under Player at some point but never landed the code in this build.

## `playerWork` schema (the player↔server data contract)

`playerbaseclass_work.lua::defineWork()` returns five groups that
together declare the wire shape of the `PlayerBaseClass.playerWork`
struct:

```text
group 1: account meta
  test_account            string(16)

group 2: top-level scalars
  test_goodbye            integer32
  weatherNow              integer16
  weatherDefault          integer16

group 3: arrays
  guildleveId             integer16 [16]
  guildleveDone           boolean   [16]
  guildleveChecked        boolean   [16]
  event_achieve_aetheryte boolean   [512]    # base id 1280000 (see below)

group 4: structured "guildleve" record
  guildleve = { guildleveId[], guildleveDone[], guildleveChecked[] }

group 5: alias for sheet-style lookups
  achieveAetheryte -> event_achieve_aetheryte[.]
```

Notes:

- The player only carries **16 active guildleves at a time**. Server
  must enforce this; the client array is fixed-size and overflow
  would silently truncate.
- Each guildleve has two booleans: `Done` (completed in the field) and
  `Checked` (turned in for reward). `isClearedGuildleveById` only
  returns true when *both* are set on the same slot.
- `event_achieve_aetheryte` is a 512-bit bitmap indexed by
  `aetheryteId - 1280000`. Aetheryte ids in 1.x are 1280000-based.
- `weatherNow` and `weatherDefault` are zone-scope state — the server
  pushes these on zone entry / weather change.

This is **not the complete player schema**. The fields used elsewhere
(`tribe`, `guardian`, `birthdayMonth`, `birthdayDay`, `initialTown`,
`npcLinkshellChatCalling`, `npcLinkshellChatExtra`, ...) are not
declared here — they come from the parent `CharaBaseClass`'s own
`defineWork`. Player only *extends* the schema with the fields above.

## `PlayerBaseClass` native binding surface (~94 bindings)

`playerbaseclass_u.lua` enumerates the `_cpp` functions the player
can call. The full list, grouped by purpose:

```text
Events / dialogs / emotes
  _isEventPlaying_cpp(mode)
  _executeTalk_cpp     _canExecuteTalk_cpp     _cancelTalk_cpp
  _executeEmote_cpp    _canExecuteEmote_cpp    _cancelEmote_cpp
  _cancelNotice_cpp    _cancelPush_cpp

Commands (client-side + ask-server)
  _executeCommand_cpp(cmdId, ...)
  _callServerOnCommand_cpp(cmdId, ...)   # ASK SERVER TO RUN COMMAND
  _doServerOnCommand_cpp(cmdId, ...)
  _cancelCommand_cpp   _isCommandPlaying_cpp   _canExecuteCommand_cpp
  _countCommandPlaying_cpp                _breakCommand_cpp

Player control locking (UI primitives for cutscenes/events)
  _lockPlayerControl_cpp     / _unlockPlayerControl_cpp     / _isPlayerControlEnabled_cpp
  _lockLockonControl_cpp     / _unlockLockonControl_cpp     / _isLockonControlEnabled_cpp
  _lockCameraControl_cpp     / _unlockCameraControl_cpp     / _isCameraControlEnabled_cpp
  _setLockonTarget_cpp       / _getLockonTarget_cpp
  _forceCameraTPSMode_cpp
  _turn_cpp

Fade / loading
  _fadeIn_cpp / _fadeOut_cpp / _waitForFading_cpp / _isFading_cpp /
  _cancelFading_cpp / _resetFade_cpp
  _fadeInAfterWarp_cpp
  _fadeInNowLoadingForNoticeEventJustInArea_cpp
  _waitForMapLoaded_cpp                                     # ZONE READY GATE

Touch / interaction
  _setTouchAttribute_cpp / _isTouching_cpp

Environment
  _setWeather_cpp / _setMusic_cpp

Chat
  _chat_cpp(...)

Inn
  _setPositionDirectionInn_cpp(x, y, z, dir) / _readyInnBed_cpp

GM / Trophies / Achievements (~25 bindings)
  _getGMRank_cpp
  _canGetTrophy_cpp / _isAchievedTrophy_cpp / _achieveTrophy_cpp
  _countAchievementCategory_cpp / _getAchievementCategoryId_cpp
  _countAchievementItem_cpp     / _getAchievementItemId_cpp
  _isDoneAchievement_cpp / _getAchievementPoint_cpp
  _getAchievementTitle_cpp / _setAchievementTitle_cpp
  _countEnableAchievementTitle_cpp / _getEnableAchievementTitle_cpp
  _hasAchievementTitle_cpp / _hasAchievementItem_cpp
  _getAchievementSheetData{Point,Icon,Title,Item}_cpp
  _getAchievementRate_cpp / _clearAchievementRateCache_cpp
  _countAchievementRateList_cpp / _getAchievementRateList_cpp
  _isDoneAchievementRateList_cpp

Grand Company / Behest / Occupancy
  _getBelongGrandCompany_cpp / _getGrandCompanyRank_cpp
  _getOccupancyContentsTime_cpp
  _getNormalBehestTime_cpp / _getCompanyBehestTime_cpp

Cutscene replay
  _isCompletedCutSceneReplayQuest_cpp
  _getCutSceneReplaySnpcNickname_cpp
  _getCutSceneReplaySnpcCoordinate_cpp
  _getCutSceneReplaySnpcSkin_cpp
  _getCutSceneReplaySnpcPersonality_cpp

Inventory (limited)
  _canStoreItem_cpp / _countStoredItem_cpp / _getStoredItem_cpp

Hamlet Defense / NM Rush
  _countHamletDefenseScore_cpp / _getHamletDefenseScore_cpp
  _getHamletDefenseScoreAll_cpp / _getNMRushUpdateTime_cpp

Misc
  _getWarpRecastTime_cpp
  _getChocoboGrade_cpp / _getChocoboRidingGrade_cpp / _isEnabledGoobbue_cpp
  _haveEnmityCharacters_cpp / _isPushingOut_cpp
```

Server-relevant bindings (those that imply a server interaction):

- `_callServerOnCommand_cpp` / `_doServerOnCommand_cpp` — **the
  outgoing command channel into Lua-land**. When Lua wants to ask the
  server to do something, this is the path. It almost certainly
  serialises through `PacketRequestBase` documented in the
  EXE-bridge finding.
- `_executeCommand_cpp` — the client-side counterpart (no server
  round-trip; for UI-only or cosmetic commands).
- `_waitForMapLoaded_cpp` — the gate the client uses to know zone
  load is finished and the server can start sending IPC for that zone.
- `_setWeather_cpp` / `_setMusic_cpp` — visual/audio side; usually
  driven by an incoming server packet.

## Crafting flow (without `playerbaseclass_craft`)

### `CraftCommand` (the action)

```lua
require("/Command/Game/GameCommandBaseClass")
_defineClass("CraftCommand", "GameCommandBaseClass")

function CraftCommand:isUseActionGauge()         -- crafting does NOT use the global action gauge
  return false
end

function CraftCommand:canAimForRelation()
  local id = self:getCommandId()
  if id == 22012 or id == 22016 then
    return true, true, false              -- can aim, requires target, not optional
  end
  return true, false, false                 -- can aim but no target required
end
```

The whole `CraftCommand` class is ~50 lines. All the real work happens
in `GameCommandBaseClass` (57 KB) which is shared by every game
command and is *not* craft-specific.

Recognisable command ids (incomplete — only those visible in
CraftCommand so far):

```text
22012   craft command that targets a relation (target required)
22016   craft command that targets a relation (target required)
```

These are the only two craft command ids in the 22000 range that
demand a target; other craft-family ids in the same range exist and
default to `canAimForRelation() = (true, false, false)` (no target).

### `CraftProgressWidget` (the state-bearing UI)

The widget is what holds the live crafting session. Its declared `work`
schema:

```text
progressPercentage     integer8     0..100
maxProgress            integer8     normally 100
craftPoint             integer16    current CP
maxCraftPoint          integer16    max CP
qualityPoint           integer16    current quality value
maxQualityPoint        integer16    max quality value
initialized            boolean
isTuningPhase          boolean      true during the "tuning" sub-phase
focusEnable            boolean
itemID                 integer32    item being crafted
itemQuality            integer32    final quality (=1 at start)
param1/2/3             integer32    variable params (likely action effect)
oldparam1/2/3          integer32    previous-step params (for diff/animation)
previousCommand        integer32    last command executed
chosenCommand          integer32    command player chose this step
focusedCommand         integer32    command currently hovered/selected in UI
localBuf               boolean
firstChoise            integer8     (yes, typo "Choise" preserved in source)
```

This is the **complete craft session state** kept on the client. It is
22 fields totalling roughly `1+1 + 2+2+2+2 + 1+1+1 + 4+4 + 4+4+4 +
4+4+4 + 4+4+4 + 1 + 1 = ~58 bytes` of declared data, plus framing.
Server packets that drive crafting **update these fields**; the widget
re-renders off them.

`init(initialProgress, initialMaxProgress?, initialCP, maxCP,
initialQuality, maxQuality)` is the entry that fires when a craft
session starts. After init, the widget calls
`updateProcess(progress, cp, quality, ..., chosenCommand, ...)`
whenever a step completes. Defaults `maxCraftPoint = 999` and
`maxQualityPoint = 999` if zero/nil is provided — so the server can
omit those and the client takes 999 as the cap.

The visibility hide of `"Grid_Top_2"` after init (line 199-201)
indicates the widget has multiple panel layouts depending on whether
this is a normal craft or some restricted variant.

## What this implies for the server

1. **Crafting state is a server-pushed snapshot.** The server owns the
   `CraftProgressWidget.work` fields. To drive a craft session a
   minimal server needs to push:
   - `init`: itemId, initialProgress, maxProgress (=100), initialCP,
     maxCP (or 0 -> client defaults 999), initialQuality, maxQuality
     (or 0 -> 999).
   - `updateProcess`: per-step new values for progressPercentage,
     craftPoint, qualityPoint, and the chosen-command id. Optionally
     param1..3 for animation hooks.
   - A "session end" packet that closes the widget (likely a final
     `updateProcess` with `progressPercentage = 100` or an explicit
     close event).
2. **The two "aim" craft commands (22012, 22016)** require a target
   actor on the wire. Most other craft commands target self.
3. **The `_craft` / `_harvest` / `_negotiation` Lua slots are inert.**
   The server should not expect the client to react to packets named
   for those sub-systems via Player. Their actual entry points are the
   game commands (under `command/game/`) and their respective widgets.
4. **The 16-slot guildleve cap** in `playerWork` is a hard client-side
   limit. Servers should never assign a 17th simultaneous guildleve to
   a player.
5. **Aetheryte achievements** are flagged in a 512-bit bitmap keyed
   `aetheryteId - 1280000`. Server-side aetheryte ids must fall in
   `[1280000, 1280512)` or the client will index out of bounds.

## Assessment

```text
Confirmed:
  - playerbaseclass_craft / _harvest / _negotiation are empty (18 B)
    in 1.23b. Only _cliprog has content among the four sub-module slots.
  - CraftCommand is a thin GameCommandBaseClass subclass; the heavy
    lifting is in the shared GameCommandBaseClass.
  - The live craft session state is the CraftProgressWidget.work
    struct (22 fields, schema above).
  - PlayerBaseClass exposes ~94 native _cpp bindings. The
    server-interacting ones are _callServerOnCommand_cpp and
    _doServerOnCommand_cpp; the rest are local UI / state queries.

Likely (High):
  - Server-driven crafting updates the widget via a "process update"
    packet whose payload is positional: (progress, cp, quality,
    param1, param2, param3, chosenCommand, [oldparam1..3], ...). The
    init/update method signatures already pin most of this.
  - Command ids 22012 / 22016 are the two craft commands that need a
    target on the wire (e.g. crafting at a workstation NPC).
  - Aetheryte ids on the wire are in the 1280000-1280511 range.

Likely (Medium):
  - The "_u" suffix override-slot convention applies the same way to
    PlayerBaseClass: the 17.8 KB _u file *is* the bindings table for
    the player and there is no separate override of game logic. SE's
    `_p`->`_u` rename is purely build-pipeline.
  - The dead _craft / _harvest / _negotiation slots were planned in
    an earlier design (perhaps an XI-style class extension model) and
    abandoned before 1.23b.

Speculative:
  - That a future version of FFXIV 1.x would have filled the empty
    Player slots with class-specialised craft/harvest logic. There is
    no evidence in the 1.23b binary either way.

Next test:
  - Read command/game/gamecommandbaseclass.lua to extract the full
    crafting command lifecycle: setup, execution, server hand-off,
    completion notification.
  - Read widget/craftstartwidget.lua and widget/craftrecipewidget.lua
    to learn the *entry* into a craft session (recipe selection,
    materials check) and the wire payload that triggers it.
  - Read chara/charabaseclass.lua to harvest the rest of the player
    schema (tribe, guardian, birthday, town, npc linkshell tables).

Commit suggestion:
  docs(re/lua): document player slots and where crafting actually lives
```
