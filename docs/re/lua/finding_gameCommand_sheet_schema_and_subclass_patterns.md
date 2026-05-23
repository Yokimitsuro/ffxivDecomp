# Finding: gameCommandSheet/BasicSheet Schema + Sheet-Driven Subclass Patterns

Drills down into specific sheet column meanings + sample subclass
bodies for Magic / Ability. Reveals:
1. **TWO command sheets**: `gameCommandSheet` (full) + `gameCommandBasicSheet` (cost summary).
2. Specific column meanings (HP/MP cost + cast time + ammo + recast + 4 grow curves).
3. **Sheet-driven defaults**: most spells/abilities are 8-line declarations; only EXCEPTIONS like AncientMagic override behavior.

## Two distinct sheets

GameCommandBaseClass reads from TWO separate sheets via two accessor methods:

```text
getGameCommandData(col)         -> gameCommandSheet[row=cmd_id, col]
                                    full per-command engine data

getGameCommandBasicData(col)    -> gameCommandBasicSheet[row=cmd_id, col]
                                    UI-summary cost data
```

The split likely separates:
- **Engine config** (gameCommandSheet): the params, growth curves, range, etc.
- **Player-facing cost** (gameCommandBasicSheet): what the UI tooltip shows.

This matches the FFXIVTool catalog where `gameCommand.csv` and
`gameCommandBasic.csv` are separate files (per
`finding_complete_3channel_opcode_inventory.md`).

## Column index mapping (confirmed)

### gameCommandSheet (full engine data, ~140 columns)

```text
col   meaning                                source method
----  -------                                -------------
 42   Param 1 grow-curve column index        getCommandParam1LevelAdjustGrow
 47   Param 2 grow-curve column index        getCommandParam2LevelAdjustGrow
 52   Param 3 grow-curve column index        getCommandParam3LevelAdjustGrow
 57?  Param 4 grow-curve column index        (extrapolated; pattern is +5)
 75   ActionGauge cost (raw)                 getActionGaugeCost path
 82   isRegistable (bool/int)                isRegistable
 ...
```

### gameCommandBasicSheet (cost summary)

```text
col   meaning                                source method
----  -------                                -------------
 76   Cast Time                              getCommandTPCost path
114   HP cost                                getCostHP
115   MP cost                                getCostMP
 76   (also Cast Time as cost?)              shared with above
```

So `gameCommandBasicSheet[114]` = HP cost, `[115]` = MP cost,
`[76]` = Cast Time. Triple cost info in one tiny sheet -- consistent
with this being the PLAYER-FACING summary.

## Cost computation flow

```text
ACTOR.calculateCommandCost(value)
  is called by getCostHP / getCostMP / getCostTP
  scales the raw cost based on actor's modifiers
  (e.g. Refresh buff, Silence debuff, etc.)

OVERRIDE pathway (per-actor force-cost):
  getForceCostMPForCaster()  -> returns (multiplier, override)
  getForceCostTPForCaster()  -> same
  getForceCastTimeForCaster() -> same
  
  if override != -1: cost = override (absolute force)
  else if multiplier != 1: cost = cost * multiplier
  
Cost validation returns:
  cost == 0   -> -1 (free / no-cost command)
  cost > resource -> -2 (insufficient resource)
  else        -> cost (the deductible amount)
```

So actors can FORCE specific costs via the `getForce*` methods:
- A buff/debuff that sets a fixed cost: override path
- A buff that scales cost (e.g. -25% MP): multiplier path

## Command ID ranges (from isRecastSeparationHands)

```text
22100-22499      Job-specific actions (battle/craft)
   exceptions with SEPARATE per-hand recast:
   22101, 22102, 22103, 22105, 22106, 22107, 22109,
   22110, 22111, 22112       (= 10 specific actions in lower band)
   22301, 22304, 22305, 22306 (= 4 specific actions in upper band)

26000-29999      Gift / extended commands
   exceptions:
   29458-29464              (= 7 specific gift IDs)
   29497, 29501              (= 2 specific gift IDs)
```

So the player can have DIFFERENT recast timers on each hand for the
exceptions listed -- typical for dual-wield characters where each
hand has its own weapon-skill cooldown.

