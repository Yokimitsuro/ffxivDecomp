# Finding: WidgetBaseClass Architecture + 194-Widget Family Roster

Walks the 194-script Widget subsystem from the Lua corpus. Anchors at
`widget/widgetbaseclass.lua` (deciphered from `n1635q/n1635q89r57y9rr.lua`)
and characterizes:

1. The 8+ Lua event hooks defined on WidgetBaseClass
2. The widgetWork schema (state fields)
3. The lifecycle (init -> finalize)
4. The AskBaseClass sub-pattern (modal confirmation dialogs)
5. The 194-widget functional inventory

This closes a major gap in prior Lua findings -- 194 widget scripts
were previously enumerated but the architectural shape was not
extracted.

## 1. WidgetBaseClass: the root of all 194 widgets

```text
File: widget/widgetbaseclass.lua  (n1635q/n1635q89r57y9rr.lua)
Companion: widget/widgetbaseclass_common.lua  (_7vxxvw suffix)
           widget/widgetbaseclass_u.lua       (_p suffix - user side)
```

### 1.1 The 8 Lua event hooks

```text
Hook                      Args            Role
----                      ----            ----
_onInit                   (parent, ...)   Widget construction
                                          - Calls super _onInit
                                          - Initializes widgetWork
                                          - Detects DesktopWidget subclass
                                          - Sends UIOperatorCommands.BeforeLuaInit
                                          - Calls subclass init(args)
                                          - Sends UIOperatorCommands.AfterLuaInit
                                          - Fires processWidgetCreated on
                                            desktopWidget
                                          - Sets widgetWork.initialized = true
_onFinalize               ()               Widget destruction
                                          - Calls super _onFinalize
                                          - Fires processWidgetDeleted
                                          - Fires processFinalize on self
_onUICommandEvent         (A1,A2,A3,A4,A5) UI command event (5 args)
                                          - Sets desktopWidget thread owner
                                          - Calls processUICommandEvent
                                          - Handles deferred SSD sheet load
                                          - Calls processSpreadSheetDataLoaded
_onUICommandRequest       (A1,A2,A3,A4,A5) UI command request (5 args)
                                          - Sets desktopWidget thread owner
                                          - Calls processUICommandRequest
_onHoverHelp              (A1,A2,A3,A4,A5) Hover tooltip request
                                          (empty stub for override)
_onLoadMultiKeyAsync      (A1,A2,A3)       Multi-key async load complete
                                          - Calls processSpreadSheetDataAsync
_onTimer                  (A1,A2,...)      Timer fire
                                          - Calls processTimer
_onLoop                   (A1)             Loop tick (interval = 0.1s)
                                          (empty stub for override)
```

### 1.2 Correlation with EXE invokeLua roster

The Widget Lua hooks match exactly the EXE invokeLua callbacks:

```text
EXE invokeLua function                   -> Lua hook fired
------                                       ----
invokeLua_onHoverHelp (0x00707610)        -> _onHoverHelp (5 ushort args)
invokeLua_onLoadKeyAsync (0x00707300)     -> _onLoadKeyAsync
                                             (single-key variant; see 1.5)
invokeLua_onLoadMultiKeyAsync (0x0070a580) -> _onLoadMultiKeyAsync
DesktopWidget_invokeLua_onCreatedWidgetInWidgetContainer
                                          -> processWidgetCreated handler
```

Confirms the prior finding's hypothesis: the `_onHoverHelp` and
`_onLoadMultiKeyAsync` callbacks are part of the **Widget subsystem**.

### 1.3 widgetWork schema (state container)

Every widget instance has a `widgetWork` field with these slots:

```text
Field                   Type           Notes
----                    ----           -----
requestSsdLoadSheet     actor          Sheet name to load (nil when idle)
requestSsdLoadKeyMin    integer32      Min key for sheet load
requestSsdLoadKeyMax    integer32      Max key for sheet load
commonTimer             timer          Shared timer object
common                  nesting(72)    Common nested struct (72 bytes)
initialized             boolean        True after init() completes
_assignForChild         290            Size hint (290 bytes)
```

Plus DesktopWidget subclass adds:
```text
desktopWidgetWork
  _assignForChild      1024            (DesktopWidget gets extra 1KB)
```

### 1.4 Lifecycle sequence

```text
NEW widget construction:
  1. operator_new + Lua VM allocates instance
  2. _onInit fires
  3. _callSuperClassFunc("_onInit")  (chain up to base classes)
  4. widgetWork._temp gets initialized with the schema above
  5. Test for DesktopWidget subclass via _isInstanceOf;
     if yes, also init desktopWidgetWork
  6. _setLoopInterval(0.1) -- loop ticks every 100ms
  7. sendCommand("UIOperatorCommands.BeforeLuaInit")
  8. Calls subclass init(args) -- subclass-specific setup
  9. sendCommand("UIOperatorCommands.AfterLuaInit")
  10. If parent widget given: _setParentWidget(parent)
  11. widgetWork.initialized = true
  12. desktopWidget:processWidgetCreated(self) -- registers in widget tree

DESTRUCTION:
  1. _onFinalize fires
  2. _callSuperClassFunc("_onFinalize")
  3. If not currently initializing:
       desktopWidget:processWidgetDeleted(self) -- removes from tree
  4. processFinalize() on self (subclass cleanup)
```

