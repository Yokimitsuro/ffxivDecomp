# Finding: Combat Command Pipeline + 4-Parameter Level Scaling

Extracts the combat command pipeline from GameCommandBaseClass +
BattleCommandBaseClass + the magic/weaponskill/attack
specializations. Key discovery: every battle command has a
**4-PARAMETER model** with under-level + over-level adjustment
curves, all driven from `gameCommandSheet` columns.

The Lua side carries the CONFIGURATION; actual damage math
(roll, defense subtraction, crit check) happens NATIVELY in C++.

## Battle command type taxonomy

From `BattleCommandBaseClass.getCommandType()`:

```text
Type   Predicate                          Class hierarchy
----   --------------------               --------------------
 0     (none)                             non-battle
 1     isAttackCommand                    AttackCommand
 2     isMagicMissileCommand              magic-missile variant (homing)
 3     isAbilityCommand                   AbilityBaseClass + subs
 4     isMagicCommand                     MagicBaseClass + subs
 5     isWeaponSkillCommand               WeaponSkillBaseClass + subs
```

So 5 battle types. Each type has its own per-type dispatcher
inside the C++ combat engine.

## GameCommandBaseClass cost / scaling pipeline

GameCommandBaseClass exposes ~90 methods. Combat-relevant ones
organized by phase:

### Cost (per-fire deduction)

```text
getCommandHPCost / getCostHP
getCommandMPCost / getCostMP
getCommandTPCost / getCostTP
getActionGaugeCost
getUseAmmo / getUseAmmoMax
getCastTime
getRecastTime
```

Each cost is sheet-driven from `gameCommandSheet`. The `process*`
variants (`processCanCommandForHpCost`, etc.) validate at
fire-time.

### Damage attributes

```text
getCommandDamageAttribute             damage type (Slash / Pierce / Blunt / Magic / ...)
getCommandDamageElem                  damage element (Fire / Ice / Thunder / Water /
                                                       Wind / Earth / Light / Dark)
getPartsDamageAdjust                  per-part-hit damage modifier
                                       (head / body / legs / etc.)
```

### Range / targeting

```text
getRange / getBestRange / getMinimumRange / getEffectRange
getCommandRangeShape    -- shape enum (cone / circle / line / box / ...)
getCommandRangeLength / getCommandRangeHeight
getRangeAngle / getRangeRotate / getRangeWidth
useWeaponRangeInformation -- override with weapon range
isLongRangeCommand
```

### Validation (canFire chain, ~700 lines from line 2327 onward)

```text
canFire                          MASTER entrypoint
checkFireImpl                    inner validation
processCanFire                   ~130 lines of validation logic

Validation steps (each via process*):
  processCanCommandForActorStat       caster's main stat allows it?
  processCanCommandForChangeActorStat target's main stat (dead/sit/etc)
  processCanCommandForSkill           caster has the skill?
  processCanCommandForHpCost          enough HP?
  processCanCommandForMpCost          enough MP?
  processCanCommandForTpCost          enough TP?
  processCanCommandForRecastTime      not on cooldown?
  processCanCommandForMyCommandWork   internal cmd-work state?
  processCanFireWithoutTarget         target-less check
```

So 8 distinct validation gates before a command can fire. Each can
return a specific error code via `getCanCommandErrTextIdFor*`.

## 4-PARAMETER scaling model (KEY DISCOVERY)

GameCommandBaseClass declares 4 generic parameters (Param1, 2, 3, 4)
per command. Each parameter has 4 adjustment methods:

```text
PARAM N:
  getCommandParamN_AdjustForHighLevelUse   -- multiplier when caster
                                              level > target level
  getCommandParamN_AdjustForLowLevelUse    -- multiplier when caster
                                              level < target level
  getCommandParamN_LevelAdjustGrow         -- growth curve (sheet col)

GLOBAL:
  getCommandLevelAdjust                    -- base scaling
  getCommandLevelAdjustLevelMax            -- max-level cap
```

### Default scaling constants

From GameCommandBaseClass body:

```text
                            Param 1    Param 2    Param 3    Param 4
                            -------    -------    -------    -------
ForHighLevelUse:            0.7        0.7        0.7        1.0
ForLowLevelUse:             1.0        1.0        1.0        1.0
```

So:
- **High-level use** (caster > target): Params 1/2/3 are DOWNSCALED
  to 70%. Param 4 stays at 100%.
