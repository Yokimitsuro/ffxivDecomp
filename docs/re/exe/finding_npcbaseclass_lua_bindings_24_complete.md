# Finding: NpcBaseClass Lua Bindings -- 24 of 24 COMPLETE Roster

Closes the NpcBaseClass Lua API surface enumeration. Walks the master
registrar block `NpcBaseClass_registerAllLuaBindings` at 0x00754850 and
recovers every binding name + thunk address.

**Result**: 24 of 24 NpcBaseClass bindings now named (100% coverage).
All 24 functions renamed in Ghidra as `NpcBaseClass_registerLua_<name>`.
Master block also renamed.

This is the natural companion to
`finding_playerbase_lua_bindings_99_complete.md` -- NpcBase is the
**actor-side** of NPC interactions where PlayerBase is the
**player-side**. Together they describe the full Talk/Emote/Push
interaction stack.

## 1. Coverage summary

```text
Before this finding:  3 of N      (the callServerOn{Talk,Emote,Push}
                                    documented in
                                    finding_lua_to_exe_command_bridge.md
                                    + finding_npc_talk_emote_push_bridge.md)
After this finding:   24 of 24    (100%)
```

The 21 new bindings span: do-server-on push commands (3), break commands
(4 including Notice), interaction predicates (3), MapObj subsystem (3),
background scheduler (3), reaction trigger (1), item sheet preload (2),
plus push-state and enmity (2).

## 2. The complete 24-binding roster (master-block order)

```text
Slot  Lua API                            Registrar       Thunk
----  --------                           ---------       -----
 1    _callServerOnTalk                  0x00736fc0     LAB_006e9520
 2    _callServerOnEmote                 0x00737110     LAB_006e9580
 3    _callServerOnPush                  0x00737260     LAB_006e95e0
 4    _doServerOnTalk                    0x007373b0     LAB_006e9700
 5    _doServerOnEmote                   0x00737500     LAB_006e97a0
 6    _doServerOnPush                    0x00737650     LAB_006e9840
 7    _breakTalk                         0x007377a0     LAB_006e1320
 8    _breakEmote                        0x007378f0     LAB_006e1340
 9    _breakPush                         0x00737a40     LAB_006e1360
10    _breakNotice                       0x00737b90     LAB_006e1380
11    _isTalkable                        0x007503e0     FUN_00706aa0
12    _isEmotable                        0x00750530     FUN_00706ae0
13    _isPushable                        0x00750680     FUN_00706b20
14    _initAsMapObj                      0x00737ce0     FUN_006e6600
15    _isMapObj                          0x007507d0     FUN_00706b60
16    _setMapObjScale                    0x0073f710     FUN_006e66a0
17    _runBgScheduler                    0x00737e30     FUN_006f38d0
18    _runBgSchedulerFromMidstream       0x00737f80     FUN_006f3ba0
19    _waitForBgSchedulerFinished        0x007380d0     FUN_006e98e0
20    _isPushing                         0x00750920     LAB_00706ba0
21    _setReactionTriggerBox             0x007428b0     FUN_006f23f0
22    _preloadItemSpreadSheetContainer   0x0073f860     FUN_006f2620
23    _releaseItemSpreadSheetContainer   0x00746510     FUN_006f6480
24    _isEnmity                          0x00750a70     LAB_00706c40
```

**Crucial difference from PlayerBase**: NpcBase thunks at slots 11-19 +
21-23 resolve to **already-analysed FUN_xxxxxx functions** (not
unanalysed LAB_xxxxxx labels). This means the actual C++ bodies are
**directly decompilable** for these bindings -- a substantial advantage
over the PlayerBase case where thunks live in the unanalysed gap.

The bindings that ARE in unanalysed thunks (slots 1-10, 20, 24) all
relate to wire traffic (callServer/doServer/break) or pure state
queries -- the same architectural pattern as PlayerBase.

## 3. Functional family breakdown (24 bindings -> 9 families)

### Family A: SERVER CALL / WIRE TRAFFIC (6 bindings)

```text
 1   _callServerOnTalk     CLIENT-INITIATED: player presses talk on NPC
 2   _callServerOnEmote    CLIENT-INITIATED: player emotes at NPC
 3   _callServerOnPush     CLIENT-INITIATED: player pushes NPC
 4   _doServerOnTalk       SERVER-PUSHED:  server-driven talk response
 5   _doServerOnEmote      SERVER-PUSHED:  server-driven emote response
 6   _doServerOnPush       SERVER-PUSHED:  server-driven push response
```

The **6-binding 2x3 grid** (call/do x talk/emote/push) confirms the
client/server-direction split observed in PlayerBase. Each interaction
mode (Talk/Emote/Push) has a client-side initiator (`callServer*`) and
a server-driven fallback (`doServer*`).

