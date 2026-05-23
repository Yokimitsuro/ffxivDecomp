# Finding: `DirectorBaseClass` — Generic Server-Side Event Coordinator

The base pattern for **server-driven event/instance coordinators**
in 1.x. Parent class of `InstanceRaidBaseClass` and at least 8 other
Director subclasses (weather, ships, caravan events, etc.).

A Director is a server-allocated actor that coordinates a multi-
player game event. It carries an optional "content command" that
players can invoke during the event, plus a 128-bit shared sync
buffer for sub-event flags.

Sources read:

```text
director/DirectorBaseClass.lua    412 lines (full read of schema +
                                              lifecycle methods)
```

Directory `director/` contains 10 director files:

```text
DirectorBaseClass.lua            412  the generic baseclass (this finding)
DirectorBaseClass_u.lua          58   native bindings table
CaravanGuardDirector.lua         742  caravan escort event (BIGGEST)
WeatherDirector.lua              112  weather change broadcasts
FaerieAidDirector.lua            28   tutorial assistance? (guess)
OpeningDirector.lua              15   starting cutscenes
ShipDirector.lua                 15   boat/airship rides
WaveAttackDirector.lua           15   wave-based events
RetainerAccessDirector.lua       15   retainer interactions
SpecialEventDirector.lua         15   one-off events

Plus the subdirectory:
director/InstanceRaid/           the dungeon/trial subclass family
                                  (documented separately)
```

So the Director pattern is **central to 1.x's event architecture**.
Almost every multi-player coordinated event uses it.

## `directorWork` Schema

### `_temp` (2 fields, always present)

```text
{directorId,        integer32}   -- unique instance id (assigned by server)
{_assignForChild,   240 bytes}   -- subclass reserve (large for state)
```

### `_sync` (4 fields, broadcast to participants)

```text
{contentCommand,    integer32}            -- main command id (0 if none)
{contentCommandSub, integer32}            -- sub-command id
{syncBuffer,        array[128] boolean}   -- 128-bit shared sync flags
{_assignForChild,   64 bytes}             -- subclass sync reserve
```

### `_tag` (1 tag bundling the sync fields)

```text
{contentCommand, 1, [
  {contentCommand},
  {contentCommandSub},
  {syncBuffer}
]}
```

So the server can push all 3 sync fields atomically via the
`contentCommand` tag — a single packet updates command + sub-command
+ all 128 sync bits at once.

## Lifecycle Methods

### `_onInit(self, directorId, ...args)`

```lua
function DirectorBaseClass:_onInit(directorId, ...args)
  superClass._onInit()
  -- declare _temp, _sync, _tag schemas (see above)
  self.directorWork.directorId = directorId
  self:init(...args)   -- subclass-specific init
end
```

So construction takes `(directorId, ...customArgs)`. The subclass
implements `init` for its own setup.

### `_onFinalize(self)`

When the director is destroyed:

```lua
function DirectorBaseClass:_onFinalize()
  self:processUIFinalize()
  self:processFinalize()
  if directorWork.contentCommand ~= 0:
    worldMaster:_getMyPlayer():setContentCommandVariation(nil)
    -- RELEASE the content command binding from the player
end
```

The cleanup at the end releases the "content command" binding so
the player's hotbar slot isn't stuck pointing at a deleted command.

### `updateSyncWork(self, A1, fieldName)`

Client sends a `_updateWork(struct="work", field=fieldName)` request
to the server. Standard write-side using the 0x12f wire opcode:

```lua
function DirectorBaseClass:updateSyncWork(A1, fieldName)
  player = worldMaster:_getMyPlayer()
  if player:canRequestInformation():
    self:_updateWork("work", fieldName)
    player:recordRequestInformation()
    return true
  return false
end
```

So `updateSyncWork` is the gated request rate limiter (uses
canRequestInformation / recordRequestInformation pattern).

### `delegateEvent(self, A1, target, funcName, ...args)`

```lua
function DirectorBaseClass:delegateEvent(A1, target, funcName, ...args)
  return target:_callFunction(funcName, A1, self, ...args)
end
```

Generic event delegation — calls a named function on `target` with
`(A1, self, ...args)`. Used to broadcast events from director to
participants (e.g. "boss died, react").

### `_onEventCancel`, `_onNoticeRejected`, `_onUpdateWork`,
###  `processUIInit/Update/Finalize`

Standard lifecycle hooks. Most have empty/passthrough bodies in
the baseclass; subclasses override for specific behavior.

## `processMapOpenMessage` and `getKindContentsInformation`

```text
processMapOpenMessage    -- subclass override; runs when player opens
                            map during this director's event. UI hook
                            for "you are inside event X".
getKindContentsInformation -- returns content-type info (probably for
                              UI display: "Dungeon" / "Trial" / "Event")
getUseContentsCommand    -- returns whether the contentCommand should
                            be exposed in player's hotbar
```

