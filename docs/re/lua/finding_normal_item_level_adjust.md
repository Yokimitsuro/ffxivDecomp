# Finding: `NormalItemBaseClass_common` — Level Adjust Formula + Materia

The behavior layer for normal (non-equipment) items. Most importantly,
this file holds the **level-adjust multiplier formula** that gates
under-level item use, plus the materia + degradation mechanics.

Sources read:

```text
item/Normal/NormalItemBaseClass_common.lua    805 lines  (23 functions)
```

## Function Inventory (23 functions)

```text
BASIC ACCESSORS (6):
  getNormalItemLife            current durability
  getNormalItemUse             use count remaining
  getNormalItemPolish          polish (HQ/quality value)
  getNormalItemParam1/2/3      3 params (vs 4 for ItemBase)
  getNormalItemFitness         fitness (HQ-related)
  isUseForBattle               battle-usable?
  getObjectClassId             type tag

MATERIA (6):
  getNormalItemMateriaType
  getNormalItemMateriaGrade
  getNormalItemMateriaFreeIndex
  isMateriaAttached
  getMateriaAttachedCount
  isMateriaFitItemEquipPoint
  getMateriaTypeAndGrade
  getMateriaCatalogID
  getMateriaEfficiency

HQ TIERS (2):
  getNormalItemMainQuality
  getNormalItemSubQuality

KEY FORMULAS (2):
  calculateLevelAdjust         level-adjust multiplier
  getDegradeRate               durability decay rate

LIFECYCLE (1):
  init                          constructor
```

## The `calculateLevelAdjust` Formula

When using an item at a different level than designed for, this
function returns a **multiplier (0.1 to 1.0)** applied to the
item's effective stats.

```text
calculateLevelAdjust(userLevel, itemLevel):
  if itemLevel == nil or itemLevel <= userLevel:
    return 1.0           -- no penalty when user is at or above item level

  diff = min(7, itemLevel - userLevel)   -- cap at 7-level deficit

  if itemLevel >= 31:                     -- HIGH-LEVEL ITEMS (severe)
    diff 1 -> 0.7
    diff 2 -> 0.6
    diff 3 -> 0.5
    diff 4 -> 0.4
    diff 5 -> 0.3
    diff 6 -> 0.2
    diff 7+ -> 0.1                        -- 90% penalty for 7+ under-level

  elif itemLevel >= 11:                    -- MID-LEVEL ITEMS (moderate)
    diff 1 -> 0.9
    diff 2 -> 0.8
    diff 3 -> 0.7
    diff 4 -> 0.6
    diff 5 -> 0.5
    diff 6 -> 0.4
    diff 7+ -> 0.3

  else:                                    -- LOW-LEVEL ITEMS (gentle)
    diff 1 -> 0.9
    diff 2 -> 0.85
    diff 3 -> 0.8
    diff 4 -> 0.75
    diff 5 -> 0.7
    diff 6 -> 0.6
    diff 7+ -> 0.5
```

### Implications

This is the **under-level gear punishment table**. Three regimes:

```text
Item Level   Penalty for +1   Penalty for +7+
----------   --------------    -----------------
   1..10     -10%              -50%   (gentle)
  11..30     -10%              -70%   (moderate)
  31+        -30%              -90%   (severe)
```

So **using a level-50 item at level 43** (diff=7) gives only 10%
of its stats — effectively unusable. This forces players to upgrade
gear at the level appropriate for it.

But low-level items (1-10) keep 50% effectiveness even at +7 under-
level — early game is more forgiving.

This is **distinct from** the over-level scaling (per the ItemBase
finding where adjustments are applied above item level). Under-level
penalties are punitive; over-level adjustments scale gently.

### Server Implementation

```text
For any item being used:
  diff_signed = userLevel - itemLevel
  if diff_signed >= 0:
    use ItemParam_AdjustForHighLevelUse (over-level scaling)
  else:
    multiplier = calculateLevelAdjust(userLevel, itemLevel)
    apply multiplier to item's effective stats

Effective stats:
  attack_effective = item.attack * multiplier
  defence_effective = item.defence * multiplier
  etc.
```

So a level-50 sword used by a level-44 character does **30% damage**
(item level 50, diff = 6, in 31+ regime, multiplier = 0.2).

## Materia System Detail

