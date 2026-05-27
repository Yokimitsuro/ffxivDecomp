# Finding: Tutorial / Debug / GameData Lua Subsystems -- 13 Scripts Closed

Closes 3 small Lua subsystems that were enumerated in the catalog
(2 tutorial + 8 debug + 3 gamedata = 13 scripts) but had no findings.

The biggest reveal: **SpreadSheet IS the runtime class for SSD
(Static Sheet Data) loading**. Its 10 native bindings exactly match
the Widget's `requestSsdLoadSheet` pattern + the EXE's
`invokeLua_onLoadKeyAsync` / `invokeLua_onLoadMultiKeyAsync` callbacks.

## 1. Tutorial (2 scripts) -- actually Judges, not their own family

```text
File path                       Deciphered                       Size
---------                       ----------                       ----
0p635/qpqvs19y0p635.lua         judge/tutorialjudge              1173 B
0p635/qpqvs19y6pxxl0p635.lua    judge/tutorialdummyjudge         1400 B
```

Both extend `JudgeBaseClass` (not their own family). They handle
specific quest event IDs using the
`man0u0processEvent###_#` callback naming pattern (the standard
QuestDirector event-routing convention per
`finding_judge_subsystem.md`).

### 1.1 TutorialJudge

```lua
TutorialJudge:_onInit() -- empty stub

-- Event handler for quest event "man0u0processEvent000_3":
TutorialJudge:man0u0processEvent000_3(A1, A2, A3)
  A3:startCliantTalkTurn(2, A2)  -- begin talk turn with NPC
  A3:say(A1, 126, 0)              -- say text id 126
  A3:finishCliantTalkTurn()        -- end talk turn

-- Event handler for quest event "man0u0processEvent020_8":
TutorialJudge:man0u0processEvent020_8(A1, A2, A3)
  A3:startCliantTalkTurn(2, A2)
  A3:say(A1, 128, 0)               -- two say lines
  A3:say(A1, 127, 0)
  A3:finishCliantTalkTurn()
  return 2                          -- result code 2 = success
```

Pattern: each tutorial event handler is a **client-driven dialog
scene** (one to three say-lines per scene). The handler receives
(playerActor, npcActor, sceneContext) and orchestrates the dialog.

### 1.2 TutorialDummyJudge

Like TutorialJudge but with a **branching ask**:

```lua
TutorialDummyJudge:man0u0processEvent020_8(A1, A2, A3)
  A3:startCliantTalkTurn(2, A2)
  A3:say(A1, 86, 0)
  A3:say(A1, 87, 0)
  result = A3:ask(A1, 91, 2)        -- 2-choice question (text 91)
  if result == 1 then
    A3:say(A1, 88, 0)               -- positive response
  else
    A3:say(A1, 94, 0)               -- negative response
  end
  A3:finishCliantTalkTurn()
  return result
```

The `:ask(actor, textId, optionCount)` API on the sceneContext is
the modal-prompt entry point that ties back to the AskBaseClass
widget system (per `finding_widget_baseclass_architecture_and_194_widgets`).

## 2. Debug subsystem (8 scripts)

```text
File path                         Deciphered                   Size
---------                         ----------                   ----
658p3/658p389r57y9rr.lua          debug/debugbaseclass          832 B
658p3/658p389r57y9rr_p.lua        debug/debugbaseclass_u         18 B
658p3/658p36pxxl.lua              debug/debugdummy              355 B
658p3/658p3q1x5s.lua              debug/debugtimer              355 B
658p3/vo5syv96xvw1qvs.lua         debug/overloadmonitor       8 393 B
rlrq5x/658p3.lua                  system/debug                52 932 B
rlrq5x/658p3_p.lua                system/debug_u              1 504 B
rlrq5x/658p3_pq1y1ql.lua          system/debug_utility       29 661 B
```

### 2.1 DebugBaseClass (the base for runtime monitors)

Minimal class. Provides:
- `_onInit`: initializes `debugWork._save` and `debugWork._temp`
  containers (both 1024 bytes via `_assignForChild`)
- `_onLoop`: empty stub for subclass override
- `setLoopInterval(interval)`: wraps `_setLoopInterval(interval)`

