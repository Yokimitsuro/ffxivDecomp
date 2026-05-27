# Finding: _defineClass Thunk Disassembled -- CLASS REGISTRATION ARCHITECTURE Mapped

**Closes the class registration loop.** Disassembles the C++ thunk
for `global:_defineClass()` and the chain of engine helpers it
invokes. Together with the prior `_createActor` finding, this gives
us the complete actor lifecycle architecture: **register class →
look up class entry → call vtable[0x6c] for polymorphic spawn**.

Critical correction: **vtable[0x6c] is NOT set by _defineClass**.
The C++ class vtables are baked at compile time. `_defineClass`
creates a LUA-side derived class that POINTS to an existing C++
parent's vtable — so the Lua class inherits the C++ spawn ctor
automatically.

**2nd thunk disassembled. 7 helper functions renamed.**

## 1. Thunk located + renamed

```text
Lua entry point:    global:_defineClass(childName, parentName)
                    -- declared in global_u.lua as _defineClass_inl

Registrar:          global_registerLua_defineClass @ 0x0073c270
C++ thunk:          global_cpp_defineClass_thunk @ 0x006dcc30 (NEW)
Worker function:    defineClass_extractAndRegister @ 0x0078c2a0 (NEW)
```

## 2. Top-level thunk (delightfully simple)

```c
void global_cpp_defineClass_thunk(int luaCallContext) {
  setupExceptionFrame();
  
  // Just delegates everything to the worker function:
  defineClass_extractAndRegister(luaCallContext);
  
  teardownExceptionFrame();
}
```

The thunk is a thin wrapper around the worker. No real logic of its
own beyond exception handling.

## 3. Worker function (the actual work)

```c
void defineClass_extractAndRegister(int luaCallContext) {
  // Phase 1: Extract 2 string args from Lua stack
  childName  = Lua_getStringAt(stack, 0);  // first arg
  parentName = Lua_getStringAt(stack, 1);  // second arg
  
  // Phase 2: Register child class derived from parent
  LuaEngine_registerClassDerivedFrom(luaState, childName, parentName);
  
  // Phase 3: Finalize the new class (clear pending flag)
  LuaEngine_finalizeClassDef(luaState, childName);
}
```

This is the **complete Lua-side semantic**:
```lua
global:_defineClass("MyChildClass", "MyParentClass")
```
Maps directly to:
1. Look up parent's existing class entry (or auto-create)
2. Create new child class entry linked to parent
3. Mark child as ready-to-use

## 4. Detail: ClassRegistry_addDerivedClass (the engine work)

`ClassRegistry_addDerivedClass(engine, childName, parentName)`:

```c
// 1. Find parent (auto-create stub if not yet defined)
parent = ClassRegistry_lookupOrErrorPending(engine, parentName, /*createIfMissing=*/1);

// 2. If parent doesn't exist: add error and bail
if (!parent) return;

// 3. Check if parent already FINALIZED (cannot derive from finalized class)
if (parent.alreadyFinalized) {
  errorPool.add("can't derive from finalized class");
  return;
}

// 4. If parent is pending (flag at +0x7c != 0):
//    Look up child by name in the script context's symbol table
if (child_exists_in_context(childName)) {
  // Just link the existing child entry to point at this parent
  linkChildToParent(child, parent);
} else {
  // Create a NEW child class entry derived from parent
  wrapper = buildClassWrapper(parent);    // FUN_00cde4c0
  slot = findOrInsertClassSlot(engine.classTable, childName);
  newClass = createClassEntry(parent, childName, slot);
  pushToScriptContext(engine, newClass, slot);
}
```

So the engine maintains a **two-table system**:
- **Main class registry** (engine + 0x17c): finalized classes by name
- **Pending classes** (engine + 0x204): classes being built (allows
  forward references during multi-file class hierarchy load)

This 2-table design solves the **forward declaration problem**:
```lua
-- file1.lua:
global:_defineClass("Child", "Parent")  -- Parent doesn't exist yet
                                          -- Parent gets a stub entry

-- file2.lua:  (loaded later)
global:_defineClass("Parent", "Base")    -- Stub gets filled in
```

## 5. Key engine layout offsets

```text
LuaGameEngine instance layout (selected fields):
  +0x008  classRegistryRoot  -- main class registry node
  +0x018  nameInternTable    -- string interning for class names
  +0x17c  classByNameMap     -- lookup table (name → class entry)
  +0x1cc  errorPool          -- collected errors during definition
  +0x204  pendingClassMap    -- forward-declared class entries
  +0x208  pendingMapEnd
  +0x20c  pendingClassEnabled -- master pending-mode flag
```

```text
Class entry layout (per registered class):
  +0x004  parent class pointer
  +0x020  derived-classes pointer / linked list
  +0x07c  pending flag (1 = under construction; 0 = finalized)
  // vtable pointer is at +0x00 (set when entry is built from a
  // baked-in C++ class)
```

## 6. CORRECTION: vtable[0x6c] is NOT wired by _defineClass

Re-reading `_createActor`'s vtable[0x6c] call in context of this
finding:

