# Finding: `InstanceRaid` System — Content/Dungeon/Trial Lifecycle

The Director system that drives instanced content (dungeons, trials,
events) in 1.x. Reading `InstanceRaidBaseClass` exposes the full
lifecycle model: instance enter, tick-based countdown, clear/fail,
cutscenes, and per-instance state.

Sources read:

```text
director/InstanceRaid/InstanceRaidBaseClass.lua    742 lines
                                                    (full read of lifecycle)
```

Directory `director/InstanceRaid/` contains:

```text
file                                purpose
----                                -------
InstanceRaidBaseClass.lua          742  the lifecycle baseclass (this finding)
InstanceRaid.lua                       global module
InstanceRaid_HamletDefence.lua     823  Hamlet Defence event (BIGGEST)
InstanceRaid_HyperIfrit.lua          8  Hyper-Ifrit (stub; inherits all behavior)
InstanceRaid_DarkMoogle.lua          8  Dark Moogle event
InstanceRaid_CuttersCry.lua          8  Cutter's Cry dungeon
InstanceRaid_BeaconBattle.lua        8  Beacon Battle event
InstanceRaid_AurumVale.lua           8  Aurum Vale dungeon
InstanceRaid_NormalIfrit.lua         8  Ifrit (normal mode)
InstanceRaid_NormalGaruda.lua        8  Garuda (normal mode)
InstanceRaid_NormalWhiteGeneral.lua  8  Hydra/Behemoth normal
InstanceRaid_LesserIfrit.lua        25  Easy Ifrit
InstanceRaid_LesserGaruda.lua        8
InstanceRaid_LesserWhiteGeneral.lua 65
```

Most subclasses are STUBS (8 lines) that just `_defineClass` and
inherit all baseclass behavior. The dungeons differ only in their
scripted events (which live elsewhere — probably the
ContentGroup/RelationGroup actor that owns the instance).

`HamletDefence` is the biggest concrete subclass (823 lines) —
likely because of its wave-based event mechanics.

## `instanceRaidWork` Schema (8 fields + 192-byte child reserve)

`instanceRaidWork._temp` declared in `init()`:

```text
{startTime,        integer32}    -- server timestamp when instance began
{finishTime,       integer32}    -- server timestamp when it ends (timeout)
{contentID,        integer16}    -- which dungeon/trial id
{eventType,        integer8}     -- 0..N (event type discriminator)
{countdownStatus,  integer8}     -- 0=no countdown active, 1..7=tier
{clearFlag,        boolean}      -- has the instance been cleared
{initFlag,         boolean}      -- has init completed
{_assignForChild,  192 bytes}    -- reserve for subclass extensions
```

The 192-byte child reserve is huge — allows each instance subclass
to track its own boss state, wave progress, item drops, etc.

## Lifecycle Sequence

```text
1. PLAYER ENTERS INSTANCE
   ↓
2. server sends startEvent(contentID, startTime, finishTime,
                            eventType, alreadyClear)
   - sets instanceRaidWork fields
   - if startTime > 0: arms the countdown timer
   - calls processLogin(true)
   - triggers fadeInNowLoadingForNoticeEventJustInArea + _fadeIn
   - sets initFlag = true
   ↓
3. TICK LOOP (every 1 sec via _setLoopInterval(1)):
   - _onLoop() called
   - computes current countdown tier via getRestTimeStatus()
   - tiers: 1=30min, 2=20min, 3=10min, 4=5min, 5=3min, 6=1min, 7=halftime
   - when tier decreases (time running out), notify via worldMaster:notify
     (msg 52009 for normal countdown, 52092 for halfway warning)
   ↓
4. ... gameplay (boss fights, mob waves, mechanics) ...
   ↓
5a. (CLEAR) server sends clearEvent
   - countdownStatus = 0
   - notify msg (specific per event type)
   - close information widget

5b. (FAIL) server sends failedEvent(failType, ...)
   - failType 1 -> msg 52065 (specific failure)
   - failType 2 -> msg 52054
   - failType 3 -> msg 52010
   - failType 4 -> msg 52093
   - if failType != 1: processFailedEffect + warp out
                       (different wait times: 2=3sec, others=1sec)

5c. (RE-ENTER) server sends reloginEvent
   - cancel countdown
   - notify msg 52021 ("you are in...")
```

