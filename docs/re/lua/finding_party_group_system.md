# Finding: Party Group System — `PartyGroupBaseClass` + Party Size Multiplier

The party (group of players) system in 1.x. Built on top of the
generic `GroupBaseClass` pattern. Notable for its **party size
multiplier** on combat potencial — bigger parties get a higher
combat power multiplier (with diminishing returns).

Sources read:

```text
group/GroupBaseClass.lua                          71 lines (base for all groups)
group/PartyGroup/PartyGroupBaseClass.lua         125 lines
group/PartyGroup/PartyGroupBaseClass_battle.lua  198 lines
group/PartyGroup/PlayerPartyGroup.lua            358 lines (NOT read this pass;
                                                            sibling MonsterPartyGroup
                                                            also 193 lines)
```

## Group Inheritance Tree

```text
ActorBaseClass
  └── GroupBaseClass
      ├── PartyGroupBaseClass               (this finding)
      │   ├── PlayerPartyGroup              (player parties; 358 lines)
      │   ├── MonsterPartyGroup             (monster groups in combat)
      │   └── MonsterPartyGroup_battle      (sibling for monster battle)
      ├── CommunityGroupBaseClass           (43 lines)
      │   ├── CompanyGroup                  (515 lines; FREE COMPANY analog)
      │   └── RetainerGroup                 (496 lines; retainer system)
      ├── ContentGroupBaseClass             (411 lines; raids/dungeons membership)
      └── RelationGroupBaseClass            (43 lines)
          ├── GroupInvitationRelationGroup  (195 lines)
          ├── TradeRelationGroup            (181 lines)
          ├── ExecuteCommandRelationGroup   (87 lines)
          ├── GroupExecuteCommandRelationGroup (87 lines)
          ├── BazaarBuyItemRelationGroup    (34 lines)
          └── + several stub subclasses
```

So the Group system is a **major axis of the actor architecture**.
4 group families × multiple subclasses each.

## `GroupBaseClass` — Generic Base

```text
groupWork._temp:  256-byte child reserve
groupWork._sync:  256-byte child reserve
```

5 lifecycle hooks (mostly empty stubs):

```text
_onInit
_onUpdateMember              (member joined/left)
_onUpdateMemberInformation   (member field changed)
_onUpdateGroupInformation    (group-level field changed)
_onUpdateWork                (generic update)
_onFinalize
```

That's the minimum group contract — track members, fire hooks on
membership changes, support work-sync.

## `PartyGroupBaseClass` Schema

```text
partyGroupWork._temp:
  _assignForChild  128 bytes  (subclass reserve)

partyGroupWork._sync:
  _globalTemp  nesting(8)     (the actual group-shared data)
```

The 8-slot `_globalTemp` nested struct holds the synced party data:

```text
_globalTemp nesting layout:
  owner  member         (single actor ref + array of actors)
```

So `partyGroupWork._globalTemp.owner` (binding 400001) = the leader
actor, and `partyGroupWork._globalTemp.member` = the array of party
members.

## Party Size Multiplier (`getAllMembersPotencial`)

The most interesting finding — the **party size combat multiplier**:

```lua
function PartyGroupBaseClass:getAllMembersPotencial()
  totalPotencial = 0
  totalLevel = 0
  count = 0
  for each member in party:
    if not member.isNotoriousMonster():
      totalPotencial += member.getPotencial()
      totalLevel += member.getStateMainSkillLevel()
      count += 1
    -- (NM members handled separately, summed for difficulty calc)

  avgLevel = totalLevel / count

  -- PARTY SIZE MULTIPLIER:
  size = self._countMember()
  if size == 1: multiplier = 1.0
  elseif size == 2: multiplier = 1.5    -- BIGGEST bonus!
  elseif size == 3: multiplier = 1.4
  elseif size == 4: multiplier = 1.3
  elseif size == 5: multiplier = 1.2
  else size >= 6:   multiplier = 1.1

  totalPotencial *= multiplier
  return totalPotencial, avgLevel
end
```

### Surprising design

The **2-member duo** gets the BIGGEST multiplier (×1.5), more than
parties of 3-6. The curve is:

```text
party size  multiplier   total scaling factor
1           1.0          1.0
2           1.5          3.0   (1.5 × 2)
3           1.4          4.2   (1.4 × 3)
4           1.3          5.2   (1.3 × 4)
5           1.2          6.0   (1.2 × 5)
6           1.1          6.6   (1.1 × 6)
8           1.1          8.8   (1.1 × 8 — cap at 1.1)
```

So total combat power roughly scales SUPER-LINEARLY up to 6 members,
then linear. Encourages bigger parties but no exponential reward.

The +50% bonus for duos suggests 1.x balanced its content around
2-player duos as the "sweet spot" — pair coordination beats solo by
a lot, but adding a 3rd person only marginally adds value beyond
the raw headcount.

