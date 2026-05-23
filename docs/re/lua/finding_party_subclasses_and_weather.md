# Finding: PlayerPartyGroup, MonsterPartyGroup, WeatherDirector — Subclass Implementations

Three additional Lua subclasses documented. Together they close the
PartyGroup concrete implementations + the WeatherDirector (the
simplest Director subclass).

Sources read:

```text
group/PartyGroup/PlayerPartyGroup.lua    358 lines (6 methods)
group/PartyGroup/MonsterPartyGroup.lua   193 lines (5 methods)
director/WeatherDirector.lua             112 lines (3 methods)
```

## 1. PlayerPartyGroup (358 lines) — Player Party UI Orchestrator

The concrete subclass for **player parties** (vs PartyGroupBaseClass
which is the abstract parent and MonsterPartyGroup the monster variant).

### Methods (6):

```text
isPlayerPartyGroup()                returns true (overrides parent's false)
initAsPartyGroup                    UI refresh on init
_onUpdateMember(member, op)         UI refresh on member add/remove
_onUpdateMemberInformation(idx)     UI refresh on member info change
_onUpdateGroupInformation(...)      UI refresh on group state change
_onFinalize                         cleanup on party disband
```

### Behavior Pattern

When ANY event fires on the party (init / member change / info
change), if the local myPlayer is a member of the party, it:

```text
1. Calls desktopWidget:processUpdateGroupInformation(myPlayer,
                                                       kind, self)
2. Refreshes the nameplate of the affected member
   (myPlayer:getDepictionJudge():judgeNameplate(member))
3. Iterates ALL party members and refreshes each nameplate
4. ALSO iterates the OCCUPANCY GROUP (the broader player party
   container) and refreshes those nameplates too
```

So a party change triggers a **cascading nameplate refresh** across
all party members + occupancy group members. The party UI panel
updates AND the nameplates of related actors all re-render.

This explains why party state changes feel responsive in 1.x —
every related actor's nameplate updates immediately on any party
change.

## 2. MonsterPartyGroup (193 lines) — Monster Pack

Smaller subclass for monster groups (e.g. a pack of enemies that
share a leader).

### Methods (5):

```text
initAsPartyGroup
_onUpdateMember
_onUpdateMemberInformation
_onUpdateGroupInformation
_onFinalize
```

Same hook structure as PlayerPartyGroup but **193 lines vs 358** =
half the size. Difference: no occupancy group iteration (monsters
don't have the player-party-occupancy concept). Just refreshes
nameplates + member info via DepictionJudge.

### Use Case

Used by NPCs in coordinated groups:
- A boss + minions (boss leads)
- An ambush squad (one leader, multiple soldiers)
- Pack hunters (linked AI behavior)

When the pack changes (one dies, leader changes), nameplates
refresh to show the new state.

## 3. WeatherDirector (112 lines) — The Smallest Director

The simplest concrete Director subclass. Broadcasts global weather
changes to players in a zone.

### Schema

```text
work._sync = [{weatherId, integer16}]
work._tag = [{weatherInfo, 1, [{weatherId}]}]
```

Just ONE synced field: the current weather id (uint16).

### `init`

Sets up the schema via `initWork` + `initWorkSyncTag`.

### `processUpdateWork` and `processUIUpdate` (BYTE-IDENTICAL)

```lua
function WeatherDirector:processUpdateWork(A1, A2)
  myPlayer = worldMaster:_getMyPlayer()
  current = myPlayer:getWeatherId()
  if current == 0:
    -- No current weather; instant transition
    myPlayer:_setWeather(work.weatherId, 1)
  else:
    -- Smooth transition over 15 game ticks
    myPlayer:_setWeather(work.weatherId, 15)
  myPlayer:setWeatherId(work.weatherId)
end
```

**Transition durations**:
- `1` (instant) when going from "no weather" state
- `15` (smooth, ~15 ticks = ~15 sec) when changing existing weather

So the client uses **server-time-based weather transitions**: server
pushes new weatherId; client smoothly cross-fades over 15 seconds.

### Wire Surface (Server Implementation)

Per zone with active weather:

```text
1. Server allocates a WeatherDirector instance
2. Sets work.weatherId = newWeather
3. Pushes via "weatherInfo" tag (single sync packet)
4. Client receives, calls processUpdateWork
5. Client smooth-transitions to new weather over 15 sec

Bandwidth: 1 packet per weather change (~rare; every 30-60 min)
Wire cost: ~30 bytes per change
```

So weather is **practically free** on the network. Per-actor sync
of weather is minimal.

## Assessment

```text
Confirmed:
  - PlayerPartyGroup is the concrete player party class (358 lines).
  - Its 6 methods drive UI refresh cascading across party members
    + occupancy group.
  - MonsterPartyGroup is the simpler monster version (no occupancy
    group iteration).
  - WeatherDirector has 1 sync field (weatherId) and 2 transition
    modes (1 = instant, 15 = smooth).
  - processUpdateWork and processUIUpdate in WeatherDirector are
    BYTE-IDENTICAL (copy-paste in source).

Likely (High):
  - The cascading nameplate refresh in PlayerPartyGroup is what
    drives the immediate-feedback feeling when joining/leaving
    parties in 1.x.
  - MonsterPartyGroup is used for ENEMY PACKS that share state
    (e.g. ifrit fight where the boss + adds are one pack;
    aggro/hate is shared).
  - Weather transition over 15 ticks (~15 seconds) is a typical
    smooth-fade duration for outdoor weather changes.

Speculative:
  - The duplicate code in WeatherDirector (processUpdateWork ==
    processUIUpdate) suggests the architecture was meant to have
    DIFFERENT logic for the 2 paths but ended up identical --
    typical refactoring artifact.
  - WeatherDirector is so small because weather state is just
    "what weather it is now" -- no other parameters needed (visual
    effects are sheet-driven from weatherId).
```

## Closing the Group + Director Family

With these 3 subclasses:
- **Director family**: BaseClass + InstanceRaid + Caravan +
  Weather (+ smaller stubs) -- fully documented.
- **Group family**: BaseClass + Party (Player + Monster) +
  Community (Grand Company + Retainer) + Content + Relation
  family -- fully documented.

Every major Group + Director subclass has been documented at the
architectural level.

## Server Implementation Picture

```text
PARTY OPERATIONS:
  Server tracks party roster (member list + leader)
  On membership change: push partyGroupWork._globalTemp updates
    via the leader/member tags
  Client cascades: updates party panel + all related nameplates
  Bandwidth: ~50-100 bytes per change

WEATHER:
  Server picks weatherId for zone (probably time-of-day +
    sheet-driven schedule)
  Pushes via WeatherDirector.work.weatherId
  Client smooth-transitions visually
  Bandwidth: ~30 bytes per change, ~once per 30-60 minutes

MONSTER PACKS:
  Server tracks pack as MonsterPartyGroup with leader + members
  On member changes (kill, despawn): push updates
  Clients with members visible refresh nameplates
  Bandwidth: ~50-100 bytes per pack change
```
