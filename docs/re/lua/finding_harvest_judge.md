# Finding: `HarvestJudge` — Three Gathering Types + Pattern Confirmation

Read of the deciphered `judge/harvest/harvestjudge.lua` (10.3 KB,
11 methods). Confirms and extends the orchestrator-not-computer
pattern from `finding_judges_battle_stubs_craft_orchestrator.md`.

Source read:

```text
judge/harvest/harvestjudge.lua    0p635/29so5rq/29so5rq0p635.lua   (10.3 KB)
```

## Headline result

`HarvestJudge` is a **UI orchestrator just like `CraftJudge`**, with
three sibling flows (one per gathering type) and a shared
`InputWidget` family. The judge mediates between server-pushed
"present this prompt" commands and the player's input choices, then
returns the choice. There is **no outcome math in the judge**; the
server decides what gets gathered.

**Plus, a documentation correction:** the previous mapping of command
ids 22002..22009 as "craft" was wrong. The right names are gathering
+ other player actions; the actual craft commands live elsewhere. See
"Corrected command ranges" below.

## The three gathering types (corrected command ids)

```text
cmdId  type      InputWidget                 first-prompt text id
22002  Mining    Ask/MiningInputWidget        22701
22003  Felling   Ask/FellingInputWidget       22704
22004  Fishing   Ask/FishingInputWidget       22711
```

Each branch of `HarvestJudge:openInputWidget` and
`HarvestJudge:orderInputWidget` switches on the command id to bring up
the matching `Ask/*InputWidget`. Mining and Felling are symmetric
(land + felling tree); Fishing has an extra parameter A8 (the
pole/bait, passed only on this branch).

## Method inventory

```text
lifecycle
  _onInit / _onFinalize    -- inherited boilerplate
  initText                 -- placeholder
  loadTextData             -- preload text ids

targeting
  targetCancel             -- cancel the harvest target (e.g. interrupted)
  turnToTarget             -- rotate the player to face the gather node

UI flow
  openInputWidget          -- "show the gathering UI now"
  orderInputWidget         -- "ask the player to pick from a set of choices"
                              and return the selection
  askInputWidget           -- variant: ask with a contextual message
                              (e.g. "do you want to use this bait?")
  textInputWidget          -- text-input variant
  rangeInputWidget         -- range-input variant
  closeInputWidget         -- dismiss the gathering UI

debug
  testAsk
```

`orderInputWidget` is the **main interactive sink**. It picks the
right widget per command id, configures the primary/retry text ids,
the prompt text, and an optional auxiliary "cancel hint" text id,
then calls `desktopWidget:selectEventModeWidgetYield(...)` and yields
the judge's coroutine until the player picks an option. It returns
`(value1, value2, isAccepted)`.

## `openInputWidget` shape

```lua
function HarvestJudge:openInputWidget(actor, _, A3, A4, A5)
  if not actor:isPlayer() then return false end
  if A5 == 22002 then
    return desktopWidget:updateEventModeWidget("Ask/MiningInputWidget",  A3, A4)
  elseif A5 == 22003 then
    return desktopWidget:updateEventModeWidget("Ask/FellingInputWidget", A3, A4)
  elseif A5 == 22004 then
    return desktopWidget:updateEventModeWidget("Ask/FishingInputWidget", A3, A4)
  end
  return false
end
```

A3 / A4 are the per-step state values the server pushes — likely
durability of the current strike, remaining attempts, current
hint/feedback flag, etc. The widget renders off these.

## `orderInputWidget` text ids and behaviour

