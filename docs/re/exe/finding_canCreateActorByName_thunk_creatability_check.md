# Finding: `_canCreateActorByName` Thunk -- Creatability Pre-check + 3 Non-Createable Category Tags

**Bonus class-system thunk closed.** The `_canCreateActorByName`
Lua binding implements a creatability pre-check: looks up a class
by name in the registry and returns TRUE only if it's a creatable
category. Discovered alongside `_isInstanceOf` walk.

This brings the **class-system thunk family to 4 confirmed thunks**:
- `_defineClass` (registers class)
- `_createActor` (instantiates)
- `_isInstanceOf` (type-checks via dual dispatch)
- `_canCreateActorByName` (pre-checks creatability) -- NEW

## 1. Thunk identification

```text
Registrar:   global_registerLua_canCreateActorByName @ 0x00753320
Thunk:       global_canCreateActorByName_thunk_creatabilityCheck
             @ 0x006ff1a0
Bound name:  "_canCreateActorByName"
Args:        className (string)
Returns:     bool
Lua usage:   if _canCreateActorByName("PartyCharaActor") then
               actor = _createActor("PartyCharaActor", ...)
             end
```

## 2. Dispatch chain

```text
_canCreateActorByName(className):
  │
  ├─ Read className from Lua stack
  │
  ├─ ClassRegistry_lookupAndCheckCategoryTag_wrapper(this+4, name)
  │    └─ ClassRegistry_lookupAndCheckCategoryTag(this, name)
  │        ├─ ClassRegistry_lookupOrErrorPending(this, name, '\0')
  │        │    → returns class_entry* or NULL
  │        ├─ if NULL: return 0
  │        └─ ClassEntry_isInNoncreatableCategorySet_3tags(entry)
  │            → returns 1 if entry[+0x08] ∈ {DAT_0130d4fc,
  │                                            DAT_0130d500,
  │                                            DAT_0130d504}
  │            → returns 0 otherwise
  │
  ├─ INVERT: returns TRUE iff inner returned 0
  │
  └─ Push bool to Lua stack
```

## 3. The 3 non-createable category tags

```text
class_entry[+0x08] = category tag

Special tags (returns "non-creatable" if matched):
  DAT_0130d4fc   ← tag A (likely abstract root, e.g., ActorBase)
  DAT_0130d500   ← tag B (likely singleton, e.g., WorldMaster)
  DAT_0130d504   ← tag C (likely engine-spawned, e.g., Director)

Any other tag value → createable.
```

The exact semantics of each DAT require an xref walk to whoever
WRITES those constants (likely the class registration code in
`_defineClass` path that assigns category tags based on registration
flags).

## 4. Why this thunk exists (vs just letting _createActor fail)

```text
EXPECTED USE PATTERN:

  -- BAD pattern (lets createActor fail with error):
  local actor = _createActor("WorldMaster", ...)  -- engine error

  -- GOOD pattern (checks first):
  if _canCreateActorByName("MyClass") then
    local actor = _createActor("MyClass", ...)
  else
    -- handle: class abstract / singleton / unknown
  end
```

This is the **defensive type-system primitive**: lets script code
gracefully handle class names that may have changed across patches
or that may be conditionally registered.

## 5. Updated class-system thunk family (4 thunks)

```text
Thunk                       Address         Bound name              Role
-----                       -------         ----------              ----
_defineClass                0x006e4d20      "_defineClass"          Register class into parent chain
_createActor                0x006e1700      "_createActor"          Instantiate via vtable[0x6c]
_isInstanceOf               0x006ff210      "_isInstanceOf"         Dual-dispatch type check
_canCreateActorByName       0x006ff1a0      "_canCreateActorByName" Creatability pre-check (NEW)
```

Together these 4 thunks form the **complete Lua class system**
exposed to script code. No additional class-management thunks
exist in the searched function space.

## 6. Cross-references

- `finding_isInstanceOf_thunk_dual_dispatch_rtti_plus_luachain.md`
  -- sister thunk discovered in the same walk
- `finding_createActor_thunk_async_actor_factory.md`
  -- the thunk this pre-check guards
- `finding_defineClass_thunk_class_registration.md`
  -- where class entries (and their +0x08 tags) are created
- `ClassRegistry_lookupOrErrorPending` -- already-named registry
  lookup helper used by both _canCreateActorByName and other thunks

## 7. Renames applied

```text
0x006ff1a0  FUN_006ff1a0   → global_canCreateActorByName_thunk_creatabilityCheck
0x00cc7200  FUN_00cc7200   → ClassRegistry_lookupAndCheckCategoryTag_wrapper
0x00cd9c60  FUN_00cd9c60   → ClassRegistry_lookupAndCheckCategoryTag
0x00ce16c0  FUN_00ce16c0   → ClassEntry_isInNoncreatableCategorySet_3tags
```

Plus decompiler comments at 0x006ff1a0 and 0x00ce16c0 documenting
the creatability check semantics.

## 8. Server implications

```text
Pure client-side dispatch. Server has NO involvement.

But: the 3 non-createable category tags tell us about CLASS DESIGN:
- Some classes are abstract roots (don't instantiate directly)
- Some classes are singletons (already exist)
- Some classes are engine-spawned (Director by quest system,
  not by Lua script)

Server-side parallel: when designing spawn opcodes, server
should know which classes are SPAWNABLE by spawn opcode vs
which are spawned implicitly (WorldMaster on zone enter,
Director on quest start, etc.).
```

## 9. Confidence

```text
Confirmed:
  - FUN_006ff1a0 is _canCreateActorByName binding (registrar evidence)
  - 5-function dispatch chain mapped end-to-end
  - 3 category-tag DAT constants identified at 0x0130d4fc/0x0130d500/0x0130d504
  - Inversion logic (returns TRUE iff class is creatable) confirmed
  - Renames + decompiler comments applied to 4 functions

Likely (High):
  - The 3 tags represent: abstract root / singleton / engine-managed
  - Tags are assigned at class registration time via flags passed to _defineClass

Speculative:
  - Exact tag-to-meaning mapping requires xref walk to constant writers
  - There may be additional creatability-related flags beyond the 3 tags
```

## 10. Next test

```text
1. Xref walk to DAT_0130d4fc, DAT_0130d500, DAT_0130d504 to find
   their initializers (will reveal which classes are categorized
   into which tag)
2. Trace _defineClass to see how the category tag is determined at
   registration time
3. Sample Lua calls to _canCreateActorByName to see which classes
   are commonly checked (validates real-world usage pattern)
```

## Commit suggestion

```
docs(re/exe): _canCreateActorByName thunk -- creatability pre-check + 3 non-createable category tags; class-system thunk family now 4 complete
```
