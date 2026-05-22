# Finding: `NegotiationJudge` — Pattern Triply Confirmed (Craft + Harvest + Negotiation)

Read of `judge/negotiation/negotiationjudge.lua` (4.7 KB, 7 methods).
This is the **third concrete judge** read with the same shape: UI
orchestrator with a server-pushed update sink, no outcome math.

Source read:

```text
judge/negotiation/negotiationjudge.lua    0p635/w53vq19q1vw/w53vq19q1vw0p635.lua  (4.7 KB)
```

## Method inventory and shape

All 7 methods are short (10–30 lines) and follow the same skeleton:

```lua
function NegotiationJudge:<verb>(actor, _, A3..AN)
  if actor:isPlayer() then
    return desktopWidget:<specificWidgetMethod>("Ask/<WidgetName>", ...)
  end
end
```

Specifically:

```text
method                       widget                       desktopWidget call               returns
---------------------------  ---------------------------  -------------------------------  ----------------
openListWidget               Ask/NegotiationListWidget    askEventModeWidgetYield          choice index
openAskWidget                Ask/NegotiationAskWidget     askEventModeWidgetYield          choice index
openNegotiationWidget        Ask/NegotiationWidget        openEventModeWidgetYield         (none)
inputNegotiationWidget       Ask/NegotiationWidget        selectEventModeWidgetYield       selected index
updateNegotiationWidget      Ask/NegotiationWidget        updateEventModeWidget            (none)
closeNegotiationWidget       Ask/NegotiationWidget        closeEventModeWidget             (none)
negotiationEmote             —                            actor:_runCharaScheduler(arg)    (none)
```

## The server-side sink

```lua
function NegotiationJudge:updateNegotiationWidget(actor, _, A3, A4, A5, A6, A7, A8)
  if actor:isPlayer() then
    desktopWidget:updateEventModeWidget("Ask/NegotiationWidget", A3, A4, A5, A6, A7, A8)
  end
end
```

So the wire payload from the server for a negotiation update carries
**6 positional args** that the widget consumes. Compared with the
other two:

```text
CraftJudge:updateInfo                  -> 7 ints + a trailing 0 flag
NegotiationJudge:updateNegotiationWidget -> 6 args
HarvestJudge: (no single updateXxx;
              uses orderInputWidget yield-then-return pattern)
```

So the *shape* of the update sink varies by flow, but every flow has
one or both of:

- A **forward-only update sink** (`updateXxxWidget` taking server's
  positional args).
- A **yield-then-return interactive method** (`orderXxx` /
  `inputXxxWidget`) where the judge calls a `*Yield` UI helper and
  the player's choice comes back as a return value, to be forwarded
  to the server in a subsequent command request.

## Negotiation's three widgets

```text
Ask/NegotiationListWidget    Multi-choice list (e.g. "what to ask the NPC")
Ask/NegotiationAskWidget     Single Yes/No or short-prompt question
Ask/NegotiationWidget        The main negotiation panel (status / counters)
```

Naming convention: `Ask/<XxxNamedWidget>` for any widget that lives in
the "event mode" namespace and yields the player's coroutine until
input arrives. The `Ask/` prefix marks "this is interactive event UI"
as opposed to e.g. HUD overlays or persistent menus.

## `negotiationEmote` and the CharaScheduler

```lua
function NegotiationJudge:negotiationEmote(actor, _, A3)
  actor:_runCharaScheduler(A3)
end
```

`_runCharaScheduler(scheduleId)` is a new binding pinned by this
read. From context:

- Invoked **on the NPC actor** (not on the player) during negotiation.
- Drives a pre-baked sequence of animations / emotes / movements for
  that NPC (the "scheduler" is a timeline of character actions stored
  in client data).
- Unrelated to the Tutorial scheduler (`_runCharaSchedulerTutorial`
  documented on WorldMaster).

So during an NPC negotiation, the server can push a "play schedule N"
order and the client's CharaBase will animate the NPC accordingly,
independently of any negotiation outcome math.

## The unified pattern, after three judges

After reading CraftJudge, HarvestJudge and NegotiationJudge:

