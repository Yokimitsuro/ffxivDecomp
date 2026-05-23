# Finding: Hamlet Defence + Retainer Group Systems

Two related-but-distinct 1.x systems documented together:

1. **HamletDefence** — village/settlement defence event (the most
   fleshed-out InstanceRaid subclass, 823 lines)
2. **RetainerGroup** — the player's personal retainer NPCs (496 lines)

Sources read:

```text
director/InstanceRaid/InstanceRaidHamletDefense.lua  823 lines
group/CommunityGroup/RetainerGroup.lua               496 lines
```

## Part 1: HamletDefence — The Wave Defense Event

Extends `InstanceRaidBaseClass`. The biggest concrete InstanceRaid
subclass, suggesting it had the most elaborate mechanics.

### Hamlet ID Mapping (3 city-state hamlets)

```text
contentID 8  -> hamletID 1   (Limsa-aligned hamlet)
contentID 9  -> hamletID 2   (Gridania-aligned hamlet)
contentID 10 -> hamletID 3   (Ul'dah-aligned hamlet)
```

So 3 hamlets exist — one per city-state. Each is a separate
defendable settlement.

### `work._temp` Schema (9 fields)

```text
{hamletRank,      integer8}              -- hamlet's prestige tier (1-3?)
{hamletID,        integer8}              -- 1/2/3 = Limsa/Gridania/Uldah
{cargoTarget,     integer8}              -- cargo objective count
{battleValue,     integer8}              -- player's contribution score
{bossFlag,        boolean}               -- boss spawned?
{harvestTbl,      array[3] integer8}     -- 3 harvest station states
{lineStatusTbl,   array[3] integer8}     -- 3 defense line states
{goodsStatusTbl,  array[4] integer8}     -- 4 supply/goods states
{fieldBuffTbl,    array[6] boolean}      -- 6 field buff flags
```

So the event has multiple parallel subsystems:
- **3 harvest stations** (gather resources to help defense)
- **3 defense lines** (the actual battle lines protecting the hamlet)
- **4 supply lines** (goods/resources delivered to hamlet)
- **6 field buffs** (3 gatherer + 3 crafter; activated by completing
   objectives)

### Buff Tables (split by class category)

```lua
function HamletDefence:getGathererBuffTbl()
  return [1, 2, 3]   -- Buff IDs for Disciples of the Land
end

function HamletDefence:getCrafterBuffTbl()
  return [4, 5, 6]   -- Buff IDs for Disciples of the Hand
end
```

So **gatherers and crafters get DIFFERENT buff sets** — the event
rewards different player roles with different field buffs. Pattern
matches FFXI's similar "Conquest" / "Besieged" events where
different classes had distinct contributions.

### 28 Server-Pushed Event Types (`processUserMessage`)

When the server sends `_onReceiveDataPacket(A1=3, eventType, ...)`,
HamletDefence dispatches by `eventType` (1-28):

```text
eventType  popup  msgId
---------  -----  -----
1-10       false   0        -- silent events (notify worldMaster only)
11-20      false   0        -- silent events
21         true   1019      -- specific game event w/ popup
22         true   1091
23         true   1022
24         true   1063
25         true   1013
26         true   1018
27         true   1017
28         true   1063
```

So 28 different event types fire during a Hamlet Defence run:
- **1-10**: Silent state changes (line/goods/harvest updates)
- **11-20**: Silent state changes (probably the 10 sub-objectives
  completed/failed)
- **21-28**: Major popup events (boss spawn, wave incoming,
  victory, defeat — the 8 "moments" of the event)

### `dispInformation(msgId)` — Per-Hamlet NPC Voice

```lua
function HamletDefence:dispInformation(msgId)
  hamletNPCs = [1600146, 1200220, 1000062]
                -- Limsa     Gridania   Ul'dah
                -- hamlet master NPCs
  npcId = hamletNPCs[work.hamletID]
  desktopWidget:showLog(npcId, channel=35, ...)
end
```

So **each hamlet has its own master NPC** that "speaks" during the
event. The NPC ids 1600146 / 1200220 / 1000062 are the 3 hamlet
elders (one per city-state).

Channel **35** = Hamlet Defence specific log channel (distinct from
the 32/33/38/40 channels documented earlier).

### Assessment (HamletDefence)

```text
Confirmed:
  - 3 hamlets (Limsa/Gridania/Ul'dah aligned).
  - 9 _temp fields tracking event state (rank, ID, cargo, battle
    value, boss, harvest×3, lines×3, goods×4, buffs×6).
  - 6 field buffs split 3-gatherer + 3-crafter (DoL/DoH content).
  - 28 server-pushed event types (10 silent + 10 silent + 8 popup).
  - 3 hamlet master NPCs (1600146 / 1200220 / 1000062).
  - Channel 35 = Hamlet Defence specific log.

Likely (High):
  - The 3 defense lines mirror the 3 PERIMETER WALLS of a typical
    hamlet -- each line independently defendable.
  - The 4 goods are the 4 resource types (food/wood/stone/water?)
    delivered to the hamlet during the event.
  - Boss spawn at event end (bossFlag=true) is the final wave's
    challenge enemy.
  - Hamlet rank determines event difficulty (rank 1 = easy, 3 = hard).

Likely (Medium):
  - The event rewards both DoW/DoM (defense) and DoL/DoH (resource
    delivery + crafting buffs) players -- a cross-class event by
    design.
  - The 21-28 popup events likely include: boss spawn, line breach
    warnings, victory, time-out failure.
```

---

## Part 2: RetainerGroup — Personal Retainer NPCs

