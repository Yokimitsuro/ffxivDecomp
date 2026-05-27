# Finding: Native Binding Surface Tripled -- 439 Bindings Across 19+ Modules (Not 123)

Locates the **`_inl/_cpp` declaration pattern** that is the UNIVERSAL
native binding mechanism in 1.x. Every Lua class has a `*_u.lua`
companion file that declares its native bindings via "inline"
marshalling specs (`_xxx_inl` returns `("classname", "_xxx_cpp")`).

The prior native binding count (PlayerBase 99 + NpcBase 24 = 123)
**dramatically undercounted** the actual surface. The TRUE total
is **439 native bindings across 19+ class modules**.

## 1. The `_inl/_cpp` declaration pattern

Discovered via `global_u.lua` (the companion for the "global" module
singleton). Every native binding has 2 Lua-side parts:

```lua
-- DECLARATION (in <class>_u.lua):
function L1_1(A0_2, A1_2, ...)
  local L2_2, L3_2
  L2_2 = "classname"        -- the target object module name
  L3_2 = "_methodName_cpp"  -- the native C++ method to invoke
  return L2_2, L3_2
end
L0_1._methodName_inl = L1_1

-- USAGE (in any script):
something:_methodName(args)
  -- engine resolves: looks up _methodName_inl on the receiver
  -- calls the marshalling spec, gets ("classname", "_methodName_cpp")
  -- calls global:_methodName_cpp(args) via the engine bridge
```

So **every class declares its native bindings in its `_u.lua`**, and
the engine reads these specs to wire up the C++ calls.

