# Finding: DirectorBaseClass -- Content Orchestration Model (client-side engine + server state-sync + notice authorization)

**Maps the Director orchestration model** — the root class for all
content (quests, instances, events, guildleves, weather). Confirms
the architectural model end-to-end: a Director is a **client-side
content engine** that replicates state to the server via WorkSync and
requests server authorization at key transitions via "notices".

DirectorBaseClass (61s57qvs89r57y9rr.lua, 412 lines, 24 functions).
226+ concrete director subclasses inherit from it (per prior inventory).

## 1. Director work tiers

```text
initWork(self, ?, tempInit, syncInit)                  [179]
   -> work._temp = tempInit or {}    (LOCAL transient state)
   -> work._sync = syncInit or {}    (REPLICATED state, server-synced)

initWorkSyncTag(self, tag)                             [198]
   -> work._tag = tag                (WorkSync group/tag name)

A Director has TWO work tiers:
  work._temp   client-only (UI state, animation timers, scratch)
  work._sync   replicated to server (event phase, progress, flags)
  work._tag    the WorkSync binding tag for the _sync tier
```

## 2. State replication (updateSyncWork)

```text
updateSyncWork(self, ?, value)                         [217]
   ↓ player = worldMaster:_getMyPlayer()
   ↓ IF player:canRequestInformation():        <- RATE LIMIT GATE
   ↓    self:_updateWork("work", value)          <- WorkSync push to server
   ↓    player:recordRequestInformation()
   ↓    return true
   ↓ ELSE return false  (rate-limited, push deferred)

getSyncWork(self, key) -> work[key]                    [207]

The director pushes its _sync state to the server via the SAME
_updateWork WorkSync mechanism mapped in prior findings (-> wire
opcode 0x12F/0x133). It is GATED by canRequestInformation -- the
same rate-limit primitive used by player commands (commandBurstBlocker
sibling). Directors can't spam server updates.
```

## 3. Event delegation (delegateEvent)

```text
updateSyncWork is also overloaded as delegateEvent's helper:
delegateEvent(self, ?, handlerFunc, arg)               [250]
   -> handlerFunc:_callFunction(arg, ?, self, ...)

A Director runs event STEPS by delegating to handler functions via
_callFunction. This is the step-execution primitive: each event
phase is a function the director invokes. (Used with the event
script system -- directors drive multi-step content.)
```

## 4. Event lifecycle + notice authorization

```text
init / _onInit                                          startup
_onFinalize / processFinalize                          teardown
   - on finalize: if directorWork.contentCommand != 0:
     player:setContentCommandVariation(nil)  -- clear content command set

_onEventCancel(self, ?, eventType, ?)                  [264]
   - desktopWidget:closeAllOwnedContentWidget(self)
   - if eventType == "noticeEvent": event._resetFade()

_onNoticeRejected(self, ...)                           [287]
   - server REJECTED a notice (the director's request denied)

NOTICE SYSTEM (server authorization points):
  "noticeEvent" = a director event that requires server acknowledgment.
  The director sends a notice; the server either accepts (event proceeds)
  or rejects (_onNoticeRejected fires, event aborts).
  This is how the server GATES content transitions (quest accept,
  instance start, cutscene trigger) without running the content itself.
```

## 5. UI + content coordination

```text
processUIInit / processUIUpdate / processUIFinalize    director-owned UI
processMapOpenMessage                                  map integration
getContentCommandVariation                             content-specific command set
getKindContentsInformation                             content type info
getUseContentsCommand                                  content command usage
_onUpdateWork / processUpdateWork                      inbound WorkSync apply
```

Directors own CONTENT WIDGETS (instance UI, quest UI) and a
CONTENT COMMAND VARIATION (a command set specific to the content,
e.g. instance-only abilities). On finalize, the content command set
is cleared.

## 6. The complete content orchestration model

