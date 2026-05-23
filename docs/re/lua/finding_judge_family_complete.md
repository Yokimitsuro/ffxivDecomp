# Finding: Judge Family Complete + ActorBaseClass + Craft Command Roster

Closes the Judge subsystem family at the architectural level.
Documents JudgeBaseClass + ChocoboJudge + the massive CraftJudge
(1109 lines). Also adds ActorBaseClass (33 lines, abstract base).

Sources read:

```text
ActorBaseClass.lua                             33 lines  (5 hooks)
judge/JudgeBaseClass.lua                      111 lines  (5 methods)
judge/ChocoboJudge.lua                        138 lines  (7 methods)
judge/Craft/CraftJudge.lua (full inventory) 1109 lines  (35 methods)
judge/DepictionJudge.lua                      814 lines  (covered prior)
judge/Harvest/HarvestJudge.lua                427 lines  (covered prior)
judge/Negotiation/NegotiationJudge.lua        198 lines  (covered prior)
```

## 1. ActorBaseClass.lua (33 lines, ABSTRACT BASE)

The absolute root class. ALL actors derive from this.

```text
5 lifecycle hooks (ALL EMPTY -- subclasses override):
  _onInit
  _onFinalize
  _onTimer
  _onReceiveDataPacket
  _onReceiveTimingPacket
```

Nothing else. The ActorBase is a TRUE abstract base — its behavior
comes entirely from the 11 native bindings (`_bindWork`,
`_callSuperClassFunc`, etc.) documented in
`finding_remaining_native_bindings_sweep.md`.

## 2. JudgeBaseClass (111 lines, 5 methods)

Parent of all judge subclasses:

```text
_onInit                  base init
initText                 init translatable text
init                     main init
prepareSpreadSheet       load sheets
unprepareSpreadSheet     release sheets
```

So judges all have a setup phase that prepares + releases their
sheet data. This is the **sheet-data management base** for all
judges.

## 3. ChocoboJudge (138 lines, 7 methods)

Judge for chocobo/goobbue mounted state.

### State Detection

```lua
function ChocoboJudge:isRiding(actor)
  return actor:_getActorMainStat() == 15
end

function ChocoboJudge:isRidingChocobo(actor)
  return mainStat == 15 and ridingGrade != 257
end

function ChocoboJudge:isRidingGoobbue(actor)
  return mainStat == 15 and ridingGrade == 257
end
```

So **ridingGrade == 257 means Goobbue**, anything else (during
mainStat 15) means chocobo. Main stat 15 = "riding state" applies
to both.

### Permission Predicates

```text
hasWhistle()         _getChocoboGrade() != nil
hasGoobbueWhistle()  _isEnabledGoobbue() == true
```

Whistle = the item that unlocks the mount. Chocobo requires
"chocobo grade" be set; Goobbue has a separate enabled flag.

### `getRidingErrorTextId` -- Goobbue-Specific Error Variants

If the actor is on a Goobbue (grade 257), maps generic error
message ids to Goobbue-specific variants:

```text
generic   goobbue
-------   -------
26005 -> 26022
26010 -> 26024
26013 -> 26029
26014 -> 26030
32507 -> 32508
```

So Goobbue mount uses different error message strings (probably
mentioning "Goobbue" vs "Chocobo" in the localized text).

## 4. CraftJudge (1109 lines, 35 methods)

The CRAFT UI ORCHESTRATOR — the largest judge class. Manages the
entire crafting flow: recipe selection, action execution, repair,
materia attach, leve flow.

### Method Categories

```text
COMMAND PREDICATES (8):
  isCraftSystemCommand
  isCraftStandardCommand     (cmd range 22550-22698)
  isCraftStandardNormalCommand
  isCraftStandardRapidCommand
  isCraftStandardBoldCommand
  isCraftGiftCommand          (cmd range 29501-29698)
  isMainToolOrder             (returns false if toolType in {2, 6})
  getAvailableStandardCraftCommand

WIDGET/UI LIFECYCLE (5):
  openCraftProgressWidget
  closeCraftProgressWidget
  closeCraftStartWidget
  updateInfo
  craftCommandUI / craftTuningUI

CRAFTING FLOW (5):
  start
  selectRcp                   (recipe selection)
  confirmRcp                  (recipe confirmation)
  startRepair                 (repair flow entry)
  cancelTarget

LEVE FLOW (4):
  sendTutorialGuildleve
  selectCraftQuest
  cfmQst                      (confirm quest)
  confirmLeve

LOCALEVE FLOW (2):
  askContinueLocalleve
  askRetryLocalleve

MATERIA JOIN (2):
  askJoinMateria
  askJoinResult

OTHER (3):
  selectRecipeBookTest
  displayRate
  selectTestMotion

LIFECYCLE (2):
  _onInit
  _onFinalize

TEXT DATA (2):
  initText
  loadTextData
```

### Craft Command ID Roster

CONFIRMED from CraftJudge body:

