# Finding: Director State Machine Concrete Patterns -- 2 Samples + Quest/Guildleve Templates

Extends `finding_director_judge_purely_lua_no_exe_bridge.md` with
concrete examples of how the abstract Director architecture is
specialised in real content. Samples:

1. `QuestDirectorBaseClass` -- the parent of all 117 quest directors
2. `RequestDirector` (guildleve content) -- a concrete director

Reveals the **uniform state-machine pattern** used by all 245+
directors: UiStep + UiState + content tracking + time limits +
desktopWidget integration.

## 1. QuestDirectorBaseClass (the 117-quest parent)

```text
File: director/quest/questdirectorbaseclass.lua
Size: 1628 B
Extends: DirectorBaseClass

questDirectorWork fields (auto-managed):
  _temp:  16 bytes _assignForChild (reserved for per-quest custom)
  _sync:  32 bytes _assignForChild (reserved for per-quest sync)

key methods:
  init(...)                                  template entry; calls
                                              initAsQuestDirector(args)
  initAsQuestDirector(...)                    abstract -- subclass override
  getUseContentsCommand()                     calls
                                              worldMaster:_getMyPlayer()
                                                .getQuestContentsCommandPermitFlag()
                                              (returns whether player can use
                                               content commands for this quest)
  getOwnClientQuestId()                       abstract -- returns the quest's ID
  processFinalize()                            cleanup using quest ID
```

So each of the 117 quest directors:
- Subclasses QuestDirectorBaseClass via `_defineClass("QuestDirectorXxx",
  "QuestDirectorBaseClass")`
- Implements `initAsQuestDirector(args)` to set up its specific quest
- Implements `getOwnClientQuestId()` to return the quest's unique ID
- Inherits the standard director lifecycle from
  DirectorBaseClass

The fact that QuestDirectorBaseClass is ~1.6 KB shows that the
PER-QUEST customization is what holds the actual quest logic. The
shared part is just orchestration helpers.

## 2. RequestDirector -- a concrete guildleve content director

```text
File: director/guildleve/requestdirector.lua
Size: 10813 B (one of the larger directors)
Extends: GuildleveBaseClass (extends DirectorBaseClass)

work fields:
  _temp:                                 (passed to initWork as 2nd arg)
    requestId        integer32           (the guildleve's request ID)
  _sync:                                 (passed to initWork as 3rd arg)
    aimNpcBoss[4]    array of integer8   (4-slot target tracker)

work-sync tag (initWorkSyncTag):
    {
      "infoRequest" = 1,                  (tag ID)
      { "aimNpcBoss" }                    (synced field name)
    }

key methods (in observed order):
  initAsGuildleve(requestId)
    - calls initWork(nil, _temp_schema, _sync_schema)
    - setTempWork("requestId", requestId)
    - calls initWorkSyncTag(tagStruct)
  
  getTimeLimit()                          returns 20 (minutes/seconds TBD)
  
  processUIInit()                          UI initialization called per frame
    For each of 4 slots (i=1..4):
      setAimNumNowTmpOf(i, getAimNumNowOf(i))   -- snapshot count to tmp
      setUiStateTmpOf(i, getUiStateOf(i))       -- snapshot UI state
    
    If getStartTime() > 0 and getUiStep() == 0:
      setUiStep(1)                                -- advance to step 1
      desktopWidget:processUpdateContentsInformation(self, "start")
                                                  -- notify HUD
      setMiniMapMarkerForGL()                     -- show map markers
```

## 3. The universal director state machine pattern

Distilling from QuestDirectorBaseClass + RequestDirector:

```text
Director state machine:
  - UiStep      : current step (integer; 0 = pre-start, 1 = active, 2 = success, ...)
  - UiState[]   : per-slot UI states (array)
  - aimNum*[]   : per-slot counts (array; e.g., "kill 4 of X")
  - StartTime   : when content was started (timestamp)
  - TimeLimit   : how long the player has

Per frame (processUIInit OR similar tick method):
  1. Snapshot per-slot state to *Tmp* fields (for diffing this frame)
  2. Check if content has started (StartTime > 0)
  3. If just started: advance UiStep, notify HUD via
     desktopWidget:processUpdateContentsInformation, set map markers
  4. Subclass adds: target completion checks, reward calculations,
     UI updates, state transitions

State transitions (typical):
  step 0 (pre-start) -> step 1 (active)
  step 1 (active) -> step N (success or fail)
  step N -> finalize -> _onFinalize fires
```

## 4. The desktopWidget integration

Directors call `desktopWidget:processUpdateContentsInformation(self, msg)`
to notify the HUD of content state changes. Messages observed:

```text
"start"  -- content started; show notification + map markers
(other messages exist in concrete directors)
```

This is the **bridge from Director to HUD**. The desktopWidget then
updates the UI (notification text, map icons, content timer display).

## 5. The 4-slot pattern

RequestDirector uses 4 slots for `aimNpcBoss[4]` (track 4 different
enemy types). This 4-slot pattern is canonical for guildleve content:

- Each slot tracks one target type (an NPC, a boss, an item to gather)
- aimNumNow = current count
- aimNumNowTmp = snapshot for delta
- UiStateOf = per-slot UI display state
- UiStateTmpOf = previous frame's state

Per-slot snapshotting lets the director DETECT CHANGES (e.g., new
kill happened this frame) and trigger appropriate UI updates without
expensive per-frame compares.

## 6. The complete director lifecycle (concrete)

```text
PHASE 1: Spawn (server triggers)
  Server: send NamedActor-creation opcode + directorId + contentCommand
  Client: _createActor("RequestDirector_<id>", "RequestDirector",
                       isModal, ...args)
  Client: instance._onInit(directorId)
           -> work field initialization
           -> DirectorBaseClass.init(args)
           -> RequestDirector.initAsGuildleve(requestId)
                -> initWork(_temp, _sync schemas)
                -> setTempWork("requestId", requestId)
                -> initWorkSyncTag(tagStruct)

PHASE 2: Per-frame tick (engine drives)
  Engine: Actor_perFrameUpdate ticks RequestDirector
       -> RequestDirector.processUIInit()
             -> snapshot per-slot state to tmp
             -> check startTime
             -> if just-started: advance UiStep + notify HUD + set markers

PHASE 3: Event-driven progression (server pushes / client computes)
  Server pushes monster-defeated event via Paradigm 1 invokeLua
  -> RequestDirector receives via DispatcherA/B/C
  -> Director's state machine advances (e.g., increment aimNumNow)
  -> Next frame: processUIInit detects delta, updates HUD

PHASE 4: Content end
  Director: setUiStep(2 or 3) -- success or fail
  Director: triggers finalization via _onFinalize
  -> DirectorBaseClass: notify worldMaster:_getMyPlayer():
                         setContentCommandVariation(nil)
  -> Server learns content has ended
  -> Server: send NamedActor-deletion opcode
  -> Client: instance._delete()
```

## 7. Server design implications (concrete)

```text
For Stage-1 server to support RequestDirector (1 guildleve):

  SPAWN:
    Send opcode to spawn "RequestDirector" with requestId = N
    (need to identify which exact opcode -- likely NamedActor spawn
     via _createActor binding; binding not yet located in Ghidra)
  
  STATE PUSH (via WorkSync opcode 0x12f):
    directorId = (the spawned director's ID)
    contentCommand = (assigned during spawn; identifies as guildleve)
    contentCommandSub = (sub-state, e.g., difficulty level)
    syncBuffer[128] = (custom flags)
    Plus per-director _sync fields:
      aimNpcBoss[4] = (per-slot kill counts; updated by server)
  
  EVENT TRIGGERS (via Paradigm 1 invokeLua):
    When a player kills an NPC matching aimNpcBoss[i]:
      server sends invokeLua_<Director's onKill hook>(npc_id)
    Director's Lua state machine updates aimNumNow[i]
    Director's per-frame tick detects delta and updates HUD
  
  COMPLETION:
    When all aimNpcBoss counts reach target:
      Director sets UiStep = 2 (success)
      Director calls notification on HUD
      Server may then send a "claim reward" hook trigger
  
  TEARDOWN:
    Director _onFinalize signals end
    Server deletes the Director instance (via NamedActor-delete opcode)
```

