# Finding: CharaBaseClass `_cliprog` and `_event` Companion Modules

Documents the two unread CharaBase companion modules: `_cliprog`
(client-side progression / query layer, 454 lines) and `_event`
(event-related helpers, 444 lines). Reveals NM Undead category +
job stone mapping + active/dead state model.

Sources read:

```text
chara/charabaseclass_cliprog.lua    454 lines  (22 methods)
chara/charabaseclass_event.lua      444 lines  (12 methods)
```

## `charabaseclass_cliprog.lua` (22 methods)

The "client progression" layer -- a set of high-level predicates
and getters that dispatch to underlying bindings or stored state.

### Predicates + Queries

```text
hasGameParameter                  has battle params?
isDealer                          bazaar dealer?
isPropertyEnabled(idx)            property[idx] bit set?
getStateMainSkill                 current job/class id
getConstanceCommand               passive command
getGiftCommand                    gift command

getSkillLevel(idx)
getAbilityCostPointUsed/Max
getConstanceCostPointUsed/Max
getGiftCostPointUsed/Max

isCommandAcquired(cmdId)          has unlocked this command?
getCustomCommand / getCustomCommandSlotLength
getMoneyOnHand                    gil
isDead                            main stat 1 or 3 = dead
isActiveMode                      main stat 2/4/8/16 = active
getCommunityGroupCurrent(cat)     current community group for category
isUndead                          NM type 12 detection
hasJobStone(jobId)                has the soul crystal for job?
```

### KEY DISCOVERY 1: Actor State Model

```text
Main Stat values (from isDead + isActiveMode):
  1   = dead
  2   = active (variant 1)
  3   = dead (alternate)
  4   = active (variant 2)
  8   = active (variant 3)
  15  = riding (already known)
  16  = active (variant 4)
  32  = sit (already known)
```

So the **actor main stat** is a state-machine enum with multiple
active/dead/special states. Previously found 15 (riding) and 32
(sit); now adding the dead/active multi-state model:

- 1 / 3 = dead variants
- 2 / 4 / 8 / 16 = active variants
- 15 = riding
- 32 = sit

### KEY DISCOVERY 2: NM Type 12 = Undead

```lua
function CharaBaseClass:isUndead()
  if isPlayer: return false
  if not isPropertyEnabled(3): return false
  isNM, nmType = self:isNotoriousMonster()
  if isNM and nmType == 12:
    return true
  return false
end
```

So **NM type 12 specifically is the "Undead" category**. Combining
with earlier findings:

```text
NM Type   Category               Source
-------   --------               ------------
   11     Regular NM             potencial = -1
   12     UNDEAD NM              potencial = -2 (NEW: confirmed via isUndead)
   13     HNM (probably)         potencial = -3
   14     World Boss (probably)  potencial = -4
```

So players can identify undead via the standard NM mechanic
(potencial = -2). Allows undead-specific skills (e.g. holy magic
extra damage) to query `isUndead()`.

### KEY DISCOVERY 3: Job Stone Mapping (Package 101)

```lua
function CharaBaseClass:hasJobStone(jobId)
  jobToCrystalMap = {
    15 -> 2000202   (Paladin Soul Crystal)
    16 -> 2000201   (Monk Soul Crystal)
    17 -> 2000203   (Warrior Soul Crystal)
    18 -> 2000205   (Dragoon or similar)
    19 -> 2000204   (Bard or similar)
    26 -> 2000207   (Black Mage or similar)
    27 -> 2000206   (White Mage or similar)
  }
  return self:hasItem(101, jobToCrystalMap[jobId])
end
```

The function checks if the player has the soul crystal item in
package 101. So:
- **Package 101** = the soul crystal / job stone inventory
- Each job has a specific item id in the 2000201-2000207 range
- The 7 jobs match `finding_ffxivbattle_stats_and_jobs.md`

## `charabaseclass_event.lua` (12 methods)

Event-system helper layer. Used by Lua scripts during NPC dialog
and bazaar interactions.

### Methods

```text
isRetailDealer                  is bazaar in retail mode?
isRepairDealer                  is bazaar in repair mode?
isMateriaAttachDealer           is bazaar in materia attach mode?
getBazaarTax                    current tax rate
getRepairType                   repair sub-type

getLinkshellIconId              get the 4 linkshell icons

initEventSyncWork               schema init (covered in earlier
                                 finding_event_and_battle_sync_schemas.md)

countStackAtIndex               item stack at package idx
createVirtualItem               make a temporary virtual item
checkSameItem                   compare items

getPassiveGuildleveIcons        UI icons for passive guildleve
isValidFacility                 check facility id validity
```

