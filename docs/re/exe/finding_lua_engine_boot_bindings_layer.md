# Finding: LuaGameEngine Boot Bindings Layer -- 11 Global Functions + Embedded Bootstrap Script

Locates and characterizes the engine function that installs the
**bottom-most layer of global Lua bindings** at startup. The function
embeds a small Lua bootstrap script that replaces `require` with an
engine-controlled version and disables `collectgarbage`.

This finding does NOT yet locate `_createActor` / `_defineClass`
(those are installed in a SEPARATE function above this layer), but it
characterizes the foundation that everything else builds on.

## 1. LuaGameEngine_installBootBindings (FUN_00cd8990)

Called from the engine init chain (`FUN_00cd9e80`, which allocates
a 0x10c-byte engine config struct first):

```text
FUN_00cd9e80 (engine init):
  1. operator_new(0x10c)  -- allocate engine config
  2. FUN_00d0c870 -- initialize config
  3. LuaGameEngine_installBootBindings
       -- install foundational Lua bindings (this finding)
```

## 2. The embedded Lua bootstrap script

Loaded via `luaL_loadbuffer` and executed in the Lua VM:

```lua
require = nil

function require(filename, listener, errorNotify)
  if _luaGameEngineRequire(filename, listener, errorNotify) == true then
    _luaGameEngineLoad(filename, listener)
  end
  _luaGameEngineRequireEnd()
end

function __lge_isAlive()
  return false
end

function __lge_returnNil()
  return nil
end

collectgarbage = nil
```

Key observations:
- **`require` is REPLACED** with an engine-controlled version that
  routes through 3 native C functions
- **`collectgarbage` is DISABLED** — the engine manages Lua VM memory
  via its own allocator, not Lua's GC
- 2 helper stubs: `__lge_isAlive` (returns false; placeholder for
  liveness check) + `__lge_returnNil` (returns nil; placeholder for
  default handler)

The custom `require` flow:
1. Call `_luaGameEngineRequire(filename, listener, errorNotify)` 
   -- engine checks if the script needs loading
2. If returns true: call `_luaGameEngineLoad(filename, listener)`
   -- engine loads + executes the script
3. Always: call `_luaGameEngineRequireEnd()` -- cleanup

This explains why we never see Lua loading errors -- the engine
intercepts every require and handles loading internally.

## 3. The 11 boot-bindings registered

Installed via `lua_pushcfunction` + `lua_setglobal`-equivalent pattern
(FUN_00cf3360 pushes name string, FUN_00cf32e0 pushes C function +
sets):

```text
Lua name                       C function (FUN_*)       Renamed
--------                       -----------                -------
_luaGameEngineRequire          0x00d08a10                lua_luaGameEngineRequire
_luaGameEngineLoad             0x00d08180                lua_luaGameEngineLoad (existing)
_luaGameEngineRequireEnd       0x00d08e50                lua_luaGameEngineRequireEnd (existing)
__lge_getWork                  0x00d094a0                lua_lge_getWork
assert                          0x00d08ed0                lua_lge_assert
error                           0x00d090c0                lua_lge_error
(DAT_0110e850 = "print"?)       0x00d09240                (not yet renamed)
_pcall                         0x00d093b0                lua_lge_pcall
                                                          (also: pcall rebound to _pcall)
_time                          0x00d082a0                lua_lge_time_or_clock
_clock                         0x00d082a0                lua_lge_time_or_clock (SAME FN)
__lge_setLoopInterval          0x00d083b0                lua_lge_setLoopInterval
__lge_syncById                 0x00d09810                lua_lge_syncById
__lge_getIndividualIndex       0x00d098d0                lua_lge_getIndividualIndex
__newindex                     0x00d099b0                lua_metatable_newindex_handler
```

Note: `_time` and `_clock` are bound to the SAME function -- the
engine doesn't distinguish wall-clock vs monotonic time at the boot
layer.

## 4. The metatable setup

Before the boot bindings, the engine sets up the GLOBAL METATABLE
with these hooks:

```text
Metatable key            Function bound
-------------            --------------
__index                   FUN_00d085b0    -- "read" missing globals
__newindex                FUN_00d07eb0    -- "write" globals (different
                                            from the boot binding above)
DAT_0110eab8              FUN_00d08890    -- ?
DAT_0110eaac              FUN_00d08070    -- ?
_onLoop                   (no fn ptr)     -- key reserved
```

The "Read" hook (`__index` at 0x00d085b0) is what fires when Lua code
references an undefined name -- the engine can lazy-load the binding
on demand.

The "Write" hook (`__newindex` at 0x00d07eb0) is different from the
`__newindex` boot binding (lua_metatable_newindex_handler at
0x00d099b0). They likely operate on DIFFERENT tables -- one for the
main `_G` table, one for a sub-namespace.

## 5. The "actor bindings" layer is SEPARATE

The boot bindings layer installs ONLY the foundational functions
needed for `require` to work. The HIGHER-LEVEL bindings used by the
content corpus (e.g. `_createActor`, `_defineClass`, `_defineBaseClass`,
`_getActorByName`, `_isInstanceOf`, etc.) are installed in a
SEPARATE function not yet located.

Probable separation:
- BOOT LAYER (this finding): `require` + math/string lib + basic
  utilities (assert/error/print/pcall/time)
- ACTOR/CLASS LAYER (TBD): `_createActor` + `_defineClass` +
  `_getActorByName` + `_isInstanceOf` + actor metamethods
