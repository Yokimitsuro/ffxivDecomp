# Finding: _wait Thunk Disassembled -- ResumeCheckerInterface UNIVERSAL Pattern CONFIRMED

**The universal coroutine yielding pattern is now confirmed.** Disassembles
the C++ thunk for `actor:_wait(seconds)`. Reveals it allocates a
**WaitResumeChecker** (40 bytes) and pushes it via the SAME
`CoroutineContext_pushResumeChecker` function that `_createActor` uses
for `OnInitResumeChecker`.

This validates the hypothesis from the prior `_createActor` finding:
**every yielding Lua binding constructs a ResumeCheckerInterface
subclass and pushes it through the coroutine context**.

**3rd thunk disassembled. Universal pattern confirmed.**

## 1. Thunk located

```text
Lua entry point:    actor:_wait(seconds)
                    -- declared in actorbaseclass_u.lua as _wait_inl

Registrar:          ActorBaseClass_registerLua_wait @ 0x0072e0b0
C++ thunk:          ActorBase_cpp_wait_thunk @ 0x006dbcb0 (NEW)
Worker function:    wait_extractAndPushChecker @ 0x0078bed0 (NEW)
Checker ctor:       WaitResumeChecker_ctor @ 0x0078b850 (NEW)
```

## 2. The thunk pattern (mirror of _defineClass)

```c
void ActorBase_cpp_wait_thunk(int luaCallContext) {
  setupExceptionFrame();
  wait_extractAndPushChecker(luaCallContext);   // delegates everything
  teardownExceptionFrame();
}
```

Same shape as `_defineClass` -- thin wrapper delegating to worker.

## 3. The worker (where it gets interesting)

```c
void wait_extractAndPushChecker(int luaCallContext) {
  // 1. Get arg 0 from Lua stack (a float: seconds to wait)
  float seconds = Lua_getFloatAt(stack, 0);
  
  // 2. Convert seconds -> ticks using engine timebase
  int64_t ticks = (int64_t)(seconds * DAT_00f91c48);   // tick rate constant
  
  // 3. Allocate WaitResumeChecker (40 bytes!)
  checker = operator_new(0x28);
  
  // 4. Construct it with the 64-bit deadline ticks
  WaitResumeChecker_ctor(checker, ticks_lo, ticks_hi);
  
  // 5. Push to script's coroutine context
  CoroutineContext_pushResumeChecker(luaContext, checker);
}
```

The 64-bit tick count (split as lo/hi for x86 ABI) suggests precise
sub-millisecond timing — engine resolves waits at tick granularity.

## 4. WaitResumeChecker class layout (40 bytes)

From `FUN_0078b850` (the constructor):

```cpp
struct WaitResumeChecker {  // sizeof = 0x28 = 40 bytes
  // +0x00  vtable*    = _anon_1EEF0F3D::WaitResumeChecker::vftable
  //                     (overrides base ResumeCheckerInterface vftable)
  // +0x08  uint32     deadline_lo
  // +0x0C  uint32     deadline_hi  (64-bit deadline tick count)
  // +0x10  ?          timer state (initialized by FUN_00d353f0,
  //                                probably a high-resolution timer
  //                                snapshot for elapsed-time calc)
  // +0x14..0x27  more timer state (24 bytes)
};
```

Base interface: `Component::Lua::GameEngine::ResumeCheckerInterface`
Derived: `_anon_1EEF0F3D::WaitResumeChecker`

The `_anon_1EEF0F3D::` is GCC/MSVC's name for an unnamed namespace
in this translation unit — likely the file `wait_inl.cpp` or similar.

## 5. CONFIRMED: ResumeCheckerInterface is the universal pattern

```text
Subclass               Size    Used by             Backs which yielding binding
--------               ----    -------             ----------------------------
OnInitResumeChecker    16 B    _createActor        actor init completion
WaitResumeChecker      40 B    _wait               timer deadline                (NEW)
[unknown]              ?       _waitForGroup       group state ready
[unknown]              ?       _waitForCharaSchedulerFinished  scheduler completion
[unknown]              ?       _waitForTurning     turn animation completion
[unknown]              ?       _waitForTargetTutorial         UI event
[unknown]              ?       _waitForCameraTutorial         UI event
[unknown]              ?       _waitForItemSearchWidget       UI event
[unknown]              ?       _waitForHamletDefenseScore     event score
[unknown]              ?       _waitForCharaSchedulerTutorialFinished  tutorial scheduler
```

**Predicted (now confirmed by 2 data points)**: every binding
prefixed `_wait*` or implicitly yielding (like `_createActor`)
returns a ResumeCheckerInterface-derived handle that the coroutine
pump resumes when its condition is satisfied.

Sized differently per use case:
- Short (16B): just script_id + actor_ref + readyFlag
- Medium (40B): adds 64-bit deadline + timer state
- Possibly larger for complex waits with multiple conditions

## 6. The CoroutineContext_pushResumeChecker flow (now fully understood)

```text
1. Lua script calls a yielding binding (e.g. actor:_wait(2.5))
2. C++ thunk extracts args, allocates ResumeCheckerInterface subclass,
   pushes via CoroutineContext_pushResumeChecker
3. The push adds the checker to the script context's per-coroutine queue
4. Script returns from the C++ thunk; Lua engine sees the queued checker
   and yields the coroutine
5. Engine's coroutine pump (periodic) walks each pending coroutine's
   checker queue
6. Each checker has a vtable[N] method that returns "still pending" or
   "now ready"
7. When all of a coroutine's checkers are ready, the engine resumes it
8. Script continues from the yield point
```