### Bazaar Dealer Predicate Family

```text
isRetailDealer         eventTemp.bazaarRetail bit
isRepairDealer         eventTemp.bazaarRepair bit
isMateriaAttachDealer  eventTemp.bazaarMateria bit
```

Three orthogonal flags identifying the kind of bazaar
operation the actor is currently set up for. From earlier
findings, bindings 4001 (retail) + 4002 (repair) + 4003 (materia)
sync these flags.

So 1.x bazaar had **3 distinct dealer modes** -- not just
"buy/sell" but specifically retail (sell) + repair (service)
+ materia attach (service).

### Virtual Item Creation

`createVirtualItem` is the **temporary item factory** used by
Lua scripts during event flows:
- Trade preview (show what items would change hands without
  actually transferring them)
- NPC dialog quotes (show "would this cost?" without commit)
- Crafting result preview

These items exist only client-side and disappear on event end.

## Updated NM Catalog

```text
Type   Sign of potencial   Category               Source
----   -----------------   --------                ------------
 11    -1                  Regular NM              (FFXIV battle)
 12    -2                  UNDEAD NM               (isUndead)
 13    -3                  HNM (high-tier)
 14    -4                  World Boss
```

Server implications: if an NPC is undead, server pushes potencial
= -2 to mark it. Client's `isUndead()` returns true automatically.
No separate undead packet needed.

## Updated Actor State Model

```text
Main Stat   Meaning                            Triggers (Lua side)
---------   --------                           ----------
   1        Dead                               isDead = true
   2        Active variant 1                   isActiveMode = true
   3        Dead alternate                     isDead = true
   4        Active variant 2                   isActiveMode = true
   8        Active variant 3                   isActiveMode = true
  11        casting / channeling (from earlier)
  13        casting / channeling (alternate)
  15        Riding chocobo                     _onChangeActorMainStat fires;
                                                 desktopWidget chocobo status
  16        Active variant 4                   isActiveMode = true
  32        Sit emote                          isSitMode = true
```

So the main stat is a 6-bit state enum with at least 10 known
states. The "active variants" (2/4/8/16) likely correspond to
different combat stances or weapon-drawn states.

## Assessment

```text
Confirmed:
  - charabaseclass_cliprog has 22 high-level query methods
  - charabaseclass_event has 12 event-system helpers
  - NM type 12 = Undead (specific category in the NM type space)
  - Job stones live in package 101 with item ids 2000201-2000207
  - Actor main stat is a state-machine with 10+ identified states
  - 3 bazaar dealer modes: retail, repair, materia attach

Likely (High):
  - The "active variants" (main stat 2/4/8/16) correspond to
    weapon-drawn / unarmed / combat-ready / etc. states.
  - The dual dead states (1 and 3) may distinguish KO'd-in-combat
    vs "knocked out" by other means (e.g. cutscene-induced death).

Likely (Medium):
  - The 7 soul crystal items in package 101 are persistent across
    sessions. Equipping = having in package 101.
  - Each soul crystal item has metadata in itemDataSheet linking
    it to the job id.

Speculative:
  - The "Undead" NM category was used for late-game content (e.g.
    Crystal Tower mobs, raid bosses with undead theme).
  - Holy magic + restorative magic likely had isUndead() checks
    for bonus damage / inverted heals.
```

## Closes the CharaBase Family

With these companion modules documented, the CharaBaseClass family
is now FULLY enumerated:

```text
charabaseclass.lua            base + _onInit (1734 lines)
charabaseclass_parameter.lua  parameterSave schema (1867 lines)
charabaseclass_battle.lua     combat math + battle sync (2027 lines;
                              partial coverage)
charabaseclass_event.lua      event helpers (444 lines; THIS finding)
charabaseclass_cliprog.lua    high-level queries (454 lines;
                              THIS finding)
charabaseclass_ffxivbattle.lua  stat indices + jobs (636 lines)
charabaseclass_u.lua          91 native bindings
```

All major files in the CharaBase family have been read or
inventoried. The biggest remaining gap is the deeper math in
`_battle.lua` (lines 1150-2027 cover detail beyond what's been
documented).
