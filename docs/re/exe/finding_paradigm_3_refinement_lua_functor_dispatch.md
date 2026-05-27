# Finding: Paradigm 3 Refinement -- DispatcherA Fires Stored Lua Functors (Not Method Names)

Refines `finding_widget_3tier_dispatcher_architecture.md` by walking
DispatcherA's per-event dispatch path. **DispatcherA does NOT fire
Lua method names like DispatcherB does** -- it fires **stored Lua
functors (closures/function references)** that were CREATED during
widget initialization from Lua source code.

This is a SUB-PARADIGM within Paradigm 3 -- a fundamentally different
invocation mechanism than UIEventDispatcher (DispatcherB).

## 1. The two Paradigm 3 sub-mechanisms

```text
Mechanism            Stored at        Invocation              Use case
---------            ---------        ----------              --------
By method name       dispatcher+0x128 Lua_callMethod(name)    Standard UI events
(DispatcherB)        as string ptr    on receiver's metatable (button clicks)

By stored functor    cached per       Lua_invokeFunctor_      Tweens, animations,
(DispatcherA retry)  receiver at      withTimeProgress on     timed callbacks
                     receiver+0x10    the functor (closure)
```

So Paradigm 3 has TWO ways to dispatch a Lua call:
- **Named-method dispatch**: fire a known hook name on the receiver
- **Stored-functor dispatch**: fire a pre-created Lua closure that
  encapsulates its own code

The second is more powerful (the closure can capture arbitrary state)
but requires up-front functor creation.

## 2. DispatcherA's retry path

`DispatcherA_retryEventViaCachedFunctor` (FUN_00ce1840):

```c
void DispatcherA_retryEventViaCachedFunctor(receiver, frameTimeRef,
                                             stringArg, progressArg) {
  if (receiver->disabledFlag /* +0x7e */ == 0) {
    cached = receiver->cachedFunctor /* +0x10 */;
    if (cached == NULL) {
      // Create + cache the functor on first invocation
      cached = Lua_createCallableFunctor_cached(luaState, receiver,
                                                 DAT_01377ee8 /* descriptor */,
                                                 false /* not forced */);
      if (cached->isValid /* +0x13a */ == 0) {
        receiver->cachedFunctor = cached;
      }
    }
    Lua_invokeFunctor_withTimeProgress(cached, receiver,
                                        stringArg, progressArg);
  }
}
```

Key observations:
- `receiver+0x7e` is a "disabled" flag (e.g., widget not currently
  visible); skips dispatch if set
- `receiver+0x10` caches the created functor (lazy creation; once)
- `DAT_01377ee8` is a STRING/DESCRIPTOR that names the functor source
  -- need to read this address to know what method/source is bound
- The cached functor object is 0x140 bytes (320B) with internal state
  flags at +0x138/0x139/0x13a/0x13b

## 3. Lua_createCallableFunctor_cached (FUN_00cf1060)

This is the **Lua functor creator**. It:

1. Initializes Lua VM stack via `FUN_00cf34c0`, `FUN_00cf32c0` etc.
   (these are Lua stack push/pop primitives)
2. Pushes globals via `DAT_0130d508`, `DAT_0130d4e8` (Lua type tags
   for `_G` / function table)
3. Resolves the descriptor (`param_2`) via `FUN_00cf08c0` to get the
   actual ushort-keyed source
4. Tests via `FUN_00cf3740` if the function exists in the global
   table; if not, REGISTERS it (and runs the registration block)
5. If `force` flag set OR function doesn't exist in cache: creates a
   new functor object
6. Allocates 0x140 bytes for the functor object
7. Initializes via `FUN_00cce2d0(functor, key, widget, caller,
   sourceKey, ptrToFunction, callerCallChain)`
8. Sets flags based on the descriptor type:
   - `+0x138`: which byte from the descriptor's source-type tag
   - `+0x139`: bool (descriptor type == 1377ed0)
   - `+0x13a`: bool (descriptor type in 1377ed0 / 130cee8 / 130ceec)
   - `+0x13b`: 0 (reserved)

So the **functor caches a Lua source reference** and lazy-loads the
actual function on first invocation. Subsequent invocations reuse
the cached functor.

## 4. Lua_invokeFunctor_withTimeProgress (FUN_00cceac0)

