# Finding: Negotiation / Bazaar / Shop / Trade Widget Family

Maps the entire negotiation / bazaar / shop subsystem at the Lua
architectural level. The negotiation entry point is the slim
`NegotiationJudge` (198 lines) which is a thin wrapper over
`desktopWidget` coroutine-yielding methods. The actual UI lives
in a family of large widget classes (10+) totalling ~60,000 lines
of Lua.

## File map (cipher decoded)

The 1.x cipher is the involution `a↔9, b↔8, c↔7, d↔6, e↔5, f↔4,
g↔3, h↔2, i↔1, j↔0` for digits and `k↔z, l↔y, m↔x, n↔w, o↔v, p↔u,
q↔t, r↔s, s↔r` for letters. Applied to the directory tree:

```text
0p635           = judge
n1635q          = widget
7vxx9w6         = command
39x5            = game
9rz             = ask        (a sub-folder of widget)

CIPHERED PATH                                          DECODED FILE          LINES
-----------------------------------------------------  --------------------  -----
0p635/w53vq19q1vw/w53vq19q1vw0p635.lua                 negotiationjudge       198
7vxx9w6/39x5/w53vq19q1vw7vxx9w6.lua                    NegotiationCommand      47
n1635q/89k99sy1rqn1635q.lua                            BazaarListWidget      5705
n1635q/89k99s561qn1635q.lua                            BazaarEditWidget      3999
n1635q/qs965561qn1635q.lua                             TradeEditWidget       4565
n1635q/1q5xy1rqn1635q.lua                              ItemListWidget        6813
n1635q/s5q91w5s1q5xy1rqn1635q.lua                      RetainerItemListWidget 9508
n1635q/9rz/r2vur5yyn1635q.lua                          ShopSellWidget        3051
n1635q/9rz/x9q5s19s5xvo5n1635q.lua                     MateriaRemoveWidget   3517
n1635q/9rz/tp5rq65y1o5sln1635q.lua                     QuestDeliveryWidget   4121
n1635q/9rz/s5q91w5s1q5xy1rqn1635q.lua                  RetainerItemListWidget
                                                       (Ask variant)         6661
n1635q/5tp1un1635q.lua                                 EquipWidget          (multi)
n1635q/7s94q561qn1635q.lua                             CraftEditWidget      (multi)
```

Total negotiation/bazaar widget code: ~60,000 lines of Lua.

## NegotiationJudge (198 lines, 7 methods)

The minimal abstraction layer. Each method is a 1-2 line wrapper
calling `desktopWidget`:

```text
openListWidget(...)              -> desktopWidget.openEventModeWidgetYield("Ask/NegotiationWidget", ...)
openAskWidget(...)
openNegotiationWidget(...)       -> openEventModeWidgetYield (main entry)
inputNegotiationWidget(...)      -> selectEventModeWidgetYield  (returns user input)
updateNegotiationWidget(...)     -> updateEventModeWidget       (server-driven UI update)
closeNegotiationWidget(...)      -> closeEventModeWidget
negotiationEmote(...)            -> _runCharaScheduler          (NPC emote during negotiation)
```

The widget name is **"Ask/NegotiationWidget"** -- a coroutine-yielding
"event mode" widget. This is the central design pattern for 1.x
modal UI: the C++ side calls a yielding Lua function; the function
suspends the coroutine until the widget closes; resumes with the
user's choice as the return value.

So `NegotiationJudge` is NOT the negotiation engine. It is just
the FACADE that the C++ side calls when it wants to open / update /
close the negotiation UI. The actual negotiation flow logic lives
in the EXE (which decides when to open/close the widget) and the
widget classes (which render the UI and process button input).

The Judge's methods are CALLED ONLY FROM NATIVE CODE -- no other
Lua script references `openNegotiationWidget` or its siblings.

## NegotiationCommand (47 lines, 5 methods)

The COMMAND CLASS for triggering a negotiation. Inherits from
`GameCommandBaseClass`. Just provides configuration:

```text
canAimForRelation()         -> (false, false, true)
canFireForRelation()        -> (false, false, true)
getCommandRangeCode()       -> 2  (probably close-range)
getCommandTargettingMode()  -> 1  (single target)
isUseActionGauge()          -> false
```

So negotiation is a single-target close-range command without an
action gauge. The actual mechanic happens entirely through the
widget after the command fires.

## Bazaar widget family (~60,000 lines total)

Three widget categories serve as the bazaar/shop UI:

### 1. Bazaar viewing -- BazaarListWidget (5705 lines)

The widget that displays an NPC's bazaar (the items they have for
sale). Inherits from `WidgetBaseClass`; uses `ItemListWidget` XML
form for layout.

Key methods (47+ identified):

