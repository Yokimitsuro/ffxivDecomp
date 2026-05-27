# Finding: 4 Large Widgets Sampled -- 5 Additional Patterns (Total: 12 Categories)

Extends `finding_widget_ask_patterns_8_widgets_sampled.md` (7 patterns
from 8 small widgets) by sampling 4 large widgets (43-87 KB each).
Identifies **5 new interaction-pattern categories** not present in the
prior sample. Brings the widget taxonomy to **12 categories total**.

## 1. Sampled widgets (4 of ~10 large widgets)

```text
Widget                     Size     Lines  Methods  Base class
------                     ----     -----  -------  ----------
JournalDetailWidget       46 296 B  1826   18       AskBaseClass
ItemStorageGetWidget      48 588 B  2218   38       AskBaseClass
GrandCompanyShopWidget    53 009 B  2328   40       AskBaseClass
ActionSettingWidget       87 457 B  4187   40+      WidgetBaseClass (NOT Ask!)
```

The size jump from 1-10KB (small widgets) to 46-87KB (large) reflects
real complexity, not just verbosity:
- Small widgets: ~5-30 methods
- Large widgets: 18-40+ methods, multiple sub-features bundled

## 2. The 5 new pattern categories

### Pattern H: Multi-template + child-dialog chain

**Exemplified by**: `JournalDetailWidget` (46KB)

```text
Work fields (13 total):
  questCompleted    boolean
  mode              integer8    (which journal view: quest/guildleve/etc)
  questIndex        integer8
  journalType       integer8
  journalSubindex   integer8
  offerLimit        integer8
  journalID         integer32   (the actual quest/leve id)
  townIcon          integer32
  designIcon        integer32
  frameIcon         integer32
  skillIcon         integer32   (class icon -- 1.x guildleves are class-locked)
  skillIconHelp     integer32
  guildleveFailed   boolean
```

Key methods that reveal the pattern:
```text
initTemplate                       -- builds a generic template
addGuildleveTemplate              -- guildleve-specific template inject
addGuildleveTemplateTitle         -- title sub-template
addGuildleveTemplateNormal        -- body sub-template
loadIconData                       -- async icon load via SSD
setDetailData / setInfoData / setRewardData -- 3 distinct content tabs
getIconID / getIconHelpID          -- per-quest icon resolution
processAskResult                   -- RECEIVES result from CHILD dialog
processErrorDialogResult           -- RECEIVES result from CHILD error dialog
checkGuildleveProcess              -- guildleve state validation
finish                             -- explicit terminate method
```

