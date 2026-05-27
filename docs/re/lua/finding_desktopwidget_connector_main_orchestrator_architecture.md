# Finding: DesktopWidget Connector -- THE UI Orchestrator (26,564 Lines, 255 Methods Across 13 Subsystems)

**Deep-dive into the largest Lua file in the corpus.** Maps the
architecture of `desktopwidget_connector.lua` -- the master
DesktopWidget connector that orchestrates the entire 1.x client UI.

255 methods organized into 13 functional subsystems. The connector
serves as the central nervous system: every UI panel, every chat
message, every target selection, every menu state transition flows
through here.

## 1. File facts

```text
Path:       widget/desktopwidget_connector.lua
Obfuscated: lua/decompiled/src/n1635q/65rzqvun1635q_7vww57qvs.lua
Size:       26,564 lines (~687 KB)
Methods:    255 named functions assigned to DesktopWidget
Scope:      The CLIENT UI ORCHESTRATOR
```

This is the largest single Lua file in the entire 1.x corpus and
the most-referenced (every other widget calls into `desktopWidget`).

## 2. The 13 functional subsystems

### A. Lifecycle (5 methods)
```text
init, initDesktopInitialParameter, show, hide, isShow
```
The `init` method (line 4-764) sets up the work-sync schema with
~30+ fields AND registers ~30+ UI command conditions. It then
calls `orderDesktopWidgetMode(8)` to enter the main UI mode.

### B. Target Cursor System (~30 methods)
```text
initializeTargetCursor, getDefaultTargetMode, executeSubTarget,
subTargetDecided, processSubTargetDecided, setMainTargetCursorStatus,
isMainTargetDecided, maskAllTargetCursorDisplay,
getMainTargetCharacter, cancelMainTargetCharacter,
getSubTargetCharacter, getCurrentTargetCharacter,
isSubTargetSelectMode, cancelSubTargetSelect,
setMainTargetGmMode, _onCheckTargetable, isValidTarget,
checkPlayerModeTarget, checkEnemyModeTarget,
isInvalidEnmityTarget, isValidModeTarget, checkTargetInBattle,
checkSubTargetable, _onCheckTargetableNearest,
setTargetCharacter, setCurrentTarget,
setTargetCharacterForMyPlayer, afterTargetChanged, ...
```

The most extensive subsystem. Two-tier target model:
- **Main target**: locked-in target (HP bar visible)
- **Sub target**: hover/cursor target (highlight only)

Each target has its own cursor image, mode, and validation chain.
The `_onCheckTargetable*` callbacks are bound from C++ thunks
(per `_setTargetCursorImage` etc. in the master walk findings).

### C. Bazaar/Trade System (~10 methods)
```text
updateBazaarPackage, checkActor, getBazaarActor, isValidBazaarActor,
setBazaarActor, getBazaarActorName, getTradeActor,
getTradeActorName, dictateOpenTradeWidget, dictateCloseTradeWidget,
checkReplyTradeWidget, dictateNoticeTradeWidget,
processUpdateTradingItem
```

The 1.x Bazaar (player shop on character) UI flow. `setBazaarActor`
stores the target's bazaar inventory ref; widget panels query
via `getBazaarActor`. Trade flow uses "dictate" prefix for the
4 trade lifecycle messages.

### D. Tutorial System (~10 methods)
```text
isTutorialMode, isTutorialLock, getTutorialMenuType,
setTutorialMenuStatus, getTutorialMenuStatus,
isTutorialMainMenuMask, openTutorialSuccessWidget,
closeTutorialSuccessWidget, openTutorialWidget,
closeTutorialWidget, askTutorialDeviceType, setTutorialDeviceType
```

New-player tutorial coordinator. Tied to the 7-binding tutorial
subsystem on WorldMaster (per master walk findings).

### E. Map / Navigation (~10 methods)
```text
processCommandMap, postMapOpen, setMapNavigationWidgetMarkerData,
openMapForCutScene, closeMapForCutScene, setMiniMapWidgetMarkerData
```

Map UI orchestration. The `MapNavigationWidget` is consumed by
the 2D map subsystem (matches the 4 `2Dmap_*.csv` engine-internal
tables from the catalog).