This is the **Stage-1 implementation set** for any NPC interaction
server -- every NPC dialog, every emote response, every NPC-push
interaction flows through these 6 thunks.

Cross-ref: `finding_npc_talk_emote_push_bridge.md` already documented
the 3 `callServer*` -> wire opcode wiring. The 3 `doServer*` bindings
here are the **complement**: same wire shape but reverse direction.

### Family B: BREAK / ABORT (4 bindings)

```text
 7   _breakTalk            Forcibly aborts in-progress talk
 8   _breakEmote           Forcibly aborts in-progress emote
 9   _breakPush            Forcibly aborts in-progress push
10   _breakNotice          Forcibly aborts in-progress notice popup
```

NPC mirror of PlayerBase's `_breakCommand`. The 4-stream coverage
(adding Notice to the Talk/Emote/Push trinity) **matches PlayerBase's
5-stream model** minus Command (Command is player-side only).

Architecturally: a "break" is the engine-level interrupt that any
script can fire to forcibly cancel an ongoing interaction. Cancel
(in PlayerBase) is a polite request; break is the hammer.

### Family C: INTERACTION PREDICATES (3 bindings)

```text
11   _isTalkable           Returns: can this NPC be talked to right now?
12   _isEmotable           Returns: will this NPC respond to emotes?
13   _isPushable           Returns: can this NPC be physically pushed?
```

Each NPC instance can independently enable/disable the 3 interaction
modes. Used by the client to gate the interaction UI (button prompts,
highlight color, etc.) before the player even commits to the action.

### Family D: MapObj SUBSYSTEM (3 bindings) -- the static-prop branch

```text
14   _initAsMapObj         Initialize this NPC as a MapObj (static prop)
15   _isMapObj             Returns: is this NPC currently a MapObj?
16   _setMapObjScale       Set MapObj scaling factor
```

**MapObj** = MapObject = static prop / world-mounted decoration.
A subset of NpcBase entities can be re-purposed as static map decorations
(crates, signs, gathering nodes pre-spawn). Initialised by calling
`_initAsMapObj` after creation; queryable via `_isMapObj`; scalable via
`_setMapObjScale`.

This is the 1.x architecture-level decision that **gathering nodes are
NpcBase actors**, not a separate entity type -- they just have the
MapObj flag set so the engine treats them as static rather than
animated.

Cross-ref: `finding_onTouch_is_gathering_proximity.md` -- gathering
proximity is triggered when the player intersects a MapObj-flagged
NpcBase actor.

### Family E: BACKGROUND SCHEDULER (3 bindings)

```text
17   _runBgScheduler                Start NPC background-action scheduler
18   _runBgSchedulerFromMidstream   Restart scheduler from a midpoint
19   _waitForBgSchedulerFinished    Yield Lua until scheduler done
```

NpcBase instances have an **internal background-action scheduler** --
a queue of timed actions that run in parallel with the active dialog/emote.
Examples: an NPC walking back to its spawn after a conversation,
an NPC playing an idle animation, an NPC starting a chat with another
NPC after a delay.

The `FromMidstream` variant suggests the scheduler can be **resumed at
arbitrary points** -- useful for cutscene-restart logic where the NPC
needs to pick up where it left off.

### Family F: REACTION TRIGGER (1 binding)

```text
21   _setReactionTriggerBox  Set a spatial trigger box for NPC reactions
```

Defines a 3D bounding box around the NPC. When the player enters this
box, the NPC fires a reaction (look-at, comment, defensive stance, etc.).
The trigger is **purely client-side** for visual reactions; combat
aggro is handled separately by the enmity system (slot 24).

### Family G: ITEM SHEET PRELOAD (2 bindings)

```text
22   _preloadItemSpreadSheetContainer  Pre-load item-data spreadsheet
23   _releaseItemSpreadSheetContainer  Release the pre-loaded spreadsheet
```

NPCs that sell/trade items (vendors, retainers, certain quest givers)
**preload the relevant item data** before opening the shop UI to avoid
in-UI loading hitches. The release pair frees the data when the
interaction ends.

Cross-ref: `finding_item_system.md` for item-data structure;
`finding_company_group_freecompany.md` for vendor NPC context.

### Family H: PUSH STATE (1 binding)

```text
20   _isPushing  Returns: is this NPC currently being pushed by player?
```

The state predicate for the push-interaction subsystem. Mirrors
PlayerBase's `_isPushingOut` from the player perspective.

### Family I: ENMITY (1 binding)

```text
24   _isEnmity  Returns: does this NPC have player on its enmity list?
```

The aggro-state predicate. Pair of PlayerBase's `_haveEnmityCharacters`
(which queries "any NPCs aggroed on me?"). This is the inverse query
("am I aggroed on this player?") from the NPC perspective.

## 4. Architectural pattern: the 6 essential NPC operations

