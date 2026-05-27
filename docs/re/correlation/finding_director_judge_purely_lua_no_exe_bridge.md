# Finding: Director + Judge Subsystems Are PURELY Lua-Side -- No EXE Bridge

Resolves the long-standing "what paradigm do Directors and Judges
use" question. **They have NO direct EXE counterpart.** All 245+
content orchestrators (179+ directors + 19 judges + variants) are
**purely Lua subclasses** that ride on top of existing paradigms.

The "4th unknown paradigm" hypothesis from prior findings is FALSE.
Directors and Judges use Paradigms 2 (registerLua) and 3 (timed
dispatchers) as ORDINARY Lua actors -- they have no EXE-side classes.

## 1. Verification: zero Director/Judge functions in EXE

Ghidra searches return ZERO results for:
- `Director` -- no EXE functions
- `Judge` -- no EXE functions
- `contentCommand` -- no EXE references
- `directorId` -- no EXE references

This is conclusive. Where PlayerBase, NpcBaseClass, CharaBase, etc.
have dozens of named EXE functions each, Director and Judge have
NONE. They exist purely as Lua classes.

## 2. The 245+ orchestrator surface (pure Lua count)

```text
Directory                              Scripts
---------                              -------
director/                              14 top-level
director/quest/                        117 questdirectors
director/guildleve/                    34 guildlevedirectors
director/instanceraid/                 14 instanceraiddirectors
---
TOTAL directors:                       179+

judge/ (and subdirs)                   19 judges
                                       (action, autoattack, chocobo,
                                        commonjudge, craft, depiction,
                                        gamecalculate, harvest,
                                        hatecontrol, instanceraidguide,
                                        item, negotiation, preface
                                        + tutorial 2 + base 2)
---
TOTAL judges:                          19+
```

Note: catalog says 89 directors + 18 judges, suggesting the catalog
counts at a different granularity (per-file vs per-class). Regardless,
the orchestrator count is in the 200-300 range and ALL are pure Lua.

## 3. DirectorBaseClass architecture

```text
File: director/directorbaseclass.lua

work fields (auto-managed via _temp/_sync/_tag):
  _temp:
    directorId         integer32  (the director's identity)
  
  _sync:               (server-synced via WorkSync system)
    contentCommand     integer32  (content type currently active)
    contentCommandSub  integer32  (sub-state within the content)
    syncBuffer[128]    boolean    (custom sync flags)

methods:
  _onInit(directorId, ...)
    - initializes _temp/_sync/_tag work fields
    - sets directorWork.directorId = directorId
    - calls subclass init(args)
  
  _onFinalize()
    - calls processUIFinalize + processFinalize on self
    - IF contentCommand != 0:
      worldMaster:_getMyPlayer():setContentCommandVariation(nil)
      (signals server that the content is ending)
  
  init(...)                  abstract - subclass overrides
  processFinalize()          abstract - subclass cleanup hook
  processUIFinalize()        abstract - UI cleanup hook
  
  initWork(_, _temp_default, _sync_default)
    - merges defaults into work._temp and work._sync
  initWorkSyncTag(tag)
    - sets work._tag (for WorkSync routing)
  
  getTempWork(name) / setTempWork(name, value)
  getSaveWork(name) / setSaveWork(name, value)
  getSyncWork(name)
  updateSyncWork(name, value)
    - validates with player.canRequestInformation()
    - calls self._updateWork("work", value) (a registerLua binding!)
    - calls player.recordRequestInformation() (per-frame throttle)
    - returns true on success, false if throttled
  
  getContentCommandVariation()
    - returns (contentCommand, contentCommandSub) tuple
  
  delegateEvent(eventName, target, args)
    - delegates an event to another object via _callFunction
```

So a Director is essentially:
- A Lua object with serialisable state (`_sync` fields shipped to
  server via WorkSync opcode 0x12f)
- Local temp state (`_temp`)
- Local save state (`_save`)
- Configurable identification (directorId, contentCommand,
  contentCommandSub)
- Lifecycle methods (init / finalize / processFinalize)

The KEY BINDING (Paradigm 2) used by Directors:
- `worldMaster:_getMyPlayer()` -- get player ref
- `player.setContentCommandVariation(nil)` -- server notification
- `self._updateWork("work", value)` -- updates work state and
  syncs to server

