# Finding: `CompanyGroup` — Free Company System (1.x)

The Free Company-like organization system in 1.x. Built on
`CommunityGroupBaseClass` (which extends `GroupBaseClass`). Players
join a Company; each Company has a crest, name, ranks, and members
with per-member rank tracking.

Sources read:

```text
group/CommunityGroup/CompanyGroup.lua    515 lines (this file)
```

## Inheritance + Required Modules

```text
GroupBaseClass
  └── CommunityGroupBaseClass
      ├── CompanyGroup       (Free Company; this finding)
      └── RetainerGroup      (Retainer family; 496 lines, similar)
```

## `work` Schema (Community Group)

```text
work._globalSave  nesting(32)    -- 32-slot global state
work._memberSave  array[N]       -- per-member state (N = capacity)
                  nesting(1)        each member has 1-slot nesting

(where N = self:_getProperty(0))
```

The capacity N is **looked up via `_getProperty(0)`** at init time —
suggests the FC tier determines max members (e.g. tier 1 = 16,
tier 2 = 32, tier 3 = 64, similar to FFXIV ARR's FC ranks).

### `_globalSave._nesting` (3 fields)

```text
{master, member}                    -- pair: master actor + member array
{crestIcon, array[4] integer16}     -- 4 icon ids for the FC heraldry
{rank, integer8}                    -- company tier/rank
```

The crest is **4 stacked icons** (background + 3 overlays), similar
to FFXIV ARR's company crest editor.

### `_memberSave[i]._nesting` (per-member, 1 field)

```text
{rank, integer8}                    -- per-member rank within FC
                                       (e.g. 0=member, 1=officer, etc.)
```

So each member has ONE byte of state: their FC rank. Other per-
member data (name, level, last login) comes from the broader actor
system.

## Sync Tags

```text
{baseInfo, 1, [
  {_globalSave.master},
  {_globalSave.crestIcon},
  {_globalSave.rank}
]}
-- "baseInfo" bundles the FC-level fields for a single sync packet

{memberRank, 1, [
  {_memberSave[*].rank}
]}
-- wildcard '[*]' = "all members" -- one packet syncs ALL member ranks
```

The two-tag split is efficient:
- `baseInfo` rarely changes (FC promoted up a rank, crest changed)
- `memberRank` changes when members promote/demote
- Each is bundled into ONE sync packet on change

## `_bindWorkNestingArray` — Dynamic-Size Binding

```lua
_bindWorkNestingArray(300001, "work", "_memberSave", "rank", N)
                       where N = self:_getProperty(0)
```

Confirms catalog binding **300001 = community group `_memberSave[*].rank`**.
The dynamic N (member capacity) is passed as the array bound at
init — server can vary capacity per FC tier.

## Hook Dispatch

```text
_onUpdateMemberInformation(memberIdx):
  -> superClass._onUpdateMemberInformation(memberIdx)
  -> desktopWidget:processUpdateCurrentCommunityGroup(self, 1)
  -> desktopWidget:processUpdateCurrentCommunityGroup(self, 2)
  -- Calls with both mode 1 AND mode 2 to refresh both UI views

_onUpdateGroupInformation:
  -> superClass._onUpdateGroupInformation()

_onUpdateMember(memberIdx, op):
  -> superClass._onUpdateMember(memberIdx, op)
  -> desktopWidget refresh (mode 1 + mode 2)

_onUpdateWork(field, sub):
  if sub == "baseInfo":
    -> desktopWidget refresh (mode 1)
  elif sub == "memberRank":
    -> desktopWidget refresh (mode 2)
  -- The tag name from the work-sync identifies WHICH panel to refresh
```

So the desktopWidget `processUpdateCurrentCommunityGroup` has 2
modes:
- **mode 1**: FC name / crest / rank panel
- **mode 2**: member roster panel

## Notable Methods

```text
getMasterMember()         master actor ref
getCompanyRank()          FC tier (1..N)
getUniqueIdentifier()     unique ID for this FC instance

countNpc()                count of NPCs associated with this FC
                          (likely the FC house's resident NPCs)

getCrestIcon()            returns 4 icon ids for the crest
                          (background + 3 layers)

isCurrent(player)         returns true if this FC is player's
                          getCommunityGroupCurrent(20002)
                          -- so type 20002 = "FC current" category

isOwner()                 local player is FC master

updateMemberInformation() rebuild local view of member info
updateRankInGroup()       update player's rank in this FC

getMemberIndex(member)        index of member in roster
getMemberUniqueIdentifier(m)  member's UID (cross-session id)
getMemberRank(member)         member's FC rank (uses _memberSave[i].rank)
```

## The "Current Community Group" Concept

```lua
isCurrent(player):
  current = player:getCommunityGroupCurrent(20002)
  return current ~= nil and self == current
```

The constant **20002** is a category id for "current Free Company".
A player has multiple community group memberships (FC, multiple
linkshells, possibly Grand Company), and `getCommunityGroupCurrent`
returns the player's currently-selected one for each category.

The full category id range (catalog of community group types):

```text
category id   purpose
-----------   ---------------------------------
20001         ?? (probably linkshell)
20002         Company (Free Company)
20003         ?? (probably retainer group)
...
```

(Specific ids beyond 20002 not yet pinned; would need to read
`RetainerGroup.lua` + LinkshellGroup files.)

## Assessment

```text
Confirmed:
  - CompanyGroup is 1.x's Free Company system.
  - work._globalSave has 3 fields: master+member pair, crestIcon[4],
    rank.
  - work._memberSave is per-member; each member has just 1 byte
    (rank).
  - Binding 300001 = _memberSave[*].rank (dynamic size from
    _getProperty(0)).
  - Crest is 4 stacked icons (typical layered heraldry).
  - Category 20002 = "current Free Company" in the community group
    type system.

Likely (High):
  - FC capacity (N) scales with FC tier -- higher rank = more
    member slots. Common MMO design.
  - The 32-slot _globalSave is over-provisioned for the 3 fields
    shown; the rest are for subclass extensions (RetainerGroup
    probably uses more slots for retainer-specific data).
  - countNpc() returns the FC's resident NPCs in the FC house --
    1.x had FC housing similar to ARR's FC house, with quartermaster
    NPCs etc.

Likely (Medium):
  - "memberRank" is a single int8 (0..255 range) -- typical FC
    rank system has ~5-10 ranks (Member, Officer, Lieutenant,
    Co-Master, Master).
  - The mode 1 / mode 2 distinction in processUpdateCurrentCommunityGroup
    splits the FC UI into "info panel" and "roster panel" -- they
    refresh independently.

Speculative:
  - The category ids 20001-20003 are probably Linkshell, FC, and
    Retainer Group respectively. Other community types (Grand
    Company, free company in another nation) would use 20004+.
  - The 32-slot _globalSave hints at SE planning for richer FC
    features later (alliance, ranking ladder, etc.) that weren't
    implemented before 1.x sunset.
```

## Server Implementation Picture

```text
COMPANY DATA MODEL (server-side):
  per-FC instance:
    master_actor_id       -- the FC owner
    member_actor_ids[]    -- the roster (size N based on FC tier)
    crest_icons[4]        -- heraldry layers
    rank                  -- FC tier
    member_ranks[]        -- per-member rank (parallel to member array)

SYNC:
  - On FC tier promotion / crest change: push baseInfo tag
  - On member promotion / demotion: push memberRank tag (entire
    member ranks array, or specific [i].rank for one member)
  - On member join/leave: push _onUpdateMember signal, then
    rebuild the member array sync

CATEGORY DISPATCH:
  - When player queries player:getCommunityGroupCurrent(20002):
    server returns the FC the player belongs to (or nil)
  - When player joins FC: server assigns FC actor ref to player's
    community group set at category 20002

NPC INTEGRATION (FC house):
  - countNpc() reads NPC actors associated with the FC instance
  - These are server-allocated NPCs that exist while the FC is
    active (e.g. quartermaster, decoration vendor)
```
