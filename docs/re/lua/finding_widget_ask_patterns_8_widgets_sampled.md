# Finding: Widget/Ask Interaction Patterns -- 8 Widgets Sampled, 7 Pattern Categories

Samples 8 representative widgets from the `widget/ask/` subdirectory
to characterize the interaction-pattern taxonomy used by AskBaseClass
subclasses. Extracts the shared widget API surface (~30 methods) and
classifies the 7 distinct user-interaction patterns observed.

## 1. Sampled widgets (8 of ~30 ask widgets)

```text
Widget                          Pattern category         Size
------                          ----------------         ----
AskWidget                       multi-choice paginated   15166 B
LinkshellConfirmWidget          2-button + context        3310 B
ChocoboNamingWidget             text input + IME branch   7416 B
LinkshellSelectIconWidget       icon grid (1-of-58)       7047 B
GuildleveSelectLevelWidget      variable-count list       4705 B
ContentRewardWidget             read-only confirmation   13267 B
HamletDefenseScoreWidget        live-data display         3007 B
BonusPointAssignWidget          slider/distribute        37233 B
```

## 2. The shared Widget API surface (~30 methods)

Observed across the 8 sampled widgets. All methods are defined on
WidgetBaseClass / AskBaseClass / their bases.

### 2.1 UI construction (called during initAsk)

```text
Method                                           Purpose
------                                           -------
setConfirmCondition(buttonName)                  Mark button as "fires askResult"
setCancelCondition()                              Mark cancel as enabled (no btn)
setCloseCondition()                               Mark close as enabled
setCommandParameter(btnName, value)               Bind a param to the button
setHelpParameter(btnName, helpType, helpId)       Contextual help text
setControlCommandCondition(ctlName, command)      Control-level cmd hook
setApplicationOperateCommand(ctlName)             App-level operate hook
_setUICommandCondition(btnName, cmd, ?int)        Low-level UI cmd binding
_setUICommandTemplateCondition(tpl, ctl, cmd, ?) Template instance binding
```

### 2.2 Control properties

```text
setControlProperty(ctlName, propName, value)     Direct property write
_setProperty(?, ctlName, propName, ...)          Low-level (with worldMaster)
setText(ctlName, textId, ...args)                Text via worldMaster text id
setContent(ctlName, contentRef)                  Content (text or struct)
setVisibility(ctlName, bool)                     Show/hide
setEnable(ctlName, bool)                          Enable/disable input
setIcon(ctlName, iconId, ...args)                Icon assignment
setLogicalFocus(ctlName)                          Set logical focus
setKeyboardFocusedControl(ctlName, ?tplBtn)      Set keyboard focus
setItemVisibility(?, listItemName, bool)         Per-list-item visibility
setIMEInput(ctlName, bool)                        IME input enable (CJK)
setAcceptChars(ctlName, charSet)                  Input char restriction
```

### 2.3 List operations (for ListBox-based widgets)

```text
addListBoxItem(listName, itemName, count)        Add dynamic items
setListText(listName, idx, role, textId, ...)   Per-item text
setListProperty(listName, idx, propName, value) Per-item property
updateListProperty(listName)                     Flush list updates
```

### 2.4 Result + state methods (AskBaseClass)

```text
setBaseAskResult(value)              Sets askResult (the user's choice)
getBaseAskResult()                    Reads askResult
isAskFinish()                         True if askResult != 0
setInputContorlFlag(bool)             Toggle input control during ask
setModal(bool)                        Modal-on/off
initialWidget()                       Finalize widget post-init
```

### 2.5 Event handlers (subclass overrides)

```text
initAsk(args...)                      Per-widget initialization
processAfterShow(arg)                  Hook after widget shown
processUICommandOperate(A1,A2,A3,A4)  Button pressed (A3 = param value)
processUICommandCancel(A1,A2,A3,A4)   Cancel pressed
processUICommandRequest(...)           UI request (read)
processWaitCallFunction(self)          Polling check (default: isAskFinish)
processSpreadSheetDataAsync(sheet, ?) SSD load callback
```

## 3. The 7 interaction-pattern categories

### Pattern A: Pure confirmation (single button, acknowledge-only)

**Examples**: `ContentRewardWidget`