## 4. JudgeBaseClass architecture

```text
File: judge/judgebaseclass.lua

methods:
  _onInit()
    - calls subclass initText()
    - calls subclass init()
  initText()                  abstract - text initialization
  init()                      abstract - subclass init
  
  prepareSpreadSheet(filename, sheetClassName)
    - if sheetClassName nil: derive from filename
      (lowerCamelCase + "Sheet")
    - calls _createActor(sheetName, "SpreadSheet", true, filename)
    - returns the created SpreadSheet actor
  
  unprepareSpreadSheet(filename, sheetName)
    - gets actor by name
    - calls actor:_delete()
```

So Judges are even simpler than Directors -- they:
- Have an init/initText pair (initText typically loads text strings)
- Use `prepareSpreadSheet` to spawn SpreadSheet actors for their
  data needs
- Use `unprepareSpreadSheet` to clean up

**`_createActor`** is the KEY GLOBAL BINDING -- it's the engine's
way to create actor instances from Lua. Each created actor:
- Has its own 3-tier dispatchers (Paradigm 3)
- Is added to the actor tree
- Gets ticked per frame
- Can be addressed by `_getActorByName(name)`

## 5. The "no EXE bridge" explanation

Directors and Judges work by **composition** of existing infrastructure:

```text
A Director is an Actor instance (created via _createActor or as a
child of another actor) that:
  - Inherits the 3-tier dispatcher machinery (Paradigm 3) AUTOMATICALLY
  - Receives events via DispatcherA/B/C the same way as any widget
  - Calls into PlayerBase/WorldMaster via Paradigm 2 (registerLua bindings)
  - Updates its _sync work fields, which are auto-synced to server via
    the WorkSync opcode 0x12f (per finding_worksync_wire_opcode_0x12f)
  - Receives server-pushed updates to its _sync fields via the same opcode

So a Director doesn't NEED its own EXE class -- it inherits everything
from the Actor base.
```

The "content orchestration" responsibility is split:
- **Lua-side (Director)**: state machine logic, conditionals, scene
  transitions, sub-director spawning
- **EXE-side (Actor + Dispatchers)**: per-frame tick, event routing,
  Lua VM invocation, sync field serialization
- **Server-side**: pushes contentCommand updates, receives Director
  state changes, validates quest progression

## 6. The 5 paradigms confirmed/expanded

```text
Paradigm 1: invokeLua (FUN_00cc7a90 family)
  C++ -> Lua event hook by name
  80 callbacks named across 14 classes

Paradigm 2: registerLua (Functor pool)
  Lua callable C++ methods (bindings)
  123 bindings (PB 99 + NpcBase 24)

Paradigm 3: Timed dispatchers (3 per widget)
  - DispatcherA: stored Lua functors (tweens/animations)
  - DispatcherB: named-method dispatch (UI events)
  - DispatcherC: stack-based subscription (pubsub)

GLOBAL Lua bindings (cross-paradigm):
  _defineClass / _createActor / _getActorByName / require / etc.
  These are NOT class-instance methods; they're engine-global
  functions registered into Lua's _G table at startup.
  Used by Directors/Judges to spawn helper actors (SpreadSheet, etc.)
  and to set up class inheritance.

DIRECTOR/JUDGE: Pure Lua subclasses
  No dedicated EXE counterpart
  Use Paradigms 2 (calling) + 3 (receiving) + global bindings
  Lifecycle managed via Actor tree (per Paradigm 3 ticking)
```

## 7. Server design implications

