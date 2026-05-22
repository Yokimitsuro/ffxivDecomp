# Finding: Battle Judges Are Stubs; CraftJudge Is a UI Orchestrator (Server Is Authoritative)

Read of representative judges in the 1.23b corpus to test the previous
hypothesis (in `finding_judge_subsystem.md`) that judges compute
outcomes for both client prediction and server authority.

**Conclusion: in 1.23b, the client judges DO NOT compute combat or
craft outcomes.** They orchestrate UI widgets and forward the server's
result snapshots into the right Lua-side display calls. The
prediction-on-client model implied by the judge architecture is
**not realised in this build for combat**; it is *partially* realised
for crafting (UI flow + a virtual-item helper), but the actual
quality / progress math is server-side.

Sources read (deciphered paths):

```text
judge/action/actionjudge.lua            170 B    EMPTY STUB (class decl only)
judge/autoattack/autoattackjudge.lua    174 B    EMPTY STUB
judge/battle/battlejudge.lua             18 B    EMPTY STUB (Lua 5.1 chunk header only)
judge/battleprocess/battleprocessjudge.lua  177 B  EMPTY STUB
judge/craft/craftjudge.lua            25,054 B    REAL — 33 methods, UI orchestrator
```

The four combat-side judges have:

```lua
-- the whole content of actionjudge.lua, equivalent to all four:
require("/Judge/JudgeBaseClass")
_defineClass("ActionJudge", "JudgeBaseClass")
-- nothing else; no methods, no instance, no behaviour
```

`ActionJudge` is **not referenced anywhere else** in the entire
2,671-script corpus (`grep -r ActionJudge` returns only the file's own
declaration). The same is true for the other three combat stubs.

By contrast `CraftJudge` has 33 methods spanning sheet helpers,
command categorisation, lifecycle, and (most importantly) a complete
**UI orchestration surface** for the craft session.

## CraftJudge method inventory

```text
sheet & data
  getCraftCommandData                getAvailableStandardCraftCommand
  isCraftSystemCommand               isMainToolOrder
  isCraftStandardCommand
  isCraftStandardNormalCommand
  isCraftStandardRapidCommand
  isCraftStandardBoldCommand
  isCraftGiftCommand

lifecycle
  _onInit  _onFinalize  initText  loadTextData

widget orchestration  (the heart)
  openCraftProgressWidget        closeCraftProgressWidget
  updateInfo                     <-- the server -> client packet sink
  closeCraftStartWidget          craftCommandUI
  craftTuningUI                  start
  selectRcp                      confirmRcp
  startRepair                    selectCraftQuest
  cfmQst                         confirmLeve
  askContinueLocalleve           askRetryLocalleve

leve / quest
  sendTutorialGuildleve          (outbound packet builder?)
  selectCraftQuest

materia / equipment
  askJoinMateria                 cancelTarget
  askJoinResult

debug / dev
  selectRecipeBookTest           displayRate     selectTestMotion
```

## The `updateInfo` packet sink

```lua
function CraftJudge:updateInfo(actor, _, p1, p2, p3, p4, p5, p6, p7)
  if actor:isPlayer() then
    desktopWidget:orderCraftProgressWidgetUpdate(p1, p2, p3, p4, p5, p6, p7, 0)
  end
end
```

This is the **packet handler** on the Lua side for "craft progress
update". It is invoked by the actor framework (likely via
`_onReceiveDataPacket` or directly through the C++ `PacketProcessor`)
with **7 positional integer fields**, all of which it forwards to the
widget. Mapping (high confidence, by position vs the widget's
`init/updateProcess` signatures documented in
`finding_player_slots_and_craft_flow.md`):

```text
p1   progressPercentage (int8 0..100)
p2   craftPoint
p3   qualityPoint
p4   param1
p5   param2
p6   param3
p7   chosenCommand
0    a trailing literal -- likely an "is-final" flag
```