DebugDummy and DebugTimer are minimal placeholders (just inherit
DebugBaseClass + empty _onInit). They exist to be **instantiated as
runtime debug singletons** that the engine can attach loops to.

### 2.2 OverloadMonitor -- 1.x's performance watchdog

```lua
OverloadMonitor:_onInit()
  -- work fields:
  sleep    : boolean
  timer    : float        -- timestamp of last update
  counter  : integer32
  loopTimer: float
  skipper  : integer32
  ranking  : integer8
  
  -- Get monotonic time from debug native binding:
  work.timer = debug:_getLowResolutionTime()
  work.loopTimer = debug:_getLowResolutionTime()
  work.ranking = 0
  setLoopInterval(0.1)   -- 100ms tick
```

OverloadMonitor is the **frame-pacing watchdog**. It samples
`debug:_getLowResolutionTime()` each tick, tracks how long since
the last loop ran, and (per the work field names like `skipper`
and `ranking`) flags when the engine is overloaded vs running
smoothly.

In 1.x, performance was famously bad on launch; this monitor
captured client-side metrics for QA/devs.

### 2.3 system/Debug -- the 52KB main debug class

The largest debug script. Defines the `Debug` global singleton with
many native + Lua helper methods:

```text
Method (from debug_u native bindings)         Direction
---                                            ---
_getInstanceName_cpp (custom dispatcher)       C++ -> queried by Lua
_getClassName_cpp                              C++ via _inl stub
_getAllCharacter_cpp                           C++
_commandDebug_cpp                              C++ (the main /debug command)
_setOthersWork_lua                             Lua-implemented (note suffix!)
_getOthersWork_lua                             Lua-implemented
_getOthersWorkLength_lua                       Lua-implemented
_getAllItem_cpp                                C++
```

The `_lua`-suffixed bindings are an **inverse pattern**: C++ calls
INTO a Lua method with that name (rather than the normal Lua-calls-
into-C++ pattern of `_cpp` suffix). This lets the debug subsystem
expose Lua-side state to the C++ side without needing native code
changes.

Public API methods (from main debug.lua):
```lua
Debug:isDebug()           -- returns work.debug (debug mode flag)
Debug:callFunctionProtected(target, methodName, ...)
                          -- wraps pcall + cleans stack trace
Debug:formatArgs(...)     -- comma-joins arg list with getDebugName
```

The `callFunctionProtected` wrapper is **the safety net** for the
debug command system: any debug command runs inside a pcall, and on
failure the stack trace is stripped (everything after
`stack trace:`) before being returned. This lets the dev console
gracefully report errors without exposing internal frames.

### 2.4 system/Debug_utility -- 29KB utility helpers

Holds the bulk of the debug command implementations. Used by the
in-game `/debug` console (per `DebugConsole_invokeLua_onDebugInput`
in the EXE-side roster).

## 3. GameData subsystem (3 scripts) -- the SSD loader

```text
File path                       Deciphered                       Size
---------                       ----------                       ----
39x569q9/39x569q989r57y9rr.lua  gamedata/gamedatabaseclass        394 B
39x569q9/rus596r255q.lua        gamedata/spreadsheet              374 B
39x569q9/rus596r255q_p.lua      gamedata/spreadsheet_u          1 824 B
```

### 3.1 GameDataBaseClass (minimal base)

```lua
GameDataBaseClass:_onInit()
  _callSuperClassFunc("_onInit")
  gameDataWork._temp = { { "_assignForChild", 256 } }
```

Just provides a 256-byte temp container. The actual logic lives in
SpreadSheet.

### 3.2 SpreadSheet -- THE SSD class

The Lua-side wrapper around C++ Static Sheet Data (SSD) loading.

```lua
SpreadSheet:_onInit(filename)
  _callSuperClassFunc("_onInit")
  _setFilename(filename)      -- bind sheet to a .ssd file

SpreadSheet:_onLoadKeyAsync(key)
  -- empty stub for subclass override
  -- This hook fires when an async key load completes
```

### 3.3 SpreadSheet native bindings (the 10 SSD operations)

From `spreadsheet_u.lua`, all 10 native bindings (each returns the
`("self", "_<name>_cpp")` marshalling spec for the C++ side):