```text
getNormalItemMateriaType()        type id of attached materia
getNormalItemMateriaGrade()       grade (1-5? tier system)
getMateriaTypeAndGrade()          combined (type, grade) return
getMateriaCatalogID()             catalog id of materia item
getMateriaEfficiency()            efficiency multiplier (probably HQ bonus)
isMateriaFitItemEquipPoint()      can this materia attach to this item slot?
```

Materia is a **sub-item attached to equipment** for stat boosts.
The materia has:
- Type (which stat it boosts, e.g. STR/DEX/etc.)
- Grade (power tier)
- Efficiency (HQ bonus on the materia itself)
- Fit-for-equip-point (slot compatibility)

The 1.x materia system is the **precursor to ARR's Materia** with
similar shape but distinct mechanics (no overmelding tiers).

## Durability Decay (`getDegradeRate`)

Function not read in detail this pass (located at line 805), but
the existence of this binding confirms:
- Items have a **decay rate** that scales durability loss
- Probably differs per item type (weapon decays per attack, armor
  per hit, etc.)

This combined with `getNormalItemLife` + `getItemLifeMax` (from
ItemBase) implements the **1.x durability system**:

```text
On each item use:
  newLife = oldLife - degradeRate
  if newLife <= 0:
    item becomes "broken" (unusable until repaired)
```

ARR simplified this — gear durability decays but breaks much later
and is auto-repairable via dark matter.

## Quality (HQ) System for Normal Items

```text
getNormalItemMainQuality      main quality tier
getNormalItemSubQuality       sub quality (NQ vs HQ)
getNormalItemFitness          fitness (probably HQ proc chance)
getNormalItemPolish           polish state
```

Items have a 2-axis quality system:
- **Main quality**: tier (e.g. 1-5)
- **Sub quality**: variant (NQ standard, HQ enhanced)

`Polish` is a durability-like value applied during crafting (high
polish = HQ proc).

## Param Differences vs ItemBase

```text
ItemBaseClass:    4 params (Param1, Param2, Param3, Param4)
NormalItemBaseClass: 3 params (Param1, Param2, Param3)
```

So consumables / non-equipment items have 3 effect parameters,
while equipment has 4. The 4th is probably equipment-specific (stat
slot for equipment vs effect duration for consumables).

## Assessment

```text
Confirmed:
  - calculateLevelAdjust has 3 regimes (item level 1-10 / 11-30 / 31+)
    with progressively more severe under-level penalties.
  - Up to 90% penalty at 7+ levels under for high-level items.
  - Materia system: type + grade + efficiency + slot fit.
  - 3 ItemParam fields for normal items (vs 4 for equipment).
  - 2-axis HQ system (main + sub quality + fitness + polish).

Likely (High):
  - Cap at "7 levels under" is the practical "do not use" threshold.
    Beyond +7, all multipliers max out at the regime's minimum.
  - Polish state is the crafting outcome -- high polish = high
    HQ proc chance.
  - getDegradeRate likely returns a per-item-type value (sword
    decays faster than tunic).

Likely (Medium):
  - The 3-regime threshold at level 11 and 31 reflects 1.x's
    tier breakpoints (probably aligned with quest progression
    milestones).
  - Materia efficiency = HQ bonus on materia itself (HQ materia
    gives more stat boost than NQ).

Speculative:
  - The +7 cap suggests the design intent was: "you can use
    +6 over-level gear with diminishing returns, but +7+ is too
    far -- replace it."
  - The 0.1 minimum (1.0 max - 90%) creates a soft floor: even
    catastrophically under-level items retain a token amount of
    effectiveness, never reaching 0.
```

## Server Implementation Picture

```text
ITEM USE FLOW (server-side):
  1. Player tries to use item X at level userLevel
  2. itemLevel = getItemLevel(X)
  3. If userLevel >= itemLevel:
       multiplier = 1.0
     Else:
       multiplier = calculateLevelAdjust(userLevel, itemLevel)
  4. effective_stat = base_stat * multiplier
  5. Apply effective_stat in damage/heal/buff calculations

DURABILITY DECAY:
  1. On each item use, deduct getDegradeRate() from life
  2. If life <= 0: item broken (cannot be used until repaired)
  3. Repair restores life via the 5-factor repair system

MATERIA EFFECT APPLICATION:
  For each attached materia:
    boost_amount = materia.grade * efficiency
    actor.stat[materia.type] += boost_amount
```

This closes the consumable item behavior layer. The under-level
formula is the most impactful single piece — it's the gear gating
mechanism that drives all of 1.x's progression incentives.
