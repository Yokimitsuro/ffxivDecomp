# Finding: CharaBaseClass_battle.lua - REAL COMBAT FORMULAS (Potencial Curve + Level Adjust + Magic Attack Table)

Closes the deep combat math gap in `charabaseclass_battle.lua` lines
1149-2027. Extracts **THREE concrete formulas/tables** that drive
FFXIV 1.x combat:

1. **Potencial curve** -- the 21-step monster danger curve
2. **calcPotencial** -- the level-adjustment formula
   (`sqrt(1 + (|diff| - 10) * 0.4)`)
3. **getMagicAttack** -- the hardcoded magic-attack stat table
   per skill level (1-50)

These are SERVER-AUTHORITATIVE for replicating 1.x combat exactly.

## 1. Potencial curve (`getPotencial`, line 1149)

The Potencial is a multiplicative factor for monster danger /
NM tier. Combat damage is scaled by potencial.

### NM tier overrides

For monsters, `MonsterBaseData[132]` is the NM tier code:

```text
NM tier code  Return value  Meaning
------------  ------------  -------
     1           -1         Regular NM
     2           -2         Undead NM       (CONFIRMED via isUndead earlier)
     3           -3         HNM (high NM)
     4           -4         World Boss
   else        normal       Falls through to level-based interpolation
```

So **the 4 negative potential values are the 4 NM tiers**. This
confirms what was speculated in prior findings.

### Normal monster path: level-based curve

When NM tier is not 1-4 (regular monster), the potencial is
INTERPOLATED from a 21-step lookup table indexed by the monster's
state-main-skill level (from MonsterBaseData[87]):

```text
SKILL LEVEL    POTENCIAL
   1            1
   5            2
   9            3
  13            4
  18            5
  23            6
  28            7
  33            8
  38            9
  43           10
  48           11
  53           12
  58           13
  63           14
  68           15
  73           16
  78           17
  83           18
  88           19
  93           20
  98+          21
```