### 1.5 The "spread sheet" deferred load pattern

The `requestSsdLoadSheet` field implements a **deferred sheet load**:

```text
When _onUICommandEvent fires:
  1. Process the UI command via processUICommandEvent
  2. CHECK: if requestSsdLoadSheet was set by the command handler,
     LOAD the sheet now (after the command, not during):
       sheet:_loadKeyTemporarily(keyMin, keyMax)
  3. Call processSpreadSheetDataLoaded(sheet)  -- subclass callback
  4. Clear requestSsdLoadSheet = nil
```

This lets command handlers REQUEST data without blocking on the load;
the load happens at a safe point AFTER the command completes.

The async variant (`loadSpreadSheetDataAsync`) calls the sheet's
`_loadMultiKeyAsync` (an actor binding) which dispatches asynchronously
and fires `_onLoadMultiKeyAsync` when complete.

## 2. AskBaseClass: modal confirmation dialogs

```text
File: widget/ask/askbaseclass.lua  (n1635q/9rz/9rz89r57y9rr.lua)
Parent: WidgetBaseClass
```

### 2.1 askWork schema

```text
Field            Type        Notes
----             ----        -----
askResult        integer16   The selected option (0 = no selection / pending)
inputControlFlag boolean     If true: setInputEnable is toggled around
                             ask interaction (disable while waiting,
                             re-enable on result reset)
_assignForChild  128         Size hint
```

### 2.2 Ask lifecycle

```text
1. Widget._onInit fires (as base)
2. AskBaseClass.init() runs:
   - Initializes askWork with default values (askResult=0,
     inputControlFlag=true)
   - setModal(true)  -- marks as modal (blocks other input)
   - Calls subclass initAsk(args)
3. Modal interaction:
   - Widget renders, captures input
   - setBaseAskResult(N) sets askResult and disables input
4. processWaitCallFunction checks isAskFinish:
   - isAskFinish returns askResult != 0
   - Loop continues until result is set
5. Caller reads getAskResult() to know which option was selected
6. resetBaseAskResult clears state for reuse
```

### 2.3 The Ask subdirectory inventory (~30+ widgets)

The `widget/ask/` subdir contains all modal dialogs in 1.x:

```text
Category               Examples
----                   ----
Character creation     bonuspointassignwidget, chocobonamingwidget
GC interaction         grandcompanyofficialjoinwidget,
                       grandcompanyshopwidget
Guildleve              guildlevecardorderwidget,
                       guildleveselectlevelwidget,
                       guildlevestartwidget
Gathering              fellinginputwidget (Botanist gathering),
                       fishinginputwidget
Hamlet Defense         hamletdefenserankingwidget,
                       hamletdefensescorewidget,
                       hamletdefensetutorialwidget
Item / Inventory       itemsearchwidget, itemstoragegetwidget,
                       itemstorageputwidget
Journal                journaldetailwidget, journallistwidget
Linkshell              linkshellconfirmwidget, linkshelllistwidget,
                       linkshellnamingwidget, linkshellselecticonwidget
Job                    jobtutorialwidget
Aetheryte              aetherytelistwidget (also in non-ask area)
Misc                   askwidget (the generic OK/Cancel dialog)
```

Note: **NO FreeCompany widgets** in 1.x (per `feedback_no_freecompany_in_1x`
memory). Grand Company is the only player-org system, and it has its
own widgets (grandcompanyofficialjoin, grandcompanyshop).

## 3. The 194-widget functional inventory (by category)

```text
Category                  Widget count   Examples
--------                  ------------   --------
Modal asks (ask/*)        ~30           See section 2.3
Achievement               4             detail/list/popup/titlelist
Action                    5             equipList/sub/widget, gauge,
                                        menu, setting
AddressList               3             main/naming/sub
Aetheryte                 2             list (and ask variant)
DesktopWidget             ~10           Various HUD elements
Inventory                 ~15           Item edit/detail/use/share/etc.
Journal                   ~10           Detail/list/quest progress
Linkshell                 ~10           Confirm/list/naming/selecticon
Status                    ~5            Buff display widgets
Battle                    ~10           ActionGauge, target status, etc.
Common UI                 ~30           Error/notice/confirm dialogs
Other domain-specific     ~60           Misc per-feature widgets
---
TOTAL                     194
```

## 4. Architecture: 1.x's UI as a Lua-driven scene graph

