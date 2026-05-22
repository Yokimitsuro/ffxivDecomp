# Finding: `WorldMaster` Singleton and the Actor Packet Flow

Reading of the deciphered `world/worldmaster*.lua` family plus the
`actor/player` base classes, recovered from
`docs/re/lua/finding_lpb_format_blocker.md`'s decoder.

Sources read for this finding (deciphered paths):

```text
nvsy6/nvsy6x9rq5s.lua          -> world/worldmaster.lua            (2,614 B base)
nvsy6/nvsy6x9rq5s_5o5wq.lua    -> world/worldmaster_event.lua      (7,888 B)
nvsy6/nvsy6x9rq5s_p.lua        -> world/worldmaster_u.lua          (4,333 B native bindings)
97qvs89r57y9rr.lua             -> actorbaseclass.lua               (root; defines empty hooks)
729s9/uy9l5s/uy9l5s89r57y9rr.lua -> chara/player/playerbaseclass.lua (~50 KB; real packet handlers)
```

## What WorldMaster is

`WorldMaster` is a **singleton** representing the world / server-time
service inside the client. Lua scripts dereference the global
`worldMaster` to call it. It is bound to a static actor with ID
**`310001`** (acquired via `_getStaticActor(310001)` in `_onInit`).

```lua
function WorldMaster:_onInit()
  self:_callSuperClassFunc("_onInit")
  self:_loadTextDataPermanently(39, "worldMaster")     -- text sheet #39
  _getStaticActor(310001)                              -- bind static actor
end
```

`WorldMaster:_onReceiveDataPacket` is defined as **empty** in the base
file — i.e. the WorldMaster singleton does **not** route incoming IPC
packets directly. Its role is "world-scope utility object", not
"network handler".

## Native bindings WorldMaster exposes to Lua

From `worldmaster_u.lua` (the `_inl` -> `_cpp` table):

```text
_getServerTime_cpp                returns server epoch seconds (uint32)
_getHydaelynHour_cpp              hour 0..23 in Eorzean time
_getHydaelynDay_cpp               day of Eorzean week
_getHydaelynTime_cpp              raw Eorzean time
_getHydaelynMoon_cpp              moon phase
_getSpecialEventWork_cpp          query special-event state (Halloween, etc.)

_printLog_cpp                     formatted log line
_printDebugLog_cpp                debug log line

_getMyPlayer_cpp                  the local player actor
_getPendingCutSceneActor_cpp      cutscene target actor

_loadWord_cpp(self, ...)          load a "Word" (area/zone unit)
_unloadWord_cpp(self, ...)        unload it

_runCharaSchedulerTutorial_cpp                   tutorial scheduler control
_waitForCharaSchedulerTutorialFinished_cpp
_lookAtPlayerTutorial_cpp / _cancelLookAtPlayerTutorial_cpp
_aimCameraTutorial_cpp    / _cancelAimCameraTutorial_cpp
_isKeyboardOnlyTutorial_cpp

_transformIntoChocobo_cpp(self, ...) / _cancelTransformIntoChocobo_cpp
_aimCameraChocobo_cpp                / _cancelAimCameraChocobo_cpp
```

The convention is consistent: the Lua-visible name is `_xxx` and the
inline forwarder `_xxx_inl` returns `("self", "_xxx_cpp")` so the LGE
runtime knows the binding key.

## Server time → Eorzea (Hydaelyn) time

`worldmaster_event.lua` shows the JavaScript-style time conversion that
the client expects to be in agreement with what the server tells it via
`_getServerTime_cpp`:

```lua
function WorldMaster:isHydaelynNight(hour)
  local h = self:_getHydaelynHour(hour)
  return not (5 <= h and h < 19)        -- night = before 5:00 or 19:00+
end

function WorldMaster:getGuildleveTime()    -- 12-hour cycles
  local t = worldMaster:_getServerTime()
  local hourBlock = floor(t / 3600)
  local cycleIndex = floor(hourBlock / 12) + 1
  local cycleEndAt = cycleIndex * 12 * 3600
  local hoursRemaining = 11 - (hourBlock % 12)
  return cycleEndAt, hoursRemaining
end

-- getBoostTime() is identical to getGuildleveTime() (alias).
function WorldMaster:getAnimaTime()        -- 4-hour cycle (Anima regen)
  ...
end

function WorldMaster:calcJSTWeekAndDay(serverTime)   -- JST = UTC+9
  local jstTime = serverTime + 9 * 3600
  local daysSinceEpoch = floor(jstTime / 86400) + 3   -- +3 -> Sunday offset
  local weekday = math.fmod(daysSinceEpoch, 7)
  local weekIndex = math.floor(daysSinceEpoch / 7)
  return weekIndex, weekday
end
```

**Server implication for time**:

- The server's `_getServerTime` response (whatever IPC carries it) is a
  plain **unsigned 32-bit seconds-since-some-epoch**, *not* a packed
  Eorzean time. The client does the Eorzean conversion itself.
- The client computes guildleve / boost windows in fixed 12-hour real
  buckets, and Anima regen in 4-hour buckets, both keyed off the same
  server-time epoch. If a test server returns a fixed/synthetic value,
  guildleves / anima will simply land in whatever bucket the value
  selects.