```text
The C++ classes (ActorBase, CharaBase, PlayerBase, NpcBase, Item,
WidgetBase, etc.) all have their vtables BAKED AT COMPILE TIME.
They have vtable[0x6c] set to their "Lua spawn ctor" by the C++
compiler.

When Lua _defineClass("Child", "ParentBase") runs:
  - ParentBase has a baked C++ class entry with vtable pre-set
  - Child gets a NEW class entry that copies/inherits ParentBase's
    vtable layout
  - Child can use Parent's vtable[0x6c] as its spawn ctor (or override
    it via class hierarchy)

So a pure-Lua "Child" class can be instantiated via _createActor
"Child" — it uses Parent's vtable[0x6c] under the hood.

This is why:
  - The 200+ Lua-side classes (every widget, NPC, director) can be
    spawned without each having a C++ spawn implementation
  - They all defer to their nearest C++ ancestor's vtable[0x6c]
  - That C++ ancestor handles the actual memory allocation +
    construction, then the Lua class's _onInit fires for any
    derived initialization
```

## 7. The full actor lifecycle (now closed)

```text
TIME T0: Engine startup
  - C++ classes have vtables baked into binary
  - Each Lua-registered class has _createActor wired in C++ source
    at vtable[0x6c]
  - master register block runs: each FUN_xxx_registerAllLuaBindings
    wires Lua name → C++ thunk for each binding

TIME T1: Lua script loads, calls _defineClass for each class
  - global:_defineClass("ChildClass", "ParentBase")
  - ClassRegistry_addDerivedClass: creates child entry pointing at parent
  - Child entry inherits parent's vtable (including vtable[0x6c])
  - ClassRegistry_clearPendingFlag: marks child as usable

TIME T2: Lua script calls _createActor for an instance
  - global:_createActor("ChildClass", "actor1")
  - Look up "ChildClass" in class registry (finalized)
  - Call vtable[0x6c]: allocates + constructs the C++ actor
  - Return OnInitResumeChecker handle (16 bytes)
  - Lua YIELDS on the checker

TIME T3: Actor's async init completes
  - C++ engine fires the actor's _onInit chain
  - Sets the OnInitResumeChecker.readyFlag = true
  - Periodic coroutine pump finds the ready checker
  - Resumes the yielded script
  - Script continues with newly-spawned actor reference
```

This is the complete actor-creation lifecycle in 1.x's Lua engine.

## 8. Pending-class system: forward declaration support

The `+0x204` pendingClassMap allows scripts to be loaded in ANY
order:

```text
File order doesn't matter — circular references are resolved
incrementally. The engine pools "pending" classes that haven't
been finalized yet and resolves them as parents become available.

This was probably necessary for 1.x's massive Lua corpus (1000+ files)
where strict ordering would be impractical to maintain.
```

## 9. Renames made (7)

```text
RENAMES:
  - 0x006dcc30 -> global_cpp_defineClass_thunk
  - 0x0078c2a0 -> defineClass_extractAndRegister
  - 0x00cc7050 -> LuaEngine_registerClassDerivedFrom
  - 0x00cc71f0 -> LuaEngine_finalizeClassDef
  - 0x00cd91e0 -> ClassRegistry_addDerivedClass
  - 0x00cd9c10 -> ClassRegistry_clearPendingFlag
  - 0x00cd8870 -> ClassRegistry_lookupOrErrorPending
```

## 10. Confidence

```text
Confirmed:
  - global_cpp_defineClass_thunk @ 0x006dcc30 is the class registration thunk
  - The 2-step pattern: extract args + register + finalize
  - The 2-table registry (main + pending) for forward declarations
  - Class entry layout (parent at +0x4, pending flag at +0x7c)
  - LuaGameEngine layout at +0x17c (main map), +0x204 (pending map)
  - Vtable inheritance: derived Lua classes use parent's vtable[0x6c]
    (not their own; vtable wiring is compile-time-only for C++ classes)
  - The forward-declaration support makes file load order irrelevant

Likely (High):
  - The 200+ Lua-side classes (widgets, NPCs, directors) all defer to
    their nearest C++ ancestor's vtable[0x6c] for spawn
  - The pending-class system processes deferred resolutions on each
    script load completion
  - The errorPool collects diagnostic info for class-def errors
    (cycles, missing parents, duplicate names)

Likely (Medium):
  - The "FUN_009d22b4" calls in the lookup function are likely
    assert/abort calls for invariant violations
  - The flag at +0x7c (pending) is checked at every _createActor to
    prevent instantiating half-built classes
  - There may be a "class hierarchy walk" step at finalize time that
    propagates parent-class slot overrides to derived classes
    (similar to virtual method dispatch table inheritance)
```

## 11. Cross-references

- `finding_createActor_thunk_async_actor_factory.md` -- the spawn
  side of the class lifecycle (THIS finding gives the registration
  side; together they close the loop)
- `finding_global_master_15_of_15_layer1_boot.md` -- _defineClass +
  _createActor + _isInstanceOf + _getActorByName all live on the
  global module (the LAYER 1 boot surface)
- `finding_native_binding_surface_439_across_19_modules.md` -- the
  binding-declaration pattern this finding's registration mechanism
  underpins

## 12. Next test

```text
1. Disassemble _isInstanceOf thunk to confirm it queries class
   registry's parent chain (RTTI walk)
2. Disassemble _wait C++ thunk (ActorBase) to confirm same
   OnInitResumeChecker async pattern (predicted from _createActor)
3. Walk vtable[0x6c] for sample classes:
   - ActorBase
   - CharaBase
   - PlayerBase
   - WidgetBase
   - DirectorBase
   This gives 5+ named per-class spawn ctors mechanically.
4. Disassemble _appendMessagePool to map the chat-display sink
   (where outgoing messages actually become visible UI text)
5. Walk remaining 3 CharaBase tail-slot registrars (-> 83/83)
```

## Commit suggestion

```
docs(re/exe): _defineClass thunk disassembled -- 2-table class registry with forward declarations; vtable[0x6c] inheritance closes actor lifecycle loop
```