```text
Layout: Button_Confirm (only)
Pressing Confirm sets askResult to a non-zero value -> isAskFinish.
No branching, no choice.
```

ContentRewardWidget displays guildleve/content rewards. The Confirm
button is set up with text fetched via `A1:getContentRewardButtonText()`
which can return up to 33 values (single text or multiple alternatives).
If no text is returned, the button is hidden.

### Pattern B: 2-button choose-A/B + context

**Examples**: `LinkshellConfirmWidget`

```text
Layout: Button_Making (=1) + Button_Back (=2) [+ optional Button_Quit (=-1)]
Press one button -> processUICommandOperate(A3=value) -> askResult = A3.
A3 = 1, 2, or -1 distinguishes which path the user chose.
```

LinkshellConfirmWidget branches on A1 (mode):
- A1 == 1: Creator mode (shows Button_Quit too, help text ids 79241/79243)
- Else: Joiner mode (Quit hidden, different texts)

Icon + name display:
- `setIcon("IconControl_Emblem", desktopWidget:getLinkshellIconID(linkshellRef))`
- `setText("TextBlock_LinkshellName", linkshellName)`

### Pattern C: Multi-choice list (with optional pagination)

**Examples**: `AskWidget` (generic, paginated), `GuildleveSelectLevelWidget`
(variable-count)

`AskWidget` (the canonical multi-choice):
```text
Work fields:
  askDefaultAnswer (int8)  - initially-focused option
  askAnswerMax     (int8)  - total options
  askPageMax       (int8)  - total pages
  askPageNow       (int8)  - current page
  askPaging        (bool)  - whether pagination is on
  canCancel        (bool)  - whether cancel is allowed
Layout:
  ListBox_Answers (24 slots) with Item_Answers template
  Button_Previous (= UILuaCommands.PagePrevious)
  Button_Next     (= UILuaCommands.PageNext)
Each Answer button uses the TemplateButton_Answer pattern.
```

`GuildleveSelectLevelWidget` (variable-count, no pagination):
```text
Layout: ListBoxItem_Level_1 .. ListBoxItem_Level_5 (up to A1 max levels)
Each level item:
  - has its own ConfirmCondition
  - text from worldMaster ids 50016..50020 (Level 1..5)
  - higher items hidden when level > A1
Title from worldMaster id 50015.
```

The "variable-count" pattern reuses fixed slots and hides excess via
`setItemVisibility` rather than dynamically adding/removing items.

### Pattern D: Text input (with IME branching)

**Examples**: `ChocoboNamingWidget`, `LinkshellNamingWidget`

```text
Layout: TextBox_Name + Button_Decide + Button_Cancel
Press Decide -> validates -> askResult = entered text id
```

ChocoboNamingWidget branches on `desktopWidget:isChinese()`:
- Western locale: A-Z a-z only, MaxLength 10 chars, no IME
- Chinese locale: IME enabled, MaxLength 10b (10 bytes), 
  IsReplaceUnaccept=true, "Alphabet|Number" allowed,
  work.maxZenHan = 4 (max full-width chars)

The "_TextChanged" event listener fires per-keystroke; Button_Decide is
initially disabled and enabled when text is valid.

### Pattern E: Visual picker (icon grid)

**Examples**: `LinkshellSelectIconWidget`

```text
Layout: 58 icon buttons in a fixed grid (Button_Icon_1 .. Button_Icon_58)
Each: setConfirmCondition + setCommandParameter(name, i) +
      setIcon(":IconControl_Icon", iconBaseId + i - 1)
Plus Button_Next/Button_Back/Button_Quit for navigation
```

LinkshellSelectIconWidget uses iconBaseId = 387 (so icons 387..444).
Selecting an icon sets askResult = the icon index (1..58).

The "grid via loop" pattern is uniform: each cell is its own button
with its own ConfirmCondition+CommandParameter.

### Pattern F: Slider/distribute (multi-value allocation)

**Examples**: `BonusPointAssignWidget`

```text
20+ work fields for 6 stats (str, vit, dex, int, mnd, pie):
  - Current value (integer16)
  - CumulateAddBonus (integer16)
  - AddBonusLimit (integer16)
  - AddBonus (integer16)
Plus: totalRemainingBonusDefault, totalRemainingBonus
```

