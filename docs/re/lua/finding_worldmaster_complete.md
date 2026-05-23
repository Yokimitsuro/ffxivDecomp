# Finding: `WorldMaster` Complete — Time, Communication, Native Bindings

The `WorldMaster` singleton actor (id `310001`) is the **central
coordinator** for global game state on the client side. It handles
the Eorzea time/calendar, broadcast channels (say/notify/alert),
tutorial system, chocobo transformation, and exposes 24 native
bindings for global queries.

Sources read:

```text
world/WorldMaster.lua          135 lines  (main file, lifecycle + time util)
world/WorldMaster_event.lua    329 lines  (event channels + game-time cycles)
world/WorldMaster_u.lua        231 lines  (24 native binding stubs)
```

Reaches the singleton via `_getStaticActor(310001)` in `_onInit`.

## Eorzea Time Cycles

### Day/Night

```lua
function WorldMaster:isHydaelynNight(A1)
  hour = self:_getHydaelynHour(A1)
  if hour < 5 or hour >= 19:
    return true   -- night
  return false    -- day
end
```

So night = **19:00 to 04:59** Eorzea time; day = 05:00 to 18:59.
That's a 10-hour night vs 14-hour day — favoring daylight gameplay.

### 12-Hour Cycles (Guildleves + XP Boost)

`getGuildleveTime()` and `getBoostTime()` are byte-identical
functions implementing a **12-hour reset cycle** (in SERVER hours,
not Eorzean):

```lua
function WorldMaster:getGuildleveTime()  -- same code as getBoostTime
  serverTime = _getServerTime()
  hours = floor(serverTime / 3600)
  currentCycle = floor(hours / 12)
  nextResetSeconds = (currentCycle + 1) * 12 * 3600
  remainingHours = 11 - (hours % 12)
  return nextResetSeconds, remainingHours
end
```

So **leve allowances and XP boost both reset every 12 hours** on
the same boundary. Reset times in UTC depending on the server's
epoch alignment — likely 12:00 UTC and 00:00 UTC if aligned to
midnight.

### 4-Hour Cycle (Anima)

`getAnimaTime()` uses a 4-hour cycle:

```lua
function WorldMaster:getAnimaTime()
  hours = floor(serverTime / 3600)
  currentCycle = floor(hours / 4)
  nextResetSeconds = (currentCycle + 1) * 4 * 3600
  remainingHours = 3 - (hours % 4)
  return nextResetSeconds, remainingHours
end
```

**Anima** was 1.x's teleport-currency. Each player regenerated
anima slowly (1 per 6 server-hours per 1.x design notes). The
4-hour cycle here is the "next tick" boundary.

### JST Calendar (for Daily Resets)

`getJSTWeekAndDay()` computes the Japan Standard Time (UTC+9)
week-of-year and day-of-week from server time:

```lua
function WorldMaster:calcJSTWeekAndDay(serverTime)
  jstTime = serverTime + 9 * 3600        -- shift to UTC+9
  jstDays = floor(jstTime / 86400)
  shifted = jstDays + 3                   -- align Sunday=0 to week start
  dayOfWeek = shifted % 7
  weekIndex = floor(shifted / 7)
  return weekIndex, dayOfWeek
end
```

The +3 shift suggests the server's epoch (1970-01-01) was a
Thursday, so adding 3 days aligns it to start Sunday=0.

So 1.x had **JST-based daily/weekly reset boundaries** for events
and rewards. Standard for a Japan-developed MMO of that era.

## Communication Channels (final confirmation)

Three player-broadcast methods, all routing through `desktopWidget`:

```text
say(msg, ...)     -> desktopWidget:showMessage(self, channel=40, ...)
notify(msg, ...)  -> desktopWidget:showLog    (self, channel=32, ...)
alert(msg, ...)   -> desktopWidget:showLog    (self, channel=33, ...)
```

Final desktopWidget channel ID map:

```text
channel  purpose                  example
-------  -----------------------  -----------------------------
32       notification log         "[Info] You received 5 gil"
33       alert log                "[Warning] You're encumbered"
38       NPC say                  NpcBaseClass:say (from npc dialog)
40       player chat say          /say chat from player
```

(Plus channels 41-99 for specific subsystems, not fully mapped.)

## `ask` Family (dialog primitives)

```text
ask(...)                  -- general dialog with N choices
askRestrictChoices(...)   -- only enabled choices shown
askMultipleTextMacro(...) -- multi-line macro dialog (chat/log)
```

These are the WorldMaster wrappers around `desktopWidget:askForEventMode`
(the unified ask primitive from finding_npc_dialog_protocol.md).

So WorldMaster:ask is functionally identical to NpcBaseClass:ask
— same primitive, different ownership context (worldMaster = global
dialog vs npc-specific dialog).

## 24 Native Bindings (`WorldMaster_u.lua`)