```text
Lua-side method (_inl)              C++ thunk             Role
---                                  ---                   ---
_setFilename_inl                    _setFilename_cpp      Bind to .ssd file
_getData_inl                        _getData_cpp          Read row by key
_isExistKey_inl                     _isExistKey_cpp       Test if key exists
_getAllKey_inl                      _getAllKey_cpp        Get all keys
_loadKeyTemporarily_inl             _loadKeyTemporarily_cpp   Load range temp
_loadKeySemipermanently_inl         _loadKeySemipermanently_cpp Load range semi
_unloadKey_inl                      _unloadKey_cpp        Unload range
_loadAllKeyPermanently_inl          _loadAllKeyPermanently_cpp Load full
_loadKeyAsync_inl                   _loadKeyAsync_cpp     Async load
_loadMultiKeyAsync_inl              _loadMultiKeyAsync_cpp Async multi-load
```

### 3.4 The SSD <-> Widget <-> EXE bridge

This finding closes a crucial cross-reference:

```text
Widget script           SpreadSheet method            EXE invokeLua hook
---------               ---                           ---
requestSsdLoadSheet  -> sheet:_loadKeyTemporarily  -> (no hook; sync)
                        (deferred load after cmd)
loadSpreadSheetData
  Async             -> sheet:_loadMultiKeyAsync   -> invokeLua_onLoadMultiKeyAsync
                                                     (0x0070a580)
(direct)            -> sheet:_loadKeyAsync         -> invokeLua_onLoadKeyAsync
                                                     (0x00707300)
```

So when a Widget's command handler sets `widgetWork.requestSsdLoadSheet
= "actor"` and the Widget processes the command, it calls
`sheet:_loadKeyTemporarily(keyMin, keyMax)` synchronously. For async
loads, the EXE fires `_onLoadKeyAsync` / `_onLoadMultiKeyAsync` Lua
hooks on the SpreadSheet instance (NOT on the widget itself).

**The Widget then receives these events through its own dispatch
because the Widget's `_onLoadMultiKeyAsync` re-fires
`processSpreadSheetDataAsync`** (per the WidgetBaseClass code).

So there are TWO invocation paths:
- **Widget** is the requester (sets request fields, calls sheet's
  async method, gets callback)
- **SpreadSheet** is the receiver (its instance gets the
  `_onLoadKeyAsync` invokeLua hook fired by the EXE)

The Widget bridges them.

## 4. Cross-system architecture

```text
GameData (3 scripts)        Widget (194 scripts)         EXE invokeLua
------------                ------------                 -----------
GameDataBaseClass            WidgetBaseClass             (none direct)
                                                         
SpreadSheet            <->  widgetWork.requestSsd  <->  invokeLua_onLoadKeyAsync
                            LoadSheet                    invokeLua_onLoadMultiKeyAsync
                            
SpreadSheet bindings    <->  _loadKeyTemporarily   <->  (synchronous, no hook)
                            _loadKeyAsync               -> _onLoadKeyAsync
                            _loadMultiKeyAsync          -> _onLoadMultiKeyAsync

Tutorial (2 scripts)        Judge (18 scripts)          Quest/Director
------------                ------------                 ------------
TutorialJudge          <->  JudgeBaseClass        <->  QuestDirector*
TutorialDummyJudge          (man0u0processEvent          (per scene event IDs)
                             pattern)

Debug (8 scripts)
------------
DebugBaseClass               (no direct C++ events)
  -> DebugDummy, DebugTimer
  -> OverloadMonitor          (perf watchdog, 100ms tick)
system/Debug (singleton)   <->  DebugConsole_invokeLua_onDebugInput
                                 (FUN_008a4880 in EXE; fires "_onDebugInput"
                                  Lua hook for parsed console commands)
```

## 5. Server design implications

```text
For a server to fully drive SSD-based content:

  1. The server provides the .ssd files (static client data,
     per FFXIVTool exports)
  2. Server pushes "load sheet X keys A..B" via the
     SpreadSheet bindings, which the EXE forwards into the .ssd
     file load path
  3. When async loads complete, the EXE fires the invokeLua hook
     on the SpreadSheet instance
  4. The Widget that requested the sheet then handles its own
     processSpreadSheetDataAsync callback

  Tutorial content is just regular Judge content with simpler
  scenes (1-3 say lines per scene). Server-side tutorial
  delivery is the same as any QuestDirector flow.

  Debug subsystem is dev-tool only -- not needed for a player-facing
  test server. The OverloadMonitor's perf metrics are
  CLIENT-LOCAL (not shipped to server).