### F. Guildleve UI (~5 methods)
```text
askActiveGuildleveSelectWidget, askActiveGuildleveDetailWidget,
askPassiveGuildleveSelectWidget, askPassiveGuildleveReleaseWidget,
getActiveGLIcon, getLocalGLIconID
```

Active/Passive Guildleve selection + release. Consumes
`guildleve.csv` (624 rows) + `guildleve_UI.csv` data.

### G. Quest/Journal UI (~10 methods)
```text
askSelectReleaseQuestWidget, askQuestDetailWidget,
orderUpdateJournalListWidget, executeCommandJournalDetailInfo,
executeCommandJournalHistoryInfo, executeJournalCommand,
processUpdateJournalDetailWidget, getJournalIconID,
getQuestIconID, getQuestCount, openJobQuestInformationWidget,
openQuestRewardWidget
```

Quest log + journal browser. Consumes `quest.csv` + `quest_reward.csv`
(per the SpreadSheet correlation findings).

### H. Craft System UI (~6 methods)
```text
selectCraftItemSelectWidget, selectCraftRecipeSelectWidget,
selectCraftRecipeDetailWidget, askCraftRepairWidget,
selectCraftProgressWidgetDisplay, orderCraftProgressWidgetUpdate
```

Craft synthesis UI orchestration. The 3-stage select (item ->
recipe -> detail) + progress widget update.

### I. Hamlet Defense (~5 methods)
```text
askHamletDefenseRankingWidget, openHamletExecutionWidget,
getHamletExecutionWidget, getHamletPopupWidget,
askHamletDefenseScoreWidget
```

The 1.x Hamlet Defense seasonal event UI. Matches Director's
`_waitForHamletDefenseScore` + the 3 Hamlet CSVs
(itemHamletSupply, hamletDefScore variants).

### J. Cutscene UI (~6 methods)
```text
openCutSceneReplaySelectWidget, closeCutSceneReplaySelectWidget,
selectCutSceneReplaySelectWidget, openCutSceneEffectWidget,
closeCutSceneEffectWidget, showCutSceneSkip, hideCutSceneSkip,
clearCutSceneSkip
```

CutScene UI controls -- replay browser, skip prompt, effect overlays.

### K. Raid Dungeon (~3 methods)
```text
openRaidDungeonExecutionWidget, closeRaidDungeonExecutionWidget,
getReadyCommandIndex (related)
```

Raid dungeon execution UI (the 11 raidDungeon* CSVs).

### L. Universal Dialog (`ask` family; ~6 methods)
```text
ask, askForEventMode, askForEventModeMultiple, askForEventModeChild,
askChocoboNamingWidget, askMarketSelectWidget
```

The `ask` primitive at line 12035 opens an AskWidget, lets it run,
returns the result. Used by EVERY confirm/select prompt in the
game. `askForEventMode` is the event-mode variant that suspends
gameplay while the dialog is open.

```text
ask flow:
  desktopWidget:ask(...)
   -> openWidgetYield(4, "Ask/AskWidget", ...)
   -> widget.ask(prompts, choices, ...)
   -> selectWidgetYield(widget, true)
   -> widget.getAskResult()
   -> closeWidgetDirect(widget)
   -> return result
```

### M. Public Dialog Widgets (~4 methods)
```text
openPublicInformDialogWidget, openPublicInformLongDialogWidget,
openCautionInformDialogWidget, openWarningInformDialogWidget
```

System-style dialog popups (info / caution / warning).

### N. Character/Command Info Accessors (~15 methods)
```text
getCharacterStatusSlotLength, getCharacterBufferStatus,
getPlayerStatusSlotLength, getPlayerBufferStatus,
updateReadyCommand, getReadyCommandIndex, getSystemCommand,
getPlayerEquippedReadyCommand,
getPlayerEquippedReadyCommandSlotLength,
getPlayerEquippedCustomCommand, getPlayerEquippedCustomCommandCost,
getCastTimeForCustomCommand, getRecastTimeForCustomCommand,
isMyPlayerDead, isShowActionMenu, updateActionMenuWidget,
showGauge, updateMainMenuWidget, processCommandMap
```

