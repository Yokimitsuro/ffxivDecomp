# Finding: Widget Has THREE Timed Dispatchers (Per-Frame Tick) -- Not Just UIEventDispatcher

Extends `finding_ui_event_dispatcher_third_lua_path.md` by walking the
per-frame update function `Widget_perFrameUpdate_ticksAll3Dispatchers`
(FUN_00cda330). Discovers that **every widget/actor instance owns
THREE distinct timed dispatcher subsystems**, not just the one
UIEventDispatcher identified previously.

The full Paradigm 3 (timed dispatch) surface is therefore 3x what the
prior finding suggested.

## 1. The 3 timed dispatchers per widget instance

```text
Owner field   Tick function                                        Role
-----------   -------------                                        ----
+0x180        DispatcherA_tickWithTimeoutBudget (FUN_00cef510)    High-priority +
                                                                   retry queue
+0x184        UIEventDispatcher_processQueuedEvents_timed         Standard UI events
              (FUN_00cf6080, via FUN_00cf63e0 wrapper)             (RB-tree, time-keyed)
+0x188        DispatcherC_tickStackBased (FUN_00cd6e60)            Stack-based pending
                                                                   list
```

All three are ticked per frame by the widget's per-frame update
function. Each has its own data structure and dispatch semantics.

## 2. Widget instance memory layout (extended)

```text
Widget owner (per finding_widget_baseclass_architecture + this finding):

  +0x00..             vtable + WidgetBaseClass fields (per prior finding)
  +0x14..             widget state
  +0x180  4B          DispatcherA pointer (high-priority dispatcher)
  +0x184  4B          DispatcherB pointer (UIEventDispatcher)
  +0x188  4B          DispatcherC pointer (stack dispatcher)
  +0x190  4B          Child actor list head
  +0x194  4B          Child actor count
  +0x198  4B          Child actor RB-tree root
  +0x19c  4B          Child actor list tail
  +0x1c0  4B          Lua state holder (for Lua VM invocation)
  +0x1c4..0x1cc  16B  Internal state holders
  +0x1d0  4B          Game state holder
  ...
  +0x226  1B          "currently iterating children" flag
                      (set during the per-child tick loop)
```

So a widget instance is ~512+ bytes (the full size depends on the
subclass; AskBaseClass adds 128 bytes, DesktopWidget adds 1024).

## 3. DispatcherA -- high-priority timed dispatcher with retry queue

`DispatcherA_tickWithTimeoutBudget` (FUN_00cef510) is the highest-
priority dispatcher. Distinctive features:

```text
Time source:    timeGetTime() -- Windows API, absolute system time in ms
Data:           +0x0c  RB-tree of pending events (timestamp-keyed)
                +0x18  Retry queue head (events that couldn't fire in time)
                +0x20  Retry queue tail
                +0x20 (ushort)  Maximum frame-time budget in ms
                +0x14  Frame entry timestamp
Process:
  1. timeGetTime() -> currentMs
  2. Walk RB-tree to find first event with time <= currentMs
  3. For each ready event, call FUN_00cefff0 (dispatcher)
  4. After tree drain, process retry queue at +0x18..+0x20
  5. For each retry event:
       resolve receiver via FUN_00cd8160
       call FUN_00ce1840 (dispatch with retry semantics)
       if currentTime - frameEntry > budget: BREAK (defer remaining
                                                    to next frame)
  6. Returns timeGetTime() - frameEntry (total frame consumption ms)
```

So **DispatcherA enforces a per-frame budget**. If processing takes
too long, remaining events get deferred to the next frame instead of
blocking the render loop.

This is the **CRITICAL EVENT DISPATCHER** for things like:
- Quest event scripted actions
- Cutscene step transitions
- High-priority UI feedback (damage numbers, notice popups)

The retry queue means a widget that's slow to fire (e.g., due to async
data load) won't lose its event -- it just gets pushed to the next
frame.

## 4. DispatcherC -- stack-based immediate dispatcher

`DispatcherC_tickStackBased` (FUN_00cd6e60) operates on a flat stack
rather than a tree:

```text
Data:           +0x0c  Stack of pending events
                +0x14  Iterator position
                +0x18  Current event pointer
                +0x1c  Local container
                +0x20  Sub-list pointer
Process:
  1. Iterate the stack at +0x0c
  2. For each event:
       Extract type tag at (+0xc of event) -> local_28
       Extract subtype tag at (+0x10 of event) -> local_24
       Lookup receiver via FUN_00cd6b50
       Match type+subtype against existing entries
       If match: FUN_00d11940 (transfer to inner container)
       Else: FUN_009172c0 (purge)
  3. After loop: FUN_00cd73e0 (final processing) +
                 FUN_00cde6b0 (cleanup all stack entries)
  4. Reset stack head/tail
```

DispatcherC is the **SUBSCRIPTION/PUBSUB DISPATCHER** -- it matches
events against subscribers by (type, subtype) keys. Events with no
matching subscriber are purged. Matched events get transferred to the
subscriber's inner container.