```text
DIRECTOR = client-side content engine. End-to-end flow:

1. SERVER TRIGGERS content (player accepts quest / enters instance):
   server creates/activates the appropriate Director (spawn 0x17c
   with a Director class name) on the client

2. CLIENT runs the Director's Lua:
   - init: set up work._temp (local) + work._sync (replicated) + _tag
   - processUIInit: open content widgets
   - setContentCommandVariation: enable content-specific commands

3. EVENT STEPS via delegateEvent:
   - director invokes handler functions for each phase
   - dialogue/cutscene/objectives run CLIENT-SIDE

4. STATE SYNC via updateSyncWork:
   - director pushes _sync state to server (_updateWork, rate-limited)
   - server tracks quest progress / instance state

5. NOTICE AUTHORIZATION for gated transitions:
   - director sends "noticeEvent" -> server accepts or _onNoticeRejected
   - server gates: quest completion, reward grant, instance clear

6. FINALIZE:
   - processFinalize: clear content command set
   - closeAllOwnedContentWidget
   - director destroyed (despawn 0x143)

SERVER ROLE: trigger directors (spawn), track their _sync state,
authorize notices (accept/reject), grant rewards. The server does
NOT run the content logic -- it's all in the director's client Lua.
```

## 7. This validates the architectural model (3rd+ confirmation)

```text
The "client-side content, server orchestrates state/triggers"
principle now confirmed across FOUR layers:
  1. Zone data (CSVs)          -- client-local
  2. NPC dialogue/animation    -- client-local
  3. Combat formulas           -- client-local
  4. Content orchestration     -- client-side Directors (THIS finding)

In every case: STATIC CONTENT + LOGIC run on the client; the server
provides STATE AUTHORITY + TRIGGERS + AUTHORIZATION (notices).

This is the defining architecture of 1.x and explains:
  - Why the wire protocol is compact (ids/flags, not content)
  - Why a server is feasible to implement (orchestrator, not engine)
  - Why client Lua scripts are so extensive (they ARE the game logic)
```

## 8. Server-side requirements for content

```text
TO RUN CONTENT (quests/instances/events), the server must:

1. TRIGGER directors:
   - On quest accept / instance enter: spawn the Director (0x17c with
     the Director subclass name, e.g. "InstanceRaidDirector")

2. TRACK director _sync state:
   - Receive _updateWork pushes (WorkSync) from the director
   - Store quest progress / instance state / flags

3. AUTHORIZE notices:
   - On "noticeEvent": validate the transition (can complete? has items?)
   - Accept (event proceeds) or reject (-> _onNoticeRejected)

4. GRANT outcomes:
   - On authorized completion: grant rewards, update player state,
     push WorkSync updates

5. FINALIZE:
   - On content end: despawn the Director (0x143)

The 226+ director subclasses (per inventory finding) each implement
specific content; the server triggers them by class name and tracks
their _sync work. The server needs the director class roster + their
_sync schema (per-director).
```

## 9. Confidence

```text
Confirmed:
  - Director work tiers: _temp (local) + _sync (replicated) + _tag
  - updateSyncWork pushes _sync via _updateWork (rate-limited by
    canRequestInformation)
  - delegateEvent runs event steps via _callFunction
  - Notice system: noticeEvent + _onNoticeRejected = server authorization
  - Content command variation + content widgets owned by director
  - 24 functions enumerated
  - Validates client-side-content model (4th layer)

Likely (High):
  - Server triggers directors via spawn (0x17c) by class name
  - Directors despawn (0x143) on content end
  - Notice = the server-authorization checkpoint for gated transitions
  - Each of the 226+ director subclasses has its own _sync schema

Speculative:
  - "noticeEvent" specifically = events needing server-side validation
    before client proceeds (vs local-only events)
  - contentCommand != 0 means an instance-specific command set is active
  - delegateEvent + _callFunction = the event-script step machine
```

## 10. Cross-references

- `finding_director_baseclass_and_226_subclasses.md` -- the 226 subclass
  inventory (this finding adds the orchestration MECHANICS)
- `finding_npc_event_talk_turn_flow_client_side.md` -- NPC events
  (directors orchestrate multi-NPC/multi-step content)
- `finding_areabaseclass_zone_bootstrap_sequence.md` -- zone bootstrap
  (instance directors tie to instance zones)
- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- how the server spawns a director
- `finding_playerbaseclass_command_flow_and_player_module.md` --
  canRequestInformation rate-limit (shared with director sync)

## 11. Next test

```text
1. Read a concrete director (guildleve director 3p1y6y5o5/, 1560 lines)
   to see a full content orchestration with real event steps
2. Map the "notice" wire path (how a notice reaches the server)
3. Document the director _sync schema for 2-3 key directors
4. Trace setContentCommandVariation -> content-specific command sets
5. Map _callFunction event-step dispatch
```

## Commit suggestion

```
docs(re/lua): DirectorBaseClass content orchestration model -- client-side engine, _sync state to server (rate-limited _updateWork), notice authorization; validates client-side-content model (4th layer)
```