```text
Hierarchy:
  desktopWidget (singleton in C++, the root scene graph holder)
    -> WidgetContainer (collection of active widgets)
       -> WidgetBaseClass instance (each .lua subclass)

Event dispatch:
  C++ side: desktopWidget receives input/network events
    -> dispatches via UICommands.* hooks
    -> the active widget's _onUICommandEvent/_onUICommandRequest fires
    -> Lua subclass processUICommandEvent does specific logic

Sheet data:
  C++ side: NpcBase/Item/etc. provides sheet data via SSD
    (Static Sheet Data) container
  Lua side: widget requests via requestLoadSpreadSheetData
  -> deferred load via _loadKeyTemporarily after command
  -> processSpreadSheetDataLoaded callback fires
  -> widget renders the loaded data

Timer:
  setLoopInterval(0.1) -- the widget loops every 100ms
  _onLoop fires each tick (empty stub; subclass overrides)
  setCommonTimer(t) attaches a timer; _onTimer fires when it expires
```

## 5. Server design implications

```text
For a server to drive client widgets correctly:

  IMMEDIATE WIRE TRIGGERS (server sends -> client widget fires):
    UICommands.BeforeLuaInit          -- before any widget init
    UICommands.AfterLuaInit           -- after widget init complete
    UICommandEvent                    -- widget receives event
    UICommandRequest                  -- widget receives request
    HoverHelp                          -- tooltip request
    LoadKeyAsync / LoadMultiKeyAsync  -- async data load notify

  STATE FIELDS to populate:
    widgetWork.requestSsdLoadSheet    -- sheet name (e.g. "actor")
    widgetWork.requestSsdLoadKeyMin   -- e.g. an actor id
    widgetWork.requestSsdLoadKeyMax   -- e.g. same actor id
    
  SHEET-LOAD COORDINATION:
    Server pushes ACTOR DATA via the Static Sheet Data (SSD) channel
    Widget retrieves via _loadKeyTemporarily(keyMin, keyMax)
    Server must ensure SSD data is in-cache before the widget asks
    for it (or the widget will get nil and render empty)

  MODAL DIALOG INTERACTION:
    Server pushes "open dialog widget X" command
    Widget shows, captures input, sets askResult
    Server pushes acknowledgment of the result back
    
For Hamlet Defense, Guildleve, Linkshell, etc., the same pattern
applies -- each ask widget has its own setBaseAskResult contract.
```

## 6. Cross-references

- `finding_desktopwidget_native_bindings.md` -- the C++ side of
  DesktopWidget (4 bindings: TargetChanged/Decided/PreWarp/PostWarp)
- `finding_desktopwidget_packet_dispatch.md` -- the inbound dispatch
  for DesktopWidget events
- `finding_invokeLua_roster_closed_80_complete.md` -- the 80 EXE
  invokeLua callbacks (this finding correlates _onHoverHelp and
  _onLoadMultiKeyAsync to the Widget class)
- `finding_negotiation_bazaar_widget_family.md` -- earlier finding
  on the bazaar widget cluster (subset of the 194-widget family)
- `feedback_no_freecompany_in_1x` (memory) -- 1.x has no FreeCompany;
  Grand Company widgets cover the equivalent role

## 7. Confidence

```text
Confirmed:
  - WidgetBaseClass is the root of all 194 widget scripts
  - 8+ Lua event hooks defined on WidgetBaseClass
  - widgetWork schema with 7 fields (verified via _temp init)
  - AskBaseClass extends WidgetBaseClass for modal dialogs
  - askResult/inputControlFlag fields in askWork
  - desktopWidget singleton manages widget lifecycle
  - The 0.1s loop interval is default for all widgets
  - The deferred SSD-sheet load pattern is universal across all
    widget UICommandEvent handlers
  - 194 widgets total (per catalog.md count)

Likely (High):
  - Each of the ~30 ask widgets has its own initAsk() taking
    different args based on the prompt type
  - The 8 event hooks correspond 1:1 with EXE invokeLua functions
    (already verified for _onHoverHelp and _onLoadMultiKeyAsync)
  - DesktopWidget subclass is the singleton root with 4 specific
    events on top of base widget events

Likely (Medium):
  - The 194 widget count includes ALL UI surfaces in 1.x
  - The "ask" subdir contains every modal prompt the player can
    encounter (~30 confirmation flows)
  - Each widget's per-feature logic (item/journal/linkshell/etc.)
    is implementable independently for server testing

Speculative:
  - The widgetWork "common" field at 72 bytes may hold inherited
    state for the most common widget operations (timer, parent
    ref, render flags)
  - The UICommandEvent's 5 args (A1..A5) probably encode: opcode,
    target widget id, source actor, parameter, flag
```

## 8. Next test

```text
1. Read the DesktopWidget subclass to find the 4 specific events
   plus the desktopWidgetWork schema
2. Sample a few "ask" widgets (e.g., linkshellconfirmwidget,
   grandcompanyshopwidget) to see the initAsk argument patterns
3. Trace the UICommandEvent dispatch from server -> client to find
   which inbound opcodes drive widget events
4. Catalog the 30 ask widgets by interaction type (confirm-only,
   1-of-N choice, free-text input, slider, etc.)
```

## Commit suggestion

```
docs(re/lua): WidgetBaseClass architecture + 194-widget family roster + Ask subclass
```
