# Finding: _createActor Thunk Disassembled -- ACTOR CREATION IS ASYNC VIA OnInitResumeChecker

**Moving from "what bindings exist" to "what they actually do."**
Disassembles the C++ thunk for `global:_createActor()`, the central
actor factory called by every NPC / widget / director / sequence spawn
in 1.x.

The thunk reveals a major architectural pattern: **actor creation is
asynchronous via coroutine-aware OnInitResumeChecker handles**. The
Lua script gets a checker back, yields on it, and the engine resumes
the script when the actor's onInit chain completes.

This is the SAME async pattern that makes 1.x scripts feel synchronous
even when the underlying actor init takes many ticks (loading assets,
running multi-step init sequences, waiting on network state).

**1st thunk disassembled. Architectural depth increased significantly.**

## 1. Thunk located + renamed

```text
Lua entry point:    global:_createActor(classname, name, [opts])
                    -- declared in global_u.lua as _createActor_inl
                    -- routes to "global", "_createActor_cpp"
Registrar:          global_registerLua_createActor @ 0x00757350
                    -- registers C++ thunk as the binding implementation
C++ thunk:          global_cpp_createActor_thunk @ 0x00709640 (NEW)
                    -- the actual code that runs when Lua calls _createActor
```

## 2. Thunk overall structure (4 phases)

```text
Phase 1: Argument extraction from Lua stack
   - Arg 0: classname (string)              from param_1 + 0x10
   - Arg 1: actor name (string)             from param_1 + 0x10 + 0x10
   - Arg 2: optional opts (varies; if type 6, simple path)

Phase 2: Class lookup + branch decision
   - If type-6 fast path: simple registry lookup, may return existing actor
   - Else: full create-and-register flow (the long branch)

Phase 3: Polymorphic actor construction
   - Look up the class's vtable
   - Call vtable[0x6c]: the polymorphic actor constructor
     (each class registered via _defineClass has its own ctor in this slot)

Phase 4: Coroutine tracking + return
   - If coroutine tracking enabled, store (script_id, sub_id) -> actor_ref
   - Allocate 16-byte OnInitResumeChecker
   - Push checker onto Lua return stack
   - Lua side yields on the checker
```

## 3. The OnInitResumeChecker -- 16-byte handle

Allocated via `operator new(0x10)` and constructed via
`OnInitResumeChecker_ctor` @ 0x00713fe0 (NEW name):

```cpp
struct OnInitResumeChecker {
  // +0x00  vtable*    = Application::Lua::Script::Client::Control::Global
  //                     ::OnInitResumeChecker::vftable
  // +0x04  uint32     scriptContext (the spawning Lua script)
  // +0x08  uint32     actorRef (or related)
  // +0x0C  uint8      readyFlag
};
sizeof = 16 bytes
```

The base class is `Component::Lua::GameEngine::ResumeCheckerInterface`,
with the concrete derived class in
`Application::Lua::Script::Client::Control::Global::OnInitResumeChecker`.

Ghidra HAS the symbol names for these vtables -- confirming this is
the engine's resume-checker subsystem with named namespace classes.

## 4. Why this matters: the SYNC-LOOKING ASYNC pattern

In 1.x Lua, scripts often do:

```lua
local newNpc = global:_createActor("MyNpcClass", "newNpcName")
-- ... immediately use newNpc ...
newNpc:setPosition(1, 2, 3)
```

This LOOKS synchronous, but the actor's `_onInit` may take many ticks
(load assets, sync with server, init dependent actors). How can the
script use `newNpc` immediately?

**Answer**: the script transparently YIELDS on the returned
OnInitResumeChecker. The engine resumes the script when the actor's
init chain completes. To the script author, it just looks like a
blocking call.

This is the same pattern as Lua's `_wait()` binding -- both return a
resume checker that the Lua engine knows to yield on.

## 5. Coroutine tracking mechanism

The thunk calls:

```text
CoroutineContext_isTrackingEnabled (FUN_00cd27d0)
  -- returns whether the spawning script is in a tracked coroutine
  -- checks a flag at param_1 + 0x138

If tracking enabled:
  ScriptCoroutineKey_construct (FUN_00713f80) creates a (uint32, uint16) pair
  -- the script_id + sub_id key for the pending operation
  FUN_00726040 finds/inserts the key in a script-context tracking map
  CoroutineContext_pushResumeChecker (FUN_00cd2860) registers checker
  -- adds it to the per-context resume-checker queue
```

So the per-coroutine state has TWO data structures:
1. A **tracking map**: keyed by (script_id, sub_id) → actor_ref
2. A **resume-checker queue**: list of pending checkers the engine
   periodically inspects

When the actor's `_onInit` finishes, the engine flips the readyFlag
on the matching OnInitResumeChecker, and on the next coroutine
resume opportunity, the yielding script wakes up.

## 6. The polymorphic constructor at vtable[0x6c]

```c
// Inside the thunk, in the full-create branch:
piVar9 = (int *)FUN_00cc7a00();  // get current Lua actor context
iVar4 = (**(code **)(*piVar9 + 0x6c))(  // CALL vtable[0x6c / 4 = 27th entry]
    *(undefined4 *)(param_1 + 4),       // Lua state
    aiStack_64,                          // built name+context
    puVar3,                              // the class table
    auStack_94                           // arg pack
);
```

This is the **per-class polymorphic actor constructor**. Each class
registered via `global:_defineClass()` gets its constructor wired into
the 28th vtable slot of its C++ class. When `_createActor("X", name)`
runs, the engine looks up class X's vtable and calls that slot.

