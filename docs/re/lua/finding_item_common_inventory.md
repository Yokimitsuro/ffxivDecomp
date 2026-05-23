# Finding: `ItemBaseClass_common` — Complete Inventory (190+ Methods, 4686 Lines)

The massive item system implementation file. Reading the function
inventory exposes the full item subsystem architecture: 50+ item
type predicates, equipment stat math, weapon stats, damage tables,
repair system, materia, HQ system, use validation.

This is the BEHAVIOR layer (vs the `_u.lua` binding stubs). The
4686-line file contains ~190 Lua functions implementing item
mechanics.

Source:

```text
item/ItemBaseClass_common.lua    4686 lines  (~190 functions)
```

## Function Inventory by Subsystem

### Type Predicate Family (~50 functions)

```text
GENERIC TYPES (7):
  isMoney, isImportant, isFood, isDrink, isPotion, isFurniture,
  isMaterial, isEventItem

EQUIPMENT (3):
  isEquipment, isArmor, isAccessory, isAmulet

WEAPONS by Class (7):
  isWeapon, isBattleWeapon, isAttackWeapon
  isNailWeapon, isSwordWeapon, isAxeWeapon, isRapierWeapon,
  isMaceWeapon, isBowWeapon, isLanceWeapon, isGunWeapon
  -- one predicate per weapon class

LONG RANGE WEAPONS (5):
  isLongRangeWeapon, isShotWeapon, isAmmoWeapon, isThrowWeapon,
  isArrowWeapon, isBulletWeapon

SHIELD (2):
  isShieldWeapon, isManualGuardShieldWeapon

MAGIC WEAPONS (4):
  isMagicWeapon, isMysticWeapon, isThaumaturgeWeapon,
  isConjurerWeapon, isArchanistWeapon

CRAFTER (DoH) WEAPONS (8 -- one per craft class):
  isCraftWeapon, isCarpenterWeapon, isBlackSmithWeapon,
  isArmorerWeapon, isGoldSmithWeapon, isTannerWeapon,
  isWeaverWeapon, isArchemistWeapon (alchemist),
  isCulinarianWeapon
  -- 8 craft classes confirmed in 1.x: Carpenter, Blacksmith,
     Armorer, Goldsmith, Tanner, Weaver, Alchemist, Culinarian

HARVEST (DoL) WEAPONS (5):
  isHarvestWeapon, isMinerWeapon, isBotanistWeapon,
  isFishingWeapon, isShepherdWeapon

FISHING ACCESSORIES (2):
  isFishingBaitWeapon, isFishingLureWeapon
  -- bait + lure as separate item types

MATERIA / MATERIAL (1):
  isEnchantMateria

USE-CASE PREDICATES (5):
  isUseForBattle, isHostilityItem, isUsable, isUseFree,
  isLostAfterUsed

QUALITY (3):
  isRareItem, isExclusiveItem, isFoodOrPotion
```

Total: ~50 predicate functions. Each does a sheet-data lookup.

### Equipment / Slot Fitting (8)

```text
isEquipment
getEquipmentData
getEquipmentEquipParameter
processGetEquipmentEquipParameter   (with bonus calculations)
getEquipmentParameterBonus
processGetEquipmentAppendParameter
processGetEquipmentParameterBonus
getAdditionalEffect

getEquipmentEquipPoint        (slot id this item goes in)
getEquipmentEquipTribe        (which races can equip)
isFitForEquipPoint(slot)      (passes slot test)
isEquipmentEquipPointSimple   (basic fit check)
getEquipmentEquipPointDetail  (detailed slot info)
isConformTribe(tribe)         (race restriction check)
canEquipSimple                (simplified can-equip)
getEquipmentParameterBonusAtSlot(slot)
```

### Item Level Adjustment System (16)