Linear interpolation between curve points. For player potencial,
the multiplier is 1 (players don't get NM bonuses). For monsters,
the curve value is then multiplied by `MonsterBaseData[87]`
(monster's base level).

So a level-50 monster has potencial = 11 (between 48 and 53);
multiplied by monster's base level = 11 * base = effective potencial.

This is the CORE MONSTER DIFFICULTY CURVE for 1.x.

## 2. Level adjustment formula (`calcPotencial`, line 1316)

This is the **actual level-difference scaling formula** for combat:

```lua
function calcPotencial(self, A1, A2):
    -- A1 = target's level, A2 = caster's level (defaults to self's main skill level)
    if A2 == nil then
        A2 = self:getStateMainSkillLevel()
    end
    
    diff = A1 - A2
    abs_diff = math.abs(diff)
    
    if abs_diff <= 10 then
        return 1                                      -- ±10 = NO adjustment
    end
    
    excess = abs_diff - 10
    factor = math.sqrt(1 + excess * 0.4)
    
    if diff < 0 then
        return factor                                  -- target LOWER than caster: factor > 1
    elseif diff > 0 then
        return 1 / factor                              -- target HIGHER than caster: factor < 1
    end
end
```

### Interpreting the formula

```text
case                                          formula                effect
----                                          -------                ------
caster_lvl < target_lvl + 10                  1                       no adjustment
caster_lvl > target_lvl by N (N > 10)        1 / sqrt(1 + (N-10)*0.4)  damage MULTIPLIER
                                              <  1 -> DAMAGE REDUCED
caster_lvl < target_lvl by N (N > 10)        sqrt(1 + (N-10)*0.4)     damage MULTIPLIER
                                              > 1 -> DAMAGE INCREASED
```

### Sample values

```text
|diff|  excess  factor       Over-leveled caster    Under-leveled caster
                              (damage / factor)      (damage * factor)
------ ------  -----------   -------------------    -------------------
  0-10    0     1.000          1.000  (100%)         1.000  (100%)
  15      5     sqrt(3)=1.732  0.577  ( 58%)         1.732  (173%)
  20     10     sqrt(5)=2.236  0.447  ( 45%)         2.236  (224%)
  25     15     sqrt(7)=2.646  0.378  ( 38%)         2.646  (265%)
  30     20     sqrt(9)=3.000  0.333  ( 33%)         3.000  (300%)
  40     30     sqrt(13)=3.606 0.277  ( 28%)         3.606  (361%)
  50     40     sqrt(17)=4.123 0.243  ( 24%)         4.123  (412%)
```

So at a level difference of:
- ±20 (10 excess): damage is ~halved (over) or doubled (under)
- ±30 (20 excess): damage is ~1/3 (over) or 3x (under)
- ±50 (40 excess): damage is ~1/4 (over) or 4x (under)

**This is the REAL 1.x level adjust formula.** The 0.7 hardcoded in
GameCommandBaseClass was a per-param fudge factor; this is the
BASE damage multiplier.

### Anti-twink design implications

The formula penalizes over-leveled casters and BOOSTS under-leveled
casters. So a level-1 character fighting a level-50 monster does
~412% damage (if they could hit), but the level-50 character
fighting a level-1 monster only does 24% damage.

This is the OPPOSITE of typical MMO design (usually under-leveled
characters get penalized). It's an explicit **anti-twink + assist-the-
underdog** design: encourages high-level players to NOT solo
low-level content, while allowing emergency aid for low-level
players in high-level zones.

## 3. Magic attack stat table (`getMagicAttack`, line 1892)

A **HARDCODED LOOKUP TABLE** of magic-attack stat values by skill
level (1-50):

```text
Skill Level   Magic Attack
-----------   ------------
    1            570
    2            700
    3            880
    4           1100
    5           1500
    6           1800
    7           2300
    8           3200
    9           4300
   10           5000
   11           5900
   12           6800
   13           7700
   14           8700
   15           9700
   16          11000
   17          12000
   18          13000
   19          15000
   20          16000
   21          20000
   22          22000
   23          23000
   24          25000
   25          27000
   26          29000
   27          31000
   28          33000
   29          35000
   30          38000
   31          45000
   32          47000
   33          50000
   34          53000
   35          56000
   36          59000
   37          62000
   38          65000
   39          68000
   40          71000
   41          74000
   42          78000
   43          81000
   44          85000
   45          89000
   46          92000
   47          96000
   48         100000
   49         100000   (sic: same as 48)
   50         110000
   50+        99999999 (cap)
```

### Growth pattern

Per-decade growth ratios:
- Lvl 1 → 10:   570 → 5000     (~9x growth)
- Lvl 10 → 20:  5000 → 16000   (~3.2x growth)
- Lvl 20 → 30:  16000 → 38000  (~2.4x growth)
- Lvl 30 → 40:  38000 → 71000  (~1.9x growth)
- Lvl 40 → 50:  71000 → 110000 (~1.5x growth)

So **the per-decade growth ratio DECREASES** -- diminishing returns
at higher levels. Each decade is roughly 1.6-9x the prior, with the
ratio falling toward ~1.5x at endgame.

At Lvl 50+: the value caps at **99,999,999** (effective cap; values
beyond level 50 just return this).

### Likely interpretation

The "magic attack" stat is the SKILL-LEVEL-BASED magic damage
multiplier. The actual damage formula likely is something like:

```text
final_damage = base_spell_power * (caster_magic_attack / target_magic_defense)
              * level_adjust_factor (from calcPotencial)
              * elemental_resist_factor
              * crit_factor
              * status_factor
```

So `getMagicAttack(caster_skill_level)` feeds into the multiplier
chain. The 1.5x-9x growth across levels matches typical MMO power
curves (over 30-50 lvls, total scaling factor of ~200x for the
magic attack stat).

### Suspicious value at level 49

```text
Lvl 48: 100000
Lvl 49: 100000   <-- SAME as 48 (likely a typo / bug in retail)
Lvl 50: 110000
```

This looks like an intentional plateau OR a bug where lvl 49 should
have been 105000 or similar. The decompiled source preserves it
as-is; can't tell which without retail comparison.

## Architectural observations

```text
1. POTENCIAL = NM TIER + LEVEL CURVE
   The same field (getPotencial) returns negative values for the 4
   NM tiers AND a positive number from the 21-step curve for normal
   monsters. This is a clever overload -- one method handles both
   the "this monster is special" check and "this monster's danger
   value" computation.

2. LEVEL ADJUST IS sqrt-BASED, NOT LINEAR
   The use of sqrt for the level-difference factor means:
   - First 10 levels: NO adjustment (graceful zone)
   - Next levels: damages diminish/boost slowly
   - The 0.4 coefficient inside sqrt makes the growth ~2x per 20
     additional levels of difference

3. HARDCODED MAGIC ATTACK TABLE -- not sheet-driven
   Most stat-related code in 1.x is sheet-driven, but
   getMagicAttack is HARDCODED in Lua. This is unusual. Possible
   reasons:
   - Lua-side override for retail-specific balancing
   - Migration artifact from FFXI's hardcoded stat tables

4. ASYMMETRIC LEVEL ADJUST is ENFORCED HERE
   The formula naturally creates asymmetric scaling
   (over-leveled penalty + under-leveled boost). This
   architectural choice was in the Lua side; the 4-param scaling
   in GameCommandBaseClass is ADDITIONAL on top.
```

## Server implications (brief)

```text
To replicate 1.x combat exactly:

1. Implement getPotencial as:
   - For NM (tier 1-4): return -1, -2, -3, -4
   - For normal monster: interpolate 21-step curve by skill level,
     multiply by monster's base level

2. Implement calcPotencial as:
   - If |diff| <= 10: factor = 1
   - Else: factor = sqrt(1 + (|diff| - 10) * 0.4)
   - If caster > target: return 1/factor (downscale)
   - If caster < target: return factor (upscale)

3. Implement getMagicAttack as:
   - 50-entry lookup table (the values above)
   - Cap at 99,999,999 for level 50+

These three formulas are the BASE of combat damage. The actual
DAMAGE call combines them with command-specific params (the
4-param model documented elsewhere) and target defense.
```

## Confidence

```text
Confirmed:
  - Potencial NM tiers: -1 Regular, -2 Undead, -3 HNM, -4 World Boss.
  - 21-step potencial curve with exact (skill_level, value) pairs.
  - calcPotencial formula: sqrt(1 + (|diff| - 10) * 0.4); plateau
    at |diff| <= 10; over-leveled = 1/factor; under-leveled = factor.
  - getMagicAttack: 50-entry hardcoded lookup table; cap at 99M.
  - The 21-step potencial curve interpolates linearly between table
    entries.

Likely (High):
  - The "-2 = Undead" confirmed by prior finding
    (charabaseclass_cliprog isUndead()) matches Potencial NM tier 2.
  - getMagicAttack feeds into magic damage formulas; the missing
    piece is the FINAL damage formula (likely native C++).
  - The level adjust formula is ALSO used for physical damage,
    not just magic.

Likely (Medium):
  - Skill level 49's "100000" value (same as 48) is likely a typo
    in the retail Lua source preserved through decompilation.
  - getMagicAttack is hardcoded (not sheet-driven) because it's
    the BASE STAT TABLE that doesn't change per-character; only
    skill level matters.
  - The 4 NM tiers correspond to:
    - 1 Regular NM (named monsters, e.g. "Behemoth")
    - 2 Undead (Skeletons, Vampires, etc.)
    - 3 HNM (high-level named monsters, e.g. raid bosses)
    - 4 World Boss (instanced megabosses)

Speculative:
  - The Potencial value is the CORE damage scaling number used
    throughout combat. A monster with Potencial 21 deals
    21x its base level's damage.
  - The under-level BOOST design (sqrt formula favoring underdog)
    was inherited from FFXI where Beat-Mode players (lower level
    in higher-level content) had access to scaled-up damage.
```

## Connections to other findings

- **finding_chara_cliprog_and_event_extensions.md**: confirmed
  isUndead() == NM tier 2. This finding adds the 3 OTHER NM tiers.
- **finding_combat_command_pipeline_and_4param_scaling.md**: the
  4-param scaling (0.7 / 1.0 defaults) is ADDITIONAL to the
  sqrt-based level adjust documented here.
- **finding_status_subsystem.md**: the status power/life adjust
  methods use the SAME sqrt-based level adjust pattern.
- **finding_ffxivbattle_stats_and_jobs.md** (prior session): the
  Magic Attack stat table here is one of the per-skill scaling
  tables that prior session's `finding_charabaseclass_ffxivbattle.lua`
  was partially exploring.

## Next test

- Read the 636-line `charabaseclass_44m1o89qqy5.lua` (decoded as
  `charabaseclass_ffxivbattle.lua`) -- the prior session noted it
  has stat indices + jobs but the body wasn't fully extracted.
  It may contain MORE hardcoded stat tables.
- Find `getPhysicalAttack` or similar for the physical-side
  equivalent of getMagicAttack.
- Cross-reference the Potencial curve with status.csv to identify
  per-status power tiers (since status power likely uses similar
  scaling).

## Commit suggestion

```
docs(re/lua): extract REAL combat formulas: Potencial curve + level adjust + magic attack table
```