```text
SETUP & CONFIG:
  getFormName               returns "ItemListWidget" (shared form)
  init                       full init
  setInitialData             populate from server-pushed data
  processBeforeShow          pre-render hook

DATA MANAGEMENT:
  makeBazaarItemList         build the list from the package data
  makeListFromPackage        build/refresh list from a specific package
  getItemBazaarData          extract per-item bazaar info
  canItemSell                check if an item can be sold
  setItemToBackup            snapshot for diff detection
  compareItemToBackup        detect changes after server push
  copyItem / isSameItem      item comparison utilities

UI:
  updateWindowDisplay
  updateListFocus / setWindowFocus / setGridVisibility
  displayBagcapacityAndMoney
  initListBox / resetListBox
  setItemToXmlLight / displayBazaarGrid / displayHelp
  setBazaarLabelVisibility / updateBazaarLabel

COMMAND DISPATCH (button presses):
  processUICommandOperate    operate / confirm button
  processUICommandCancel
  processUICommandClose
  processUICommandSelection
  processUICommandDefault

REWARDS / DEPENDENCIES:
  checkRewardDependency
  isRewardItemActor          for item-for-item trades
```

### 2. Bazaar editing -- BazaarEditWidget (3999 lines)

Widget for setting up YOUR OWN bazaar (player as seller). When a
player wants to sell items to other players, they edit their
bazaar entries through this widget.

### 3. Shop ask widgets (under widget/ask/)

Three modal ASK widgets for NPC interactions:

```text
ShopSellWidget        sell items to an NPC (3051 lines)
MateriaRemoveWidget   materia extraction from gear (3517 lines)
QuestDeliveryWidget   submit quest item to NPC (4121 lines)
```

Plus the generic `TradeEditWidget` (4565 lines) for player-to-player
trading.

## Per-item bazaar field schema

From `initTargetItem` in BazaarListWidget (line 2738) and
`makeListFromPackage`, the per-item list properties are:

```text
itemIndex         int32     index in the source package
catalog           int32     item catalog id (the master id)
quality           int32     quality level (HQ flag etc.)
rare              int32     is-rare flag
ex                int32     is-exclusive flag (untradeable)
stackCount        int32     current stack count
stackMax          int32     max stack size
stackable         int32     can-stack flag
bazaarkind        int32     bazaar dispatch kind (1 = retail / 2 =
                            buy / 3 = repair / 4 = materia / ...)
rewardprice       int32     PRICE IN GIL (if sold for gil)
rewardpackage     int32     reward package id (if traded for item)
rewarditem        int32     reward item id (if traded for item)
```

**BARTER mechanic confirmed**: each bazaar item can be priced in
EITHER `rewardprice` (gil) OR `(rewardpackage, rewarditem)` (item
for item). This is the 1.x barter system that ARR removed.

## Multi-chunk update protocol (state machine)

`ShopSellWidget.operateSell(packageId, itemIndex)` reveals the
client-server protocol for a sell action:

```text
1. Client opens ShopSellWidget; player selects items + confirms.
2. Client sends "sell N items" command (probably outbound 0x12d
   with discriminator = sell).
3. Server processes the sell + pushes multiple async updates:
   - inventory minus the sold items
   - gil plus the price
   - possibly bonus items / reward items (for quest deliveries
     that involve gil + bonus)
4. Each server push lands on the client as a call into operateSell()
   with a packageId.
5. The widget tracks pending updates via work.updatecount:
   - On each call: increment expected count
   - When chunk N processes: decrement updatecount
   - When updatecount == 0: refresh display + optionally close widget
6. The flag work.closeok is set when the chosen item is the same as
   the affected item AND no edit widget is open -- triggers auto-
   close on completion.
```

So the wire protocol has a MULTI-CHUNK pattern for a single sell
action. The widget waits for all chunks before completing the UI
state transition. This is one of the few places in 1.x where the
client EXPLICITLY waits for multiple server pushes.

## 3 bazaar dealer modes (confirmed)

From `charabaseclass_event.lua` (per
`finding_chara_cliprog_and_event_extensions.md`):

```text
isRetailDealer         eventTemp.bazaarRetail bit     -- retail (sell items)
isRepairDealer         eventTemp.bazaarRepair bit     -- repair service
isMateriaAttachDealer  eventTemp.bazaarMateria bit    -- materia attach service
```

These are SET BY the server on NPC actors when the NPC is
configured as a bazaar dealer. Each mode opens a different widget:

```text
retail   -> BazaarListWidget       (buy from NPC)
sell-to  -> ShopSellWidget         (sell TO NPC)
repair   -> ? (RepairWidget? not yet inventoried)
materia  -> MateriaRemoveWidget (extract) +
            MateriaAttachWidget (attach -- not yet inventoried)
```

## Coroutine yield model (Modal UI)