## `_onReceiveDataPacket(self, A1, ...)` — Server Commands

Inbound directive from the server. A1 selects the action:

```text
A1 == 1: SET CUTSCENE TIMES + clear flag
         - clearFlag = true
         - extract 2 args (startTime, finishTime)
         - setCountDownTimer(startTime, finishTime, false)
         - close information widget

A1 == 2: MARK CLEAR (no countdown change)
         - clearFlag = true
         - countdownStatus = 0
         - close information widget

A1 == 3: USER MESSAGE
         - call processUserMessage(...args)
         - subclass overrides this for per-event UI
```

So the server has 3 in-band command types for an active instance,
beyond start/clear/fail/relogin. Used for mid-instance events like
"phase 2 boss spawn" or "additional time granted".

## Countdown Tiers and Timing

```text
getRestTimeStatus(): returns 0-7 based on current server time

  serverTime    = worldMaster:_getServerTime()
  halfTime      = ceil((finishTime - startTime) / 2)
  thresholds    = [60, 180, 300, 600, 1200, 1800]  (in seconds)
                   1m   3m   5m   10m   20m   30m

  for tier_i = 1..6:
    threshold = thresholds[tier_i]
    countdownPoint = finishTime - threshold
    if serverTime >= countdownPoint and halfTime > threshold:
      return tier_i
  if serverTime >= startTime + halfTime:
    return 7    # past halfway warning
  return 0      # no countdown announcement
```

Each tier's announcement (from `_onLoop`):

```text
tier  remaining time   notification
----  --------------   ---------------------------
 7    halfway          msg 52092 with arg = halfTime/60 (minutes)
 6    30 seconds       msg 52009 with arg = "30"
 5    20 seconds       msg 52009 with arg = "20"
 4    10 seconds       msg 52009 with arg = "10"
 3    5 seconds        msg 52009 with arg = "5"
 2    3 seconds        msg 52009 with arg = "3"
 1    1 second         msg 52009 with arg = "1"
```

(Note: the tiers count DOWN — tier 1 fires last, near the deadline.)

When the countdown crosses a tier boundary, `_onLoop` decrements
`countdownStatus` and emits the notification. The server doesn't
push these — they fire purely client-side from the local tick.

## Cutscene Integration

```text
executeCutScene(self, cutSceneId, target, isFullscreen, ...args):
  mode = 1 if isFullscreen else 2
  cs = worldMaster:createCutScene(cutSceneId, target or self)
  cs:startCutScene(1, 63, mode, ...args)
  cs:_delete()
```

Two trigger paths:

```text
cutSceneEvent(self, cutSceneId, ...):
  - if initFlag false: skip
  - fade out + wait + executeCutScene(fullscreen=true) + fade in

exitCutScene(self, cutSceneId, ...):
  - fade out + executeCutScene + fade in (after warp)
  - desktopWidget orderDesktopWidgetMode(126)
```

So cutscenes can happen mid-instance (`cutSceneEvent`) or as part
of instance exit (`exitCutScene`).

## Required Companion: `RaidPlayers`

The first line requires `Director/InstanceRaid/OccupancyPlayers/RaidPlayers`
— the player set inside the instance. This is the data structure
that tracks which players are currently inside.

Not read this pass, but the `OccupancyPlayers` directory pattern
suggests a per-instance member registry (player joins/leaves/disconnects).

## Notable Wire Surface

For implementation purposes, the server needs to send:

```text
event                    payload                              direction
-----                    -------                              ---------
startEvent               contentID, startTime, finishTime,    S->C
                          eventType, alreadyClear
reloginEvent             (none -- just trigger)               S->C
clearEvent               clearType (1..4 -> message)          S->C
failedEvent              failType (1..4), 2 extra args        S->C
_onReceiveDataPacket     A1=1: setCountDownTimer w/ times     S->C
                         A1=2: just clearFlag = true
                         A1=3: user message
cutSceneEvent            cutSceneId, ...                      S->C
exitCutScene             cutSceneId, ...                      S->C
```

Plus the implicit per-tick state push needed for:
- HP/Aggro of instance bosses (via standard bindWork sync)
- Phase indicators (instanceRaidWork._save subclass extensions)

## Notable Message IDs