Read-side helpers for command/status state queries. Used by HUD
widgets to display buffs, cast bars, equipped commands.

## 3. The work-sync schema (init function, lines 4-764)

The init declares ~30+ work fields for DesktopWidget. Sample
(first 17 entries):

```text
Field                           Type          Purpose
-----                           ----          -------
bazaarActor                     actor         Currently-targeted bazaar
bazaarTargetActor               actor         Selected for purchase
mainTargetCursorImage           integer8      Main cursor sprite ID
subTargetCursorIndex            int8[1]       Array of sub cursor sprite IDs
subTargetCursorType             integer8      Cursor type (player/enemy/ally)
targetCursorMask                boolean       Hide all target cursors flag
mainTargetGmModeFlag            boolean       GM-mode target (admin)
mainTargetDecidedFlag           boolean       Target is locked-in
subTargetExecuteWidget          actor         Widget executing sub-target
subTargetMacroFlag              boolean       Sub-target from macro
subTargetWidgetHideFlag         boolean
subTargetMagicFlag              boolean       Sub-target for magic spell
subTargetCloseFlag              boolean
subTargetActor                  actor         Currently hovered sub-target
targetMode                      integer8      Targeting mode (idle/active/AoE)
commandIndex                    int8[18]      18-slot command bar
bazaarUpdateTime                integer32     Throttle Bazaar refresh
```

The 18-slot `commandIndex` matches the hotbar/command-bar size
(1.x had 18 visible action slots before the ARR-era 30+ slot
hotbar).

## 4. The init UI command condition table

After the work schema, init registers ~30+ UI commands:

```text
"UILuaCommands.PartyTarget1" through "PartyTarget7" (7 entries)
"UILuaCommands.TargetLastAttacker"
"UILuaCommands.ChangeTargetCircleAll"
"UILuaCommands.ChangeTargetCirclePlayer"
"UILuaCommands.ChangeTargetCircleParty"
"UILuaCommands.ChangeTargetCircleEnemy"
"UILuaCommands.ChangeCurrentLinkshell"
"UILuaCommands.SetCurrentLinkshell"
(... and many more)
```

These are the **Lua-side UI command bindings** that fire when
the user presses corresponding keybinds. The `UILuaCommands.` prefix
is the engine's convention for UI-triggered actions.

The chat command parser (per `_parseTextCommand` thunk finding)
resolves text commands via `xtx/_textCommand.csv`. The UI command
bindings here are the COMPLEMENTARY system for keybind / button
triggered actions (which never go through the text parser).

## 5. The "yield-style" widget pattern

The `ask` function reveals a UNIVERSAL widget interaction pattern:

```text
openWidgetYield(zIndex, widget_path, ...)  -- create + show widget
selectWidgetYield(widget, blocking=true)   -- await user input
                                              (script YIELDS here)
widget.getAskResult()                       -- read user's choice
closeWidgetDirect(widget)                   -- destroy widget
```

This is the **client-side counterpart** to the ResumeChecker pattern
on the C++ side. Every widget that needs user interaction follows
this pattern:
1. Open
2. Yield-await selection
3. Read result
4. Close

This is the **3rd async pattern** alongside:
- ResumeCheckerInterface (C++ side, 11 subclasses)
- FunctionEndCallbackInterface (C++ side, I/O completion)
- **Widget yield** (Lua side, user interaction)

The 3 patterns together cover all client-side asynchrony.

## 6. Cross-references to prior findings

```text
- 5 widget types (per widget_3tier_dispatcher_architecture):
  This connector wires into the 194 widget classes (each is a
  WidgetBaseClass subclass)
- 13 widget interaction patterns (per widget_inventory):
  ask, askForEventMode, openWidget, selectWidget, etc. -- all
  here are USED BY this connector
- desktopwidget_packet_dispatch.md:
  Documents the processXxx functions that this connector also has
- 44 DesktopWidget native bindings (per master walk):
  This connector USES those bindings (setTargetCursorImage,
  appendMessagePool, parseTextCommand, etc.)
```

## 7. Server-side implications

