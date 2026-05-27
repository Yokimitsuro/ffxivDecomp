# Finding: 5 Inventory Widgets -- Pattern L Verified, Pattern M Added (Total: 13)

Samples 5 widgets from the inventory family to verify Patterns J + L
from `finding_widget_large_4_complex_patterns.md`. Adds **1 new
pattern (M)** + key 1.x feature discoveries (Materia, Bazaar, Sub-widget
trees).

## 1. Sampled widgets (5 of ~9 inventory widgets)

```text
Widget                        Size       Lines  Base class           getFormName()
------                        ----       -----  ----------           -----------
ItemListWidget               (~150 KB)*  6991   WidgetBaseClass     (own form)
ItemStoragePutWidget          (~75 KB)*  2838   AskBaseClass         "ItemListWidget"
ItemDetailWidget              (~45 KB)*  1519   WidgetBaseClass     (own form)
ItemSubWidget                 (~15 KB)*   429   WidgetBaseClass     (own form)
ItemSelectWidget              (~110 KB)*  3535   WidgetBaseClass     "SubItemListWidget"

*Approximate byte sizes scaled by line count; the catalog reports
ItemStoragePut at 64331 B and ItemSelect at unknown.
```

## 2. Pattern L (form reuse) CONFIRMED

Verified across all 5 sampled inventory widgets:

```text
Widget                    Form file (.ui)        Notes
------                    ----------              -----
ItemListWidget            ItemListWidget         OWN form (the shared parent)
ItemStoragePutWidget      ItemListWidget         REUSES via getFormName
ItemStorageGetWidget      ItemListWidget         REUSES via getFormName (prior finding)
ItemDetailWidget          ItemDetailWidget       OWN form
ItemSubWidget             ItemSubWidget          OWN form
ItemSelectWidget          SubItemListWidget      REUSES different shared form
```

**Form-reuse hierarchy revealed**:
- `ItemListWidget.ui` is the **primary inventory grid form**
  - Used by: ItemListWidget (owner), ItemStorageGetWidget, ItemStoragePutWidget
- `SubItemListWidget.ui` is the **secondary inventory list form**
  - Used by: ItemSelectWidget (and likely other smaller item pickers)
- `ItemDetailWidget.ui` is **the item info tooltip/popup form**
- `ItemSubWidget.ui` is **the item context menu form**

So there are at minimum **4 shared inventory form files** with multiple
Lua widget subclasses each. This confirms the Pattern L hypothesis at
scale.

## 3. Pattern I extended -- most inventory widgets are non-modal

Of the 5 sampled inventory widgets, **4 extend WidgetBaseClass directly**
(non-modal, Pattern I) and only **1 extends AskBaseClass** (modal):

```text
Widget                    Base class           Modal?
------                    ----------           ------
ItemListWidget            WidgetBaseClass     NO (persistent panel)
ItemStoragePutWidget      AskBaseClass         YES (modal)
ItemDetailWidget          WidgetBaseClass     NO (tooltip-style)
ItemSubWidget             WidgetBaseClass     NO (sub-widget; child)
ItemSelectWidget          WidgetBaseClass     NO (panel)
```

Only the storage Get/Put widgets are TRULY MODAL ask-style; the rest
are persistent UI panels (the inventory window itself, item detail
popup, sub-context-menu).

This is consistent with the actual 1.x UX:
- Inventory window: always-open persistent panel
- Item right-click context menu: sub-widget child
- Storage chest: modal dialog (blocks other input)
- Item detail tooltip: persistent overlay (hover-driven)

## 4. NEW Pattern M: Context-menu sub-widget delegating to parent

**Exemplified by**: `ItemSubWidget` (429 lines)

```text
Architecture:
  Parent widget (e.g. ItemListWidget) shows the inventory
  User right-clicks an item -> parent opens ItemSubWidget as child
  ItemSubWidget shows a context menu (Bazaar / Repair / Materia / etc.)
  User clicks a context-menu button
  ItemSubWidget delegates: parent:operateXxx()
  If parent returns true -> parent:closeSubWidget() (self-destruct)

  Button "Sort" is special: opens a sub-sub-widget (SortChangeWidget)
  via desktopWidget:openChildWidget(...) -- so 3-level widget trees
  are possible.
```

The full button -> operation dispatch table from ItemSubWidget:

```text
Button name              Calls on parent          Notes
-----                    ---                       -----
Button_BazaarAbort       operateBazaarAbort        Cancel a bazaar listing
Button_BazaarSell        operateBazaarSell         List for sale on bazaar
Button_BazaarBuy         operateBazaarBuy          Purchase from bazaar
Button_BazaarRepair      operateBazaarRepair       Repair via bazaar service
Button_Repair            operateRepair              Self-repair (with crystals)
Button_Materialize       operateMaterialize         Convert item -> Materia
Button_MateriaAttach     operateMateriaAttach(12)  Attach Materia (slot 12)
Button_MateriaOrder      operateMateriaAttach(13)  Order Materia attach (slot 13)
Button_MateriaAbort      operateMateriaAbort        Cancel Materia operation
Button_MateriaView       operateMateriaView         View Materia info
Button_DropItemGetAll    operateGetDrop             Loot all drops
Button_DropItemGiveAll   operateShareDrop           Give all drops to party
Button_Trash             operateTrash               Trash item
Button_Sort              (opens SortChangeWidget)  Sort sub-dialog
Button_Cancel            closeSubWidget             Close menu
```

Pattern characteristics:
- All button handlers do `parent:operateXxx()` and check return
- If true: `parent:closeSubWidget()` (close self after operation)
- If false: keep menu open (operation failed validation)
- Button_Sort opens a SECOND child widget (sort chooser)
- This creates a **3-level widget tree** in 1.x (parent -> sub -> sub-sub)

## 5. 1.x feature discoveries from the button names

### 5.1 Materia exists in 1.x

The 5 Materia* buttons confirm 1.x had a **Materia system**:
- Button_Materialize: convert an item INTO Materia
  ("Spirit Bond" conversion in ARR terminology)
- Button_MateriaAttach (slot 12)
- Button_MateriaOrder (slot 13)
- Button_MateriaAbort
- Button_MateriaView

The two slots (12 and 13) suggest the 1.x materia attach had **two
distinct slots** (regular vs special / Order?). This is different from
the ARR materia system but conceptually related -- 1.x had the
materia mechanic before ARR rebuilt it.

### 5.2 Bazaar (1.x's auction-house equivalent)

4 Bazaar* buttons confirm 1.x's **player-to-player Bazaar system**:
- Button_BazaarSell: list for sale
- Button_BazaarBuy: purchase from bazaar
- Button_BazaarRepair: hire someone for repair via bazaar
- Button_BazaarAbort: cancel a bazaar listing

Bazaar was indeed in 1.x; it was replaced/integrated with the
Market Board in ARR. The "BazaarRepair" is interesting -- it was
a way to pay another player to repair your gear.

### 5.3 Repair system (with materials)

`Button_Repair` exists as a SELF-repair option (without going through
the bazaar). This matches the ARR + 1.x repair system where players
with a crafting class can repair their own gear using crystals.

### 5.4 Drop loot management

`Button_DropItemGetAll` / `Button_DropItemGiveAll` are LOOT management:
- GetAll: pick up all drops from a defeated NPC
- GiveAll: pass all drops to party

This is the **Bonus/Drop Reward** system from 1.x (later replaced by
the lot/need/greed system in ARR).

## 6. Widget tree depth observed

Maximum widget tree depth from samples: **3 levels**

```text
Level 0: ItemListWidget (inventory window, persistent)
Level 1: ItemSubWidget (context menu, opened on right-click)
Level 2: SortChangeWidget (opened from "Sort" button in context menu)
```

For Storage Get/Put, the depth is:
```text
Level 0: (some opener widget, e.g. ItemListWidget)
Level 1: ItemStorageGetWidget (modal, opened to retrieve)
```

`desktopWidget:openChildWidget(widgetName, parentWidget, isModal, ...)`
is the API for opening child widgets, with `isModal` controlling
whether the child blocks input to its parent.

## 7. Updated pattern taxonomy: 13 categories

```text
ID  Pattern                              Newly added in
--  -------                              --------------
A   Pure confirmation                    finding_widget_ask_patterns
B   2-button A/B + context                finding_widget_ask_patterns
C   Multi-choice list                    finding_widget_ask_patterns
D   Text input + IME branch              finding_widget_ask_patterns
E   Visual picker (grid)                 finding_widget_ask_patterns
F   Slider/distribute                    finding_widget_ask_patterns
G   Live-data display                    finding_widget_ask_patterns
H   Multi-template + child-dialog chain  finding_widget_large_4
I   Non-modal persistent panel           finding_widget_large_4
J   Tabbed list w/ focus+selection       finding_widget_large_4
K   Shop/transaction w/ rank gating      finding_widget_large_4
L   Reusable form template               finding_widget_large_4
M   Context-menu sub-widget delegating   THIS FINDING
```

Pattern M (sub-widget delegation) is distinct from Pattern H
(child-dialog chain) in that:
- Pattern H: parent OPENS child dialog and RECEIVES RESULT via callback
- Pattern M: child is opened as a sub-MENU and DELEGATES button presses
  back to parent's methods directly (no return value via askResult)

## 8. Architectural implications

### 8.1 Form-reuse scales

With 3 form files (ItemListWidget, SubItemListWidget,
ItemDetailWidget) shared across ~9 inventory widgets, the actual UI
asset count is much smaller than the widget class count. This is
relevant for server design: the server only needs to know WIDGET
CLASS NAMES (not form names) when triggering UI.