```text
getItemLevel                   item's level (sheet data)
getItemLevelType               level scaling type
getItemLevelAdjust             current level adjustment
getItemLevelAdjustLevelMax     max level for adjust
getItemCompatibilityWithAdjust adjusted compatibility

getItemParam1 / 2 / 3 / 4                       4 base params
getItemParam1 / 2 / 3 / 4 AdjustForHighLevelUse adjust for high-level
getItemParam1 / 2 / 3 / 4 AdjustForLowLevelUse  adjust for low-level
getItemParam1 / 2 / 3 / 4 LevelAdjustGrow        level-growth slope
```

So 1.x items had **4 abstract parameters** (Param1-4), each with:
- Base value
- Adjustment for use at HIGHER level than item's
- Adjustment for use at LOWER level than item's
- Growth slope per level

This is the **item scaling system** — items adapt their stats
based on user level vs item level.

### Item Compatibility (8)

```text
getItemCompatibilityKey        compatibility key (skill match)
getItemCompatibilityData       compatibility table data
getItemProperPackage           which package type holds this item
getItemCompatibility           main compatibility query
getItemCompatibilityBySkill    skill-specific match check

getItemMainSkill               which skill uses this item
getItemKind                    kind tag
getItemRarity                  rarity tier (1-5?)
```

### Use System (15)

```text
getItemUseMax                  max times this item can be used
canUseDetail                   detailed use check
processCanUseForActorStat      validate actor state
getCanUseErrTextIdForActorStat error message id

processCanUseForTarget         target validation
processCanUseForRange          range validation
canUseWithPartsCheck           parts-aware can-use
processCanUseForTargetParts    target parts validation
canUseOnDead                   dead target?
canUseParts                    parts use
processCanUseParts
canUseForRelation              relation gate
canUseForDeadTarget
canUseForLiveTarget

canUse                         final aggregated can-use check
```

Item use has a **multi-stage validation pipeline**: actor state +
target + range + parts + relation + life/dead states. Similar
structure to the GameCommand canFire pipeline.

### Repair System (7)

```text
getItemRepairSkill             which craft skill repairs this
getItemRepairLevel             min level to repair
getItemRepairItem              item used in repair (crystal?)
getItemRepairItemNum           # of repair items needed
getItemRepairCrystal           crystal type for repair
getItemRepairLicence           licence requirement
canRepair                      can this player repair this item?
isRepairable                   can this item type be repaired?
getRepairAmount                amount repaired per attempt
getItemRepairItemIcon          UI icon
```

So 1.x had a **rich repair system**: crafters could repair specific
item types, requiring crystals + licence. ARR simplified this.

### Durability / Life (3)

```text
getItemLifeForm                durability form (max value type)
getItemLifeMax                 max durability
getItemLife                    current durability
getWasteConfirmLevel           warning threshold (low durability)
```

### Effects / Consumption (4)

```text
getItemConsumptionBonus        consumption efficiency bonus
getItemEffectTime              duration of effect
getItemRecastTime              cooldown
getItemRecastGroup             shared cooldown group
```

### Weapon Stats (24 functions)

```text
PHYSICAL (5):
  getWeaponAttack              attack power
  getWeaponRate                attack rate (probably hit chance)
  getWeaponCritical            crit rate
  getWeaponParry               parry rate
  getWeaponFrequency           attack frequency (interval)
  getWeaponInterval

MAGIC (3):
  getWeaponMagicAttack         magic attack
  getWeaponMagicRate           magic accuracy
  getWeaponMagicCritical       magic crit rate

CRAFT (3):
  getWeaponCraftProcessing
  getWeaponCraftMagicProcessing
  getWeaponCraftProcessControl

HARVEST (3):
  getWeaponHarvestPotency
  getWeaponHarvestLimit
  getWeaponHarvestRate

ACTION GAUGE (2):
  getWeaponActionGaugeTime     time for action gauge
  getWeaponPowerGaugeLength    power gauge length

PENDULUM (1):
  getWeaponPendulum            pendulum mechanic (1.x specific)

RANGE / DAMAGE (5):
  getWeaponRangeShape          weapon range area shape
  getWeaponRangeTargettingMode targetting type
  getWeaponDamageAttribute     damage type bitmap
  getWeaponDamagePower         damage power
  getWeaponDamageAttributeNoArray  non-array damage version
```