The "Yield" suffix on `openEventModeWidgetYield` /
`selectEventModeWidgetYield` is significant: these are
**coroutine-yielding** calls. The native side calls into Lua;
Lua opens the widget; Lua YIELDS the coroutine; control returns to
the native event loop; native loop processes input; eventually
native calls back to RESUME the Lua coroutine with the user's
selection as the return value.

This is **modal UI implemented as Lua coroutines** -- a clean
pattern that makes the widget interaction look synchronous in the
calling code:

```lua
function NpcBaseClass:_onTalkEvent(actor, args)
    -- pseudo-code; actual flow goes through C++
    actor:openNegotiationWidget(...)  -- YIELDS here
    local choice = actor:inputNegotiationWidget(...)  -- RESUMES with input
    if choice == 1 then
        actor:doBuy(...)  -- handle the user's selection
    end
    actor:closeNegotiationWidget()
end
```

This pattern is why almost every widget Lua file is 3000-10000 lines:
they own the entire modal interaction lifecycle.

## Server-side picture

```text
TO RUN BAZAAR/SHOP/TRADE INTERACTIONS, THE SERVER NEEDS:

1. NPC marking: tag each NPC actor with one or more bazaar dealer
   flags (retail / repair / materia).

2. Bazaar inventory: per-NPC list of items with:
     - catalog id
     - quality / rare / ex / stackable flags
     - stack count
     - reward (gil amount OR (package_id, item_id))
     - bazaarkind (1 = retail, 2 = buy, 3 = repair, 4 = materia...)

3. Sell flow:
     - Receive sell command from client
     - Validate item is in player inventory
     - Deduct item, credit gil/reward
     - Push multi-chunk update to client (1 chunk per affected
       package, ordered for atomicity)

4. Repair / Materia flows: similar shape with different
   bazaarkind values and different effect sequences.

5. Player-to-player Trade:
     - 4-phase protocol: open trade window, offer items, lock-in,
       confirm. Each phase has its own state and packet shape.
     - Both clients must reach lock-in before commit. Either side
       can cancel.
     - Server arbitrates and pushes results to both players.

6. Bazaar (player as vendor):
     - Player puts items on their own bazaar (BazaarEditWidget).
     - Other players walk near and use BazaarListWidget to browse.
     - Server orchestrates the bazaar listings (probably as actor
       state on the seller's actor with periodic broadcast).
```

## Confidence

```text
Confirmed:
  - NegotiationJudge has exactly 7 methods, all thin wrappers
    around desktopWidget event-mode methods.
  - NegotiationCommand has 5 config methods; no behavior.
  - Bazaar item schema: 12 properties incl. catalog, quality,
    rare, ex, stack info, bazaarkind, rewardprice/package/item.
  - 1.x supports BARTER pricing (rewardpackage + rewarditem)
    distinct from gil pricing (rewardprice).
  - The multi-chunk update protocol (updatecount-tracked) is the
    real wire shape for shop transactions.
  - Modal UI is implemented as coroutine-yielding "EventModeWidget"
    methods.

Likely (High):
  - The 3 dealer flags (retail/repair/materia) are mutually
    INDEPENDENT -- an NPC can have multiple flags set (e.g. a
    blacksmith might be both retail + repair).
  - `bazaarkind` is the discriminator for which widget the bazaar
    item belongs to (1 = retail, 2 = buy-back from player, ...).
  - The 60K+ lines of widget code drive ALL of FFXIV 1.x's UI
    bazaar interactions, including the unique "barter pricing"
    that ARR dropped.

Likely (Medium):
  - There are likely 2-3 more "Ask" widgets I haven't enumerated
    yet (e.g. MateriaAttachWidget, RepairWidget, BuybackWidget).
  - The `closeok` flag in operateSell implies that selling can
    leave the widget OPEN when more items remain to sell, allowing
    chained sells without re-opening the menu.

Speculative:
  - The 1.x barter system fed into the 1.0 economy: NPCs offered
    items-for-items deals (e.g. raw materials for crafted goods),
    creating a more complex economy than ARR's pure gil pricing.
  - RetainerItemListWidget at 9508 lines is the largest single
    bazaar widget because retainers handle both inventory + market
    listings + bazaar visits (3 separate use cases in one widget).
```

## Next test

- Read the body of `processUICommandOperate` in BazaarListWidget
  to identify what outbound packet/command it sends when the
  player clicks "Buy".
- Enumerate the remaining widget/ask/ files via Glob to find
  MateriaAttachWidget, RepairWidget, BuybackWidget.
- Cross-reference the `bazaarkind` integer values with FFXIVTool
  catalog data (shopBase.csv, shopItem.csv, marketItem.csv) to
  pin which kind value maps to which dealer mode.

## Commit suggestion

```
docs(re/lua): map Negotiation/Bazaar widget family (10 widgets, ~60K lines)
```