```text
flow         widget root             update sink                       interactive method(s)
-----------  ----------------------- --------------------------------  -------------------------------
Craft        CraftProgressWidget,    updateInfo (7+1 args)             selectRcp / confirmRcp /
             CraftStartWidget,                                         startRepair / craftCommandUI /
             CraftRecipe* /                                            craftTuningUI (all UI-yielding)
             CraftRepair*

Harvest      Ask/MiningInputWidget,  (no single sink; uses yield+      orderInputWidget (yield-return)
             Ask/FellingInputWidget,  return pattern)                  askInputWidget (yield-return)
             Ask/FishingInputWidget

Negotiation  Ask/NegotiationWidget,  updateNegotiationWidget (6 args)  openListWidget / openAskWidget /
             Ask/NegotiationList*,                                     openNegotiationWidget /
             Ask/NegotiationAsk*                                       inputNegotiationWidget
```

Every flow uses **`desktopWidget`** as the UI broker. Every flow gates
on `actor:isPlayer()` so the same handler can be invoked for remote
players' actions without popping the local UI. Every flow has either a
"server tells me to update" entry, a "yield until player chooses" entry,
or both.

This is the **canonical 1.x judge shape**. Any new judge we encounter
in the rest of the corpus is almost certain to follow it (excluding the
empty combat stubs and the data-prep singletons like CommonJudge).

## Assessment

```text
Confirmed:
  - NegotiationJudge follows the same orchestrator pattern as
    CraftJudge and HarvestJudge: no outcome math, all UI brokering.
  - updateNegotiationWidget is the server -> client sink for NPC
    negotiation state updates, carrying 6 positional fields.
  - Widget namespace "Ask/" marks interactive event-mode widgets.
  - _runCharaScheduler(scheduleId) is a CharaBase binding that runs
    a pre-baked NPC animation timeline.

Likely (High):
  - The unified pattern (forward-only update sink + yield-return
    interactive methods) is the universal 1.x judge shape across all
    interactive flows. The empty combat judges and data-prep judges
    are the exceptions, not the rule.
  - The 6 args to updateNegotiationWidget map to UI fields specific
    to the NegotiationWidget's own work struct (TBD — would need to
    read the widget Lua to enumerate).

Likely (Medium):
  - "negotiation" in 1.x refers to NPC-bartering / persuasion /
    information-gathering mini-games (e.g. asking an NPC for hints,
    bartering down a price). The presence of NegotiationListWidget
    + AskWidget suggests a "pick what to say" + "respond Yes/No"
    flow.

Speculative:
  - The negotiation system was a 1.x-era feature that was scaled back
    or removed in 2.0+, similar to how Hamlet Defense and the original
    Behest were specific to 1.x. The judge being only 4.7 KB suggests
    a relatively simple gameplay scope.

Next test:
  - Read the actual negotiation UI scripts (widget/Negotiation*Widget)
    to learn the work-struct layout that updateNegotiationWidget feeds.
  - Read judge/depictionjudge.lua (23 KB, the largest single judge);
    it is the only top-level real judge left unread and probably
    handles weather / time-of-day / lighting outcomes that drive the
    WorldMaster getHydaelyn* pipeline already documented.
  - Cross-correlate with the EXE-side: when a server packet for
    "negotiation update" arrives, who routes it from PacketProcessor
    -> NegotiationJudge:updateNegotiationWidget? The current finding
    set has PlayerBaseClass:_onReceiveDataPacket but not a
    NegotiationJudge entry.

Commit suggestion:
  docs(re/lua): document NegotiationJudge; pattern triply confirmed
```

## Server implication (additions)

1. **The negotiation widget update packet carries 6 positional ints.**
   Server should pack exactly that shape; the client widget consumes
   them directly via `desktopWidget:updateEventModeWidget`. Field
   semantics TBD pending the widget Lua read.
2. **Negotiation is server-authoritative**, like crafting and combat.
   The judge only renders; outcome math (whether the NPC is convinced,
   how much information is divulged) lives server-side.
3. **NPC animation during negotiation is fire-and-forget.** Server
   sends a single `_runCharaScheduler` id; the client plays the
   timeline. No round-trip needed.
4. **Multi-judge rendering**: a single command can be flagged
   `isJudgedAtCraftJudge` AND `isJudgedAtNegotiationJudge` (e.g. an
   item-acquisition action that triggers both a craft window and a
   negotiation prompt). The server can drive both flows by sending
   one update to each judge's sink.