Extends `CommunityGroupBaseClass`. Sibling of CompanyGroup (Grand
Company) but for personal retainers instead of city-state orgs.

### `work` Schema (per-retainer 4 fields, N retainers per player)

```text
work._sync._memberSave  array[N] of nesting:
  {cdIDOffset,   integer16}    -- character data ID offset (retainer's unique ID)
  {placeName,    integer16}    -- current location/zone of retainer
  {conditions,   integer8}     -- current condition/status enum
  {level,        integer8}     -- retainer level
```

So **each retainer is 6 bytes** of synced state. N is dynamic
(_getProperty(0)) — probably 2 retainers default, scaling up to 8
with character progression (similar to FFXIV ARR's 2→9 progression).

### Sync Tag

```text
{paramsync, 1, [
  {_memberSave[*].cdIDOffset},
  {_memberSave[*].placeName},
  {_memberSave[*].conditions},
  {_memberSave[*].level}
]}
```

The `[*]` wildcard means "all retainers" — one packet syncs the
entire retainer roster's basic info.

### `_onUpdateMemberInformation(memberIdx)`

```lua
function RetainerGroup:_onUpdateMemberInformation(memberIdx)
  super._onUpdateMemberInformation(memberIdx)
  if memberExists in world and client:
    member = _getMember(memberIdx)
  end
  desktopWidget:processUpdateGroupInformation(member, kind, self)
  if member ~= nil:
    -- Refresh the retainer's nameplate (in case status/level changed)
    myPlayer:getDepictionJudge():judgeNameplate(member)
end
```

When a retainer's data changes, the desktop widget refreshes the
retainer panel and the retainer's nameplate (if visible in world).

### Retainer Schema vs Grand Company Schema

```text
RetainerGroup (per retainer, 6 bytes):
  cdIDOffset, placeName, conditions, level
  -- NO global fields (no master, no crest, no group rank)

CompanyGroup (per Grand Company member, 1 byte + globals):
  rank (per-member)
  + globals: master, member, crestIcon[4], rank
```

So:
- **RetainerGroup is FLAT**: just N retainers, no group-level
  identity.
- **CompanyGroup is HIERARCHICAL**: GC has master + crest + tier,
  plus per-member rank.

### Retainer "Conditions" Enum (inferred)

The `conditions` int8 likely encodes retainer state:

```text
0 = idle (in town, available)
1 = selling (at bazaar)
2 = adventuring (on retainer mission)
3 = returning (mission done, en route)
4 = ?
...
```

(Specific values not enumerated in this file; would need to grep
for "conditions == N" usages in dependent code.)

### Assessment (RetainerGroup)

```text
Confirmed:
  - Each retainer = 6 bytes of synced state.
  - N retainers per player (dynamic via _getProperty(0); likely 2-8).
  - 4 fields: cdIDOffset, placeName, conditions, level.
  - Single sync tag bundles all retainers' updates.
  - Sibling of CompanyGroup (both extend CommunityGroupBaseClass).

Likely (High):
  - 1.x retainer system inherited from FFXI's "mog house" / NPC
    storage concept. Each player started with 2 retainers; could
    earn more.
  - "conditions" enum covers idle/selling/adventuring states. 1.x
    had retainer ventures similar to ARR's "Retainer Ventures".
  - cdIDOffset is the retainer's unique persistent ID (different
    from actor id; survives login/logout).

Likely (Medium):
  - placeName int16 = zone/place id where the retainer currently is.
    For idle retainers: their home town. For active retainers: the
    location they're visiting on a venture.
  - level int8 = retainer level (max ~50 in 1.x per FFXI-inherited
    design).

Speculative:
  - The 3rd-4th retainer slots were unlock-able through gameplay
    (e.g. Grand Company quest line).
  - 1.x retainers had a more constrained role than ARR retainers
    (mainly storage + market sales, not adventure ventures).
```

---

## Combined Server Implementation Picture

### HamletDefence

```text
SERVER-SIDE EVENT TICK (every 1-5 seconds):
  - Track harvest stations, defense lines, goods deliveries
  - Push status updates via _onReceiveDataPacket(A1=3, eventType,
                                                   ...args)
  - eventType 1-20: silent state changes
  - eventType 21-28: significant moments (boss spawn etc)
  - Push fieldBuff updates when objectives complete

PER-PLAYER STATE:
  - battleValue: contribution score (used for reward distribution)
  - Buffs applied via fieldBuffTbl bits

WAVE TIMING:
  - Standard InstanceRaid lifecycle (start/clear/fail)
  - Boss spawns near event end (bossFlag = true)
```

### RetainerGroup

```text
ON RETAINER STATE CHANGE:
  - Update _memberSave[i].{cdIDOffset, placeName, conditions, level}
  - Push paramsync tag to player's client
  - Client refreshes retainer panel + nameplate

ON RETAINER MISSION:
  - Server tracks retainer's adventure (time, location, loot)
  - Push conditions = "adventuring" with placeName = destination
  - On return: conditions = "returning"
  - Player can claim loot from idle retainer

ON RETAINER LOGIN/LOGOUT:
  - Add/remove from _memberSave via _onUpdateMember
  - Server saves persistent retainer state via cdIDOffset
```

This closes the **community organization architecture** of 1.x.
Players belonged to:
- 1 Grand Company (CompanyGroup, category 20002)
- 0-8 Linkshells (separate CommunityGroup subclass, category 20001)
- 2-8 Retainers (RetainerGroup, category 20003)

Plus active parties + content groups + relation groups documented
earlier.

The community/group system is **fully decomposed** at this point.