Specific command IDs from FFXIVTool catalog (per prior session):
- 22004 = Fish
- 22005 = Herd (Shepherd)
- 22550-22597 = Standard craft commands

So the 22000-22499 range covers: 22004 Fish + 22005 Herd +
22000-22099 unknown (probably basic actions) + 22100-22299 battle
actions + 22301-22306 special + 22550-22597 craft.

The 26000-29999 range is the EXTENDED command space (gifts, special
items, etc.).

## Subclass body patterns

### Most spells/abilities are 8-line stubs

Sample sizes from the ability + magic directories:

```text
SPELL/ABILITY                           LINES   PATTERN
----------------                        -----   -------
AbilityBaseClass                        26      base (isAbility=true, type=3)
MagicBaseClass                          22      base (isMagic=true, type=4)
ProvokeAbility                           8      stub
ProvocationAbility                       8      stub
CamouflageAbility                        8      stub
CureMagic                                8      stub
CuraMagic                                8?     stub (extrapolated)
EsunaMagic                               8      stub
BioMagic                                 8      stub
PoisonMagic                              8      stub
PoisonaMagic                             8?     stub (extrapolated)
DrainMagic                               8?     stub (extrapolated)
RaiseMagic                               8?     stub (extrapolated)
BindMagic                                8?     stub (extrapolated)
SongMagic                                8?     stub (extrapolated)
AttackMagic                              8?     stub (extrapolated)

AncientMagic                            99      HEAVY OVERRIDES
```

So **the vast majority of spells and abilities are 8-line
declaration stubs**. They just declare:
```lua
require("/Command/Game/Magic/MagicBaseClass")
_defineClass("CureMagic", "MagicBaseClass")
```

That's it. All behavior comes from sheet data + MagicBaseClass +
GameCommandBaseClass + BattleCommandBaseClass.

### AncientMagic: the exception

`AncientMagic.lua` (99 lines) is THE anomaly -- the only Magic
subclass with heavy overrides. It overrides:

```text
METHOD                                       VALUE       BASE DEFAULT
------                                       -----       ------------
getCommandLevelAdjustLevelMax                (-1, 10)    [varies]
getCommandParam1AdjustForHighLevelUse        0           0.7
getCommandParam2AdjustForHighLevelUse        0           0.7
getCommandParam3AdjustForHighLevelUse        0           0.7
getCommandParam4AdjustForHighLevelUse        0           1.0
getCommandParam1AdjustForLowLevelUse         0           1.0
getCommandParam2AdjustForLowLevelUse         0           1.0
getCommandParam3AdjustForLowLevelUse         0           1.0
getCommandParam4AdjustForLowLevelUse         0           1.0
canUseCommandRangeAreaSelect                 false       (whatever base)
```

INTERPRETATION:
- Returning `0` for all level-adjust methods = NO LEVEL SCALING.
  The math probably treats `0` as a sentinel "skip the multiplier
  branch, use the raw sheet value".
- `canUseCommandRangeAreaSelect = false`: Ancient magic CANNOT
  do area-select targeting (single-target only).

This matches the FFXI heritage:
- Ancient magic in FFXI = Tornado, Quake, Flood, Burst, Flare, Freeze
- All 6 are SINGLE-TARGET, HIGH-COST, FIXED-POWER spells
- They are gated by skill level (only high-level BLM can cast them)
- They don't scale with caster level vs target level because they're
  already endgame content

## Server implications

```text
NO SERVER REQUIREMENTS for the bulk 8-line stubs -- they just need
to be CREATED as Lua classes when the engine loads. All behavior
is sheet-driven (the server loads gameCommand.csv +
gameCommandBasic.csv and runs the math).

For the heavy-override classes:
- AncientMagic + MonsterAttackWeaponSkill have per-command-id
  config tables. Replicating these requires either:
  (a) reading the Lua + applying the same overrides on the server, OR
  (b) baking the overrides into the sheet data extension.

Sheet columns to extract from gameCommandSheet:
  col 42 (Param 1 grow), 47 (Param 2 grow), 52 (Param 3 grow),
  57? (Param 4 grow), 75 (action gauge), 82 (registerable)
  + columns NOT YET MAPPED for: Param 1-4 base values, damage
    attribute, damage element, range, frequency, status apply id
    (TBD; mechanical work via grep on the remaining
    GameCommandBaseClass body)

Sheet columns from gameCommandBasicSheet:
  col 76 (cast time), 114 (HP cost), 115 (MP cost)
```