```text
TIME / CALENDAR
  _getServerTime_inl           server epoch seconds
  _getHydaelynHour_inl          Eorzea current hour (0-23)
  _getHydaelynDay_inl           Eorzea day of week
  _getHydaelynTime_inl          Eorzea current time (HH:MM)
  _getHydaelynMoon_inl          Eorzea moon phase

EVENT SYSTEM
  _getSpecialEventWork_inl     get current special event state

PLAYER / ACTORS
  _getMyPlayer_inl             local player actor ref
  _getPendingCutSceneActor_inl pending cutscene actor

LOGGING
  _printLog_inl                generic log output
  _printDebugLog_inl           debug log (probably disabled in retail)

TEXT DATA
  _loadWord_inl                load text by id
  _unloadWord_inl              unload cached text

TUTORIAL SYSTEM (7 natives)
  _runCharaSchedulerTutorial_inl
  _waitForCharaSchedulerTutorialFinished_inl
  _lookAtPlayerTutorial_inl
  _cancelLookAtPlayerTutorial_inl
  _aimCameraTutorial_inl
  _cancelAimCameraTutorial_inl
  _isKeyboardOnlyTutorial_inl

CHOCOBO SYSTEM (4 natives)
  _transformIntoChocobo_inl
  _cancelTransformIntoChocobo_inl
  _aimCameraChocobo_inl
  _cancelAimCameraChocobo_inl
```

The naming suffix `_inl` means "Lua-binding inline thunk" (vs
real C++ function — these are direct Lua bridges).

## Notable Surface Areas

### Tutorial System

7 dedicated natives for tutorial-driven NPC animation + camera
control. The naming pattern matches the chara scheduler IDs from
`finding_npc_event_system.md` (the 0x18098000 range). So tutorial
NPCs are puppeted via specialized camera/look helpers, not the
generic NPC animation path.

### Chocobo Mounting

4 natives for the chocobo transformation. The "Transform" semantics
(vs "Mount") matches 1.x's chocobo design where the player BECAME
a chocobo (model swap), didn't just sit on one. Helmet pop-on
toggled the model + applied chocobo movement physics.

### Special Event System

`_getSpecialEventWork_inl` — exposes current special event data.
This is a stateful query (likely 1.x's "current global event"
tracker for Halloween/Christmas/Valentine's seasonal content).

## Assessment

```text
Confirmed:
  - WorldMaster singleton lives at actor id 310001.
  - 24 native bindings spanning time, player, logging, tutorial,
    chocobo, and event data.
  - 12-hour reset cycle for guildleve + XP boost (identical code
    paths).
  - 4-hour reset cycle for anima regeneration.
  - Day/night divide: 19:00-04:59 = night (Eorzea hours).
  - Communication channels: 32 (notify), 33 (alert), 40 (say) --
    plus 38 (NPC say) from prior finding.
  - JST-based week/day calendar for daily/weekly resets.

Likely (High):
  - Anima regen was 1 anima per ~6 hours (the 4-hour cycle here
    is the TICK boundary, not the full regen interval). Players
    capped at ~12-16 anima.
  - The Hydaelyn* time bindings convert server seconds to Eorzea
    time. Ratio is probably 60:1 (1 server hour = 60 Eorzea hours,
    same as ARR). So Eorzea day = 60 server minutes.
  - The tutorial natives are ONLY usable while a player is in the
    tutorial state (server checks tutorial flag). Beyond tutorial,
    they're no-ops.

Likely (Medium):
  - Special event work is server-pushed (the bindWork system has
    no specific "specialEvent" binding catalogued; suggests the
    state is loaded via _loadWord or a separate channel).
  - The chocobo transformation is HARDCODED model swap (vs ARR's
    mount system which is a separate actor riding state).

Speculative:
  - The 7-day JST week alignment suggests the Japanese server
    epoch is Sunday-aligned. 1.x reset events probably fired at
    JST midnight (15:00 UTC).
  - The byte-identical code of getGuildleveTime and getBoostTime
    is a copy-paste bug in the SE source -- both reset on the
    same boundary, so they share the implementation.
```

## Server Implementation Picture

A WorldMaster-aware server tracks:

```text
GLOBAL TIME STATE:
  - server epoch (seconds since 1970-01-01 UTC)
  - eorzea time (derived: serverSeconds * 60 = eorzea seconds)
  - jst calendar position (server + 9 hours, day-of-week, week-of-year)

RESET BOUNDARIES (broadcast to clients via WorldMaster):
  - guildleve reset every 12 server-hours
  - XP boost reset every 12 server-hours (same boundary)
  - anima regen tick every 4 server-hours
  - JST daily reset (15:00 UTC = midnight JST)
  - JST weekly reset (e.g. Sunday 15:00 UTC)

COMMUNICATION:
  - say (channel 40) -- player chat broadcast
  - notify (channel 32) -- system info messages
  - alert (channel 33) -- warning messages
  - per-player vs zone-broadcast vs global

EVENTS:
  - special event work (seasonal content state)
  - tutorial state per player

The server doesn't need to PUSH time updates -- clients compute
all of these from the agreed serverTime. Just ensure clock
synchronization on session start.
```

This **closes the global-coordinator surface**. Combined with the
actor sync (charaWork) and the Director pattern (instances), the
client's high-level state is now nearly fully described.
