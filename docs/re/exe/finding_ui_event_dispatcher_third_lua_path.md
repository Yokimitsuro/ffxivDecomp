# Finding: UIEventDispatcher -- 3rd Lua-Call Path Discovered (Widget Events)

Closes a major gap left by `finding_invokeLua_roster_closed_80_complete.md`:
**`_onUICommandEvent` / `_onUICommandRequest` Lua hooks DO NOT use the
invokeLua mechanism** (FUN_00cc7a90 et al). They use a **separate
timed event dispatcher** -- a 3rd Lua-call path that the prior closure
finding did not cover.

This explains why my invokeLua roster (80 callbacks) did NOT contain
these hooks despite them being defined on WidgetBaseClass.

## 1. The three Lua-call paths in 1.x (corrected total)

```text
Path     Mechanism                              Examples                  Count
----     ---------                              --------                  -----
1        invokeLua_* (FUN_00cc7a90 family)      _onChangeSystemFlag,      80
         Direct C++->Lua event firing            _onTargetChanged,
                                                  _onLoadKeyAsync, etc.
2        registerLua_* (Functor pool)            _executeCommand,          123
         Lua callable C++ methods (bindings)    _fadeIn, _getHamletScore
3        UIEventDispatcher (FUN_00cf6080+5ec0)  _onUICommandEvent,        Many
         Timed queue-based UI event dispatch    _onUICommandRequest      (variable)
```

So the TRUE total of EXE<->Lua bridge points is:
- Paradigm 1 (invokeLua):  80
- Paradigm 2 (registerLua): 123
- Paradigm 3 (UIEventDispatcher): UNCOUNTED (every UI control event)
- **TOTAL minimum: 203 + Paradigm 3 surface**

## 2. The UIEventDispatcher architecture

```text
Object layout (the per-receiver UIEventDispatcher):
  +0x08  uint64    relative time (current - epoch)
  +0x14  ptr       root of timestamp-keyed RB-tree (pending events)
  +0x18  flag      "enabled" -- if 0, drain is skipped
  +0x28  ptr       ?
  +0x30  ptr       delayed dispatch queue head
  +0x34  ptr       delayed dispatch queue tail
  +0x38  ?
  +0x128 string*   the METHOD NAME to fire on receivers
                   (e.g., "_onUICommandEvent" or "_onUICommandRequest")
  +0x1c0 ptr       Lua state holder
```

Each instance fires ONE specific Lua method name on its receivers. So
there are likely **multiple dispatcher instances** -- at least 2:
- one for `_onUICommandEvent`
- one for `_onUICommandRequest`

## 3. The dispatch loop (per game tick)

```text
FUN_00cda330 (caller)
  -> UIEventDispatcher_tickUpdate (FUN_00cf63e0)
       updates relative time at +0x08
       if enabled (+0x18 != 0):
         UIEventDispatcher_processQueuedEvents_timed (FUN_00cf6080)
           current_ms = (relative_time / 1000)
           descend RB-tree to find events with time <= current_ms
           for each ready event in time order:
             UIEventDispatcher_fireOneEvent_5argMax (FUN_00cf5ec0)
               resolve receiver actor (via FUN_00cd8160)
               check receiver visibility (+0x7d, +0x7f flags)
               build Lua args from event record:
                 arg1 = stringA  (always present)
                 arg2 = stringB  (if non-zero)
                 arg3 = int      (if != sentinel)
                 arg4 = stringC  (always present)
                 arg5 = int/bool (if != sentinel)
               fire method:
                 Lua method name = *(this+0x128)
                 Lua_callMethod(luaState, receiver, methodName, args)
               return true on success
             if success: remove event from RB-tree
           handle delayed queue at +0x30..+0x34
```

This is a **CLASSIC TIMED-EVENT QUEUE** -- events are scheduled for
future times and fire when the clock catches up.

## 4. Event record format

```text
Each event in the RB-tree has shape:
  +0x00  4B  receiver actor id (uint)
  +0x04  16B first arg slot (4 dwords -- typically a string/widget name)
  +0x14  16B second arg slot (4 dwords -- string; only if non-zero)
  +0x24  4B  integer arg (skipped if == DAT_0130d78c sentinel)
  +0x28  16B third arg slot (4 dwords -- string)
  +0x38  4B  integer arg (skipped if == DAT_0130d78c sentinel)
  +0x3c  4B  bool/byte arg (skipped if == DAT_0130d79c sentinel)
```