```text
52009  countdown "X seconds remaining"  (with substitution arg)
52010  failure type 3 message
52021  re-entered instance notice
52054  failure type 2 message
52065  failure type 1 message
52092  halfway warning ("X minutes left")
52093  failure type 4 message
```

These are MessageSheet row IDs from the global messages catalog
(see desktopWidget channel architecture).

## Assessment

```text
Confirmed:
  - InstanceRaidBaseClass is the Director-pattern lifecycle for
    instanced content. 13 subclass files (most are 8-line stubs).
  - Tick loop runs at 1 Hz (via _setLoopInterval(1)).
  - 7 countdown tiers with thresholds [60, 180, 300, 600, 1200,
    1800] seconds + halfway warning.
  - 4 failure types with specific message IDs (52065, 52054,
    52010, 52093).
  - 3 in-band server commands via _onReceiveDataPacket (A1=1/2/3).
  - Cutscenes integrated via worldMaster:createCutScene; 2 trigger
    paths (mid-instance + exit).

Likely (High):
  - The 192-byte _assignForChild buffer is where each dungeon
    stores its own state (boss phase, wave count, drop tracker).
    Most subclasses are 8-line stubs because all behavior is in
    the baseclass + their config in a sheet row.
  - HamletDefence is the biggest because it has unique multi-wave
    mechanics. Other instances probably use sheet-driven boss
    triggers.
  - The clearType arg passed to clearEvent (A1) selects which
    "you cleared" message displays (4 categories, e.g. clear/no-
    deaths/under-time/all-treasures).

Likely (Medium):
  - The 'countdownStatus' field starts at 0 (no countdown), gets
    set to 7 when arming (halfway not crossed), then decreases as
    time progresses. When 0 again, no more announcements fire.
  - The 'eventType' int8 discriminator categorizes the instance
    kind: 0=basic, 1=raid, 2=PvP arena, etc.
  - The processUserMessage subclass override is the per-event
    custom UI hook (e.g. "wave 5 incoming!" specific to
    HamletDefence).

Speculative:
  - 1.x's instance design is more centralized than ARR's (each
    instance is a "Director" object owned by the world server,
    pushed to the client; client just tracks state and plays
    canned animations). Compare to ARR where instances are
    server-side scripted but client tracks lots of state.
  - The 5940 "max time" sentinel in getHalfTime suggests the
    longest instance was capped at ~99 minutes (5940 seconds).
```

## Open Threads

```text
1. Read InstanceRaid_HamletDefence.lua (823 lines) for the
   wave-based mechanics. It probably exemplifies how subclasses
   override the baseclass methods.

2. Find the RaidPlayers / OccupancyPlayers system. Tracks instance
   membership.

3. Find the Lua callsite that INVOKES startEvent/clearEvent/etc.
   on the client. These are likely from a packet handler -- the
   wire opcode for "instance state push" should be findable.

4. The 1.x InstanceRaid is parent to DirectorBaseClass -- read
   that too for the general "Director" pattern (probably also
   used for non-instance events).
```

## Server Implementation Picture

A minimal-viable server's instance subsystem:

```text
ZONE STATE: per-zone, track active Director instances.

INSTANCE STATE: per-active-instance, track:
  - contentID, startTime, finishTime, eventType, clearFlag
  - OccupancyPlayers list (player set inside)
  - per-subclass state (e.g. HamletDefence wave counter)

INSTANCE LIFECYCLE:
  - on player.enterInstance(contentID):
      create Director instance
      push startEvent(contentID, startTime=now+countdown,
                       finishTime=now+countdown+duration,
                       eventType, alreadyClear=false)
  - on player.reconnect inside instance:
      push reloginEvent
  - on instance.clear (server-side detection):
      push clearEvent(clearType=1..4)
  - on instance.timeout / fail:
      push failedEvent(failType, args...)

MID-INSTANCE EVENTS:
  - server can push _onReceiveDataPacket(A1=1, newTimes...)
    to extend/shorten time
  - server can push _onReceiveDataPacket(A1=3, msgArgs...)
    for custom UI messages
  - server can push cutSceneEvent(cutSceneId) for canned scenes

This is a relatively SMALL surface compared to per-frame combat
sync. A server can drive an instance with ~10 packets per minute
(countdown ticks fire client-side; only state transitions need
network).
```