## 8. Generalization to all 117 quest directors

Per-quest customization (per quest director):
- `initAsQuestDirector(args)` — set up the quest's specific state
  (e.g., questId, target NPCs, starting location)
- `getOwnClientQuestId()` — return the quest's unique ID
- Custom state fields beyond the base work schema
- Custom event handlers (per-quest event hooks)

Per-quest directors are TINY (most are 205 bytes — basically stubs).
The actual quest logic lives in the SHARED LIBRARIES that the
director's init method requires (e.g., NPC dialog tables, reward
tables, sheet data).

So a server implementing quest content needs:
1. Spawn the right per-quest director by name
2. Push the quest's static state via WorkSync
3. Trigger quest events via Paradigm 1 invokeLua
4. The Lua does all the per-quest logic

## 9. Cross-references

- `finding_director_judge_purely_lua_no_exe_bridge.md` -- the
  abstract architectural finding; this concretizes it
- `finding_worksync_wire_opcode_0x12f.md` -- the WorkSync wire shape
  that drives _sync field updates
- `finding_widget_3tier_dispatcher_architecture.md` -- the 3
  dispatchers that directors inherit as Actor instances
- `finding_widget_baseclass_architecture_and_194_widgets.md` -- the
  desktopWidget that directors call into via
  processUpdateContentsInformation

## 10. Confidence

```text
Confirmed:
  - QuestDirectorBaseClass extends DirectorBaseClass
  - Each quest director has getOwnClientQuestId() abstract method
  - getUseContentsCommand calls player's QuestContentsCommand permit flag
  - RequestDirector (guildleve) uses 4-slot aimNpcBoss tracking
  - Directors call desktopWidget:processUpdateContentsInformation
    to notify HUD
  - Per-frame snapshotting (setTmpOf pattern) is the standard delta
    detection mechanism
  - UiStep is the canonical state machine variable
  - getTimeLimit returns a time-limit value (units TBD, 20)

Likely (High):
  - All 117 quest directors follow the QuestDirectorBaseClass template
  - All 34 guildleve directors follow the GuildleveBaseClass template
  - The 4-slot pattern (aimNpcBoss[4]) is the default for multi-target
    content
  - desktopWidget message strings include "start", "complete", "fail",
    "update" (need to enumerate from other directors)

Likely (Medium):
  - Per-quest directors at 205 bytes contain ONLY:
    - _defineClass call
    - initAsQuestDirector stub that calls super
    - getOwnClientQuestId returning the literal quest ID
  - Per-quest LOGIC lives in shared libraries (NPC dialog tables,
    reward tables) loaded via require
  - The contentCommand field encodes content TYPE (1=quest,
    2=guildleve, 3=instance)

Speculative:
  - The 16-byte _temp and 32-byte _sync in QuestDirectorWork are
    PER-QUEST custom fields that each director overrides
  - The UiStep states have a fixed semantic across all directors:
    0 = pre-start
    1 = active
    2 = success
    3 = fail
    4 = cleanup
```

## 11. Next test

```text
1. Identify the NamedActor-creation opcode that spawns directors
   (search for _createActor binding in EXE)
2. Read 1-2 of the 205-byte quest directors (e.g., questdirectorblm0j101)
   to verify the "stub" hypothesis
3. Map contentCommand IDs to content types (search worldMaster Lua
   for setContentCommandVariation callers)
4. Enumerate the desktopWidget message strings used by directors
   (grep all directors for processUpdateContentsInformation)
```

## Commit suggestion

```
docs(re/lua): Director state machine concrete patterns -- QuestDirectorBaseClass + RequestDirector
```
