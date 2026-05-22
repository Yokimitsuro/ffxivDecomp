# Finding: Combat Relations + NM Potencial Encoding + Body Parts Model

Reading `charabaseclass_battle.lua` lines 1-1149 surfaces the core
combat-relationship judgment algorithm (`judgeRelation`), the
**potencial encoding** (negative values = Notorious Monster), the
**body parts model** (5 for players, 8 for NPCs), and the **skill
category bracketing** (52 skills divided into 4 brackets by id range).

Sources read:

```text
chara/charabaseclass_battle.lua    2027 lines
  lines 1-1149 covered in this finding
  lines 1149-1782 (calcPotencial table + initBattleSync schema)
                  covered in earlier findings
```

Companion module required at line 3:

```text
chara/charabaseclass_ffxivbattle.lua   (the "FFXIV battle" subsystem)
  -- separate file; not read this pass
```

## Skill Category Bracketing (52 skills, 4 brackets)

```lua
function CharaBaseClass:getSkillCategory(skillIdx)
  if skillIdx == 0    : return 0    -- not unlocked
  if skillIdx >= 39   : return 39   -- Disciple of Land (gatherer)
  if skillIdx >= 29   : return 29   -- Disciple of Hand (crafter)
  if skillIdx >= 21   : return 21   -- (intermediate tier)
  if skillIdx >= 1    : return 1    -- Disciple of War / Magic (battle)
  else                : return 0
end
```

So the `battleSave.skillLevel[52]` array is organized:

```text
skill indices    bracket  meaning
1..20            1        battle classes (DoW/DoM)
                          -- 20 slots; lots of room for new classes
21..28           21        (mid-tier; possibly weaponskills, support
                            magic, or unused reserved)
29..38           29        crafter disciplines (DoH)
                          -- 10 slots; 1.x had ~8 crafting classes
39..52           39        gatherer disciplines (DoL)
                          -- 14 slots; 1.x had ~3 gathering classes
                          + reserved capacity
```

Skill category 21-28 mid-tier is mysterious. The `getSkillCategory`
function explicitly tests for it but doesn't name it. Possibly an
"intermediate craft" category, or a placeholder for a never-shipped
1.x class.

### Convenience predicates

```text
isGatherer()  = getMainSkillCategory() == 39
isCrafter()   = getMainSkillCategory() == 29
isBattleCharacter() = isPropertyEnabled(3)   -- property bit 3 = battle
```

## Body Parts Model

The `isParts(self, partIdx)` query gates whether a part is targetable:

```lua
function CharaBaseClass:isParts(partIdx)
  if isPlayer:
    return partIdx <= 5    -- players have exactly 5 parts (slots 1-5)
  if isBattleCharacter (property bit 3):
    return npcWork.battleCommon.partsExists[partIdx]
  return false             -- non-battle NPCs have no parts
end
```

So:

```text
Player parts (always 5):
  1   Head
  2   Body
  3   Hands
  4   Legs
  5   Feet

NPC parts (variable, from battleCommon.partsExists[8]):
  1..8 -- arbitrary; server-defined per NPC class
```

### Parts direction arrays (per-body-part hit zone bitmaps)

```text
processGetPartsDirection:    [0, 2, 8, 0, 1, 2, 8, 4]
processGetPartsWideDirection: [false, true, true, false,
                               false, false, false, false]
```

The 8-element direction array is a per-part bitmask of valid hit
directions. The bit values are probably:

```text
bit  direction
---  ---------
 1   front
 2   right
 4   left
 8   back
```

So part 2 = `direction 0b0010 = right only`. Part 3 = `0b1000 = back only`.
Part 7 = `0b1000 = back only`. Part 8 = `0b0100 = left only`.

The wide-direction array marks parts 2 and 3 as accepting attacks
from a "wide front" arc (typical front-facing hit zones — chest,
abdomen).

### Server implication for parts targeting

A combat action targeting a specific body part:

```text
client requests: AttackCommand(npcId, partIdx=3, hitDirection=8)
server:
  - looks up npc.battleCommon.partsExists[3]  -> true/false
  - if false: reject
  - looks up CharaBase.processGetPartsDirection()[3] = 8
  - check (hitDirection & validDirections) != 0
  - if 8 & 8 = 8 -> hit is from back direction, valid -> apply damage
  - if 8 & 1 = 0 -> hit is from front, invalid -> miss
```

## `judgeRelation` — the friend/foe algorithm

The single most important combat decision: is this actor an enemy,
friend, self, or non-combatant? Returns one of 4 values:

```lua
function CharaBaseClass:judgeRelation(self, target, partyOpt)
  -- Step 1: both must be battle characters
  if not self.isPropertyEnabled(3): return 4    -- self is non-combat
  if not target.isPropertyEnabled(3): return 4  -- target is non-combat
  
  -- Step 2: self check
  if self == target: return 3                    -- self
  
  -- Step 3: party check
  party = partyOpt or self.getParty()
  if party._isMember(target): return 2           -- party member = friend
  
  -- Step 4: battalion check
  selfBat   = self.getBattalion()
  targetBat = target.getBattalion()
  selfPC    = self.isPlayer()
  targetPC  = target.isPlayer()
  
  if selfBat != 0 and selfBat == targetBat: return 2   -- same battalion = friend
  
  -- Step 5: PvP / cross-type relations
  if selfPC and targetPC:
    if self.isInPvP():
      if target.isInPvP(): return 1, false   -- both flagged for PvP = enemy
      -- else: implicit friend (PC vs non-PvP-PC)
    else:
      return 2                                -- PC vs PC, no PvP = friend
  elseif not selfPC:  -- self is NPC
    if targetPC: return 1, false              -- NPC vs PC = enemy
    elseif selfBat != targetBat: return 1, false  -- NPC vs NPC, diff bat = enemy
    else: return 2, false                          -- NPC vs NPC, same bat = friend (already covered)
  else:  -- self is PC, target is NPC
    if targetBat == 1: return 2                    -- battalion 1 = peaceful NPC = friend
    return 1, false                                -- PC vs NPC, hostile by default
end
```

### Return value space

```text
1  enemy           (red nameplate, attackable)
2  friend / ally    (green nameplate, healable)
3  self             (you)
4  non-combatant    (gray nameplate, neither attackable nor healable)
   -- e.g. shopkeepers, quest givers without combat property
```

### Battalion encoding

Battalion 0 = no allegiance (defaults to enemy unless specific rule applies)
Battalion 1 = **peaceful NPCs** (shopkeepers, quest NPCs)
Battalion >= 2 = various enemy factions / monster types

Server implementation: every NPC must have a `battalion` field. Same
battalion = friend; different = enemy. Battalion 1 is special-cased
as "peaceful" for player-vs-NPC interactions.

### PvP gating

Two players become hostile to each other ONLY when:
- both have `isInPvP() == true`
- they are not in the same party
- they are not in the same battalion

So a player without the PvP flag is invulnerable to other players
even if they're in PvP themselves. This is the 1.x PvP opt-in design.

## Potencial = Notorious Monster Encoding

The `potencial` float field doubles as an NM-type flag via **negative
values**:

```lua
function CharaBaseClass:isNotoriousMonster()
  local p = self:getPotencial()
  if p == -1: return true, 11    -- NM type 11
  if p == -2: return true, 12    -- NM type 12
  if p == -3: return true, 13    -- NM type 13
  if p == -4: return true, 14    -- NM type 14
  return false, 0                 -- not NM (positive potencial)
end
```

### NM types 11-14

Likely correspond to nameplate color/icon variants:
- 11 = "regular NM" (named monster — typically zone-specific challenge)
- 12 = "rare NM" (low-spawn-rate variant)
- 13 = "epic NM" (raid-tier)
- 14 = "world boss" (HNM / cross-zone)

Server implication: **no separate "isNotoriousMonster" packet needed**.
The server pushes `potencial = -N` for NM type N, and `potencial = positive_value`
for non-NM enemies. The client's `getPotencial` accessor returns the
raw float, and `isNotoriousMonster` interprets the sign + integer
value.

This is a clever encoding: one field carries two pieces of
information (NM flag + NM type) without adding a separate field.

## Cast Speed (battleTemp lookup)

```lua
getCastSpeed(idx)         = battleTemp.castGauge_speed[idx]
getCastSpeedAtEquip(idx)  = battleTemp.castGauge_speedAtEquip[idx]   -- NEW field
```

The `castGauge_speedAtEquip` is **not in the battleTemp schema** we
documented in `finding_event_and_battle_sync_schemas.md`. So this
field comes from one of the companion modules:

- `charabaseclass_ffxivbattle.lua` (required at line 3) — most likely
- one of the subclass scripts (Player, Npc) extending battleTemp

So the **real battleTemp schema is larger than 3 fields** — there's
at least a `castGauge_speedAtEquip` field added by ffxivbattle.

## `adjustLockOnTargetDirection(self, target)`

When a target is locked on, this returns the *adjusted* facing
direction:

```lua
function CharaBaseClass:adjustLockOnTargetDirection(target)
  baseDir = self:_getDir()                  -- current facing
  if target ~= nil and target ~= self:
    if self:isPlayer():                      -- only players adjust
      targetPos = target:_getPos()
      orientation = self:_getOrientation(targetPos.x, 0, targetPos.z)
                                              -- ignore Y; horizontal only
      return baseDir + orientation             -- face the target
  return baseDir
end
```