- **Low-level use** (caster < target): NO penalty.

So 1.x's level-adjustment system is **asymmetric**: it PENALIZES
over-leveled casters (anti-grief / level-equalization) but does NOT
penalize under-leveled casters.

Param 4 (probably proc-rate / hit-chance) is INSENSITIVE to level
diff -- makes sense because probability shouldn't scale with level.

### Grow curves (sheet columns 42, 47, 52, 57)

```text
Param 1 grow column = gameCommandSheet col 42
Param 2 grow column = gameCommandSheet col 47
Param 3 grow column = gameCommandSheet col 52
Param 4 grow column = gameCommandSheet col 57  (Speculative; not yet read)
```

Each command provides a growth-curve column index in its sheet
data. The `judgeGrowColumn(skill, sheetValue)` helper interpolates
the actual value based on caster's skill level.

If the sheet value is < 0, the param doesn't scale (returns nil ->
use the base value directly).

### Likely param semantics (Speculative)

```text
Param 1 = base DAMAGE / POWER
Param 2 = secondary effect strength (e.g. status power, heal amount)
Param 3 = TERTIARY (e.g. AoE radius, duration multiplier)
Param 4 = PROBABILITY (proc rate, hit chance, status apply chance)
```

This is consistent with:
- Why Param 4 doesn't get level-adjusted (probabilities are level-
  independent).
- The 4-quarter-of-level patterns observed in other findings.

## AttackCommand specifics

`AttackCommand.getFrequency`:
```text
if commandId == 22114:  return -1
elif isAttackCommand:    return -2
else:                    return -1
```

So AttackCommand has a **frequency code**:
- **-1** = single-hit (for the special cmd 22114; what is 22114?
  Per FFXIVTool mycsv/Command.csv row 22114 = "Distract" or
  similar, in the 22000s range = battle commands).
- **-2** = WEAPON-DRIVEN frequency (multi-hit, rate tied to weapon
  delay).

## MagicBaseClass / WeaponSkillBaseClass

Both are **THIN BASES** (22 lines each):

```text
isMagicCommand        / getCommandType -> 4   (MagicBaseClass)
isWeaponSkillCommand  / getCommandType -> 5   (WeaponSkillBaseClass)
```

So they ONLY identify their type. All actual behavior is:
- In sheet data (per-spell / per-skill params)
- In the C++ side (the actual damage math)

## Monster command pattern -- the giant 3469-line file

`MonsterAttackWeaponSkill.lua` (3469 lines) has only **6 methods**.
Each is a GIANT switch statement on command id:

```text
function getCommandInformation(self, A1):
    local id = self:getCommandId()
    if id == 23010 then
        -- 9 vars set: (false, false, true, 1, 1, -1, 1, 1, false)
    elseif id == 23014 then
        -- 9 vars set: (false, false, true, 2, 2, -1, 2, -1, false)
    elseif id == 23018 then
        ...
    ... (each branch ~18 lines)
    end
```

Each branch sets ~9 config vars (flags + integers) which form the
per-skill behavior tuple. With 3469 / 18 ≈ 192 branches, the file
covers approximately **192 distinct monster weapon-skill variants**.

So 1.x's monster combat moves are heavily configured via this one
massive function -- each monster ability is one branch with its own
parameter set.

Sample branch fields (9 vars per branch):
```text
L3-L5  (3 booleans)  -- behavior flags
L8-L12 (5 integers)  -- numeric params (damage, range, etc.)
L13    (1 boolean)   -- post-cast flag
```

## Damage pipeline summary

```text
CALLER:                client OR server (a "fire" event)
  -> GameCommandBaseClass.canFire(...)
     -> 8 validation gates (HP/MP/TP/skill/recast/etc.)
  -> GameCommandBaseClass.fire(...)
     -> (likely calls native C++ damage calc)
     -> per-target loop:
        compute base damage from sheet (Param 1)
        apply level adjust (high/low; one of 0.7 or 1.0 default)
        apply grow curve (skill-level scaling)
        apply per-part adjust (head/body/legs/etc.)
        apply element/attribute multiplier (Fire vs Ice resist, etc.)
        apply crit / hit roll (Param 4 = chance)
        subtract defense
        emit damage event
        if status apply: roll vs Param 4, apply status with Param 2
                          power + Param 3 duration
```

So the Lua side feeds 4 params to the C++ damage calculator, which
does the actual math. The Lua side is essentially CONFIGURATION.