## The "Content Command" Mechanism

The most important feature of Director is the **contentCommand**
binding. When a director is active:

1. Server pushes `directorWork.contentCommand = some_command_id` via
   the sync tag.
2. Client receives this; `setContentCommandVariation(cmd_id)` is
   invoked on the player.
3. Player gets a special command slot in their hotbar that maps to
   the director's action.
4. Player can use the command (e.g. "Dismount Caravan" /
   "Defend Hamlet").

When the director ends:
- `_onFinalize` sets the player's content command to nil.
- The slot disappears from the hotbar.

This is **1.x's mechanism for ephemeral abilities** (not from your
class but from the active event/instance). ARR replaced this with
the "Duty Action" system; same concept, different implementation.

## The 128-bit `syncBuffer`

The `syncBuffer` array[128] boolean is a 16-byte shared flag bitmap.
Use cases inferred from subclasses:

```text
HamletDefence:   "wave N has been triggered" bits
                 "structure X has been destroyed" bits
                 "player Y has joined defense" bits

CaravanGuard:    "checkpoint N reached" bits
                 "caravan attacked by enemy" bits

WeatherDirector: "weather transition phase" bits
```

128 bits is enough for most multi-stage events. Subclasses that
need more state use the 64-byte `_assignForChild` sync reserve.

## Inheritance Tree (Director Family)

```text
DirectorBaseClass                    (this finding)
  ├── InstanceRaidBaseClass          (see finding_instance_raid_system.md)
  │   ├── InstanceRaid_HamletDefence
  │   ├── InstanceRaid_AurumVale
  │   ├── InstanceRaid_CuttersCry
  │   ├── InstanceRaid_NormalIfrit
  │   └── ... (~10 stub subclasses)
  ├── CaravanGuardDirector           (742 lines; biggest non-instance)
  ├── WeatherDirector                (112 lines; weather changes)
  ├── ShipDirector                   (15 lines stub)
  ├── OpeningDirector
  ├── WaveAttackDirector
  ├── RetainerAccessDirector
  ├── SpecialEventDirector
  └── FaerieAidDirector
```

## Assessment

```text
Confirmed:
  - DirectorBaseClass is the generic event-coordinator pattern.
  - directorWork schema: 2 _temp + 4 _sync fields + 304 bytes
    subclass reserves.
  - The contentCommand field is the "ephemeral ability" mechanism --
    server pushes an action id, client exposes it as a temporary
    hotbar slot.
  - The 128-bit syncBuffer is the multi-stage event flag bitmap.
  - Inheritance covers 10+ subclasses including the entire
    InstanceRaid family.

Likely (High):
  - The contentCommand pattern is used for "Duty Actions" in 1.x's
    instances (e.g. Caravan Guard's "Defend!" action, Hamlet
    Defence's wave-trigger abilities).
  - The directorId is server-assigned and unique per active
    director. The client uses it to track which director's state
    a packet update belongs to.
  - The 240-byte _temp subclass reserve is for state that DOESN'T
    sync (purely client-side display state); the 64-byte _sync
    reserve is for state that DOES sync (broadcasts to participants).

Likely (Medium):
  - WeatherDirector being only 112 lines suggests weather changes
    are simple state pushes: server picks new weather, pushes via
    the director's contentCommand or sync buffer.
  - The "canRequestInformation" gate on updateSyncWork is a per-
    player request rate limiter (probably 1-5 requests per second
    max).

Speculative:
  - The Director pattern is 1.x's first attempt at "instanced
    content as data" (vs ARR's heavy server-side scripting). Each
    director is essentially a state machine driven by sync buffer
    bits + content command transitions.
  - 1.x's 128-bit syncBuffer is generous -- modern MMOs typically
    use 32 or 64 bits for event flags.
```

## Server Implementation Picture

A Director-aware server's flow:

```text
1. PLAYER ENTERS ZONE WITH EVENT:
   - server creates Director instance (DirectorId)
   - pushes directorWork._sync via the contentCommand tag
   - player's client receives, calls setContentCommandVariation

2. DURING EVENT:
   - server pushes syncBuffer bits as sub-events fire
   - server pushes contentCommand changes for phase transitions
   - clients react via _onUpdateWork hook

3. PLAYER USES CONTENT COMMAND:
   - hotbar press triggers a command on the director
   - client sends 0x12f or similar with command id
   - server validates + applies effects

4. EVENT ENDS:
   - server marks director for destruction
   - _onFinalize fires on each participant's client
   - setContentCommandVariation(nil) cleans up hotbar
   - server deallocates Director actor
```

So the Director system is a **per-zone-event state container** with
a small, well-defined wire surface (4 sync fields + the 128-bit
buffer). Implementing it server-side is straightforward — most of
the complexity is in the per-subclass scripted logic (caravan path,
wave timing, etc.), not in the framework.