```lua
function HarvestJudge:orderInputWidget(actor, _, cmdId, phase, hasAux,
                                       fishingState1, fishingState2,
                                       A8, A9)
  -- Pick the "primary text" id (first vs retry)
  local primaryText
  if phase == 1 then
    primaryText = ({[22002]=22701, [22003]=22704, [22004]=22711})[cmdId]
  else
    if cmdId == 22002 then primaryText = 22703
    elseif cmdId == 22003 then primaryText = 22705
    elseif cmdId == 22004 then
      if fishingState1 == true and fishingState2 == false then primaryText = 22711
      elseif fishingState1 == true and fishingState2 == true  then primaryText = 22711; secondaryText = 22708
      else primaryText = 22708
      end
    end
  end

  -- "Prompt to start" text
  local startPrompt = ({[22002]=22702, [22003]=22706, [22004]=22709})[cmdId]

  -- Optional aux ("cancel hint")
  local auxText = (hasAux ~= 0) and 22710 or nil

  if actor:isPlayer() then
    local widgetName = ({[22002]="Ask/MiningInputWidget",
                        [22003]="Ask/FellingInputWidget",
                        [22004]="Ask/FishingInputWidget"})[cmdId]
    accepted, choiceA, choiceB =
      desktopWidget:selectEventModeWidgetYield(
        widgetName, primaryText, secondaryText, auxText, startPrompt,
        nil, phase, (cmdId==22004 and A8 or nil), A9
      )
    if not accepted then choiceA, choiceB = 0, 0 end
  end
  return choiceA, choiceB, accepted
end
```

The yield+return mechanic is the same pattern as `WorldMaster:ask`
(documented in `finding_worldmaster_and_actor_packet_flow.md`): the
client opens an event-mode widget, yields, the user picks, the choice
comes back to Lua, and the calling code presumably forwards it to the
server via `_callServerOnCommand` or a similar binding.

## Pinned text-id family `22700..22711`

```text
22701  Mining   first-attempt prompt
22702  Mining   "begin" prompt
22703  Mining   retry prompt
22704  Felling  first-attempt prompt
22705  Felling  retry prompt
22706  Felling  "begin" prompt
22707  (gap)
22708  Fishing  retry prompt (or "bait absent" variant)
22709  Fishing  "begin" prompt
22710  generic  cancel-hint / auxiliary line
22711  Fishing  first-attempt prompt (or "with bait" variant)
```

## `askInputWidget` and the `_createVirtualItem` integration

```lua
function HarvestJudge:askInputWidget(actor, _, cmdId, A4, A5, A6, ...)
  if A5 == nil and A9 ~= 0 then A5, A6 = 64, A9 end
  local widget = desktopWidget:getChildWidgetByWindowName(
    ({[22002]="Ask/MiningInputWidget",
      [22003]="Ask/FellingInputWidget",
      [22004]="Ask/FishingInputWidget"})[cmdId]
  )
  local icon = nil
  if A5 == 25 then
    -- A5 == 25 means "showing a virtual item icon"
    local vitem = actor:_createVirtualItem(A6, 1, 1)
    icon = vitem:getItemIcon()
  end
  widget:orderHarvestOwnerMessageDisplay(A4, A5, A6, A7, A8, icon)
end
```

`A5` (message subtype) constants seen:

```text
25  show a virtual-item icon, A6 = item id (uses _createVirtualItem)
64  generic message (synthesised when A5 nil + A9 non-zero)
```

The judge calls `widget:orderHarvestOwnerMessageDisplay(...)` — the
widget itself decides how to render the gathering point's "owner
message" (the dialogue/feedback line from the harvest node).

`_createVirtualItem(itemId, count, kind)` is the same player binding
already pinned in `finding_judges_battle_stubs_craft_orchestrator.md`
for the craft-repair path. **It is the shared "make a transient
in-memory item handle" primitive** used wherever the client needs to
display an item icon without modifying inventory.

## Corrected command ranges

In `finding_game_command_pipeline.md` we attributed the range
`22002..22009` to "craft" based on `GameCommandBaseClass:isPlayerCommand`:

```lua
function GameCommandBaseClass:isPlayerCommand()
  if 22002 <= self:getCommandId() and self:getCommandId() <= 22009 then
    return true
  end
  return false
end
```

That method name was misread. **`isPlayerCommand` is a generic
"player-issued action" check**, not "isCraftCommand". The actual
`isCraftCommand` returns `false` in the base class. With evidence from
HarvestJudge we now know:

```text
22001         harvest-base   (the abstract "I am gathering" command — isHarvestCommand)
22002         Mining          (gathering subtype)
22003         Felling         (gathering subtype)
22004         Fishing         (gathering subtype)
22005..22009  TBD — other "player-issued" action commands (likely the
              remaining DoH/DoL primary verbs in 1.x)
22012, 22016  Craft commands that REQUIRE a target (the actual craft
              commands documented in CraftCommand.lua)
22502         Tutorial-only craft command (excluded from the standard
              craft list — see CraftJudge inventory finding)
```