The 4-field-per-stat structure (Current + CumulateAddBonus + 
AddBonusLimit + AddBonus) is the **character creation point-allocation
pattern**:
- `Current` = current stat value
- `AddBonus` = points being added in THIS session
- `AddBonusLimit` = per-stat cap
- `CumulateAddBonus` = total cumulative bonus already applied

Submit: validates total <= totalRemainingBonusDefault; commits per-stat
AddBonus values; the server-side stat-assignment packet uses these
6 deltas.

### Pattern G: Live-data display (with on-load fetch)

**Examples**: `HamletDefenseScoreWidget`

```text
initAsk fetches data from worldMaster:_getMyPlayer():
  count = player:_countHamletDefenseScore()
  for i = 1 to count:
    (point, bonus) = player:_getHamletDefenseScore(i)
    setListText("DataMaker_ListBox", i-1, "bonus", 13019, bonus)
    setListProperty("DataMaker_ListBox", i-1, "point", point)
  
  (point, level, finalPoint, ?, ?) = player:_getHamletDefenseScoreAll()
  setText("TextBlock_ContentsTitle", 13012, A1, point)
  setText("TextBlock_PointTotalValue", 225, finalPoint)
  setText("TextBlock_CorrectionLevelValue", 3189, point)
  setText("TextBlock_PointAfterCorrectionValue", 225, finalPoint)
  setText("TextBlock_ClearTimeValue", 225, ...)

updateListProperty("DataMaker_ListBox")  -- flush rendering
```

This pattern is **READ-DRIVEN**: the widget pulls data from a Lua
binding on first show, populates the UI, and offers a Confirm button
to dismiss. No round-trip with the server during interaction.

The `setText(ctlName, textId, ...args)` pattern uses **worldMaster
text ids** (which are format strings with placeholders); the trailing
args fill the placeholders.

## 4. Universal interaction protocol

Distilling across all patterns, every ask widget follows this protocol:

```text
1. WidgetBaseClass._onInit fires
2. AskBaseClass.init runs:
   - askWork init (askResult=0, inputControlFlag=true)
   - setModal(true)
   - calls subclass initAsk(args)
3. SUBCLASS initAsk(args):
   - Initialize work._temp with widget-specific fields
   - Loop over UI controls:
     - setConfirmCondition + setCommandParameter (for clickable)
     - setText / setIcon / setVisibility (for display)
   - setCancelCondition (if cancel allowed)
   - initialWidget() to finalize
4. processAfterShow may set initial focus
5. USER INTERACTS:
   - Click button -> processUICommandOperate(A1, A2, A3, A4)
     -> typically: setBaseAskResult(A3 or computed value)
   - Cancel -> processUICommandCancel
     -> typically: setBaseAskResult(0 or sentinel)
6. processWaitCallFunction polls isAskFinish (askResult != 0)
7. Caller reads getAskResult() to know what user chose
```

## 5. Server design implications

```text
For a server to support these widget interactions:

  TRIGGER WIDGET OPEN:
    Server pushes "open widget X with params A1..AN" via the
    UI command channel
    -> Client instantiates Widget subclass with initAsk(A1..AN)

  RECEIVE RESULT:
    Widget's processUICommandOperate sets askResult
    Caller polls isAskFinish
    When done, getAskResult is read and an outbound command is
    submitted back to the server

  STAT-ASSIGNMENT (BonusPointAssignWidget):
    Server pushes initial stat state (current, limits, totals)
    Client widget shows sliders, validates locally
    Server receives per-stat deltas in submit packet

  HAMLET DEFENSE SCORE (HamletDefenseScoreWidget):
    Server pushes player's HamletDefenseScore data via
    PlayerBase_registerLua_getHamletDefenseScore (per session 1)
    Widget fetches via _getMyPlayer()._countHamletDefenseScore /
    _getHamletDefenseScore / _getHamletDefenseScoreAll
    NO direct server packet during widget interaction; data must
    be in-cache before widget opens

  LINKSHELL CREATE/JOIN (LinkshellConfirm/Naming/SelectIcon):
    Multi-step flow: ConfirmWidget -> NamingWidget -> SelectIconWidget
    Each step's askResult feeds the next; final submit sends
    (name + icon + color) tuple to the server
    Server validates + creates the linkshell record

  CHOCOBO NAMING (ChocoboNamingWidget):
    Single text input; server receives the name on submit and
    validates length/charset (server-side check mirrors the
    client-side IME/alphabet restrictions)
```