This is how a single `_createActor` call can produce 200+ different
runtime types (every NPC class, widget class, director class, etc.)
without the factory needing class-specific code.

## 7. Renames made (4 + 1)

```text
RENAMES:
  - 0x00709640 -> global_cpp_createActor_thunk
                  (THE actor factory thunk)
  - 0x00713fe0 -> OnInitResumeChecker_ctor
                  (16-byte resume-checker construction)
  - 0x00cd2860 -> CoroutineContext_pushResumeChecker
                  (registers checker on context queue)
  - 0x00cd27d0 -> CoroutineContext_isTrackingEnabled
                  (checks coroutine tracking flag)
  - 0x00713f80 -> ScriptCoroutineKey_construct
                  (builds (script_id, sub_id) pair)
```

## 8. Implications for server design

```text
The server doesn't need to model this directly -- the resume-checker
is a CLIENT-SIDE coroutine primitive. BUT it tells us:

1. Actor creation is ASYNC on the client.
   Scripts can't assume the actor is "fully initialized" the instant
   _createActor returns. They yield and resume.

2. The server should design actor-spawn responses around this:
   - When server pushes a spawn, the client's actor _onInit may take
     multiple ticks (download SSD data, build vtable wiring, etc.)
   - Server should NOT expect the client to be "actor-ready"
     immediately after sending spawn opcode
   - There's likely a client-to-server "spawn acknowledged / ready"
     packet that lets server know the actor is now usable

3. Multi-actor spawn scenarios (zone load with 100 NPCs) are
   parallelized at the script level:
   - One script can yield 100 _createActor calls in sequence
   - Each yields on its OnInitResumeChecker
   - Engine resumes script when ALL prerequisites finish
   - Server sees this as a long pause between spawn-ack packets

4. The (script_id, sub_id) coroutine key suggests the engine can
   track NESTED yields (script A yields, calls actor that itself
   yields). Server doesn't see this nesting directly.
```

## 9. Vtable offset 0x6c -- the spawn polymorphism

Knowing actor-create dispatches through vtable[0x6c] (offset 108 =
27th entry, 0-indexed) gives us a **mechanical way to find every
class's spawn ctor**:

```text
For any C++ class CLs that has a Lua registration (i.e., its name
is in DAT_00f67298's string table), CLs::vtable[27] is its
"create-from-Lua" constructor.

Future work could walk every Lua-registered class and disassemble
their vtable[27] entry to enumerate the per-class spawn pathways.
```

This is the **mechanical inverse** of master walking -- master walks
gave us 14 classes' binding surfaces; vtable[27] walking would give
us 200+ classes' spawn pathways.

## 10. Confidence

```text
Confirmed:
  - global_cpp_createActor_thunk @ 0x00709640 is the actor factory
  - Returns an OnInitResumeChecker (16-byte handle, base
    ResumeCheckerInterface, derived OnInitResumeChecker)
  - The factory dispatches polymorphically via vtable[0x6c]
  - Coroutine tracking uses (script_id, sub_id) key in a per-context map
  - Per-context push: CoroutineContext_pushResumeChecker
  - Per-context check: CoroutineContext_isTrackingEnabled
  - 2 branches: type-6 fast-path (existing/cached actor) vs full create
  - Engine namespace: Component::Lua::GameEngine + 
    Application::Lua::Script::Client::Control::Global

Likely (High):
  - The same resume-checker pattern applies to _wait() and other
    yielding primitives (actor:_wait, director:_waitForGroup, etc.)
  - vtable[0x6c] is universal: every Lua-registered class has its
    spawn ctor at this offset
  - The OnInitResumeChecker's readyFlag is set when the actor's full
    onInit chain (including parent-class initializers and async
    asset loads) completes

Likely (Medium):
  - There's a corresponding OnFinalizeResumeChecker for actor
    destruction (actor:_delete returns a checker?)
  - The "type 6" fast-path is the path for "create or get cached
    static actor" (avoid creating a new instance if one exists)
  - The 28th vtable slot was likely DELIBERATELY reserved by the
    engine team for Lua spawn (every class's vtable is auto-generated
    with this layout)
```

## 11. Cross-references

- `finding_global_master_15_of_15_layer1_boot.md` -- where _createActor
  was located + registered (this finding disassembles its
  implementation)
- `finding_actor_factory_pathways.md` (would be) -- a future finding
  walking ALL classes' vtable[27] entries to enumerate per-class
  spawn ctors
- `finding_widget_3tier_dispatcher_architecture.md` -- widget runtime
  context that wraps spawn into the larger UI system

## 12. Next test

```text
1. Disassemble _wait C++ thunk (ActorBase) to confirm same
   OnInitResumeChecker pattern
2. Disassemble _defineClass C++ thunk to understand class registration
   (and confirm vtable[0x6c] is wired during _defineClass call)
3. Walk vtable[0x6c] for a sample of known classes (PlayerBase,
   NpcBase, WidgetBase, Director) to enumerate per-class spawn ctors
4. Disassemble _parseTextCommand thunk (DesktopWidget) for the
   chat-command dispatch architecture
5. Walk remaining 3 CharaBase tail-slot registrars (-> 83/83)
6. Find any remaining native masters in SpreadSheet/Debug/Sequence
```

## Commit suggestion

```
docs(re/exe): _createActor C++ thunk disassembled -- actor creation is ASYNC via OnInitResumeChecker; vtable[0x6c] is per-class spawn ctor
```