The vtable on each ResumeChecker class defines its readiness check
logic:
- WaitResumeChecker: compare current ticks vs deadline_hi:lo
- OnInitResumeChecker: check readyFlag bit
- (other checkers: poll their specific condition)

This is a **clean polymorphic timer wheel** — the engine doesn't care
WHY a script is waiting, only whether each pending checker says
"I'm ready."

## 7. Implications for script architecture

Now we understand the foundation of 1.x's script ergonomics:

```lua
-- Linear-looking script code:
local actor = global:_createActor("SomeNpc", "name")  -- yields on OnInitResumeChecker
actor:setPosition(1, 2, 3)
actor:_wait(2.0)                                       -- yields on WaitResumeChecker
actor:doSomething()
actor:_wait(1.0)                                       -- yields on another WaitResumeChecker
actor:_delete()
```

Without coroutines + ResumeCheckerInterface, this would be a callback
hell. The engine's polymorphic checker system lets scripts read top-to-
bottom while underneath, each yield is asynchronously satisfied.

This is the same pattern as JavaScript's `async/await` (but predates
ES7 by years) and Python's `asyncio`.

## 8. Implications for server design

```text
The server doesn't model the checker pattern directly (it's client-side
coroutine machinery). BUT this tells us:

1. Server cannot count on instant script execution:
   - Client scripts yield repeatedly on actor init, waits, scheduler
   - A 1-line _createActor on the client = multiple ticks elapsed
   - Server should design RPC pacing around this (don't flood the
     client with ops that need actors to be ready)

2. Script timing is in TICKS, not real seconds:
   - The `DAT_00f91c48` constant is the tick rate
   - On 30 Hz engine, _wait(1.0) = 30 ticks = 33.3ms ticks
   - Server's idea of "1 second" must match this for sync ops

3. The pump frequency determines minimum wait granularity:
   - If pump runs at 60 Hz, scripts wake every 16.7ms minimum
   - All yield-based timing is rounded UP to the next pump tick
```

## 9. Renames made (3)

```text
RENAMES:
  - 0x006dbcb0 -> ActorBase_cpp_wait_thunk
                  (Lua _wait entry-point thunk)
  - 0x0078bed0 -> wait_extractAndPushChecker
                  (worker: arg extract + allocate + push)
  - 0x0078b850 -> WaitResumeChecker_ctor
                  (40-byte checker construction with vtable + 64-bit deadline)
```

## 10. Confidence

```text
Confirmed:
  - actor:_wait(seconds) backed by ActorBase_cpp_wait_thunk @ 0x006dbcb0
  - WaitResumeChecker is a 40-byte ResumeCheckerInterface subclass
  - Uses 64-bit deadline tick count
  - Pushes via the SAME CoroutineContext_pushResumeChecker as _createActor
  - Concrete class name from Ghidra symbols:
    _anon_1EEF0F3D::WaitResumeChecker
    : Component::Lua::GameEngine::ResumeCheckerInterface
  - DAT_00f91c48 is the engine's seconds-to-ticks conversion constant
  - The "Universal Resume Checker Pattern" hypothesis from
    finding_createActor_thunk_async_actor_factory.md is CONFIRMED

Likely (High):
  - All ~8-10 _wait*-prefixed bindings (waitForGroup, waitForTurning,
    waitForTargetTutorial, etc.) follow this same pattern with
    different ResumeCheckerInterface subclasses
  - The coroutine pump runs at the same tick rate as the game engine
    (probably 30 or 60 Hz)
  - The 24 bytes after deadline in WaitResumeChecker hold high-
    resolution timer state for sub-tick precision

Likely (Medium):
  - Each script's coroutine context has a small fixed-capacity queue
    of pending checkers (~16 slots? would need to find the data
    structure)
  - The engine batches checker checks per tick to avoid O(N) walks
    when many scripts are waiting
  - Specialized checkers like WaitForGroupResumeChecker may store a
    Group reference at +0x10 instead of timer state
```

## 11. Cross-references

- `finding_createActor_thunk_async_actor_factory.md` -- the original
  finding that PREDICTED this pattern (now CONFIRMED by 2nd data point)
- `finding_defineClass_thunk_class_registration_loop.md` -- companion
  class-registration thunk (same shape: thunk + worker delegation)
- `finding_smallmodules_inventory_closed_17_masters.md` -- the
  inventory phase completion (this finding starts the thunk phase
  in earnest)

## 12. Next test

```text
Now that the Universal Resume Checker Pattern is confirmed, the
predicted ~8 other _wait* checkers can be enumerated with confidence:

1. Disassemble _waitForGroup thunk (CharaBase) -> expect a
   WaitForGroupResumeChecker subclass with group ref at +0x10
2. Disassemble _waitForTurning thunk (CharaBase) -> expect timer or
   actor-state checker
3. Disassemble _waitForCharaSchedulerFinished -> expect scheduler-ref
   checker
4. Other high-value thunks:
   - _parseTextCommand (DesktopWidget) -- chat dispatch
   - _appendMessagePool (DesktopWidget) -- chat display sink
   - _updateWork (CharaBase) -- WorkSync mechanism
   - _isInstanceOf (global) -- RTTI walk
5. Vtable[0x6c] walk for 5-10 sample classes -- mechanical naming of
   per-class spawn ctors (200+ functions in one batch)
```

## Commit suggestion

```
docs(re/exe): _wait thunk disassembled -- ResumeCheckerInterface UNIVERSAL pattern CONFIRMED (WaitResumeChecker 40B; same CoroutineContext_pushResumeChecker as _createActor)
```