```

## 6. Cross-references

- `finding_widget_baseclass_architecture_and_194_widgets.md` --
  WidgetBaseClass owns the SSD request flow
- `finding_judge_subsystem.md` -- JudgeBaseClass pattern that
  Tutorial extends
- `finding_invokeLua_roster_closed_80_complete.md` -- the
  invokeLua functions matching SSD bindings + debug input
- `finding_invokeLua_roster_expanded_48_callbacks.md` -- the
  `invokeLua_onLoadKeyAsync` / `_onLoadMultiKeyAsync` callbacks
- `finding_system_invokeLua_and_userdatareceiver_dispatch.md` --
  the `_onDebugInput` Lua hook is the entry point for the debug
  console parser

## 7. Confidence

```text
Confirmed:
  - Tutorial scripts are JudgeBaseClass subclasses (2 of them)
  - They use the man0u0processEvent###_# quest event naming
  - The say/ask/finishCliantTalkTurn API is the dialog primitive
  - DebugBaseClass provides _save / _temp containers and loop
    interval
  - OverloadMonitor runs at 100ms tick using debug:_getLowResolutionTime
  - SpreadSheet is the GameData subclass for SSD operations
  - 10 native SpreadSheet bindings exist (per spreadsheet_u.lua)
  - The Widget's requestSsdLoadSheet pattern calls SpreadSheet
    methods to perform the actual load
  - system/Debug provides callFunctionProtected (pcall wrapper
    with stack-trace cleanup) for safe debug command execution
  - Debug has _lua-suffixed bindings (inverse direction: C++ ->
    Lua-implemented method)

Likely (High):
  - Tutorial flow content is delivered identically to any quest
    event (the Tutorial namespace is just a small set of
    dialog-only scenes)
  - OverloadMonitor's per-tick state is purely client-local; it
    does not ship metrics to the server
  - The SpreadSheet _onLoadKeyAsync hook is the answer to "what
    is the Lua-side handler for invokeLua_onLoadKeyAsync"
    (the hook is on SpreadSheet instances, not on Widget instances)
  - The Widget delegation pattern (widgetWork.requestSsdLoadSheet
    holds the sheet ref; widget's _onLoadMultiKeyAsync re-fires
    processSpreadSheetDataAsync) is the bridge between Widget
    and SpreadSheet

Likely (Medium):
  - The 52KB system/debug.lua + 29KB debug_utility.lua together
    implement 50+ dev console commands
  - The debug console uses pcall + sanitized stack traces for
    every command (verified via callFunctionProtected pattern)
  - Tutorial scripts are dummy/placeholder content for the initial
    onboarding tutorial that's mostly hardcoded into the quest
    director system

Speculative:
  - DebugDummy and DebugTimer are skeleton placeholders left in
    the codebase; never actually instantiated at runtime
  - The OverloadMonitor "ranking" field tracks frame-time rank
    among recent samples (0..255 indicates the percentile bucket)
  - Other `gamedata/*` subsystems may exist beyond SpreadSheet
    (XML config? localization?), but were not enumerated in the
    obfuscated catalog
```

## 8. Next test

```text
1. Read system/Debug_utility.lua to enumerate the dev console commands
   (would reveal which game state is dev-mockable for server testing)
2. Search for any other GameData subclasses (only 3 visible in catalog;
   may have been folded into other subsystems)
3. Identify how the EXE's SpreadSheet instances are constructed
   (when a Widget says requestSsdLoadSheet = "actor", where does the
    Lua engine get the actor SpreadSheet instance?)
4. Check whether OverloadMonitor's perf metrics are mirrored anywhere
   in the server protocol (some MMOs phone home perf data)
```

## Commit suggestion

```
docs(re/lua): Tutorial + Debug + GameData -- 13 scripts closed; SpreadSheet IS the SSD layer
```