The actual Lua invocation:

```c
void Lua_invokeFunctor_withTimeProgress(functor, widget, stringArg,
                                         progressUshort) {
  if (widget->parent->state /* +0xcc... */ == 0 &&
      widget->valid /* +0x7f */ != 0 &&
      widget->disabled /* +0xe8 */ == 0) {
    luaState = widget->parent->lua /* +0x1c0 */;
    FUN_00cf08f0(luaState, functor->cachedBindingId);
    
    // Setup Lua call:
    FUN_00cf34c0(functor->callStack);     // reset stack
    FUN_00cd7a50(widget->parent, callStack, widget);  // push self
    FUN_00cf34c0(callStack);
    FUN_00cf32c0(callStack, *stringArg);   // push string arg
    FUN_00cf3ab0(callStack);
    FUN_00cf34c0(callStack);
    FUN_00cd7b00(widget->parent, ..., callStack);  // push another arg
    FUN_00cf3380(callStack);
    
    // Compute time progress as floating point
    progress = (*progressUshort & 0x7fff) / DAT_00f91c48;  
    //              ^15-bit value          ^divisor (likely 32767)
    FUN_00cf3300(callStack, &progress);    // push progress as double
    
    // Invoke with 2 args, get 1 return value:
    FUN_00cf4230(callStack, 2, &returnVal);
    
    if (returnVal != 0) {
      // Branch on return type:
      if (returnType == TYPE_DOUBLE):
        FUN_00cd3e70(widget->parent->dispatcher, returnedValue);
      else if (returnType == TYPE_STRING):
        FUN_00cd3990(widget->parent->dispatcher, returnedValue);
      else if (returnType == TYPE_TABLE):
        FUN_00cd4080(widget->parent->dispatcher, returnedValue);
    }
    
    // Final cleanup hook
    if (!isInternalReadyToInvoke):
      FUN_00cce8e0(this);
      FUN_00cf33e0(callStack, savedDepth);
    
    FUN_00cf08f0(luaState, 0);
  }
}
```

The KEY INSIGHT: **the function takes a TIME PROGRESS as input (0 to
1.0 normalized from a 15-bit value 0..32767)** -- this is the
**animation/tween progress value**.

The Lua function being invoked is responsible for **updating widget
state at a particular point in the tween's progress** (e.g., interpolate
position from start to end at progress 0.5 = midway).

After invocation, the function's RETURN VALUE drives further dispatch:
- DOUBLE return: tween produces a numeric value -> FUN_00cd3e70
- STRING return: tween produces a string value -> FUN_00cd3990
- TABLE return: tween produces a struct value -> FUN_00cd4080

So DispatcherA is fundamentally a **TWEEN/ANIMATION ENGINE**:
1. Each event is a tween with start/end times
2. Per frame, compute the current progress (0..1)
3. Invoke the tween's Lua function with (widget, string arg,
   progress) -> get value back
4. Apply the value via the appropriate dispatcher

## 5. Updated Paradigm 3 architecture

```text
Each widget instance owns 3 dispatchers, each with distinct semantics:

DispatcherA (high-priority + tween):
  - Time-keyed RB-tree
  - Per-frame budget (defer overflow)
  - On dispatch: invokes STORED LUA FUNCTORS (per-receiver cached)
                 with (selfRef, stringArg, progress 0..1)
  - Use case: ANIMATION/TWEEN with frame-precise timing

DispatcherB (UIEventDispatcher):
  - Time-keyed RB-tree
  - On dispatch: invokes NAMED LUA METHOD (e.g. "_onUICommandEvent")
                 with variable args
  - Use case: STANDARD UI EVENTS (button clicks, list selections)

DispatcherC (subscription):
  - Stack-based pending list
  - On dispatch: matches (type, subtype) -> transfer to subscriber
  - Use case: PUBSUB EVENTS (inventory deltas, party broadcasts)
```

This explains why widget animations are smooth in 1.x: the tween
dispatcher (A) runs every frame and updates widget visuals via Lua
functions that compute interpolated values.

## 6. Server design implications (refined)

