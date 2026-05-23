# Finding: `ItemBaseClass` — Item System (19 Bindings + 5 Sheets)

The item system in 1.x. Each item is an actor instance with metadata
loaded from 5 sheets (item/equipment/weapon/armor/accessory). The
NormalItem subclass family covers 10 specific consumable types.

Sources read:

```text
item/ItemBaseClass.lua             68 lines (init + finalize)
item/ItemBaseClass_u.lua          191 lines (19 native bindings)
item/Normal/ (directory)               (10 subclass files)
```

## `ItemBaseClass:_onInit`

```lua
function ItemBaseClass:_onInit()
  superClass._onInit()
  self:_bindSpreadSheetData(itemDataSheet)
  self:_bindSpreadSheetData(equipmentSheet)
  self:_bindSpreadSheetData(weaponSheet)
  self:_bindSpreadSheetData(armorSheet)
  self:_bindSpreadSheetData(accessorySheet)
  -- ^ 5 sheets bound for any item

  if self:_getOwner() ~= nil:
    worldMaster:_loadWord("itemName", self:_getCatalogID())
    -- Lazy-load item name string ONLY if item has an owner
end
```

So **every item binds 5 metadata sheets** for unified data access:
- `itemDataSheet` — base item data (name, icon, rarity, stack)
- `equipmentSheet` — equippable item data (slot, level req)
- `weaponSheet` — weapon-specific (damage, type)
- `armorSheet` — armor-specific (defense, gear set)
- `accessorySheet` — accessory-specific (rings, earrings, etc.)

The `_loadWord("itemName", catalogId)` call dynamically loads the
item's localized name string ONLY when needed (owner exists =
player or NPC holding it = visible in UI).

## `_onFinalize` (cleanup)

```lua
function ItemBaseClass:_onFinalize()
  if self:_getOwner() ~= nil:
    worldMaster:_unloadWord("itemName", self:_getCatalogID())
end
```

Releases the item name string when item is destroyed. Pair with
_loadWord for proper lifecycle management.

## 19 Native Bindings

### Identity (4)

```text
_getCatalogID()    item catalog id (sheet row in itemDataSheet)
_getNameIndex()    name string index
_getPackage()      owner's item package containing this item
_getOwner()        owner actor (player/npc holding it)
```

### Stack Management (3)

```text
_getMaxStack()     maximum stack size for this item type
_isStackable()     boolean: stackable item?
_countStack()      current stack count
```

### Rarity (1)

```text
_isRare()          rare flag (probably means non-tradeable / unique)
```

### Locking (2) — Item Lock State

```text
_isLocking()       is the item locked (in pending trade/bazaar)?
_getLockingInfo()  info about the lock (who/why)
```

Items can be **LOCKED** when participating in a pending trade or
bazaar listing — they can't be sold/dropped/used while locked.

### Dealing (3) — Trade Dealing

```text
_isDealing()           is the item in an active deal (trade/bazaar)?
_getDealingInfo()      deal info (buyer/seller/price)
_getDealingAttached()  attached items in the deal (bonus items)
```

So a "deal" can have **attached items** (bonus throws in a trade
or bazaar bundle). Common 1.x bazaar feature.

### Attachment / Trading (2)

```text
_isAttached()      is this item attached to another (deal bonus)?
_isTrading()       is this item being TRADED right now (vs locked)?
```

Three states: trading (active transaction), dealing (offered in
a deal), locking (committed to a deal but not yet executed).

### Equipping (2)

```text
_isEquipping()        currently equipped on owner?
_getEquippingSlot()   which equipment slot
```

### Sheet Data (1)

```text
_bindSpreadSheetData(sheet)
                bind a sheet to the item; subsequent queries can
                read from the sheet via the sheet's API
```

This is the **generic sheet binding** mechanism — items bind 5
sheets at init; any other system that needs sheet access uses the
same primitive.

### Sync (1)

```text
_updateWork(...)    sync item state to server
                     (same wire opcode 0x12f as actor sync)
```

So items can have **synced state**. Examples:
- Item conditions (broken/repaired)
- Item enchantment level
- Custom item flags

## NormalItem Subclass Family

```text
file                                purpose
----                                ----------------------------
NormalItemBaseClass.lua               normal item base (61 lines)
NormalItemBaseClass_common.lua        common impl (805 lines)
FoodItem.lua                          food consumable
PotionItem.lua                        potion (HP/MP restore)
RaiseItem.lua                         raise (revive) consumable
ShieldItem.lua                        shield equipment
ToolItem.lua                          tool (gathering implements)
EnchantMedicineItem.lua               enchant medicine (stat boost)
CmnGoodStatusItem.lua                 grants beneficial status effect
CmnBadStatusItem.lua                  inflicts negative status (debuff)
CmnRemoveStatusItem.lua               removes status effects
CmnHateControlItem.lua                modifies hate/aggro
```