Likely use cases:
- Per-widget subscription channels (e.g., "subscribe to inventory
  updates")
- Multi-handler event delivery (one event -> N subscribers)
- Cross-widget messaging within the same parent

## 5. UIEventDispatcher (DispatcherB) -- standard timed events

Covered in prior finding. Quick recap:
- Relative-time RB-tree
- Method name at +0x128 (varies by instance; one for
  _onUICommandEvent, one for _onUICommandRequest)
- Fires on receiver via Lua_callMethod with up to 5 args

## 6. Per-frame tick flow

```text
Engine main loop
  -> per active widget: Widget_perFrameTick_externalEntryPoint
       (FUN_00cc98a0)
       
Widget_perFrameTick_externalEntryPoint:
  1. Widget_perFrameUpdate_ticksAll3Dispatchers (FUN_00cda330)
       a. vtable[+8] hook
       b. State advance
       c. Pause check
       d. Per-child tick (recursive: each child also goes through
          per-frame update for its own dispatchers)
       e. Tick DispatcherA (high-priority, budget-bound)
       f. Tick DispatcherB (UIEventDispatcher)
       g. Tick DispatcherC (subscription)
       h. Return DispatcherA's frame budget consumed
  2. Lua_perFrameTick (FUN_00cf1b50) on the Lua state
  3. Return (frameBudgetConsumed, luaResult) to engine
```

So per frame, a widget runs:
- 1 vtable hook + state advance
- N child ticks (recursive)
- 3 dispatcher ticks
- 1 Lua state tick (the Lua VM's own per-frame work)

This is **~5 separate work passes per widget per frame**, recursing
through children.

## 7. Server design implications

```text
For a server emitting widget-bound events:

  HIGH-PRIORITY events (DispatcherA path):
    Quest scripted transitions, cutscene steps, critical UI feedback
    Server sends opcode -> client invokeLua handler enqueues into
    DispatcherA for time-precise firing
    
  STANDARD UI events (DispatcherB path):
    Button clicks, list selections, generic widget interactions
    These are mostly client-local (no server packets); server only
    triggers the originating event
    
  SUBSCRIPTION events (DispatcherC path):
    Inventory delta broadcasts, party member updates, status changes
    Server pushes the delta -> client invokeLua handler enqueues into
    DispatcherC -> all subscribed widgets get the update

NOTE: Most widget interaction is CLIENT-LOCAL via dispatchers B and
C. The server only triggers via Paradigm 1 invokeLua. Once triggered,
the widget Lua decides what dispatcher to use for downstream events.

PERFORMANCE NOTE: DispatcherA's frame-budget enforcement means a
server that floods a client with high-priority events won't hang the
client -- excess events just get pushed to subsequent frames. This is
important for events like NPC chat barks during combat.
```

## 8. Updated EXE<->Lua bridge total

```text
Paradigm 1 (invokeLua):         80 callbacks
Paradigm 2 (registerLua):      123 bindings
Paradigm 3 (timed dispatch):   3 dispatchers per widget x N widgets
                               (~500+ widget instances at peak;
                                each fires many events per session)
Total bridge surface:           >203 (Paradigm 3 vastly expands the count)
```

## 9. Annotations made in Ghidra

```text
RENAMES (4):
  - 0x00cda330 -> Widget_perFrameUpdate_ticksAll3Dispatchers
  - 0x00cef510 -> DispatcherA_tickWithTimeoutBudget
  - 0x00cd6e60 -> DispatcherC_tickStackBased
  - 0x00cc98a0 -> Widget_perFrameTick_externalEntryPoint

COMMENTS (1 large):
  - 0x00cda330 -- full owner object layout, per-frame flow,
                  dispatcher purposes
```

## 10. Confidence

```text
Confirmed:
  - Every widget instance has 3 dispatcher fields at +0x180/0x184/0x188
  - DispatcherA uses timeGetTime() (Windows ms)
  - DispatcherA has a frame-time budget enforcement
  - DispatcherA has a retry queue at +0x18/0x20
  - DispatcherC iterates a stack-based pending list
  - DispatcherC matches by (type, subtype) tags
  - All 3 dispatchers are ticked per frame
  - Widget per-frame tick also invokes Lua_perFrameTick separately

Likely (High):
  - DispatcherA is for high-priority commands (quest events,
    cutscene transitions)
  - DispatcherC is for subscription/pubsub events (inventory deltas,
    party broadcasts)
  - DispatcherB (UIEventDispatcher) is for standard UI interactions
  - The widget pause flag (+0x1cc->+8) gates all 3 dispatchers
  - Child widgets recursively tick their own 3 dispatchers

Likely (Medium):
  - DispatcherA's budget (+0x20 ushort) is typically 4-8 ms per
    frame (enough for time-precise events without blocking render)
  - DispatcherC subscribers are registered via a separate
    SubscriptionRegistrar mechanism (would need to find)
  - The vtable[+8] hook at the start of the per-frame update is
    the widget's "before tick" callback

Speculative:
  - There may be a 4th dispatcher type for SCRIPT EVENTS
    (e.g., Lua-internal events fired by Quest/Judge scripts)
  - The "currently iterating" flag (+0x226) is a safety mechanism
    to defer child removal until iteration completes (avoids
    iterator invalidation)
```

## 11. Cross-references

- `finding_ui_event_dispatcher_third_lua_path.md` -- the prior
  finding that identified DispatcherB only; this extends to all 3
- `finding_widget_baseclass_architecture_and_194_widgets.md` -- the
  widget class hierarchy that owns these dispatchers
- `finding_widget_inventory_5_samples_pattern_M_added.md` -- the
  sub-widget delegation pattern likely uses DispatcherC for
  parent/sub-widget communication

## 12. Next test

```text
1. Read FUN_00cefff0 (DispatcherA's per-event dispatch) to identify
   what Lua method name(s) it fires on receivers
2. Read FUN_00ce1840 (DispatcherA's retry-event dispatch) for the
   retry semantics
3. Read FUN_00d19140 (DispatcherC's per-event dispatch) to find what
   it fires
4. Search the binary for callers that CREATE these dispatchers (to
   see widget initialization and what method names are assigned)
5. Walk Director/Judge masters to see if they use the same 3-tier
   dispatch architecture
```

## Commit suggestion

```
docs(re/exe): Widget has 3 timed dispatchers per instance (not just UIEventDispatcher)
```