Total event size: ~0x40 bytes per event (64 bytes).

Sentinel-based arg filtering means: if an arg slot holds the sentinel
value, it's omitted from the Lua call. So `_onUICommandEvent` is
called with VARIABLE ARITY (1 to 5 args) depending on which slots
are populated.

This matches the WidgetBaseClass signature:
```lua
_onUICommandEvent(A0_2, A1_2, A2_2, A3_2, A4_2, A5_2)
  -- A1..A5 are the up-to-5 dispatched args
```

## 5. Why this matters for the EXE<->Lua bridge model

Prior findings established 2 paradigms (registerLua + invokeLua). This
3rd paradigm is structurally different:

```text
Paradigm 1 (invokeLua):
  EVENT (C++ side) -> immediately fire Lua hook
  Synchronous, single call site per event type
  Examples: opcode 43 arrives -> CharaBase._onChangeSystemFlag fires NOW

Paradigm 2 (registerLua):
  Lua calls C++ method via functor
  Examples: Lua calls player:_fadeIn() -> functor invokes C++ thunk

Paradigm 3 (UIEventDispatcher) -- THIS FINDING:
  EVENT (C++ side) -> ENQUEUE in time-tree
  PER TICK: drain ready events, fire on each receiver
  ASYNCHRONOUS, batched, time-controlled
  Examples: UI button click -> enqueue UI event -> next tick fires
             receiver._onUICommandEvent(buttonName, paramVal, ...)
```