```text
COMMAND ID RANGES:
  22550-22597 (~48 ids):  Standard craft commands
                            48 = 8 classes × 6 actions
                            (Normal/Rapid/Bold × main/sub tool)
  22550-22698 (149 ids):  Standard + extensions
  29501-29698 (197 ids):  Gift commands (special variants)

PATTERN per 8 craft classes:
  jobId 29 -> base 22550   (Carpenter? -- 1st craft class)
  jobId 30 -> base 22556
  jobId 31 -> base 22562
  jobId 32 -> base 22568
  jobId 33 -> base 22574
  jobId 34 -> base 22580
  jobId 35 -> base 22586
  jobId 36 -> base 22592

  Per class, 6 commands available:
    base + 0  (Normal main-tool)
    base + 1  (Rapid main-tool)
    base + 2  (Bold main-tool)
    base + 3  (Normal sub-tool)
    base + 4  (Rapid sub-tool)
    base + 5  (Bold sub-tool)

  + cmd 22506 = global "Rest" or "Wait" action available with
                certain tool types (1 or 2)
```

So **1.x crafting had 3 action types (Normal/Rapid/Bold) × 2 tool
modes (main-tool / sub-tool) per class** = 6 actions per class.

This differs significantly from ARR's craft action system (where
actions are class-specific and there's no "main vs sub tool"
distinction).

### Craft Class IDs (from getAvailableStandardCraftCommand)

```text
jobId 29 = Carpenter (probable)
jobId 30 = Blacksmith
jobId 31 = Armorer
jobId 32 = Goldsmith
jobId 33 = Tanner
jobId 34 = Weaver
jobId 35 = Alchemist
jobId 36 = Culinarian
```

The 8 DoH classes match earlier finding `finding_ffxivbattle_stats_and_jobs.md`.

### Craft Flow (UI Orchestration)

```text
1. Player opens crafting UI
2. CraftJudge:start()
3. CraftJudge:selectRcp()           -- recipe selection
4. CraftJudge:confirmRcp()           -- confirm choice
5. CraftJudge:openCraftProgressWidget()
6. Action loop:
   - Player picks action (Normal/Rapid/Bold)
   - CraftJudge:craftCommandUI() / craftTuningUI()
   - Each action increments progress/quality
   - displayRate() shows success chance
7. Item completes or fails
8. CraftJudge:closeCraftProgressWidget()
```

Plus parallel flows:
- Repair: `startRepair` for repairing damaged items
- Materia: `askJoinMateria` / `askJoinResult` for attaching materia
- Leve: `selectCraftQuest` / `cfmQst` / `confirmLeve` for craft leves
- Localeve: continue/retry flows

## Updated System Inventory

```text
JUDGE FAMILY (now complete):
  JudgeBaseClass        (5 methods; base)
  ChocoboJudge          (7 methods; mounted state)
  CraftJudge            (35 methods; craft UI orchestrator)
  HarvestJudge          (per prior; gathering UI)
  NegotiationJudge      (per prior; NPC negotiation UI)
  DepictionJudge        (per prior; nameplate rendering)
  CommonJudge           (51 lines; tiny base helpers)
  TutorialJudge         (62 lines)
  TutorialDummyJudge    (74 lines)

All 9 judge classes documented at architectural level.
```

## Assessment

```text
Confirmed:
  - ActorBaseClass has only 5 abstract lifecycle hooks; behavior
    from native bindings.
  - JudgeBaseClass manages sheet data for all judges.
  - ChocoboJudge: ridingGrade 257 = Goobbue; else Chocobo.
  - CraftJudge: 1109 lines orchestrating the full crafting UI.
  - Craft has 6 actions per class (Normal/Rapid/Bold × main/sub
    tool); 8 DoH classes total.
  - Craft commands occupy id ranges 22550-22698 (standard) +
    29501-29698 (gift).

Likely (High):
  - The "Bold" action is the slow/high-quality action (1.x had
    such concept).
  - "Rapid" is the fast/cheap action.
  - Main-tool vs sub-tool: 1.x crafters had two tools (e.g.
    Hammer + Tongs for Smithing); each had its own action set.

Likely (Medium):
  - The 197 gift commands (29501-29698) include per-class gift
    variants (maybe 24-25 per class × 8 classes).
  - The 22506 "rest" action available with tool types 1 and 2
    is the "stamina recovery" action (1.x crafting had a stamina
    mechanic).

Speculative:
  - "Localeve" is "local levequest" -- 1.x had two leve types:
    regional (story) + local (combat/craft training).
  - The materia join flow uses RelationGroup (askJoinMateria
    asks via the askForEventMode primitive).
```

## Server Implementation Picture for Crafting

```text
CRAFT INITIATION:
  Server receives "I want to craft" command
  Validates: player has recipe + materials + tool + skill
  Creates craft session (server-side state object)
  Pushes initial state to client via WorkSync (work fields:
    progress, quality, durability, etc.)
  Client opens CraftJudge progress widget

ACTION LOOP (per craft action):
  Client sends opcode 0x12f (work-sync) or specific craft cmd id
    with action choice (Normal/Rapid/Bold + main/sub)
  Server validates + computes outcome (success/fail + delta)
  Pushes updated work state via WorkSync
  Client renders animation + updates UI
  Loop until item completes or fails

COMPLETION:
  Server determines HQ outcome (based on quality vs HQ threshold)
  Pushes final item + HQ flag
  Client renders result via craftCommandUI

REPAIR + MATERIA JOIN:
  Similar flow with different command id ranges
  Uses RelationGroup for confirmation prompts
```