So 1.x had **10 distinct consumable types** plus equipment items
(weapon/armor/accessory/shield/tool).

The **"Cmn" prefix** stands for "Common" — these are generic
consumables shared across multiple classes (vs job-specific items).

## Architecture Insights

### Item Lifecycle

```text
1. Item created (server pushes "you got item X"):
   - new Item actor allocated
   - bind 5 sheets
   - if owner: _loadWord(itemName, catalogId)

2. Item used (player consumes):
   - _onUse fires (subclass-specific behavior)
   - stack decremented or item destroyed

3. Item destroyed:
   - _onFinalize
   - _unloadWord (release name string)
```

### Trade/Bazaar State Machine

```text
TRADING:   actively in player-to-player trade window
LOCKING:   committed to a deal (both parties accepted), waiting
            for completion
DEALING:   listed in bazaar with proposed terms
```

Three orthogonal states with 3 separate predicates (_isTrading,
_isLocking, _isDealing) — explicit separation.

### Sheet System

```text
itemDataSheet     -> all items have an entry (base data)
equipmentSheet    -> equipable items add entry here
weaponSheet       -> weapons add detailed weapon entry
armorSheet        -> armors add detailed armor entry
accessorySheet    -> accessories add detailed accessory entry

So a SWORD has rows in:
  itemDataSheet (name, icon, stack)
  equipmentSheet (slot, level)
  weaponSheet (damage, type, attack rate)

A FOOD has rows in:
  itemDataSheet only (no equipment data)
```

Sheets are union-style — entries in different sheets compose the
full item profile.

## Cross-References

```text
_updateWork                -> WIRE OPCODE 0x12f (validated)
_loadWord / _unloadWord    -> WorldMaster native bindings (24 set)
_getOwner                  -> typically an actor (CharaBase or its subclass)
_isEquipping               -> tied to charaWork.command[64] equipped array
```

## Assessment

```text
Confirmed:
  - ItemBaseClass binds 5 metadata sheets at init.
  - Item names are lazy-loaded via worldMaster:_loadWord (only
    items with owners load their names).
  - 19 native bindings cover identity, stack, lock, deal, equip.
  - 10 NormalItem subclasses for consumables + equipment.
  - 3-state model for transactional state: trading/locking/dealing.

Likely (High):
  - The 5-sheet model means a single item ROW in itemDataSheet maps
    to 0-3 additional rows in equipment/weapon/armor/accessory
    based on the item type.
  - The "Cmn" common prefix items (GoodStatus/BadStatus/etc) are
    generic consumables; class-specific items (FoodItem etc.)
    have richer subclasses.

Likely (Medium):
  - The 805-line NormalItemBaseClass_common contains the bulk of
    the consumable logic (use effects, target validation, cooldowns).
  - The 4686-line ItemBaseClass_common (HUGE!) contains the base
    item logic including all the equipment/stat calculation paths.
    Worth reading if implementing crafting/equipment server-side.

Speculative:
  - Items in 1.x were full ACTOR INSTANCES (vs ARR's lightweight
    inventory rows). Each item had a unique actor id, allowing
    per-instance state (durability, enchantments, history).
    Heavyweight design but very flexible.
```

## Server Implementation Picture

```text
ITEM CREATION (server-side):
  - Allocate Item actor
  - Push item to player's inventory (assign owner)
  - Client receives, instantiates ItemBaseClass subclass
  - Item binds 5 sheets locally
  - Item name string loaded from sheet

ITEM STATE SYNC:
  - Item state changes (durability decay, etc.) sync via
    _updateWork -> opcode 0x12f
  - Stack count changes when item stacks (use/split/combine)

TRANSACTIONAL STATES:
  - Trade lock: server tracks lock holder + lock reason
  - Bazaar dealing: server tracks deal terms + attached items
  - On commit: transfer ownership, unlock items

CONSUMABLE USE:
  - Player invokes "use item X" command
  - Server validates target / cooldown / state
  - Apply effect (status/heal/raise/etc.)
  - Decrement stack or destroy item
```

This closes the **item system architecture** at the binding level.
The 4686-line ItemBaseClass_common would be the next read if
implementing detailed equipment / stat / enchantment server logic.