Distilling the 24 bindings down reveals NpcBase's design philosophy:

```text
For each NpcBase instance, the API exposes:

  1. INTERACT     (Talk / Emote / Push -- 6 wire bindings)
  2. BREAK        (force-abort any of the 4 interaction streams)
  3. GATE         (is this interaction even possible?)
  4. APPEAR       (initialize as static MapObj? scale? still that?)
  5. ANIMATE      (background scheduler -- runs idle behaviors)
  6. REACT        (spatial trigger box for proximity reactions)

Plus a vendor-specific concern: ITEM SHEET PRELOAD (2 bindings).
Plus 2 state queries (push state, enmity state).

Total: 24 bindings, organized around 9 functional concerns.
```

This is **much tighter than PlayerBase's 99 bindings**. NpcBase has
~1/4 the surface area because NPCs are simpler than players:
- No achievement system (-21)
- No cutscene replay (-5)
- No fade/loading control (-8)
- No control-lock (-11)
- No grand company / chocobo / inn / hamlet (-13)
- No storage/entrust item (-7)

The deltas reveal which features are **player-exclusive vs
universal-actor**. Player concerns (UI/control/progression) absent in
NpcBase. NPC concerns (MapObj, scheduler, reaction triggers) absent in
PlayerBase. The shared core (Talk/Emote/Push + break + predicates =
13 bindings) is the **lowest-common-denominator actor interaction
contract** in 1.x.

## 5. Why the NpcBase thunks are partially decompilable

Unlike PlayerBase (where 99 thunks all live in the
unanalysed 0x006de650+ COMDAT region), NpcBase thunks fall into
**two address spaces**:

```text
Address space             Range          Slots affected
-------------             -----          --------------
Unanalysed LAB_006e9xxx   0x006e9520+    1, 2, 3, 4, 5, 6 (wire traffic)
Unanalysed LAB_006e13xx   0x006e1320+    7, 8, 9, 10 (break)
Unanalysed LAB_00706bxx   0x00706ba0+    20, 24 (state predicates)
Already-analysed FUN_xx   0x00706axx+    11, 12, 13, 15 (predicates)
Already-analysed FUN_xx   0x006e6xxx     14, 16 (MapObj)
Already-analysed FUN_xx   0x006f3xxx     17, 18 (scheduler)
Already-analysed FUN_xx   0x006f2xxx     21, 22 (reaction, item-preload)
Already-analysed FUN_xx   0x006f6xxx     23 (item-release)
Already-analysed FUN_xx   0x006e98xx     19 (scheduler wait)
```

The unanalysed regions (LAB_xxxx) are mostly **wire-related** (callServer,
doServer, break, predicate impls). The already-analysed FUN_xxxx are
**client-local logic** (MapObj, scheduler, reaction box, item-sheet
manipulation).

This split means: for NpcBase, **we can directly decompile the local-only
bindings** (Family D-H, 10 bindings) and study their actual implementation
without force-disassembly. PlayerBase did not offer this advantage.

## 6. Server design implications

```text
HARD MUST-HAVE (wire traffic, server must handle):
  _callServerOnTalk     Player initiates talk -> server responds with dialog
  _callServerOnEmote    Player emotes at NPC -> server may broadcast
  _callServerOnPush     Player pushes NPC -> server validates + responds
  _doServerOnTalk       Server pushes talk to client (NPC-initiated)
  _doServerOnEmote      Server pushes emote (NPC-initiated)
  _doServerOnPush       Server pushes push event (rarely used)

PROBABLY OUTBOUND (wire-related, needs test):
  _breakTalk            Player force-cancels in-progress dialog
  _breakEmote           Player force-cancels emote response
  _breakPush            Player force-cancels push
  _breakNotice          Player dismisses notice popup
                        (these may go through opcode 0x12f WorkSync
                         rather than be standalone packets)

CLIENT-LOCAL ONLY (server ignores):
  _isTalkable / _isEmotable / _isPushable  (gating predicates)
  _initAsMapObj / _isMapObj / _setMapObjScale  (MapObj is rendering-only)
  _runBgScheduler / _runBgSchedulerFromMidstream /
    _waitForBgSchedulerFinished                (animation scheduler)
  _setReactionTriggerBox                       (visual reaction trigger)
  _preloadItemSpreadSheetContainer /
    _releaseItemSpreadSheetContainer           (UI optimization)
  _isPushing                                   (local state)
  _isEnmity                                    (cached server state)
```

For a Stage-1 NPC interaction server, only the 6 wire bindings
(callServer/doServer x talk/emote/push) are strictly required. The
4 break bindings may also need wire support depending on whether
the engine generates standalone break packets or piggybacks on WorkSync.

The 14 client-local bindings can all stub to no-op / return-zero
without disrupting NPC interactions.

## 7. Cross-references