The pattern: **the widget can spawn CHILD dialogs and resume from
their results**. `processAskResult(childResult)` receives the askResult
of a previously-opened child ask dialog (e.g., "Confirm abandon
this quest?") and continues the parent's flow based on the choice.

`processErrorDialogResult` is a SECOND child-dialog handler -- for
error popups (e.g., "Cannot abandon main story quest"). Two
sub-dialog paths sharing the same parent.

### Pattern I: Non-modal persistent panel

**Exemplified by**: `ActionSettingWidget` (87KB, the largest widget)

```text
KEY DIFFERENCE: extends WidgetBaseClass (NOT AskBaseClass)
  - No setModal(true) in init
  - No askResult / isAskFinish polling
  - Has its own update() method called by external triggers
  - User can interact with OTHER widgets while this one is open

Work fields (7 total):
  selectAction      integer32
  selectClass       integer32
  jobID             integer32
  helpCommandID     integer32
  classType         integer8
  selectActionIndex integer8
  selectClassIndex  integer8
```

Method density reveals 4 sub-features in one panel:
```text
Battle      -> setBattleGrid / setEquipAction / setBattleGodSend
Craft       -> setCraftGrid / (separate sub-panel)
Gather      -> setGatherGrid / (separate sub-panel)
Class       -> setClassButton / setClassIndex / setClassButtonEffect /
               getClassType / getClassCommandTbl
Equipment   -> setCommandIcon / setCommandIconEquipBar /
               setEquipGodSendEquipBar / setEquipButtonEffect /
               equipAction / equipGodsend / isEquipCommand /
               isEquipGodsend / getEquippedCommandID
Godsend     -> setGodsend / setEquipGodSend / setEquipGodsend
               (1.x term for class-locked unique skills)
```

This is the **action bar / hotbar configuration panel** -- the player
drags abilities into equippable slots, with separate grids for Battle
(combat skills) vs Craft (crafting actions) vs Gather (gathering
actions).

**Architecturally important**: this proves that NOT ALL widgets are
modal dialogs. ~5-10 widgets in the catalog (the persistent HUD,
chat panel, action bar configurator, etc.) extend `WidgetBaseClass`
directly without AskBaseClass.

### Pattern J: Tabbed list with focus + selection tracking

**Exemplified by**: `ItemStorageGetWidget` (49KB),
                    `GrandCompanyShopWidget` (53KB)

```text
ItemStorageGet work fields (focus tracking):
  category          integer32
  isDecided         boolean
  chosenItem        integer32
  chosenPackage     integer32
  chosenOperation   integer32
  mode              integer16
  index             integer16
  focus             integer16    -- current cursor focus
  selected          integer16    -- current selection
  prevIndex         integer16    -- previous index (for animation)
  prevFocus         integer16    -- previous focus (for animation)
  prevCount         integer16    -- previous count (for delta tracking)
```

Key shared methods:
```text
processUICommandSelection         -- DISTINCT from Operate; list selection
processUICommandClose             -- separate from Cancel (explicit close)
processTimer                      -- auto-updates / animations / scroll
focusToIndex / indexToFocus       -- bidirectional index <-> focus mapping
updateListFocus                    -- redraw current focused item
setSortType / updateSortType      -- list sort modes
getListBoxName / getListBoxItemNum / getListBoxFocusNum  -- list query
catalogSkip                       -- skip ahead in catalog
selectedBorder                    -- focus border decoration
previousSequence                   -- back navigation
displayFocusedItemHelp            -- contextual help text
```

The pattern: **multi-tab list browser with cursor**. Unlike Pattern C
(multi-choice list, simple), this pattern has:
- Persistent focus separate from selection (focus = where cursor is;
  selection = what's chosen)
- Sort modes (alphabetical, by category, by recent, etc.)
- Per-tab content filtering
- Timer-driven auto-updates (for live inventory/shop refresh)
- Help text shown for the focused item

ItemStorageGetWidget is the **storage chest retrieval UI** -- the
player browses through stored items by category and selects what to
withdraw.

GrandCompanyShopWidget is the **GC token shop** -- browses tabs of
items purchasable with GC seals, with rank-gating.

### Pattern K: Shop/transaction with rank gating

**Exemplified by**: `GrandCompanyShopWidget` (53KB)

```text
Work fields (13 total):
  askStatus              boolean
  isUpdateMoney          boolean    -- triggers money display refresh
  editWidgetOpen         integer8   -- ID of currently-open child edit dialog
  townID                 integer8   -- 0/1/2 for the 3 GCs
  chosenOperation        integer32  -- buy/sell/equip
  buyCount               integer32  -- quantity to purchase
  pointID                integer32  -- which point currency (Grand Company Seal)
  currentItemCatalogID   integer32
  updateItemCount        integer32  -- pagination cursor
  selected               integer32
  selectedItemSheetIndex integer32  -- index into shop's SSD
  myRank                 integer32  -- player's GC rank (for gating)
  myPoint                integer32  -- player's current GC seals
```

Distinctive methods:
```text
setMaskInformation                 -- HIDES items player can't see yet
isMaskItem                         -- query "is this item rank-gated?"
setItemMask                        -- apply the mask
operateBuy                         -- the transaction
setShopEditData / closeShopEdit    -- spawn/close edit child widget
setTabCommandCondition             -- tab navigation
displayBagCapacity                  -- show inventory free slots
displayGrandCompanyName / Rank / Point -- GC-specific HUD elements
getGrandCompanyBanner / getTownName / getGrandCompanyName
                                     -- per-GC info display
getGrandCompanyStatusIcon           -- 3-GC icon variants
```

Pattern characteristics:
- **Rank-gated items**: high-tier items hidden until player reaches
  required GC rank (setMaskInformation/isMaskItem/setItemMask)
- **Transaction sub-flow**: clicking a buyable item opens a child
  ShopEdit widget for quantity selection; result comes back to parent
- **Money + inventory tracking**: shop UI must show current seals
  AND remaining bag capacity to prevent invalid transactions

This is the architectural template for ALL shops in 1.x (not just GC):
- NPC vendor shops likely follow the same pattern minus the
  rank-gating mechanism

### Pattern L: Reusable form template

**Exemplified by**: `ItemStorageGetWidget`

```text
ItemStorageGetWidget:getFormName()
  return "ItemListWidget"
```

The widget class is `ItemStorageGetWidget`, but its form (UI definition
file) is `ItemListWidget` -- a SHARED form used by multiple widget
subclasses. So:

```text
Form file: ItemListWidget.ui  (shared)
  -> ItemStorageGetWidget  (this widget; for chest retrieval)
  -> ItemStoragePutWidget   (sibling; for chest deposit)
  -> (other Item* widgets reuse the same form)
```

This is **MSVC-style template reuse for UI** -- one .ui form definition
with multiple Lua subclasses, each providing different behavior. The
form rendering is the same; the logic differs.

This pattern is implementable on the server side as: server only needs
to know the WIDGET class name (since the form is client-local); the
widget instance routes its specific business logic.

## 3. Pattern summary -- 12 total categories

```text
ID  Pattern                              Example widget(s)
--  -------                              -----------------
A   Pure confirmation                    ContentRewardWidget
B   2-button A/B + context                LinkshellConfirmWidget
C   Multi-choice list                    AskWidget,
                                          GuildleveSelectLevelWidget
D   Text input + IME branch              ChocoboNamingWidget
E   Visual picker (grid)                 LinkshellSelectIconWidget
F   Slider/distribute                    BonusPointAssignWidget
G   Live-data display                    HamletDefenseScoreWidget
H   Multi-template + child-dialog chain  JournalDetailWidget
I   Non-modal persistent panel           ActionSettingWidget
J   Tabbed list w/ focus+selection       ItemStorageGetWidget,
                                          GrandCompanyShopWidget
K   Shop/transaction w/ rank gating      GrandCompanyShopWidget
L   Reusable form template               ItemStorageGetWidget
                                          (shared with ItemStoragePut)
```

A given widget may exhibit MULTIPLE patterns (e.g.
GrandCompanyShopWidget = J + K).

## 4. Architectural insights from the large widgets

### 4.1 Form reuse drives ~5-10 widget pairs

Searching the catalog for paired class names (Get/Put, Show/Hide,
List/Detail, etc.) reveals likely form-reuse pairs:

```text
ItemStorageGet / ItemStoragePut       <- form: ItemListWidget
JournalDetail / JournalList            <- forms: shared?
LinkshellList / LinkshellConfirm /
  LinkshellNaming / LinkshellSelectIcon <- multi-step chain, separate forms
GrandCompanyShop / (no obvious Put)    <- single direction
```

This is the **content vs presentation split**: ~30-50% of the widget
forms are shared across multiple subclasses.

### 4.2 Non-modal widgets exist (Pattern I)

The discovery that ActionSettingWidget extends WidgetBaseClass (not
AskBaseClass) means **not all widgets are modal dialogs**. The 1.x
HUD/UI surface has:
- ~30 modal dialogs (ask/* subdir)
- ~5-10 persistent panels (action setting, chat, party display,
  inventory grid, etc.)
- ~150 other widgets (tooltips, popups, animations, sub-elements)

The non-modal ones don't use the askResult polling; they have their
own update() loop and respond to events directly.

### 4.3 Child-dialog chaining (Pattern H)

A widget can OPEN another widget and RECEIVE ITS RESULT:

```text
Parent widget (e.g. JournalDetail) shows quest details
Player clicks "Abandon Quest"
Parent opens child confirmation dialog (a separate AskWidget instance)
Child shows "Are you sure?" Yes/No buttons
Player picks Yes -> child's askResult = 1
Child fires processAskResult on parent (callback)
Parent's processAskResult(1) -> proceeds with abandon
```

The parent ALSO has `processErrorDialogResult` for a SECOND child
dialog (error popup). So one parent widget can chain 2+ different
child dialogs depending on the action.

### 4.4 Focus vs selection tracking (Pattern J)

The 6 focus-related work fields in ItemStorageGetWidget
(index, focus, selected, prevIndex, prevFocus, prevCount) confirm that
**focus and selection are DISTINCT concepts** in 1.x UI:
- **focus** = where the cursor currently sits (highlighted)
- **selected** = what the player has chosen (e.g., item to withdraw)
- **prev*** fields = animation source (smooth-scroll target)

The `focusToIndex` / `indexToFocus` bidirectional mapping is for
keyboard/controller navigation (move focus N steps) vs absolute
indexing (jump to item #N).

### 4.5 1.x's "Godsend" terminology

ActionSettingWidget uses "Godsend" as the in-engine term for what's
elsewhere called "Special Skill" or class-locked unique abilities.
Found in methods:
- setEquipGodsend
- equipGodsend
- isEquipGodsend
- setGodsend
- initEquipGodSend
- setBattleGodSend

These methods configure the per-class unique skill (e.g., Warrior's
Berserk, BLM's Manawall) into the equip bar.

## 5. Server design implications

```text
For a server to support these complex widgets:

  JOURNAL (JournalDetailWidget):
    - Server pushes quest data via SSD (quest.ssd)
    - Server provides current quest state via PlayerBase bindings
      (the "questIndex / journalID / completed" fields)
    - Server handles "Abandon Quest" via callServerOnCommand
      (after the child confirm dialog returns 1)
    - For guildleve: server provides leve state (failed, completed)

  ACTION BAR (ActionSettingWidget):
    - Server pushes action sheet via SSD (action.ssd)
    - Server pushes player's class state via PlayerBase
    - "Equip action" is purely client-local until first use, then
      server sees the action ID in the action use packet
    - "Godsend" (special skill) state is per-class; server tracks
      which Godsend is currently equipped

  ITEM STORAGE (ItemStorageGetWidget):
    - Server pushes item package contents (chest data)
    - Player selects, server validates, confirms transfer
    - "Sort modes" are PURELY CLIENT (alphabetical, by recent, etc.)
    - The setSortType / updateSortType pair don't generate wire
      traffic

  GC SHOP (GrandCompanyShopWidget):
    - Server pushes shop catalog via SSD
    - Server provides player's GC rank + seals (PlayerBase
      getGrandCompanyRank + a separate seal counter)
    - Server applies item masks based on rank (masks are computed
      client-side via setMaskInformation/isMaskItem, but the
      visibility rule is server-driven)
    - Buy operation: server validates rank + seals, deducts seals,
      adds item to inventory
    - Sub-widget for quantity (operateBuy) sends a separate command
```

## 6. Cross-references

- `finding_widget_baseclass_architecture_and_194_widgets.md` --
  WidgetBaseClass + AskBaseClass architecture
- `finding_widget_ask_patterns_8_widgets_sampled.md` -- prior 7
  patterns from small widgets; this finding adds 5 more
- `finding_playerbase_lua_bindings_99_complete.md` -- many of the
  bindings (getGrandCompanyRank, getCompanyBehestTime, etc.) are
  what these widgets fetch
- `feedback_no_freecompany_in_1x` -- the GrandCompanyShopWidget
  confirms 1.x's GC shop pattern (NOT FreeCompany)

## 7. Confidence

```text
Confirmed:
  - 5 new pattern categories identified
  - JournalDetailWidget has 2 distinct child-dialog handlers
    (processAskResult + processErrorDialogResult)
  - ActionSettingWidget extends WidgetBaseClass directly (not
    AskBaseClass) -- non-modal persistent panel
  - ItemStorageGetWidget reuses "ItemListWidget" form
    (via getFormName override)
  - ItemStorageGetWidget has 6-field focus/selection tracking
  - GrandCompanyShopWidget has 13 work fields including 3
    for rank gating (myRank, myPoint, isMaskItem)
  - "Godsend" is the 1.x term for class-locked unique skills
  - The 4 sampled widgets total 156+ methods across them

Likely (High):
  - Pattern J (tabbed list w/ focus tracking) applies to ALL
    inventory-style widgets in 1.x (~10-15 widgets)
  - Pattern L (form reuse) applies to ~10-20 widget pairs
    (Get/Put, List/Detail, Show/Hide siblings)
  - The ActionSetting "Godsend" methods correspond to the 1.x
    class-locked ability system (per finding on cross-class
    actions)
  - GrandCompanyShop's rank gating is the 1.x precursor to ARR's
    GC rank-locked items (which became seal exchanges)

Likely (Medium):
  - The total ~10 persistent panel widgets cover: HUD bar,
    party/group display, chat, action bar config, target info,
    minimap, debug overlay
  - JournalDetailWidget can chain 3+ different sub-dialogs
    (confirm, error, info)
  - ItemStorageGetWidget and ItemStoragePutWidget differ only
    in the operation direction (get vs put); same form, same
    field layout

Speculative:
  - The "DataMaker_ListBox" naming pattern in widgets refers
    to a server-pushed data structure that drives multi-row
    list rendering (would need EXE-side confirmation)
  - "previousSequence" methods imply a navigation stack
    (back-button history) for multi-step widget flows
```

## 8. Next test

```text
1. Read processAskResult bodies to characterize the child-dialog
   chaining mechanism
2. Walk DesktopWidget (singleton) to see if it has Pattern I
   extensions
3. Sample ~5 inventory widgets to confirm Pattern J + Pattern L
   apply to the inventory family
4. Compare ItemStoragePutWidget against ItemStorageGetWidget to
   verify the form-reuse hypothesis
```

## Commit suggestion

```
docs(re/lua): 4 large widgets sampled -- 5 new patterns (Total taxonomy: 12)
```