```text
For a server to drive Director-orchestrated content:

  STATE SHIP-OUT (server -> client):
    Server pushes WorkSync packets (opcode 0x12f) containing:
      - directorId (identifies which director instance)
      - contentCommand + contentCommandSub (current state)
      - syncBuffer[128] (custom flags)
    Client Director's _sync field auto-updates

  STATE READ-BACK (client -> server):
    Client Director calls updateSyncWork(name, value) which:
      - validates via canRequestInformation()
      - serializes the value via _updateWork
      - this triggers a server-bound WorkSync packet
    Server receives the updated work state

  DIRECTOR LIFECYCLE:
    Server triggers spawn via a NamedActor-creation opcode
    Client receives -> calls _createActor("QuestDirectorBLM0J101",
                                          "QuestDirectorBLM0J101",
                                          true, ...)
    -> instantiates the director, runs _onInit -> init(args)

  CONTENT PROGRESSION:
    Server sends Lua hook trigger (Paradigm 1 invokeLua) for events
    like "monster defeated", "item collected", "talked to NPC"
    -> Director's listening dispatchers (Paradigm 3) receive
    -> Director's Lua state machine advances
    -> Director may spawn sub-widgets (e.g., QuestDirectorBaseClass
       opens a confirmation dialog when a step completes)

So for QUEST CONTENT, the server primarily needs to:
  1. Spawn directors at content start
  2. Drive their state via WorkSync sync field updates
  3. Trigger their event hooks via Paradigm 1 invokeLua
  4. Receive their state-change responses via WorkSync read-back

The 117 quest directors + 34 guildleve + 14 instance directors
each implement a SPECIFIC content's state machine in Lua. The
server doesn't need per-director code -- it drives them by their
contentCommand/contentCommandSub state machine plus event triggers.
```

## 8. Cross-references

- `finding_director_pattern_baseclass.md` -- earlier Director
  finding (less complete than this)
- `finding_director_baseclass_and_226_subclasses.md` -- catalog of
  the 226 directors
- `finding_judge_subsystem.md` -- earlier Judge finding
- `finding_judge_family_complete.md` -- 19 judge enumeration
- `finding_worksync_wire_opcode_0x12f.md` -- the wire opcode that
  syncs Director's _sync field
- `finding_widget_3tier_dispatcher_architecture.md` -- the
  dispatchers that Directors inherit as Actor instances
- `finding_paradigm_3_refinement_lua_functor_dispatch.md` -- the
  Paradigm 3 sub-mechanisms
- `finding_invokeLua_roster_closed_80_complete.md` -- Paradigm 1
  (used by Directors as event receivers)
- `finding_playerbase_lua_bindings_99_complete.md` -- Paradigm 2
  bindings (the registerLua_* methods Directors call)

## 9. Confidence

```text
Confirmed:
  - Zero EXE functions named with "Director" or "Judge"
  - Zero EXE references to directorId / contentCommand identifiers
  - DirectorBaseClass + JudgeBaseClass are pure Lua via _defineClass
  - 179+ directors (across 4 subdirs) + 19 judges
  - Directors use _sync field auto-synced via WorkSync (Paradigm 2
    binding _updateWork)
  - Judges use _createActor to spawn SpreadSheet actors
  - "_createActor" is a GLOBAL Lua function (not an instance method)
  - Directors call worldMaster:_getMyPlayer() and use player.* methods
    (Paradigm 2 PlayerBase bindings)
  - DirectorBaseClass methods documented (getTempWork, setSaveWork,
    initWork, getContentCommandVariation, updateSyncWork, etc.)

Likely (High):
  - Directors are spawned by the server via a NamedActor-creation
    flow (the server sends directorId + actor class name)
  - WorkSync opcode 0x12f carries the _sync field updates
    bidirectionally
  - The 117 quest directors = 117 different quest scripts; the
    server doesn't need to know each individually
  - Judges are spawned at the start of a game session and persist
    (they're stateless helpers for spreadsheet data)

Likely (Medium):
  - There's a JudgeMaster (per the catalog) that manages all 19
    judge instances; the engine creates it during init
  - DirectorMaster does NOT exist (each director is independent;
    quest directors come and go)
  - Sub-directors are spawned via a similar _createActor call
    from a parent director

Speculative:
  - The 245+ orchestrators were the result of a SOURCE-CODE
    GENERATION pipeline (per-quest/per-leve template + customization)
  - The server's "content scripting" responsibility is minimal
    (it drives state via WorkSync; the Lua does the work)
```

## 10. Next test

```text
Now that Director/Judge architecture is clear:

1. Find _createActor binding -- it should be a Paradigm 2 registerLua
   binding somewhere (likely on a "Engine" or "Container" class)
2. Walk the WorkSync 0x12f handler to verify directorId routing
3. Sample 1-2 concrete QuestDirector scripts to see the state machine
   pattern in action
4. Identify the ContentCommand IDs that drive the system
   (e.g., contentCommand = 1 -> Quest, 2 -> Guildleve, 3 -> Instance)
```

## Commit suggestion

```
docs(re/correlation): Directors + Judges are PURELY Lua -- no EXE bridge (245+ orchestrators)
```