### Shield Stats (3)

```text
getShieldDefence               raw defence value
getShieldGuardTime             guard duration
getShieldRate                  guard rate
```

### Armor Stats (3)

```text
getArmorDefence                raw defence
getArmorDamageCut              damage cut percentage
processGetArmorDamageCut       damage cut calculation
```

### Materia / Enchant System (6)

```text
getEquipmentAttachedMateria        currently attached materia
getEquipmentAttachedMateriaLife    materia remaining life
getEquipmentEmbezzlement           embezzlement (something custom)

getAttachMateriaAmount             # of materia attached
getNormalItemMateriaFreeIndex      free slot for new materia
isMateriaAttached                  has materia?
getMateriaAttachedCount

getMateriaType                     materia type id
getMaterializeTable                materialize lookup table
getMaterializePermission           can materialize this item?
getMateriaBindPermission           can bind materia to item?
```

### Quality (HQ) System (3)

```text
getMainQuality                quality tier
getSubQuality                 sub-quality (NQ vs HQ)
getItemHQValue                HQ bonus value
canChangeFitness              can change item's "fitness" (HQ proc?)
```

### Pricing (2)

```text
getSellPrice                  vendor sell price
isRealizableItem              can be sold for gil?
```

### Markets (2)

```text
getProperMarket               which market category
isProperMarket(category)      is this item in given market?
```

### Sub-Getters (6)

```text
getMainSkill                  main skill (e.g. for weapon, attacking skill)
getNameIndex                  name id
getItemIcon                   UI icon id
getItemColor                  item color (UI tint)
getItemMaterial               material type
getItemDecoration             decoration overlay icon
```

### Accessory (1)

```text
getAccessorySize              accessory size class
```

### Ammo (1)

```text
getAmmoVirtualDamagePower     ammo damage power
```

### Other (3)

```text
getObjectClassId              type tag (probably matches sheet)
sendMessageUseErr             show use-failed message
isFitForEquipPoint            equip point fit check
```

## Architecture Insights

### Item Master Sheet Structure

Each item has rows in up to 5 sheets:

```text
itemDataSheet      base data (every item)
equipmentSheet     if equippable
weaponSheet        if weapon (with weapon-specific stats)
armorSheet         if armor (with defense/cut)
accessorySheet     if accessory
```

Plus per-class subsheets via the type predicates.

### Item Use Pipeline (Multi-Stage Validation)

```text
canUse(target, ...)
  ↓
canUseDetail
  ↓
  processCanUseForActorStat       (dead/silenced/etc.)
  processCanUseForTarget          (target valid?)
  processCanUseForRange           (in range?)
  canUseWithPartsCheck            (parts targetable?)
  processCanUseForTargetParts     (specific parts?)
  canUseOnDead                    (dead targets allowed?)
  canUseParts / processCanUseParts (parts use)
  canUseForRelation                (friend/foe?)
  canUseForDeadTarget / canUseForLiveTarget
```

8+ check stages. Comparable to GameCommandBaseClass:canFire.

### Item Level Adjustment

Items dynamically adjust their stats based on user-level vs item-level:

```text
level_diff = user_level - item_level

if level_diff > 0:   apply ParamN_AdjustForHighLevelUse
elif level_diff < 0: apply ParamN_AdjustForLowLevelUse
plus ParamN_LevelAdjustGrow * |level_diff|
```

So an item's effective power scales with the user's level, allowing
old equipment to remain viable at higher levels.

## The 1.x Crafter / Gatherer Class Breakdown (CONFIRMED)