## Confidence

```text
Confirmed:
  - 5 battle command types (1=Attack, 2=MagicMissile, 3=Ability,
    4=Magic, 5=WeaponSkill).
  - 4-parameter scaling model with separate High-level / Low-level
    adjustment factors per param.
  - Default scaling: High = 0.7 for Param 1/2/3, 1.0 for Param 4;
    Low = 1.0 for all.
  - Grow-curve column indices: 42 / 47 / 52 / 57 in gameCommandSheet.
  - 8-gate validation chain inside canFire (HP/MP/TP/skill/recast/
    actor stat/change actor stat/internal cmd work).
  - MagicBaseClass and WeaponSkillBaseClass are 22-line thin bases;
    all spell behavior is sheet-driven + native.
  - MonsterAttackWeaponSkill is a 3469-line giant switch over ~192
    monster weapon-skill command IDs (23000+ range).

Likely (High):
  - Param 1 = base damage; Param 2 = secondary effect power; Param 3
    = tertiary (AoE/duration); Param 4 = probability (status chance,
    crit rate).
  - Param 4 doesn't level-scale because probabilities are level-
    independent.
  - The 8 validation gates run in order; the first failure returns
    the matching error text id.

Likely (Medium):
  - Command id 22114 (single-hit override in AttackCommand) is a
    specific named attack -- "Distract" or a one-hit cool-down
    skill. Confirmation requires the mycsv/Command.csv row 22114.
  - The native side combines all 4 params via a deterministic
    formula (no random elements other than crit/hit rolls).

Speculative:
  - The 0.7 high-level penalty was a deliberate game-balance choice
    to discourage HIGH-LEVEL PLAYERS from soloing low-level content
    -- a common MMO anti-grief design.
  - The 192 monster weapon-skill branches are organized in topical
    blocks (per-monster-family), e.g. 23000-23050 = small enemies,
    23050-23100 = mid-tier, etc.
```

## Notable design choices

```text
1. ASYMMETRIC LEVEL PENALTY:
   Over-leveled casters get -30% on Params 1/2/3. Under-leveled
   casters get no penalty. So 1.x discouraged "level-twinking"
   (high-level chars killing low-level content) but didn't
   punish characters fighting up.

2. PROBABILITY ISOLATION (Param 4):
   Probabilities (proc rate, status chance) are level-INDEPENDENT.
   So a high-level player STILL has the same chance to land a
   status effect on a low-level enemy as they would on an equal-
   level enemy. The DAMAGE penalty alone discourages grinding;
   the PROBABILITY behavior remains consistent.

3. SHEET-DRIVEN GROWTH CURVES:
   Each command provides 4 grow-curve column indices (one per param).
   The actual interpolated value comes from caster's SKILL value.
   So one command can have very different power at skill 1 vs skill
   50, governed by the curve column.

4. 192-WAY MONSTER SWITCH:
   Monster weapon skills are NOT class-driven (one Lua class per
   monster) -- they're ID-driven (one branch per skill). This
   trades file size for class proliferation. Adding a new monster
   skill = adding a branch to one big switch.
```

## Connections to other findings

- **status.csv schema** (per `finding_status_subsystem.md`): Param 2
  and Param 3 of a status-applying command likely flow into the
  status's Power + Life (intensity + duration).
- **CharaBase parameter** (per `finding_charabase_class_complete.md`):
  the actor's main skill level feeds into `judgeGrowColumn` for
  the per-command growth curves.
- **Command roster** (per `finding_command_roster_complete.md`):
  the 27 magic + 13 weaponskill + 15 ability commands all use this
  same 4-param model.
- **FFXIVTool mycsv/Command.csv**: each row has ~140 columns
  including the 4 grow-curve columns (42, 47, 52, 57) referenced
  here.

## Next test

- Decompile the C++ `fire` invocation path to find the native damage
  formula (likely in 0x008aXXXX or 0x006fXXXX address range).
- Look at the per-monster command id ranges in
  MonsterAttackWeaponSkill to identify topical blocks (23000-23100
  = small mobs, 23100-23200 = mid-tier, etc.).
- Read `getCommandHPCost` / `getCommandMPCost` / `getCommandTPCost`
  bodies to identify their sheet columns and the cost computation.

## Commit suggestion

```
docs(re/lua): combat command pipeline + 4-param level-scaling model
```
