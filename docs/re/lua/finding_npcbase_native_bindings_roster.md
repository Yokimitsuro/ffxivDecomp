# Finding: NpcBaseClass — 24 Native Bindings (NPC-Specific API)

The NPC-specific Lua-callable C++ surface. NPCs inherit CharaBaseClass's
91 bindings + add 24 NPC-specific bindings = ~115 total bindings
available on any NPC actor.

Sources read:

```text
chara/npc/npcbaseclass_u.lua    237 lines (24 binding declarations)
```

## Roster (24 bindings)

### Map Object Mode (3)

```text
_initAsMapObj()              initialize NPC as map object (sign,
                              chest, etc.)
_isMapObj()                  query: is this NPC a map object?
_setMapObjScale(scale)       set rendering scale for map objects
```

So an NPC can be a **map object** (treasure chest, signpost,
crafting station) — interactable but not a character. Same actor
class, different behavior mode.

### Break / Cancel Operations (4)

```text
_breakTalk()       forcibly end ongoing talk
_breakEmote()      forcibly end ongoing emote
_breakPush()       forcibly end ongoing push interaction
_breakNotice()     forcibly close notice popup
```

Server-triggered breaks (e.g. player moved out of range,
emergency cancel).

### Predicates (4)

```text
_isTalkable()      can this NPC be talked to right now?
_isEmotable()      can emote interaction happen?
_isPushable()      can push interaction happen?
_isPushing()       is the NPC currently being pushed?
```

### Server Talk/Emote/Push Flow (6) — Wire Path

```text
_callServerOnTalk    inform server: talk requested
_doServerOnTalk      ask server to execute talk
_callServerOnEmote   inform server: emote requested
_doServerOnEmote     ask server to execute emote
_callServerOnPush    inform server: push requested
_doServerOnPush      ask server to execute push
```

Symmetrical pattern to PlayerBaseClass's command flow:
- `_callServerOnX` = "I want to do X" (server may validate)
- `_doServerOnX` = "execute X server-side now" (direct request)

These bindings emit wire packets — likely the same family as
opcode 0x12f / 0x12e (work-sync wire). Both NPCs and players use
similar wire mechanisms.

### Reaction Trigger Box (1)

```text
_setReactionTriggerBox(min, max)
            set spatial bounds for proximity-triggered events
            (when player enters this box around the NPC, fire a
             reaction)
```

How NPCs detect player proximity for ambient reactions
("Hey! What do you want?" when player walks near).

### Background Animation Scheduler (3)

```text
_runBgScheduler(id)                   play background animation
_runBgSchedulerFromMidstream(id, t)   start animation mid-way
                                       (t = start time offset)
_waitForBgSchedulerFinished()         yield until animation done
```

"Bg" = Background — these run continuously as the NPC's idle
behavior. Distinct from the CharaScheduler (used for foreground
dialog emotes).

So 1.x NPCs have **two animation layers**:
- **Bg (background)**: continuous idle motion (sweeping floor,
   tending fire, walking patrol)
- **Foreground (CharaScheduler)**: triggered for dialog interactions

### Item Sheet Preloading (2)

```text
_preloadItemSpreadSheetContainer()    preload item data sheet (for
                                       shop / vendor NPCs)
_releaseItemSpreadSheetContainer()    release the sheet
```

Vendor NPCs preload their item catalog when player approaches,
release on departure. Memory optimization.

### Enmity (1)

```text
_isEnmity()      does this NPC currently have aggro on anyone?
```

Combat predicate used by judges (HateType nameplate icons).

## Architecture Notes