- JST is the wall-clock the client thinks the world runs on
  (`+9 * 3600`). Day-of-week / weekly events are anchored on JST.

## Event/dialog and notification API exposed to scripts

WorldMaster wraps the `desktopWidget` global to give scripted events a
clean way to message the player. All of these end up displayed by the
desktop widget (UI), but they map to fixed numeric "channels" the C++
side recognises:

```text
WorldMaster:say(text, ...)        -> desktopWidget:showMessage(self, 40, text, ...)
WorldMaster:notify(text, ...)     -> desktopWidget:showLog(self, 32, text, ...)
WorldMaster:alert(text, ...)      -> desktopWidget:showLog(self, 33, text, ...)
```

Channel ids that fall out of this:

```text
32  generic log line       (notify)
33  alert / warning        (alert)
40  chat say / message     (say)
```

Dialog APIs:

```text
WorldMaster:ask(prompt, kind, ?, startIdx, count, ...)
  -> desktopWidget:askForEventMode(actor, prompt, kind, mode=1,
                                   showProgress=false, allowCancel=true,
                                   startIdx, choices_table, ...)
  Returns: index of chosen option, or `nil` if the player cancelled
           (askForEventMode returns -3 on cancel; ask() maps that to nil).

WorldMaster:askRestrictChoices(...)         -- variadic boolean mask
WorldMaster:askMultipleTextMacro(...)       -- multi-select
```

**Server implication for events/dialog**:

- When a server pushes a "scripted event start" (the protocol carrier
  for an NPC dialog or scene), the client expects to be able to call
  back into `desktopWidget:askForEventMode` to obtain the player's
  choice. The server therefore must:
  1. Send an IPC packet that begins the event (the event id + parameters).
  2. Wait for a return packet from the client that carries the choice
     index.
  3. Treat any choice value of `-3` (or whatever the wire equivalent is)
     as "cancelled" and roll back.
- "Eventmode" is a UI state (the box-and-choices presentation). Servers
  don't drive it directly; they trigger it via the scripted-event
  payload, and the script (a `.lpb` registered for that event id) calls
  the WorldMaster dialog API.

## Actor packet handler hook surface (the *real* dispatch)

`ActorBaseClass` (the root of every Lua-side actor type) defines five
empty hooks:

```text
ActorBaseClass:_onInit
ActorBaseClass:_onFinalize
ActorBaseClass:_onTimer(timerId, ...)
ActorBaseClass:_onReceiveDataPacket(packetType, ...)
ActorBaseClass:_onReceiveTimingPacket(timingType, ...)
```

Every concrete actor class inherits these and overrides as needed. The
overrides chain via `self:_callSuperClassFunc("_onXxx", ...)`.

`PlayerBaseClass` (the local-player actor) gives the **richest** real
implementation of `_onReceiveDataPacket`:

```lua
function PlayerBaseClass:_onReceiveDataPacket(packetType, ...)
  self:_callSuperClassFunc("_onReceiveDataPacket", packetType, ...)
  if packetType == "requestedData" then
    local a, b = ...
    desktopWidget:processRecievedRequestedDataForWidget(a, b, select(3, ...))
  elseif packetType == "attention" then
    local a, b, c = ...
    desktopWidget:processUpdatePublicInformationDialog(a, b, c, select(4, ...))
  else
    if type(packetType) == "number" then
      local a, b, c = ...
      desktopWidget:processUpdateGeneralNotificationDialog(packetType, a, b, c, select(4, ...))
    end
  end
end
```

So the `packetType` argument that the **C++ PacketProcessor** hands to
Lua-side actor handlers is one of:

```text
"requestedData"   string  - response to a client data request
                            -> widget callback `processRecievedRequestedDataForWidget`
"attention"       string  - public information / system attention
                            -> widget callback `processUpdatePublicInformationDialog`
<number>          uint    - "general notification" id; the number itself
                            is the notification subtype (level-up, gil
                            gain, item received, etc.)
                            -> widget callback `processUpdateGeneralNotificationDialog`
other strings     string  - delegated to the parent class (CharaBaseClass,
                            ActorBaseClass) for further handling, or to
                            sibling sub-modules (craft, harvest, etc.)
```

`PlayerBaseClass:_onReceiveTimingPacket(timingType, value, more...)` —
seen branch handles **timing type `5` while inside an Instance Raid**,
fetches static actor `24301`, and invokes `_executeCommand(commandName,
actor, 30004)`. This is the "instance raid duration timer" hook
(durations command id 30004).

## What this implies for the Lua bridge in the EXE

The `PacketProcessor` secondary processor (documented at
`PacketBufferBase+0x78` in `finding_ipc_channel_framing.md`) does
**more than pass raw bytes** to Lua. It performs a first-stage decode
of the IPC payload and hands Lua a higher-level call:

```text
target_actor:_onReceiveDataPacket(packet_type_string_or_uint, payload_fields...)
target_actor:_onReceiveTimingPacket(timing_type_uint, value_uint, ...)
```

The C++ side therefore:

1. Reads segment-3 IPC payload bytes (see segment doc).
2. Looks up the target actor by the dispatch id (the segment +0x08 field —
   see `finding_packet_dispatch_by_id.md`).
3. Decides whether this is a "data" packet or a "timing" packet.
4. Decodes a small known field as `packetType`:
   - if it matches a known string-typed id, pushes the string literal
     (`"requestedData"`, `"attention"`, etc.);
   - otherwise pushes the numeric id directly.
5. Pushes the remaining payload as positional arguments to Lua and
   invokes the actor's appropriate hook.

The known string `packetType` set we can already enumerate from
`PlayerBaseClass` and from the player sub-modules:

```text
requestedData        attention
talkDefault          (from isEventPlaying check)
emoteDefault1..8
pushDefault          pushCommand          noticeEvent
```

There will be more once `chara/player/playerbaseclass_craft.lua`,
`...harvest.lua`, `...negotiation.lua`, `...cliprog.lua` are read
(they're imported at the top of the player base file).

## Assessment

```text
Confirmed:
  - WorldMaster is a singleton bound to static actor 310001, not a
    packet handler. Its _onReceiveDataPacket is empty.
  - _getServerTime returns a raw uint32 epoch in seconds; all Eorzean
    time conversion is client-side.
  - desktopWidget channels for messaging: 32 (log), 33 (alert),
    40 (say). Dialog API is askForEventMode / askForEventModeMultiple;
    cancel returns -3 and Lua wrappers normalise that to nil.
  - ActorBaseClass defines the five lifecycle hooks; every concrete
    class overrides via _callSuperClassFunc.
  - The C++ PacketProcessor delivers packets to Lua as
    actor:_onReceiveDataPacket(packetType, fields...), where
    packetType is either a known string literal or a numeric
    notification subtype.

Likely (High):
  - "Word" in _loadWord_cpp / _unloadWord_cpp refers to area/zone
    units (the server-side scope of a loadable area). Confirms with
    the C++ RTTI for Application::Main::WordWordObj... (not yet
    cross-checked, but the WorldMaster method names align).
  - The set of recognised string-typed packetTypes is small and lives
    in the C++ side (string interning at decode time). Lua never sees
    arbitrary strings.

Likely (Medium):
  - Static actor id 310001 = WorldMaster service object; ids in the
    300000-range are reserved for system singletons.
  - Static actor id 24301 (seen in the instance-raid branch) is the
    "Instance Raid" service object, similarly system-side.
  - Command id 30004 (passed to _executeCommand in the instance raid
    timing branch) is the "Instance Raid Timer Tick" command.

Speculative:
  - That every notification-subtype number on the wire matches an
    entry in a sheet loaded by _loadTextDataPermanently. Sheet 39
    ("worldMaster") is one of them; widgets likely load others. This
    would mean translating notification numbers to user-facing strings
    requires shipping the right sheet ids.

Next test:
  - Read chara/player/playerbaseclass_{craft,harvest,negotiation,cliprog}.lua
    to enumerate the remaining packetType strings and to see which
    subsystems push their own outgoing packets via PacketRequestBase.
  - Read chara/player/playerbaseclass_u.lua (override) to see the
    full native binding table for PlayerBaseClass.
  - Cross-check the static actor ids 310001 and 24301 against any
    *_cpp string table in the EXE to confirm naming.

Commit suggestion:
  docs(re/lua): document WorldMaster + actor packet flow (Lua side)
```

## Server implication (consolidated)

For a minimal viable server bring-up, this finding adds:

- **Time service** — the server must reply to whatever IPC backs
  `_getServerTime_cpp` with a uint32 seconds. Eorzean conversion is
  the client's job; *any monotonic value* will keep clocks moving.
  For a deterministic test, pin the value or feed wall time. The
  guildleve / anima / weekly windows derive from this value, so a
  fixed server time produces a static "what cycle am I in" state.
- **Notification surface** — when a server pushes an IPC packet
  targeting the local player, the client routes it through
  `PlayerBaseClass:_onReceiveDataPacket`. The minimum set the server
  needs to know about:
  - if the C++ side decodes it as `"requestedData"`, the player UI
    expects to receive whatever data was previously requested.
  - if `"attention"`, it pops a public-information dialog.
  - if a numeric subtype, it produces a general notification (level
    up, gil gain, etc.) — `desktopWidget:processUpdateGeneralNotificationDialog`
    is what actually renders these.
  Sending an unknown string packetType is silently dropped by Lua
  (it falls through the elseif chain).
- **Event dialogs** — server-driven NPC dialog must arrive as an
  event-start payload; the client opens `askForEventMode` with the
  choices the script declares; the client returns the chosen index
  in the response packet (negative-3 / nil for cancel). The server
  must accept `nil`/cancel without progressing the quest state.
- **Static service actor ids** to plan for in the actor table:
  - `310001` = WorldMaster (server time, day/night, special events,
    chocobo state)
  - `24301`  = Instance Raid service (instance timer events)
  Both are pure server-side singletons; no spatial coordinates.

This is enough to satisfy world-level Lua bootstrap without yet
serving any zone packets.