So the server sends, per craft step, a packet carrying 7 ints + a
final flag, and the client updates its `CraftProgressWidget.work`
fields off this. The server is the source of truth for every craft
step's outcome.

## UI orchestration pattern

Every UI method on the judge is a thin wrapper around a
`desktopWidget:<specificWidgetCall>`:

```lua
function CraftJudge:selectRcp(actor, _, extraArgs)
  return desktopWidget:selectCraftRecipeSelectWidget(extraArgs)
end

function CraftJudge:confirmRcp(actor, _, A3..A10)
  return desktopWidget:selectCraftRecipeDetailWidget(A3..A10)
end

function CraftJudge:openCraftProgressWidget(actor, A2, A3, A4, A5)
  if actor:isPlayer() then
    desktopWidget:openEventModeWidgetYield(
      "CraftProgressWidget", 0, A5, A3, 1000, A4, 1000
    )
  end
end

function CraftJudge:closeCraftProgressWidget(actor)
  if actor:isPlayer() then
    desktopWidget:closeEventModeWidget("CraftProgressWidget")
  end
end
```

Notes:

- `desktopWidget:openEventModeWidgetYield(widgetName, 0, ...)` is the
  blocking-style UI entry. The judge yields its coroutine until the
  widget closes (user choice or server-driven dismiss). This matches
  the `_luaGameEngineRequireYield` pattern (cooperative coroutines).
- The literal `1000` is passed for both `maxCraftPoint` and
  `maxQualityPoint` on session open. The widget's own schema defaults
  these to 999 if 0/nil is passed; CraftJudge overrides explicitly to
  1000. Server is free to pass any value here on the wire — the
  client honours what it receives.
- Only the local player triggers the UI (`if actor:isPlayer()`); the
  same judge methods receive every actor's craft events (so a remote
  player's craft doesn't pop UI but other side effects may still run).

## `startRepair` exposes one Lua-side helper

```lua
function CraftJudge:startRepair(actor, _, A3, A4, A5, A6, A7, A8)
  local virtualItem = actor:_createVirtualItem(A4, 1, A5)
  -- ... builds an array of 8 -1 / 0 slots, then:
  local result, modeA, modeB, items =
    desktopWidget:askCraftRepairWidget(0, 0, A3, virtualItem, A6, A7, A8)
  -- result codes 1->5, 2->6 remap
  ...
  return mode, count, unpack(items)
end
```

Pinned binding: **`_createVirtualItem(slot, count, kind)`** on the
player actor. This produces a transient item object for the repair
session — likely the "broken item" handle the player is repairing.
This is one of the few Lua-side helpers in the craft path that
*creates* gameplay state instead of just rendering it.

## Categorisation methods reveal more command IDs

From the inventory above:

```text
isCraftSystemCommand            specific id check (TBD)
isCraftStandardCommand          probably 22002..22009 range
isCraftStandardNormalCommand    one of 22002..22009
isCraftStandardRapidCommand     "Rapid"   variant
isCraftStandardBoldCommand      "Bold"    variant
isCraftGiftCommand              "Gift"    variant
isMainToolOrder                 main-tool slot ordering

ID 22502 is excluded from getAvailableStandardCraftCommand iteration
(seen at lines ~607-608) -- likely a tutorial-only craft command.
```

The standard craft commands (Normal / Rapid / Bold + Gift) match the
real-world 1.x craft action set: "Standard Synthesis", "Rapid
Synthesis", "Bold Synthesis", plus "Gift" variants. Server-side
balance lives in the same sheet rows.

## Reconciling with `commandSheet` columns 30..34

In `finding_command_baseclass_and_judges.md` we documented the five
`isJudgedAtXxxJudge` boolean columns. With this finding:

```text
isJudgedAtCommonJudge       (col 30)  -> CommonJudge preloads shared sheets;
                                        no per-command logic.
isJudgedAtBattleJudge       (col 31)  -> BattleJudge is an EMPTY STUB in
                                        1.23b. The column flag has no
                                        client-side effect; the server
                                        runs the math.
isJudgedAtCraftJudge        (col 32)  -> CraftJudge orchestrates UI and
                                        forwards server's progress
                                        snapshots. Client runs UI; server
                                        runs outcome math.
isJudgedAtHarvestJudge      (col 33)  -> not yet inspected; given the
                                        stubs above, likely UI orchestrator
                                        of a similar shape.
isJudgedAtNegotiationJudge  (col 34)  -> not yet inspected.
```

So the **judge flag is more a "UI flow router" than an outcome
selector**: it tells the client *which UI to bring up* when a
command's outcome arrives, not *how to compute the outcome*.

## Assessment

```text
Confirmed:
  - ActionJudge, AutoAttackJudge, BattleJudge, BattleProcessJudge are
    empty stubs in 1.23b. No methods. Not referenced elsewhere.
  - CraftJudge is a UI orchestrator with 33 methods covering recipe
    select, recipe confirm, repair, progress widget management,
    tutorial leve, materia melding.
  - The `updateInfo` method receives 7 positional integer fields from
    the server and forwards them to the CraftProgressWidget. The
    server is the authoritative source for craft step outcomes.

Likely (High):
  - Combat outcomes in 1.23b are fully server-authoritative. The
    client has no local prediction; it renders what the server tells
    it to render. This explains why the "judge" prediction model
    documented in finding_judge_subsystem.md is not realised on the
    combat side.
  - HarvestJudge and NegotiationJudge probably have similar shapes
    to CraftJudge: UI orchestrators around a server-pushed update
    method. Not yet read.

Likely (Medium):
  - The empty combat judges are placeholders that SE planned to fill
    with client-side prediction in a future build (the same way the
    PlayerBaseClass _craft / _harvest / _negotiation sub-slots are
    empty placeholders). The architecture was forward-compatible with
    prediction but the build did not exercise it.

Speculative:
  - Some pieces of the combat outcome might be partly client-side
    after all -- via PlayerBaseClass:_onReceiveTimingPacket(5, value)
    which special-cases instance raid timer commands (already noted
    in earlier findings). But these are timer ticks, not damage
    rolls, and they still arrive from the server.

Next test:
  - Read judge/harvest/harvestjudge.lua to confirm the UI-orchestrator
    pattern repeats for harvesting.
  - Read judge/negotiation/negotiationjudge.lua to do the same for
    NPC dialogue mechanics.
  - Read judge/depictionjudge.lua (23 KB; biggest judge by far) — it
    likely covers weather / time-of-day / lighting outcomes and is
    where the WorldMaster.getHydaelynHour pipeline plugs in.

Commit suggestion:
  docs(re/lua): document battle judges as stubs and CraftJudge as
                UI orchestrator (server-authoritative outcomes)
```

## Server implication (consolidated update)

1. **Combat is 100% server-authoritative in 1.23b.** The client has
   no fallback math. A minimal server can produce *any* outcome
   numbers and the client will render them; there's no local
   prediction to disagree.
2. **Craft outcomes are server-authoritative too.** The server pushes
   a 7-int update per craft step (progress, CP, quality, param1..3,
   chosenCommand). The client only manages UI.
3. **The five `isJudgedAt*` sheet flags are UI routers, not math
   routers.** A server changing one of these flags can re-route the
   client's UI flow without changing any outcome computation.
4. **`updateInfo` is the wire-end-point** the server hits for any
   "craft step happened" event. The C++ side dispatches to
   `target_actor:updateInfo(...)` (likely via the `PacketProcessor`
   route with `packetType == "updateInfo"` or similar) which lands in
   CraftJudge:updateInfo when the active "judge" for the command is
   CraftJudge.
5. **No client-side judge dump required from the server.** Empty
   judges have no behaviour; full judges only render UI. A server can
   ignore the judge subsystem entirely on the wire.
6. **Tutorial command id 22502** is excluded from the standard craft
   command list. Server should not offer it to a non-tutorial
   player.