This is **the same content design philosophy as FFXI's "Duo
content"** (Treasures of Aht Urhgan promyvions, EXP duos) which
also rewarded pairs disproportionately.

## Key Methods

```text
getPartyLeader()         returns owner if alive, else nil
isPartyLeader(actor)     checks if given actor is the owner
getPartyOwner()          direct accessor: _globalTemp.owner
getPartyMember(idx)      returns member at index (if exists in roster)
getPartyMemberBeAlive(n) returns the Nth ALIVE member (skips dead/DCed)
getAllMembersPotencial() returns (totalPotencial, avgLevel) with size mult
getObjectClassId()       returns 6 (PartyGroup type id)
isPlayerPartyGroup()     returns false (PlayerPartyGroup overrides)
```

## `_onUpdateWork` for Party Leader Change

```lua
function PartyGroupBaseClass:_onUpdateWork(field, sub)
  if sub == "_init" or (field == "partyGroupWork" and sub == "leader"):
    if self._isMember(myPlayer):
      -- Notify the desktop widget that the party leader changed
      desktopWidget:processUpdateGroupInformation(myPlayer,
                                                    self._getKind(),
                                                    self)
end
```

So **when the party leader changes, the desktop widget gets a
refresh notification** — letting the party UI re-render with the
new leader marker.

## `initForBattle` — The Binding Registration

```lua
function PartyGroupBaseClass:initForBattle()
  -- Set up _globalTemp nesting schema
  partyGroupWork._globalTemp._nesting = [{owner, member}]
  -- Set up tag for "leader" sync
  partyGroupWork._tag = [{leader, 1, [{_globalTemp.owner}]}]
  -- Register binding 400001
  _bindWork(400001, "partyGroupWork", "_globalTemp", "owner")
end
```

The `leader` tag bundles the owner field for a single sync packet
on leader change.

## Assessment

```text
Confirmed:
  - PartyGroupBaseClass extends GroupBaseClass; bindings 400001 +
    nesting schema for owner + member array.
  - The party size multiplier formula: 1.0/1.5/1.4/1.3/1.2/1.1
    for sizes 1/2/3/4/5/6+ -- duos get the biggest bonus.
  - 4 group families exist (PartyGroup, CommunityGroup,
    ContentGroup, RelationGroup), each with multiple subclasses.
  - The leader change triggers a desktopWidget refresh via
    processUpdateGroupInformation.

Likely (High):
  - The "owner = nil" check at getPartyLeader returns nil when the
    leader has died -- handling for unresponsive parties (the UI
    should show "no leader" until a new one is appointed).
  - The 6 return value of getObjectClassId is the "PartyGroup"
    type tag used in the actor system. Other group types have
    different ids (CommunityGroup probably 7, etc.).

Likely (Medium):
  - The party size cap is 8 (6+ all use ×1.1 multiplier). 1.x had
    "alliance" parties of up to 24 players for raids, but those
    were a separate Alliance system (RelationGroup family?).
  - The 128-byte _temp child reserve is for non-synced UI state
    (last hovered member, scroll position, etc.).
  - The NM (Notorious Monster) special-case in getAllMembersPotencial
    is for boss fights where the boss is technically a "member" of
    a monster party group.

Speculative:
  - The ×1.5 duo bonus reflects 1.x's design intent that solo +
    duo content should be VIABLE without needing full parties.
    Modern MMOs went the other direction (more rewards for bigger
    groups); 1.x's design was more inclusive of small-group play.
  - The 6-member upper cap matched 1.x's "Light Party" tradition
    inherited from FFXI. ARR moved to 8-person standard parties.
```

## Server Implementation Picture

A party-aware server:

```text
PARTY CREATION:
  - Player A invites Player B (via GroupInvitationRelationGroup)
  - On accept: server creates PartyGroup actor, owner=A, member=[A,B]
  - Push partyGroupWork._globalTemp via the "leader" tag to both
    players' clients
  - Both clients get processUpdateGroupInformation -> UI updates

LEADER PROMOTION:
  - Server changes partyGroupWork._globalTemp.owner
  - Push via binding 400001
  - Clients call _onUpdateWork -> desktopWidget refreshes party panel

MEMBER ADD/REMOVE:
  - Server updates _globalTemp.member array
  - Push update; clients fire _onUpdateMember + redraw

COMBAT WITH PARTY:
  - Each combat action references the party leader (via
    getPartyOwner) for shared XP / loot rolls
  - getAllMembersPotencial gives the combined party strength
    (with size multiplier) for con-check display
```

Wire surface is SMALL: just the binding 400001 + member array
sync. The party size multiplier formula is CLIENT-SIDE only --
server doesn't push the multiplier, just the membership; client
computes the bonus itself for display.