- DOMAIN LAYER (TBD): `_getQuestActorForCutSceneReplay` +
  `_prepareAllCommandStaticActor` + game-specific globals

The actor/class layer is likely installed AFTER the engine config is
fully bootstrapped, possibly by the `LpbLoader` (Lua Pre-built
loader) for compiled binary chunks.

## 6. The 22 global Lua bindings found in scripts

Cross-referenced from the corpus:

```text
Class system (LAYER 2):
  _defineClass         _defineBaseClass    _isInstanceOf

Actor management (LAYER 2):
  _createActor         _canCreateActorByName
  _getActorByName      _getStaticActor      _isExistStaticActor
  _isExistActor        _getQuestActorForCutSceneReplay
  _prepareAllCommandStaticActor

Domain helpers (LAYER 3):
  _getTutorialJudge    _getLanguage        _getUTF
  _normalizeDisplayName  _replaceMacroCodeString
  _progFunc

Standard library namespaces (always available):
  _G                   _math   _string   _table
```

The class system + actor management is LAYER 2 (after boot). The
domain helpers (LAYER 3) are likely registered even later, perhaps
per game-state.

## 7. Server design implications

```text
For a server emitting Lua-triggering events:

  ALL DIRECTORS spawn through the LAYER 2 `_createActor` binding.
  Server must somehow trigger client-side `_createActor` calls --
  this is likely done via a WIRE OPCODE that the client routes to
  the Lua VM (NamedActor spawn opcode, TBD).
  
  The `require` system is engine-controlled, so server can REQUEST
  a specific Lua module to be loaded by sending a "load script"
  command (server tells client to require a specific path).
  
  The `_pcall` (engine pcall) wraps every Lua function call with
  error handling. If a quest script crashes, the engine prevents
  it from taking down the whole client.
  
  The `_time` / `_clock` are unified -- server-driven content can
  use these for timing without worrying about clock drift.
```

## 8. Annotations made in Ghidra

```text
RENAMES (10):
  - 0x00cd9e80 -> (not renamed)
  - 0x00cd8990 -> LuaGameEngine_installBootBindings (already named)
  - 0x00d08a10 -> lua_luaGameEngineRequire
  - 0x00d094a0 -> lua_lge_getWork
  - 0x00d083b0 -> lua_lge_setLoopInterval
  - 0x00d09810 -> lua_lge_syncById
  - 0x00d082a0 -> lua_lge_time_or_clock
  - 0x00d08ed0 -> lua_lge_assert
  - 0x00d090c0 -> lua_lge_error
  - 0x00d093b0 -> lua_lge_pcall
  - 0x00d098d0 -> lua_lge_getIndividualIndex
  - 0x00d099b0 -> lua_metatable_newindex_handler
```

## 9. Confidence

```text
Confirmed:
  - LuaGameEngine_installBootBindings is the engine's Lua boot
    function
  - It loads an embedded Lua bootstrap script via luaL_loadbuffer
  - `require` is REPLACED with an engine-controlled version
  - `collectgarbage` is DISABLED (engine manages memory)
  - 11 boot bindings registered (verified by string + fn pairs in
    the decomp)
  - `_time` and `_clock` are bound to the SAME function
  - The metatable hooks (__index / __newindex) are set up before
    boot bindings

Likely (High):
  - The 22 global Lua functions found in the corpus span 3 layers
    (boot + actor/class + domain)
  - The actor/class layer (`_createActor`, etc.) is installed by
    a separate function called AFTER boot
  - The `require` chain (Require -> Load -> RequireEnd) is the
    engine's hook for managing module loading state
  - The `__lge_*` private namespace functions are for engine
    internal use only (not called from script code)

Likely (Medium):
  - The 3-layer separation is for memory budget control (engine
    can lazy-load classes only when needed)
  - The `_pcall` re-binding (pcall -> _pcall) prevents Lua's
    standard pcall from being called -- the engine version
    adds tracing/error reporting
  - DAT_0110e850 is likely "print" (the only standard global I
    don't see explicitly bound)

Speculative:
  - The actor/class layer (`_createActor`, etc.) is installed
    by LpbLoader_loadIntoLuaState (the LPB binary chunk loader)
  - The domain layer is installed per-content-load (e.g., when
    a director is spawned, its specific helpers get registered)
```

## 10. Cross-references

- `finding_director_judge_purely_lua_no_exe_bridge.md` -- Directors
  use `_createActor` (LAYER 2, not yet located)
- `finding_director_state_machine_concrete_patterns.md` -- concrete
  example showing the require/spawn flow
- `finding_invokeLua_roster_closed_80_complete.md` -- Paradigm 1
  callbacks (orthogonal to this finding)
- `finding_widget_baseclass_architecture_and_194_widgets.md` --
  Widgets ARE Actor instances created via the unlocated LAYER 2 binding

## 11. Next test

```text
1. Find the function that installs LAYER 2 bindings
   (_createActor, _defineClass, _getActorByName)
   -- search for "_createActor" string xrefs in EXE
   -- check LpbLoader_loadIntoLuaState
2. Find DAT_0110e850 (likely "print") to confirm
3. Walk lua_luaGameEngineRequire to see how require resolution works
   (path canonicalization, module caching)
4. Walk lua_lge_pcall to see what engine-specific error reporting it adds
```

## Commit suggestion

```
docs(re/exe): LuaGameEngine boot bindings layer -- 11 globals + embedded bootstrap script
```