### 8.2 Widget tree architecture

The 3-level widget tree (inventory -> context menu -> sort dialog)
proves that 1.x supports **arbitrary widget nesting**. The
`desktopWidget:openChildWidget` API takes a `parentWidget` reference
so the engine can manage the tree.

### 8.3 Operation delegation pattern

The Pattern M operation table (Button_Xxx -> parent:operateXxx) is
a clean **command pattern** -- the sub-widget just routes UI events
to parent business logic. The parent owns the operation methods
(operateBazaarSell, operateMaterialize, etc.).

This means a server can drive context-menu actions by knowing the
PARENT widget's operation surface, not the sub-widget's.

## 9. Server design implications

```text
For a server to drive inventory interactions:

  CONTEXT-MENU OPERATIONS (via ItemSubWidget delegation):
    Bazaar operations (Sell/Buy/Repair/Abort): server-validated
    Materia operations: server controls outcomes
    Repair (self): server validates crystal usage
    Trash: simple item removal
    DropItemGet/Give: server handles loot ownership

  FORM-REUSE NOTE:
    Server only needs widget class names; form files are client-local
    Opening "ItemStorageGetWidget" auto-uses "ItemListWidget" form

  WIDGET TREE NOTE:
    Server can open child widgets via UICommandRequest
    Sub-widgets like SortChangeWidget are client-local UX details;
    server doesn't need to know about them

  PERSISTENT PANELS (Pattern I):
    ItemListWidget, ItemDetailWidget, ItemSelectWidget: always
    available; no server "open" command needed; data flows via
    PlayerBase bindings + SpreadSheet async loads
```

## 10. Cross-references

- `finding_widget_baseclass_architecture_and_194_widgets.md`
- `finding_widget_ask_patterns_8_widgets_sampled.md` -- Patterns A-G
- `finding_widget_large_4_complex_patterns.md` -- Patterns H-L
- `finding_tutorial_debug_gamedata_subsystems.md` -- the SpreadSheet
  layer that loads item data for these widgets
- `finding_invokeLua_roster_closed_80_complete.md` -- the
  invokeLua callbacks that fire on SSD loads + widget events

## 11. Confidence

```text
Confirmed:
  - Pattern L (form reuse) verified across 3 inventory widget pairs
    (ItemStorageGet/Put share ItemListWidget form; ItemSelect uses
    SubItemListWidget form)
  - Pattern I (non-modal) is the DEFAULT for inventory widgets;
    only Storage Get/Put are modal
  - Pattern M (context-menu sub-widget delegation) is a distinct
    new pattern with operateXxx callback API
  - 3-level widget trees exist (parent -> sub -> sub-sub)
  - 1.x has Bazaar system with 4 buttons (Sell/Buy/Repair/Abort)
  - 1.x has Materia system with 5 buttons (Materialize/Attach/
    Order/Abort/View)
  - 1.x has self-Repair button (separate from Bazaar repair)
  - 1.x has drop loot get/give-all buttons
  - desktopWidget:openChildWidget(name, parent, isModal, ...) is
    the child-widget API

Likely (High):
  - The 4 inventory form files (ItemListWidget, SubItemListWidget,
    ItemDetailWidget, ItemSubWidget) cover ALL the ~9 inventory
    widgets in the catalog
  - The "operateXxx" methods on the parent (operateBazaarSell, etc.)
    each translate to a specific outbound server command
  - Materia slot indices (12 and 13) correspond to specific
    materia attachment slots (regular + "Order" variant)
  - Bazaar in 1.x was player-to-player only (no Market Board);
    Bazaar was the precursor to ARR's Market Board

Likely (Medium):
  - The SortChangeWidget is a small ask dialog (~few hundred
    bytes) for selecting sort order
  - The operateBazaarRepair flow opens a chain: ItemSub ->
    BazaarRepairAsk -> server submission
  - The widget tree depth in 1.x is capped at 3-4 levels for
    UX reasons; deeper nesting wasn't designed for

Speculative:
  - The MateriaOrder (slot 13) may have been a SPECIAL TYPE of
    materia binding ("Master Materia") that 1.x experimented
    with but ARR removed
  - The "DropItemGiveAll" requires the giver and receiver to be
    in the same party (server validates membership before transfer)
```

## 12. Next test

```text
1. Walk the parent's operateXxx methods (in ItemListWidget) to map
   each context-menu operation to the actual outbound packet
2. Read SortChangeWidget to confirm Pattern M is consistently used
   for short sub-dialogs
3. Sample 2-3 chat widgets to find Pattern N (text-stream display)
4. Walk DesktopWidget subclass to check if it's the topmost
   container for ALL persistent panels
```

## Commit suggestion

```
docs(re/lua): 5 inventory widgets -- Pattern L verified + Pattern M added (Total: 13)
```