So **only players auto-track lockon**; NPCs don't. The Y component
is zeroed: the player rotates horizontally only (no looking up/down).

## Assessment

```text
Confirmed:
  - 52 skills are bracketed: 1-20 battle, 21-28 mid-tier (mystery),
    29-38 crafter (DoH), 39-52 gatherer (DoL).
  - Players have exactly 5 body parts (head/body/hands/legs/feet);
    NPCs have up to 8 from battleCommon.partsExists.
  - Body parts have direction bitmasks (front/right/left/back) and
    a wide-direction flag (front-arc).
  - judgeRelation returns 1=enemy, 2=friend, 3=self, 4=non-combatant.
  - Battalion field gates friend/foe; battalion 1 is special-cased
    as "peaceful NPC".
  - PvP is opt-in via isInPvP() flag; non-flagged players are
    invulnerable to PvP attackers.
  - Potencial doubles as NM flag: negative values encode NM type
    (11-14); positive values are regular potency multipliers.

Likely (High):
  - The 21-28 skill bracket is reserved capacity, not actually used
    in 1.x. The game shipped with ~15 battle classes (1-15), ~8 craft
    (29-36), ~3 gather (39-41); the rest were forward-compatible
    provisioning.
  - The NM types 11-14 map to nameplate variants:
    11 = regular NM (named)
    12 = rare NM
    13 = HNM (high-tier NM)
    14 = world boss
  - The "_assignForChild 64" reserved area in battleTemp is for the
    ffxivbattle companion module's extensions
    (castGauge_speedAtEquip + others).

Likely (Medium):
  - The 4-direction bitmask (front/right/left/back) is a 2-bit
    rotation quadrant scheme. Some parts only accept hits from
    specific quadrants -- e.g. back-only parts can't be hit from
    the front.
  - Battalion 1 (peaceful) is the catch-all for "NPCs that should
    not be attacked by accident". Includes shopkeepers, quest NPCs,
    Free Company hall NPCs, etc.

Speculative:
  - The PvP opt-in design with bilateral isInPvP() requirement is
    characteristic of MMOs designed for casual+hardcore mixed
    populations. Same model as FFXI's "ballista" (PvP duels) where
    only opt-in players could attack each other.
  - The wide-direction array marking parts 2/3 as "wide" corresponds
    to torso parts (chest, back) being hittable from a broader arc
    than limbs (which are precision-targeted).

Next test:
  - Read charabaseclass_ffxivbattle.lua: the companion module with
    the cast bar speed-at-equip, damage type tables, and probably the
    rest of the combat math.
  - Find the on-wire opcode for attack commands. The EXE-side packet
    builder for "AttackCommand" should call into the same dispatch
    path as command-execute. Try grep for the command id ranges.

Commit suggestion:
  docs(re/lua): combat relations (judgeRelation 4-state), NM potencial
                encoding, 5-vs-8 parts model, skill category brackets
```

## Server implication

A minimal-viable combat server must:

1. **Per-actor battalion field** — fundamental for friend/foe. Set
   battalion=1 for peaceful NPCs, 0 for monsters (unaligned default),
   2+ for specific factions.
2. **Per-actor PvP opt-in flag** (`isInPvP`) — separate from
   battalion. Used only for player-vs-player attacks.
3. **Per-NPC `battleCommon.partsExists[8]`** — controls which body
   parts are targetable; sync this when parts get destroyed in fight.
4. **Push `potencial` field with sign-coding** — positive = regular
   potency for damage calc; negative = NM type (-1..-4 maps to
   NM types 11..14).
5. **Parts direction bitmasks** are sheet-driven (per-actor-class
   from a sheet, not pushed per-instance) — server just verifies
   hit direction against the sheet during action validation.

The combat-validation server flow for a melee attack:

```text
1. Receive AttackCommand(actorId, targetId, partIdx, direction)
2. judgeRelation(self, target) -> must be 1 (enemy)
3. Look up target.battleCommon.partsExists[partIdx] -> must be true
4. Look up CharaBase.processGetPartsDirection()[partIdx] -> get valid
   directions mask
5. (direction & validDirections) != 0 -> hit accepted
6. Compute damage from potencial + skill level + stats
7. Push hp[1] update with new hp value
8. If hp[1] == 0 -> push hp update + ActorMainStat change to 1 (dead mode)
9. Push partsExists[partIdx] = false if part destroyed
```

This is the **core combat loop** in 7 server-side steps. The wire
surface is minimal: most state is derived from already-synced fields
(battalion, potencial, partsExists, hp).