```text
Inheritance:
  CharaBaseClass (91 bindings) <- shared base
    └── NpcBaseClass (+24 = 115 total bindings)
        ├── NpcDefault (passive NPCs; tiny subclass)
        ├── + various event-specific NPC subclasses
        └── + monster types (extend battle behaviors)

The 24 NPC-specific bindings cover:
  3 - map object mode toggle
  4 - break/cancel operations (interrupt interactions)
  4 - predicates (talkable/emotable/pushable/pushing)
  6 - server-on-X wire calls (talk/emote/push × 2)
  1 - reaction trigger spatial box
  3 - background animation scheduler
  2 - item sheet preload (vendor optimization)
  1 - enmity check
```

## Key Discoveries

```text
1. NPCs have TWO animation layers:
   - CharaScheduler (foreground; triggered for dialogs)
   - BgScheduler (background; continuous idle motion)

2. Reaction Trigger Box is how NPCs detect player proximity for
   ambient reactions. Spatial, not event-driven.

3. Map Object mode means same actor class can be:
   - An NPC (talkable, animated character)
   - A map object (chest, signpost, vendor stand)
   Distinguished by _initAsMapObj at construction.

4. The talk/emote/push wire flow has TWO paths:
   - _callServerOnX  (request: "I want to...")
   - _doServerOnX    (execute: "do this now")
   Server may validate _callServerOnX before allowing _doServerOnX
   to proceed.

5. Item sheet preload optimization: vendor NPCs load their item
   catalog only when needed. Saves memory; common 1.x design
   given the era's memory constraints.
```

## Complete API Surface (Combined Findings)

```text
Lua-callable native binding totals:

CharaBaseClass:     91  base actor + chara features
PlayerBaseClass:    94  player-specific extensions
NpcBaseClass:       24  npc-specific extensions
WorldMaster:        24  global queries (time, channels, tutorial)
GroupBaseClass:    ~10  group-level operations (from 151-line _u file)
DirectorBaseClass:  ~6  director-level operations (from 58-line _u file)
DesktopWidget:    ~47  UI dispatcher (472-line _u file; PENDING)

ESTIMATED TOTAL: ~296 native bindings for the core gameplay APIs.

(Plus item / area / actor base classes with ~110 bindings each = ~440
bindings if we include peripheral classes.)
```

## Assessment

```text
Confirmed:
  - 24 NPC-specific bindings on top of CharaBaseClass's 91.
  - Two animation layers (foreground CharaScheduler + background
    BgScheduler).
  - Map object mode (npcs can be inanimate items/signs/chests).
  - 6 server-call bindings for talk/emote/push flow (matches
    Lua-side observed _onTalkEvent / _onEmoteEvent / _onPushEvent
    handlers).
  - Vendor optimization via _preloadItemSpreadSheetContainer.

Likely (High):
  - The 6 server calls (_callServerOnX / _doServerOnX) emit wire
    packets in the 0x12d-0x135 range (probably the small ones
    0x131-0x135 since NPC interactions are byte-sized state changes).
  - The reaction trigger box is the spatial primitive for FATE-like
    ambient world events ("guard approaches you", "merchant calls
    out").
  - BgScheduler ids occupy a separate id range from CharaScheduler
    ids (0x18098000+ for chara emotes; bg probably 0x18099000+ or
    similar non-overlapping range).

Likely (Medium):
  - The break operations (_breakTalk/Emote/Push/Notice) fire when
    server cancels mid-flow (player moved out of range, timeout,
    or explicit server stop).
  - The "is X" predicates are query bindings (return immediately
    from cached state, no network).

Speculative:
  - Map object mode used same actor class for code reuse vs ARR's
    separate "EObj" (event object) entity system.
  - The 6-pack of server calls suggests 1.x had a 2-phase commit
    pattern for all NPC interactions: phase 1 "I want to" (call),
    phase 2 "execute" (do). Could be the same packet shape twice
    with a phase flag.
```

This **closes the Chara/Npc/Player native binding surface**.
The remaining big _u files (DesktopWidget at 472 lines = ~47 bindings,
ItemBaseClass at 191 lines, AreaBase at 110 lines) cover non-actor
domains. The core actor model is now fully enumerated.