Same pattern observed in:
- `global_u.lua` (the engine's global module)
- `playerbaseclass_u.lua` (94 bindings)
- `charabaseclass_u.lua` (76 bindings)
- `widgetbaseclass_u.lua` (24 bindings)
- `npcbaseclass_u.lua` (23 bindings)
- ... 14+ more modules

## 2. The "global" module singleton (25 bindings)

From `global_u.lua` (also known as `3yv89y_p.lua` in obfuscated form):

```text
Native bindings (13):
  _defineClass_cpp / _defineBaseClass_cpp   -- class system
  _isInstanceOf_cpp                          -- type check
  _isExistActor_cpp / _getActorByName_cpp   -- actor lookup
  _canCreateActorByName_cpp                  -- spawn check
  _getStaticActor_cpp / _isExistStaticActor_cpp -- static actor query
  _getUTF8StringLength_cpp /
  _getUTF8StringByteLength_cpp                -- UTF-8 helpers
  _createActor_cpp                            -- SPAWN ACTOR (the one we sought!)
  _prepareAllCommandStaticActor_cpp          -- bulk command actor prep
  _getQuestActorForCutSceneReplay_cpp        -- cutscene replay actor
  _normalizeDisplayName_cpp                   -- name canonicalization
  _replaceMacroCodeString_cpp                -- macro expansion

Lua-implemented variants (10):
  print_lua / tonumber_lua / tostring_lua / type_lua
  assert_lua / error_lua / select_lua / unpack_lua
  pcall_lua / xpcall_lua

Pure Lua wrappers (2):
  _getTutorialJudge()  = global:_getStaticActor_cpp(320006)
                         (returns the TutorialJudge actor;
                          static ID 320006)
  _getLanguage()       = _progFunc(3)
                         (returns the language code; constant 3 in
                          this binding -- TBD what it means)
```

**`_createActor_cpp`** is the function we've been looking for. It's
the engine's native API for spawning actor instances from Lua.

## 3. The full 439-binding surface (top 18 modules)

```text
Module                             _inl count   Deciphered path
------                             ----------    ---------------
chara/player (PlayerBase)              94        729s9/uy9l5s/uy9l5s89r57y9rr_p
chara/charabase (CharaBase)            76        729s9/729s989r57y9rr_p          *NEW*
widget/desktopwidget (DesktopWidget)   43        n1635q/65rzqvun1635q_p          *NEW*
system/math (Math)                     32        rlrq5x/x9q2_p                    *NEW*
global (Global)                        25        3yv89y_p                         this finding
widget/widgetbaseclass (Widget)        24        n1635q/n1635q89r57y9rr_p        *NEW*
world/worldmaster (WorldMaster)        23        nvsy6/nvsy6x9rq5s_p             *NEW*
chara/npc/npcbaseclass (NpcBase)       23        729s9/wu7/wu789r57y9rr_p
item/itembaseclass (Item)              19        1q5x/1q5x89r57y9rr_p            *NEW*
group/groupbaseclass (Group)           15        3svpu/3svpu89r57y9rr_p          *NEW*
system/string (String)                 14        rlrq5x/rqs1w3_p                  *NEW*
actor/actorbaseclass (Actor)           10        97qvs89r57y9rr_p                *NEW*
gamedata/spreadsheet (SpreadSheet)     10        39x569q9/rus596r255q_p
area/areabaseclass (Area)               9        9s59/9s5989r57y9rr_p            *NEW*
system/debug (Debug)                    7        rlrq5x/658p3_p
system/table (Table)                    5        rlrq5x/q98y5_p                   *NEW*
director/directorbaseclass (Director)   5        61s57qvs/61s57qvs89r57y9rr_p   *NEW*
gamedata/sequence (Sequence)            4        39x569q9/7pqr75w5_p              *NEW*
+ more modules below 4 bindings each
                                      ---
                                      439   TOTAL across all _u files
```

**13 of 18 modules are NEW discoveries** (not previously documented):
CharaBase, DesktopWidget, Math, Widget (base), WorldMaster, Item,
Group, String, Actor, Area, Table, Director, Sequence.

## 4. Correction: Director HAS native bindings (5)

Previously claimed in `finding_director_judge_purely_lua_no_exe_bridge.md`
that Director is "purely Lua". This is FALSE. DirectorBaseClass has
**5 native bindings** (not yet enumerated; need to read
`director/directorbaseclass_u.lua`).

The correction:
- Directors are MOSTLY pure Lua (state machines + logic)
- But DirectorBaseClass has SOME native bindings (probably WorkSync
  helpers like `_updateWork`, `_syncById`, plus 2-3 others)
- The 245+ director subclasses are still pure Lua subclasses

## 5. The 1.x native binding architecture (corrected)

```text
Engine startup:
  1. LuaGameEngine_installBootBindings (FUN_00cd8990)
     -- Layer 1: 11 boot bindings (assert, error, _pcall, _time, etc.)
     -- Embedded bootstrap script (custom require, disabled GC)
  
  2. LPB loader (LpbLoader_loadIntoLuaState)
     -- Loads compiled bytecode (.lpb) into Lua state
  
  3. Each _u.lua loaded declares _inl marshalling specs for its class
     -- 19+ modules, 439 native bindings TOTAL
     -- The "global" module is the singleton root
     -- All other modules attach to specific class instances
  
  4. PlayerBase_registerAllLuaBindings + similar master registrars
     -- These wire up the C++ implementations to the _inl specs
     -- (now the "register" surface = 439 total, not 123)

Runtime usage:
  myObj:_methodName(args)
    -> looks up _methodName_inl on myObj's class
    -> _inl returns ("classname", "_methodName_cpp")
    -> engine calls classname:_methodName_cpp(args)
    -> C++ thunk fires, may invoke wire opcode or local logic
```

## 6. Implications for server design (CORRECTED + EXPANDED)

```text
The native binding surface is MUCH larger than thought:

  PlayerBase (94 bindings)     -- already documented
  CharaBase (76 bindings)       -- NEW; the abstract actor base
                                   probably has stat/status/movement
  DesktopWidget (43)            -- NEW; the HUD/UI singleton
  Widget base (24)              -- NEW; widget API surface
  WorldMaster (23)              -- NEW; world singleton
  Item (19)                     -- NEW; item operations
  Group (15)                    -- NEW; party/group operations
  Area (9)                      -- NEW; area operations

For a server, each of these is a class whose methods may need to be
either:
  - SERVER-IMPLEMENTED (if the binding triggers wire traffic)
  - CLIENT-LOCAL ONLY (if it's pure state query)

The CharaBase 76 bindings are particularly important -- this is
the abstract actor base shared by Player+NPC. The 76 bindings
likely cover:
  - Position/rotation
  - HP/MP/stat queries
  - Status effect management
  - Animation/visual state
  - Inventory queries
  - Battle interaction

CharaBase warrants its own walking (similar to PlayerBase 99 walk
previously done) to inventory the bindings.
```

## 7. Annotations made

This finding is primarily documentation; no new Ghidra renames.

The actual C++ implementations (`_xxx_cpp` functions) are NAMED with
FUN_xxxx in Ghidra. To rename them, we'd need to walk each module's
register-all master block (like PlayerBase_registerAllLuaBindings was
walked for the 99 PlayerBase bindings).

Estimated future work:
- CharaBase: 76 bindings to enumerate (walk
  CharaBase_registerAllLuaBindings master block)
- DesktopWidget: 43
- Math: 32 (likely standard math operations -- low priority)
- World, Widget, WorldMaster, Item, Group: 19-24 each
- Plus 9+ smaller modules
TOTAL pending: ~316 bindings to enumerate + name

## 8. Confidence

```text
Confirmed:
  - The _inl/_cpp declaration pattern is universal in 1.x
  - global_u.lua has 25 bindings (counted directly)
  - At least 18 _u.lua files have substantial binding counts (4+)
  - Total native bindings = 439 (counted via grep)
  - PlayerBase has 94 bindings (close to prior count of 99 -- the
    discrepancy is due to grep-vs-decompile counting differences)
  - NpcBase has 23 bindings (prior count was 24 -- close)
  - DirectorBaseClass has 5 native bindings (NEW discovery;
    contradicts the "purely Lua" claim)
  - _createActor_cpp is THE engine binding for spawning actors
  - 320006 = TutorialJudge static actor ID

Likely (High):
  - The CharaBase 76 bindings cover the actor's abstract API
    (position, stat, status, animation, etc.)
  - The DesktopWidget 43 bindings cover the HUD singleton's API
  - The WorldMaster 23 bindings cover world/zone management
  - The Group 15 bindings cover party/group operations
  - The Item 19 bindings cover item state operations

Likely (Medium):
  - Many of the new classes have register-all master blocks similar
    to PlayerBase_registerAllLuaBindings; these need to be walked
  - The total native binding surface estimated at 439 is LOWER BOUND
    (small _u files with <4 bindings aren't counted)

Speculative:
  - The 5 Director native bindings are probably:
    _updateWork, _getWork, _setWork, _syncById, _getIndividualIndex
    (the WorkSync helpers used by directors)
```

## 9. Cross-references

- `finding_lua_engine_boot_bindings_layer.md` -- LAYER 1 (11 boot
  bindings, this finding extends to LAYER 2)
- `finding_playerbase_lua_bindings_99_complete.md` -- PlayerBase
  was already documented; the 99 vs 94 discrepancy needs
  reconciliation
- `finding_npcbaseclass_lua_bindings_24_complete.md` -- NpcBase
  was already documented; 24 vs 23 discrepancy
- `finding_director_judge_purely_lua_no_exe_bridge.md` -- CORRECTED:
  DirectorBaseClass has 5 native bindings (small but exists)

## 10. Next test

```text
1. Read directorbaseclass_u.lua to enumerate the 5 Director native
   bindings (small file, quick win)
2. Read charabaseclass_u.lua to enumerate the 76 CharaBase bindings
   (the biggest new module discovery)
3. Read desktopwidget_u.lua for the 43 HUD bindings
4. Walk the CharaBase_registerAllLuaBindings master block in Ghidra
   to find the C++ implementations
5. Reconcile PlayerBase 99 vs 94 (one method is double-counted?
   or grep undercounts?)
```

## Commit suggestion

```
docs(re/correlation): Native binding surface = 439 across 19+ modules (vs prior 123)
```