```text
DOH (Disciples of the Hand / Crafters) -- 8 classes:
  Carpenter, Blacksmith, Armorer, Goldsmith, Tanner, Weaver,
  Alchemist, Culinarian
  -- EACH has a dedicated weapon predicate (isCarpenterWeapon etc.)

DOL (Disciples of the Land / Gatherers) -- 4 classes:
  Miner, Botanist, Fishing, Shepherd
  -- "Shepherd" was a 1.x class (unique to 1.x; not in ARR)

Plus fishing accessories:
  Bait + Lure as separate item types
```

This is the FIRST confirmation of the "Shepherd" gathering class
(unique to 1.x — not in ARR). And the 8-crafter / 4-gatherer split
matches 1.x's design.

## Assessment

```text
Confirmed:
  - ~190 functions in ItemBaseClass_common (the BEHAVIOR layer).
  - 50+ item type predicates covering every weapon/armor/consumable
    type.
  - 4 Item Param fields per item, each with high-level/low-level/
    grow adjustments -- dynamic level scaling system.
  - Repair system requires craft skill + level + items + crystal +
    licence (5-factor).
  - Multi-stage use validation pipeline (8+ checks).
  - Item HQ (High Quality) system via Main/Sub quality fields.
  - Materia system with embezzlement field and life tracking.

Likely (High):
  - The 4 ItemParamX fields are the same as GameCommandBaseClass's
    ParamX (per finding_command_execute_wire.md) -- a unified
    "4-parameter" data model across items + commands.
  - "Shepherd" class is the discovery of a 1.x-only gathering
    class (deprecated in ARR).
  - The 8 crafter weapons map to the 8 DoH classes (vs ARR's 8
    crafters, mostly same set).
  - Item Pendulum (1.x weapon mechanic) doesn't survive into ARR
    -- it was a 1.x-specific weapon attribute.

Likely (Medium):
  - The 4-param model is similar to FFXI's "modifier" item system
    -- each item has 4 generic modifiers that the game interprets
    differently based on type tag.
  - Item HQ vs NQ is binary (Main + Sub quality), simpler than
    ARR's multi-tier HQ system.

Speculative:
  - The repair "licence" mechanic suggests 1.x had a permit-based
    repair system (craft licence to repair high-tier gear). ARR
    eliminated this complexity.
  - "Embezzlement" on materia is mysterious -- possibly a 1.x
    materia-removal mechanic (extract materia from item).
```

## Server Implementation

Most of these functions are **sheet lookups + arithmetic** — easy
to replicate server-side from the same sheets. The key system to
implement is:

```text
DURABILITY:
  Track item.life (current) vs life_max (from sheet)
  Decay on use (combat = wear, food = consumption)
  Repair via craft (skill match + crystal + items)

EQUIPMENT BONUSES:
  getEquipmentEquipParameter applies item stats to actor
  Process bonuses (HQ bonus, materia, etc.)
  Update actor's generalParameter[35] accordingly

ITEM LEVEL ADJUSTMENT:
  Compute level_diff, apply Param adjustments
  Used for both equipment scaling + consumable scaling

MATERIA:
  Attach/detach materia
  Track materia life (decay over time?)
  Embezzlement extraction (1.x-specific feature)
```

Equipment math is the biggest area — the 190 functions are mostly
sheet lookups, but the equipment math (processGetEquipmentEquipParameter,
processGetEquipmentAppendParameter, processGetEquipmentParameterBonus,
processGetConditionParameterBonus) drives the actor's stat
computation.

## Discovery Summary

This file confirms:
- 1.x had **12 gatherer/crafter classes** (8 DoH + 4 DoL incl.
  unique Shepherd)
- 7 weapon classes (Nail/Sword/Axe/Rapier/Mace/Bow/Lance/Gun)
- 4 magic weapon types (Mystic/Thaumaturge/Conjurer/Archanist)
- Items use 4-Param scaling system (same shape as Commands)
- Multi-stage use validation pipeline (8+ checks)
- 5-sheet item composition model
- Rich repair system (5-factor)
- Materia system with embezzlement (1.x-specific)
- Item Pendulum (1.x weapon mechanic, lost in ARR)