Paradigm 3 also enables **DELAYED dispatch** (e.g., "fire this event
in 500ms"), which Paradigm 1 doesn't support. So animations and
transitions in the widget system use Paradigm 3.

## 6. Connecting back to the Widget findings

Now the widget pattern stack makes complete sense:

```text
Server pushes a wire opcode -> Paradigm 1 invokeLua fires
                              -> e.g., DesktopWidget._onTargetChanged

DesktopWidget processes the target change in Lua -> may ENQUEUE
                                                    one or more UI events
                                                    in Paradigm 3 queue
                                                    (e.g., "highlight new
                                                     target widget at 100ms")

NEXT game tick:
  UIEventDispatcher_processQueuedEvents_timed runs
  -> fires _onUICommandEvent on the widget
  -> widget's _onUICommandEvent calls processUICommandEvent
  -> widget subclass renders the highlight

User clicks a button -> client-local input handler ENQUEUES UI event
                       -> next tick: widget._onUICommandEvent fires
                       -> widget calls processUICommandOperate
                       -> sets askResult -> caller polls isAskFinish
                       -> caller triggers an outbound packet
```

So the full chain is: **wire (Paradigm 1) -> widget Lua -> queue
(Paradigm 3) -> widget Lua -> outbound (registerLua wrapper -> wire)**.

## 7. The 5-string command dispatch (`_onCommand`)

A related but distinct dispatch path is `FUN_00708fc0` (renamed
`Command_invokeLua_onCommand_5strDispatch`).

This fires the `_onCommand` Lua hook on a receiver. The 5-way switch
on the input command string determines which arg-building helper is
used:

```text
String match (DAT_00fd471c..0fd4734):
  Match 1: FUN_0078b910 (arg builder) + FUN_00cc7a00 (method-name lookup)
  Match 2: FUN_0078b9b0 + FUN_00cc7a00
  Match 3: FUN_0078ba50 + FUN_00cc7a00
  Match 4: FUN_0078baf0 + FUN_00cc7a20
  Match 5: special-case widget binding via FUN_006fcb80
  No match: NO-OP

If a match is found, builds final Lua args and fires:
  Lua_callMethod_storedCtx(receiver, ..., "_onCommand", args)
```

This is the FIFTH Lua-call mechanism overall (counting the typed-cast
variant as separate). It's used for the player's COMMAND system
(player abilities, in-game commands, etc.) that go through a
named-command routing layer.

## 8. Annotations made in Ghidra

```text
RENAMES (4):
  - 0x00cf5ec0 -> UIEventDispatcher_fireOneEvent_5argMax
  - 0x00cf6080 -> UIEventDispatcher_processQueuedEvents_timed
  - 0x00cd25c0 -> Lua_callMethod_storedCtx
  - 0x00708fc0 -> Command_invokeLua_onCommand_5strDispatch
```

## 9. Server design implications

```text
For a server emitting UI commands:

  PARADIGM 1 (immediate events):
    Server pushes opcode -> invokeLua fires on the relevant class
    -> Lua handler runs IMMEDIATELY (same tick)
    Used for: target events, cutscene events, system events

  PARADIGM 3 (queued UI events):
    NOT directly server-controlled. The widget Lua code itself
    queues UI events for animations/transitions. The server doesn't
    push UI events to the queue directly.
    The server's role: push the TRIGGER (Paradigm 1 invokeLua),
    then the widget Lua decides what UI events to queue.

  SO: a server that wants to "show a notification" sends an
    invokeLua-triggering opcode -> client-side widget handles it
    -> widget queues UI events for the notification animation
    -> UIEventDispatcher fires those events over time
    -> animation plays

CRUCIAL TIMING:
  The UIEventDispatcher operates on relative time (per-instance epoch).
  Each tick advances the time. Events with time <= current fire.
  This means animations can be precisely timed at any millisecond
  resolution; events are CONSUMED in time order (RB-tree key = time).
```

## 10. Confidence

```text
Confirmed:
  - FUN_00cf6080 IS the timed event drain function (RB-tree iteration
    with time comparison)
  - FUN_00cf5ec0 IS the per-event fire function (args from packet
    fields + sentinel filtering + Lua call)
  - The method name to fire is stored at *(dispatcher+0x128)
  - The event record is ~64 bytes with 5 max args
  - Tick-driven via FUN_00cf63e0 (called from FUN_00cda330)
  - This mechanism is DISTINCT from invokeLua (FUN_00cc7a90)
  - There are at least 3 Lua-call paths in 1.x
  - FUN_00708fc0 fires _onCommand via 5-string dispatch

Likely (High):
  - The UIEventDispatcher singleton has 1 instance per event type
    (one for _onUICommandEvent, one for _onUICommandRequest, etc.)
  - The "enabled" flag at +0x18 lets the engine pause UI event
    dispatch (e.g., during cutscenes)
  - The delayed dispatch queue at +0x30..0x34 is for events that
    couldn't fire on time (overdue events get bumped to next tick)
  - The 5 args in the event record correspond to the (string,
    string, int, string, int/bool) typical of UICommands

Likely (Medium):
  - Animations and tween-style effects in 1.x widgets use this
    queue (each tween step is an enqueued event with the keyframe
    time)
  - Server-pushed UI events (rare) go through a different path
    (per Paradigm 1 invokeLua, e.g., the cutscene clip events
    at opcodes 8-14)

Speculative:
  - The "delayed dispatch queue" may track per-receiver state
    (avoid firing two events on the same receiver in the same tick)
  - Some events may be PRIORITY-ordered separately from time order
    (need deeper RB-tree analysis)
```

## 11. Cross-references

- `finding_invokeLua_roster_closed_80_complete.md` -- the 80
  Paradigm 1 (invokeLua) callbacks; this finding adds Paradigm 3
- `finding_widget_baseclass_architecture_and_194_widgets.md` --
  the WidgetBaseClass that DEFINES _onUICommandEvent /
  _onUICommandRequest hooks (now explained how they fire)
- `finding_widget_ask_patterns_8_widgets_sampled.md` -- the
  AskBaseClass widgets that USE these hooks via processUICommand-
  Operate / Cancel
- `finding_widget_large_4_complex_patterns.md` -- non-modal
  widgets (Pattern I) that use Paradigm 3 events for their
  update loop
- `finding_widget_inventory_5_samples_pattern_M_added.md` --
  context-menu sub-widgets (Pattern M) that delegate via
  Paradigm 3 events to parent widgets

## 12. Next test

```text
1. Find the SECOND UIEventDispatcher instance (for
   _onUICommandRequest) -- search for *(this+0x128) = pointer
   to "_onUICommandRequest" string
2. Read FUN_00cda330 to see where the dispatcher is ticked
   (per game frame? per widget update?)
3. Map the 5-string command tags (DAT_00fd471c..0fd4734) to their
   actual command type names by reading the strings
4. Check if there's a 4th Lua-call path (typed dispatcher? script-
   eval?) that could also bypass invokeLua
```

## Commit suggestion

```
docs(re/exe): UIEventDispatcher -- 3rd Lua-call path discovered (Widget events use timed queue, NOT invokeLua)
```