```text
This connector is ENTIRELY CLIENT-SIDE LOGIC. None of its 255
methods send wire packets directly -- they all delegate to:
  - desktopWidget native bindings (44 of them)
  - worldMaster:notify/alert/say (chat output)
  - actor:_executeCommand (action wire)
  - widget panels' own methods (UI rendering)

Server doesn't need to model any of this. It just needs to send
the underlying state changes (chat messages, target updates,
inventory changes, etc.) via the standard wire protocol; the
client's DesktopWidget connector renders them via these 255 methods.

What server DOES need to know:
1. Channel routing (32/33/38/40 for chat -- per outbound chat finding)
2. Wire opcodes (0xC8/0xC9 chat, 0x12F/0x132/0x133 work-sync)
3. The 132 critical Lua-accessible CSV tables (server provides data)
```

## 8. Why this file is THE largest

```text
1. SINGLE-CLASS DESIGN: 255 methods on one class (no namespace
   subdivision like other classes)
2. CROSS-CUTTING CONCERNS: every subsystem needs UI; this is the
   shared layer for all of them
3. ASYNCHRONOUS COORDINATION: each widget interaction is its own
   yield-style flow (avg ~100 lines per ask/dialog flow)
4. STATE MACHINE COMPLEXITY: 30+ work-sync fields + per-subsystem
   state tracking
5. NO PARTIAL EXTRACTION: the engine loads this monolithically
   (no lazy class loading)

Modern UI orchestrators (e.g. React-style) would partition this
into 13 separate "controllers", one per subsystem. 1.x took the
monolithic approach common in 2010-era MMO clients.
```

## 9. Confidence

```text
Confirmed:
  - File is 26,564 lines, 255 methods on DesktopWidget
  - 13 functional subsystems identified
  - Universal yield-style widget pattern documented
  - work-sync schema with ~30+ fields
  - ~30+ UI command condition registrations
  - 18-slot commandIndex (hotbar size in 1.x)
  - Connector USES the 44 native DesktopWidget bindings (doesn't
    duplicate the wire surface)
  - Server-side: nothing to model directly; client-internal logic
  - 3rd async pattern (widget yield) complements C++ side patterns

Likely (High):
  - Many of the 255 methods are simple delegators (4-10 lines)
    -- they're mostly orchestration, not algorithms
  - The ~80% of the 26K lines is in the larger subsystem methods
    (target system, ask/dialog flows, bazaar)
  - This file rarely changes during 1.x patch development (UI
    layouts change in widget classes, not in this connector)

Likely (Medium):
  - Some 'process*' methods (processSubTargetDecided, processUpdateJournalDetailWidget,
    etc.) are receivers for inbound work-sync events (called from
    WorkSync inbound chain)
  - The Bazaar UI flow is the most complex single subsystem
    (10+ methods + state machine)
```

## 10. Cross-references

- `finding_desktopwidget_master_44_of_44_complete.md` -- the EXE
  native bindings (this connector USES them)
- `finding_widget_baseclass_architecture_and_194_widgets.md` --
  the 194 widget subclasses (this connector OPENS instances of them)
- `finding_widget_3tier_dispatcher_architecture.md` -- widget
  dispatcher (this connector is the topmost tier)
- `finding_parseTextCommand_thunk_chat_dispatch_architecture.md` --
  text command parser (UI commands are the COMPLEMENT)
- `finding_appendMessagePool_thunk_command_updater_dispatch.md` --
  chat display (used via worldMaster:say etc.)

## 11. Next test

```text
1. Trace 5-10 process* methods to confirm they're inbound work-sync
   receivers (called from CommandUpdater_invokeLua_onUpdateWork)
2. Sample the largest 'ask' flow (askForEventModeMultiple) to map
   multi-choice dialog architecture
3. Document the 18-slot commandIndex's relationship to gameCommand.csv
4. Sample the Bazaar subsystem flow end-to-end (most complex)
5. Sweep companion files (desktopwidget_itemdetail.lua 10K lines,
   equipwidget.lua 10K lines) for similar architecture
```

## Commit suggestion

```
docs(re/lua): DesktopWidget connector deep-dive -- 26,564 lines, 255 methods, 13 subsystems; 3rd async pattern (widget yield) documented
```