## 6. Text ID notes

Many widgets fetch text via `setText(ctlName, textId)`. The text IDs
observed include:

```text
ID range        Domain (inferred)
---------       -----------------
1226            "Select icon" prompt
1234..1236      Linkshell "Join" mode title/help/buttons
1245..1254      Linkshell "Create" mode title/help/buttons
3189            "Correction Level"
13012           Hamlet Defense title
13019           Hamlet Defense bonus label
50015..50020    Guildleve level select (title + levels 1..5)
79241, 79243    Linkshell help texts (Making, Back buttons)
225             Generic numeric text id (used for value formatting)
```

These IDs are looked up from a global "worldMaster" text table that
the server provides via SSD (`requestSsdLoadSheet = "text"`).

## 7. Cross-references

- `finding_widget_baseclass_architecture_and_194_widgets.md` --
  WidgetBaseClass + AskBaseClass architecture; this finding samples
  8 concrete instances of AskBaseClass
- `finding_tutorial_debug_gamedata_subsystems.md` -- SpreadSheet
  binding is the data source for many widget fields
- `finding_playerbase_lua_bindings_99_complete.md` -- many widget
  fetches use PlayerBase bindings like _getHamletDefenseScore,
  _getOccupancyContentsTime, etc.
- `feedback_no_freecompany_in_1x` (memory) -- the Linkshell widgets
  ARE the player-org confirmation flow in 1.x (no FreeCompany system)

## 8. Confidence

```text
Confirmed:
  - 7 distinct interaction patterns observed across 8 widgets
  - Universal interaction protocol (initAsk -> user interaction ->
    setBaseAskResult -> poll isAskFinish -> getAskResult)
  - ~30 widget API methods documented from 8 samples
  - Text IDs use worldMaster lookup for localization
  - LinkshellConfirmWidget branches on mode (Create vs Join)
  - ChocoboNamingWidget branches on IME locale (Chinese vs Western)
  - HamletDefenseScoreWidget uses PlayerBase bindings directly
  - BonusPointAssignWidget has 4-field-per-stat structure
    (Current/CumulateAddBonus/AddBonusLimit/AddBonus) for 6 stats

Likely (High):
  - The remaining ~22 ask widgets fall into the same 7 patterns
    (or fewer; ~30 widgets need at most 7 patterns)
  - Multi-step flows (Confirm -> Naming -> SelectIcon for Linkshell)
    chain askResult from one widget to the next
  - The "DataMaker_ListBox" / "Item_Answers" listbox templates
    are reused across many widgets
  - Pattern G (live-data display) is used by score widgets,
    journal widgets, etc.

Likely (Medium):
  - The "1.x linkshell create" flow is: Confirm -> Naming ->
    SelectIcon -> server submits the bundle
  - BonusPointAssignWidget is THE character creation stat
    assignment widget (10 of the 20 fields are stat-related)
  - Some widgets (JournalDetailWidget at 46KB, ActionMenuWidget
    at 64KB, ActionSettingWidget at 87KB) are massively more
    complex than the sampled ones

Speculative:
  - The 33-value return from getContentRewardButtonText may
    correspond to 33 distinct reward types (XP, money, item slot,
    etc.)
  - GuildleveSelectLevelWidget's max-5 levels confirms the 1.x
    guildleve difficulty system (Easy/Normal/Hard/Expert/Master)
  - Some widget categories not yet covered (multi-page browser,
    quest detail viewer, item link reference)
```

## 9. Next test

```text
1. Read JournalDetailWidget (46KB) -- the most complex widget
   in the catalog; likely contains the quest journal/log
   interaction pattern
2. Sample 2-3 more ask widgets for patterns NOT yet covered:
   - itemstoragegetwidget (49KB) -- inventory transfer pattern
   - actionsettingwidget (87KB) -- the biggest widget
   - grandcompanyshopwidget (53KB) -- shopping pattern
3. Walk the DesktopWidget subclass to find its 4 specific events
   plus the desktopWidgetWork extension fields
```

## Commit suggestion

```
docs(re/lua): Widget/Ask 8 samples + 7 interaction patterns + 30-method API surface
```