## Pattern: STUB vs HEAVY override

```text
RULE OF THUMB:
- If a command class is 8 lines: 100% sheet-driven, no Lua logic
- If 50-200 lines: a few targeted overrides (e.g. specific ID checks)
- If 200-1000+ lines: structural class (BaseClass for a family)
- If 3000+ lines: GIANT switch over per-ID configs (like
                   MonsterAttackWeaponSkill at 3469 lines)

The 8-line stubs exist because Lua's _defineClass REQUIRES a class
to exist before the engine can instantiate it from a sheet row.
So the engine has a `class_name` field per sheet row, looks up
the Lua class, instantiates it, and reads the per-row config.
```

## Confidence

```text
Confirmed:
  - TWO command sheets: gameCommandSheet (engine) + gameCommandBasicSheet
    (player-facing cost).
  - HP cost = basicSheet col 114; MP cost = basicSheet col 115;
    Cast Time = basicSheet col 76.
  - Param grow curves at gameCommandSheet cols 42, 47, 52 (and
    likely 57 for Param 4).
  - isRegistable = gameCommandSheet col 82.
  - 22100-22499 and 26000-29999 are the two main command id ranges,
    each with hand-by-hand recast exceptions.
  - Most Magic + Ability subclasses are 8-line declaration stubs.
  - AncientMagic is the heavy-override exception (99 lines; ALL 4
    params zero-scaled + no area-select).

Likely (High):
  - Param 4 grow curve column = 57 (extrapolated from +5 pattern of
    42/47/52).
  - The "0" return from override methods = sentinel "skip
    multiplier" in the native math.
  - The 22000-22099 range covers basic non-job actions (Fish=22004,
    Herd=22005). The 22100-22499 range covers job actions. The
    22550+ range covers craft (per prior craft finding).
  - Cure / Esuna / Raise / Bio / Poison / Drain are all 8-line stubs
    because their behavior is pure sheet + base class.

Likely (Medium):
  - Force-cost overrides (getForceCostMPForCaster etc.) are used by
    specific status effects (Refresh = MP regen, Reduce MP cost
    buffs, etc.).
  - gameCommandBasicSheet may have only 5-10 columns (just cost
    info; the prior FFXIVTool catalog showed col counts).

Speculative:
  - Sheet col 82 returning the bool isRegistable means players can
    only have certain commands on their hotbar (the registerable
    ones). Non-registerable commands fire automatically (auto-attack,
    passive effects) or are admin-only.
  - The "DivideMpMagic" spell (FF Convert / FFXIV's transposable
    HP-MP swap) likely uses force-cost overrides to encode its
    unusual cost calculation.
```

## Connections to other findings

- **status.csv schema** (`finding_status_subsystem.md`): the `Refresh`
  status (cost-reduction buff) probably uses `getForceCostMP/TP`
  hooks to modify command costs.
- **Command roster** (`finding_command_roster_complete.md`):
  the 27 magic + 15 ability subclasses are mostly 8-line stubs;
  AncientMagic at 99 lines is the only heavy magic class.
- **MonsterAttackWeaponSkill** (3469 lines): the per-ID switch
  pattern there is the EXTREME case of stub-vs-override.
- **FFXIVTool catalog**: gameCommand.csv (1613 rows, ~140 cols) +
  gameCommandBasic.csv (~200 rows) align with the TWO sheets used
  here.

## Next test

- Sample gameCommand.csv row for cmd 22114 (the AttackCommand
  single-hit override id) -- column meanings should align with
  the sheet cols 42/47/52/57/75/82.
- Read processCanFire body (lines 2514-2644 in GameCommandBaseClass)
  for the full validation logic.
- Look at `getCommandParam1Base` / similar to find the BASE values
  (not just grow curves; the actual numeric power per command).

## Commit suggestion

```
docs(re/lua): gameCommandSheet/BasicSheet columns + 8-line stub pattern
```