So `isPlayerCommand` is "is this a player action command" (umbrella);
`isHarvestCommand` is "is this exactly cmd 22001" (the abstract
harvest); the three concrete harvest types live at 22002/22003/22004
and are dispatched by the HarvestJudge UI orchestrator on top of the
abstract harvest. The actual `isCraftCommand` is a separate range
that we have not fully pinned yet.

## Assessment

```text
Confirmed:
  - HarvestJudge has 11 methods, all UI orchestration (no outcome math).
  - The three gathering types in 1.x with their command ids and widgets:
       22002 Mining     Ask/MiningInputWidget
       22003 Felling    Ask/FellingInputWidget
       22004 Fishing    Ask/FishingInputWidget
  - Text-id family 22700..22711 maps to mining/felling/fishing
    prompts (first / retry / begin / cancel).
  - askInputWidget's A5==25 path uses _createVirtualItem to show a
    transient item icon. Same primitive as the craft-repair flow.

Likely (High):
  - Cmd ids 22005..22009 are the remaining DoH/DoL "primary verb"
    actions (e.g. mining/felling were already 22002-22003; 22004 is
    fishing; 22005..09 might be DoH primary verbs like cooking,
    blacksmithing, alchemy, etc.). Reading any single craft-class
    file will pin them.
  - The "phase" argument to orderInputWidget is a 1=first-attempt /
    other=subsequent-attempt flag, used to swap the text id between
    initial prompt and retry prompt.

Likely (Medium):
  - On Fishing, A6/A7 encode bait-attached state and recent-cast
    state: (true,false) => bait-attached-first-cast; (true,true) =>
    bait-attached-retry-with-bait. The branching pattern matches the
    1.x fishing flow ("you have a bite!" -> "reel in or wait?").

Speculative:
  - That harvest outcomes (which item drops, in what quantity) are
    pushed to the client through CharaBase or PlayerBase's
    _onReceiveDataPacket as a known string packetType (cf.
    "requestedData" / "attention" already documented). The judge's
    UI yield only returns the player's *choice*; the resulting items
    arrive separately.

Next test:
  - Read judge/negotiation/negotiationjudge.lua to confirm the
    orchestrator pattern repeats for NPC dialogue.
  - Or read judge/depictionjudge.lua (23 KB, biggest single judge) to
    discover whether the pattern survives for visual depiction
    outcomes (weather / lighting / time-of-day).
  - Cross-check the corrected command ranges against the deciphered
    chara/player/* corpus and the command/game/* subclass files.

Commit suggestion:
  docs(re/lua): document HarvestJudge; correct cmd 22002..22009 range
```

## Server implication (additions)

1. **Three gathering modalities, one UI pattern.** A server can ship
   mining/felling/fishing with a single inbound packet shape (the
   "ask input" prompt) plus a single outbound shape (the player's
   choice). The widget chosen client-side is selected by command id;
   the server doesn't need to specify it.
2. **The judge round-trips a choice to the server.** When the player
   picks a result in the InputWidget, the choice comes back into the
   judge's calling context and from there into PlayerBase via
   `_callServerOnCommand`. Server should expect: command id (22002 /
   22003 / 22004) + choice values (`choiceA`, `choiceB`).
3. **The 22700..22711 text ids must exist in the client's text sheet
   for harvest prompts to render**. A bare server can still drive the
   UI without these (the texts come from a sheet), but the prompts
   will be blank.
4. **`_createVirtualItem` is server-free.** The client constructs the
   item handle locally for icon display purposes; the server is not
   involved.
5. **Documentation correction**: the previously-documented "craft"
   range 22002..22009 is actually the player-action range that
   *includes* the three gathering types at 22002/22003/22004. The
   actual craft commands begin at 22012 / 22016 (target-required) and
   probably extend through 22500-22999 (the tutorial craft cmd 22502
   sits in that range). Server bring-up should not assume 22002..09
   are all crafting.