```text
For a server emitting events that affect widget animations:

  ANIMATION/TWEEN events go through DispatcherA's stored functor
  mechanism. The server does NOT directly create tween functors --
  the WIDGET creates them during initialization (e.g., when the
  widget is shown, it creates "fadeIn" and "fadeOut" tween
  functors).

  The server's role: trigger a state change via Paradigm 1 invokeLua
  (e.g. _onTargetChanged) -> widget Lua receives the change ->
  widget Lua queues a tween event in DispatcherA's tree (e.g.,
  "fadeIn target highlight over 200ms") -> per frame, DispatcherA
  invokes the tween functor with current progress (0..1).

  So animations are CLIENT-LOCAL. Server only triggers the state
  change; the visual response is entirely client-side.

REFINEMENT to prior analysis:
  Paradigm 3 has TWO sub-mechanisms (named-method vs stored-functor).
  The 80-callback invokeLua roster covered only Paradigm 1, not
  these stored functors. The stored functor count is THEORETICALLY
  uncountable (each widget creates its own at init), but
  PRACTICALLY: each widget class has a fixed set of standard
  functors (fadeIn, fadeOut, slide, scale, etc.).
```

## 7. Annotations made in Ghidra

```text
RENAMES (3):
  - 0x00cf1060 -> Lua_createCallableFunctor_cached
  - 0x00cceac0 -> Lua_invokeFunctor_withTimeProgress
  - 0x00ce1840 -> DispatcherA_retryEventViaCachedFunctor
```

## 8. Confidence

```text
Confirmed:
  - DispatcherA's per-event dispatch invokes Lua via cached functor
    (NOT by method name)
  - Lua_createCallableFunctor_cached creates a 0x140-byte functor
    object that caches Lua state + binding info
  - Lua_invokeFunctor_withTimeProgress is the actual invoker
  - Time progress is a 15-bit normalized value (0..32767 / DAT_00f91c48)
  - Functor invocation passes 2 args (string, progress), gets 1 return
  - Return value is branched 3 ways by type (double/string/table)

Likely (High):
  - DispatcherA is a tween/animation engine
  - DAT_01377ee8 is the SOURCE DESCRIPTOR for what tween function to
    create (likely "DispatcherA" or "TweenEngine" Lua descriptor)
  - DAT_00f91c48 is 32767.0 (max signed 15-bit) for normalizing
    progress to 0.0..1.0
  - The 3-way return dispatch handles different visual update types:
    - double: numeric (alpha, position, scale)
    - string: text content
    - table: complex struct (color, vector)

Likely (Medium):
  - The cached functor at receiver+0x10 is keyed by widget instance
    (not class) so each widget has its own animation state
  - Multiple tweens per widget run concurrently via separate events
    in the RB-tree

Speculative:
  - The 4 status flags at +0x138/0x139/0x13a/0x13b track:
    +0x138 -- ?
    +0x139 -- "is a registered function in the global table"
    +0x13a -- "is a valid functor (ready to invoke)"
    +0x13b -- reserved
  - The "scale factor / 32767" pattern matches FFXIV's standard
    1.x normalization for animation progress
```

## 9. Cross-references

- `finding_widget_3tier_dispatcher_architecture.md` -- the 3-tier
  dispatcher architecture; this finding refines DispatcherA's
  invocation mechanism
- `finding_ui_event_dispatcher_third_lua_path.md` -- the original
  Paradigm 3 discovery (focused on DispatcherB)
- `finding_widget_baseclass_architecture_and_194_widgets.md` --
  widgets that own these dispatchers
- `finding_invokeLua_roster_closed_80_complete.md` -- Paradigm 1
  (invokeLua) which is distinct from these dispatcher functors

## 10. Next test

```text
1. Read DAT_01377ee8 to identify the SOURCE STRING that describes the
   functor (likely "DispatcherA" or "AnimationEngine" or a function
   reference)
2. Check DAT_00f91c48 value (expected: 32767.0)
3. Read FUN_00cce2d0 (the functor constructor) to find the full
   functor field layout
4. Find what creates the 3 dispatchers when a widget is born (the
   widget constructor)
5. Sample 2-3 widget Lua files (e.g. those with animation) to find
   the Lua-side counterpart functions registered as tween callbacks
```

## Commit suggestion

```
docs(re/exe): Paradigm 3 refinement -- DispatcherA fires stored Lua functors (tween/animation)
```