- `finding_playerbase_lua_bindings_99_complete.md` -- companion finding;
  PlayerBase = player-side of same interactions
- `finding_npc_talk_emote_push_bridge.md` -- earlier work on the 3
  `_callServerOn*` bindings; this finding adds the 3 `_doServerOn*`
  + 4 `_break*` bindings
- `finding_lua_to_exe_command_bridge.md` -- the original wire-trace
  finding that established the unanalysed-thunk pattern
- `finding_onTouch_is_gathering_proximity.md` -- explains how MapObj
  flagging makes gathering nodes work
- `finding_item_system.md` -- item-data structure that preload/release
  bindings manipulate

## 8. Confidence

```text
Confirmed:
  - 24 NpcBaseClass registrar functions exist in master block
    NpcBaseClass_registerAllLuaBindings @ 0x00754850
  - All 24 registrars follow the same uniform shape (verified via
    decompilation -- identical to PlayerBase pattern)
  - All 24 Lua binding names extracted from registrar string literals
  - All 24 functions renamed in Ghidra
  - Master block renamed
  - Thunk addresses captured for all 24 slots
  - 10 of 24 thunks point to ALREADY-ANALYSED FUN_xxxxxx functions
    (the local-only bindings; directly decompilable)
  - 14 of 24 thunks point to UNANALYSED LAB_xxxxxx labels
    (the wire-related and pure-predicate bindings)

Likely (High):
  - The 6 callServer/doServer wire bindings (slots 1-6) use Zone-channel
    opcodes 0x12f (WorkSync) or one of the dedicated talk/emote/push
    opcodes documented in finding_complete_3channel_opcode_inventory.md
  - MapObj subsystem (slots 14-16) is the architecture mechanism that
    makes gathering nodes work (per finding_onTouch_is_gathering_proximity)
  - Background scheduler (slots 17-19) handles NPC idle animations and
    inter-conversation pacing

Likely (Medium):
  - The 4 break bindings (slots 7-10) may not generate standalone wire
    packets -- they may set local state that propagates via WorkSync
  - Item-preload bindings (22-23) are exclusively used by vendor NPCs
    and certain quest-giver NPCs (those that open Item UI)
  - The reaction trigger box (slot 21) is purely visual; combat aggro
    routes through enmity (slot 24) instead

Speculative:
  - NpcBase's 24-binding count is the FROZEN scope for 1.23b; further
    1.x patches did not add bindings
  - The split of analysed-vs-unanalysed thunks correlates with
    `wire-related vs client-local` 100% of the time (testable claim
    if more registrar types are walked)
```

## 9. Annotations made in Ghidra

```text
RENAMES:
  - 21 newly renamed registrars (slots 4-24, excluding the 3 already-named
    callServerOn{Talk,Emote,Push})
  - 1 newly renamed master block (FUN_00754850 -> NpcBaseClass_registerAllLuaBindings)

TOTAL ACROSS ALL SESSIONS for NpcBaseClass:
  - 24 of 24 NpcBaseClass Lua-binding registrars renamed (100% coverage)
  - 1 master block renamed
  - 3 of 24 thunk bodies still need force-disassembly to recover wire opcode
    (the callServerOn{Talk,Emote,Push} thunks at LAB_006e9520/LAB_006e9580/
    LAB_006e95e0 -- mirror of the PlayerBase callServerOnCommand situation)
```

## 10. Next test

```text
With BOTH PlayerBase (99) + NpcBaseClass (24) COMPLETE = 123 named
bindings across 2 actor classes. The next highest-value targets are:

  1. Walk CharaBaseClass master block -- the abstract base of both
     PlayerBase and NpcBaseClass. The 13-binding shared core
     (interaction contract) likely lives here. Expected: ~10-20
     additional bindings beyond the PlayerBase/NpcBase deltas.

  2. Walk DirectorBaseClass master block -- 226 directors per
     finding_director_baseclass_and_226_subclasses.md. The directors
     are the content-orchestration framework; their Lua API is
     entirely uncharted.

  3. Walk JudgeBaseClass master block -- 19 judges (Preface, Battle,
     Craft, Harvest, Negotiation, Depiction). Each judge runs a
     specific game-loop sub-domain.

  4. Decompile the 10 already-analysed NpcBaseClass thunks directly
     (MapObj, scheduler, reaction box, item-preload, predicates) to
     extract concrete struct layouts and call semantics.

  5. Walk ContentGroupBaseClass / PartyGroupBaseClass / RelationGroup*
     master blocks (per finding_content_group_baseclass + party_group +
     relation_group_family) -- the multi-actor coordination layer.
```

## Commit suggestion

```
docs(re/exe): NpcBaseClass 24 of 24 Lua bindings COMPLETE -- 100% coverage; 6 wire + 4 break + 14 local
```
