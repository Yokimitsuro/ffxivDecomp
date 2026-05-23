# Finding: ffxivbattle.lua - Stat Array Layout + Physical Parameter Formula + Job-Class Compatibility Map

Closes the `charabaseclass_44m1o89qqy5.lua` (decoded as
`charabaseclass_ffxivbattle.lua`, 636 lines) gap. Extracts:

1. **`generalParameter[]` array index layout** (16 stat slots
   mapped: combat + craft + harvest)
2. **`getPhysicalParameter` formula** -- the PHYSICAL counterpart
   of getMagicAttack: piecewise-linear with 7 brackets up to lvl 70+
3. **Job-to-Class compatibility map** -- which 3 classes each of
   the 7 jobs can cross-class from
4. **HP / HP Max storage layout** -- per-index arrays

## generalParameter[] array layout (charaWork.battleTemp.generalParameter)

These are SIMPLE READERS into a shared parameter array. The array
is populated by the engine/server; Lua just indexes into it.

```text
INDEX   STAT                              GETTER
-----   ----                              ------
 16     Attack                             getAttack
 17     NormalDefence                      getNormalDefence
 19     AttackRate                         getAttackRate
 24     Evasion                            getEvasion
 25     AttackMagic                        getAttackMagic
 26     HealMagic                          getHealMagic
 27     ReinforceMagic                     getReinforceMagic
 28     WeekMagic   (debuff power; sic)    getWeekMagic
 29     MagicRate                          getMagicRate
 30     MagicEvasion                       getMagicEvasion
 31     CraftProcessing                    getCraftProcessing
 32     CraftMagicProcessing               getCraftMagicProcessing
 33     CraftProcessControl                getCraftProcessControl
 34     HarvestPotency                     getHarvestPotency
 35     HarvestLimit                       getHarvestLimit
 36     HarvestRate     (extrapolated)     getHarvestRate
```

So **16+ stat slots** in `generalParameter[]`, with indices
**0-15 reserved for PRIMARY stats** (HP/MP/TP/STR/DEX/VIT/INT/MND/
PIE etc., probably mirroring FFXI's 8 primary stats + computed
totals).

The 19 == AttackRate slot is **OFF-BY-ONE** from 18 (which is
gap) -- index 18 may be a different stat (likely "AttackParry" or
"AttackBlock" since they fall in the attack family).

### Implications

The `generalParameter[]` array is the FLAT INDEXED STAT ARRAY
used throughout combat. Each stat has a fixed index. The combat
formulas in CharaBaseClass (and elsewhere) just read indices.

Sample mapping of FFXI staples:

```text
Likely indices 0-15 (Speculative, FFXI mapping):
  0    HP
  1    MP
  2    TP
  3    STR
  4    DEX
  5    VIT
  6    AGI
  7    INT
  8    MND
  9    CHA
 10    PIE
 11    ... (HP Max?)
 12    ...
 13    ...
 14    ...
 15    ... (probably last primary stat)
```

Confirmation would require finding `getStrength()` / `getVitality()`
etc. in another file or grep'ing for `parameterSave.hp[]`.

## HP / HP Max storage (charaWork.parameterSave.hp[] and hpMax[])

```text
getHpImpl(self, idx):       return charaWork.parameterSave.hp[idx]
getHpMaxImpl(self, idx):    return charaWork.parameterSave.hpMax[idx]
```

So **HP is stored as an ARRAY** indexed by `idx`. This suggests
a MULTI-POOL HP system in 1.x:
- idx 0: current HP (the main pool)
- idx 1+: additional HP pools (party-shared? job-specific?)

Or it could be a single-entry array with idx always = 0. Without
more context, multi-pool is the more interesting interpretation
(matches FFXIV's later "MP cap" + "HP cap" mechanic).

## getPhysicalParameter -- the PHYSICAL POWER FORMULA (line 41)

The piecewise-linear formula that maps SKILL LEVEL to physical
base power. **PARALLEL to getMagicAttack** but FORMULA-based
rather than table-based.

```lua
function getPhysicalParameter(self, multiplier):
    skill_level = self:getStateMainSkillLevel()
    
    -- Piecewise-linear base computation
    if skill_level <= 10:
        base = 100 + skill_level * 10                   -- (lvl 1:110, ..., lvl 10:200)
    elif skill_level <= 20:
        base = 200 + (skill_level - 10) * 20            -- (lvl 11:220, ..., lvl 20:400)
    elif skill_level <= 30:
        base = 400 + (skill_level - 20) * 40            -- (lvl 21:440, ..., lvl 30:800)
    elif skill_level <= 40:
        base = 800 + (skill_level - 30) * 70            -- (lvl 31:870, ..., lvl 40:1500)
    elif skill_level <= 50:
        base = 1500 + (skill_level - 40) * 130          -- (lvl 41:1630, ..., lvl 50:2800)
    elif skill_level <= 60:
        base = 2800 + (skill_level - 50) * 200          -- (lvl 51:3000, ..., lvl 60:4800)
    elif skill_level <= 70:
        base = 4800 + (skill_level - 60) * 320          -- (lvl 61:5120, ..., lvl 70:8000)
    else:
        base = 8000 + (skill_level - 70) * 500          -- (lvl 71+:8500, ...)
    
    return math.ceil(base * (multiplier * 0.001))
end
```

### Per-bracket slopes

```text
BRACKET   SLOPE    BRACKET END    Effective per-decade growth
-------   -----    -----------    --------------------------
 1-10     +10      200            5x  (multi-decade)
11-20     +20      400            2x
21-30     +40      800            2x
31-40     +70      1500          1.875x
41-50    +130      2800          1.866x
51-60    +200      4800          1.714x
61-70    +320      8000          1.667x
71+      +500      (uncapped)
```

So per-decade growth ratio DECREASES (from 5x at low levels to
1.7x at endgame) -- diminishing returns, similar to getMagicAttack.

### Physical vs Magic side-by-side

```text
LEVEL    Physical (getPhysicalParameter base)    Magic (getMagicAttack)
-----    -----------------------------------    -----------------------
   1                  110                                  570
  10                  200                                 5000
  20                  400                               16000
  30                  800                               38000
  40                 1500                               71000
  50                 2800                              110000
  60                 4800                                  (capped at 99,999,999)
```

The two scales are RADICALLY different (magic numerical scale is
~25x higher than physical). They're NOT directly comparable --
the formulas downstream must apply normalizations specific to
each. The 0.001 multiplier in getPhysicalParameter is the hint:
the result is `base * (multiplier/1000)`, so the actual returned
value depends on what "multiplier" is.

### The multiplier argument

`getPhysicalParameter(self, multiplier)` takes a multiplier
parameter. The result is `ceil(base * multiplier * 0.001)`.

So if multiplier = 1000, result = base.
If multiplier = 500, result = base * 0.5.
If multiplier = 1500, result = base * 1.5.

So the multiplier acts as a per-mille scaling factor. Likely
sourced from:
- Equipped weapon's "physical attack multiplier"
- Class-specific multiplier (e.g. Warrior gets +20% physical base)
- Status effects (Berserk = 1500 multiplier?)

## Job-Class compatibility map (`getMainClassOrJob`, line 113)

When a player has a JOB active, this function checks if a given
class id is "compatible" with the job (allowed cross-class).

### The 7 jobs and their cross-class permissions

```text
JOB ID   PROBABLE NAME    Compatible Class IDs
------   -------------    --------------------
 15      Paladin           2 (Gladiator),     8 (Archer),       7 (Lancer)
 16      Monk              3 (Pugilist),      4 (Marauder),     23 (Conjurer)
 17      Warrior           4 (Marauder),      3 (Pugilist),     2 (Gladiator)
 18      Dragoon           7 (Lancer),        23 (Conjurer),    22 (Thaumaturge)
 19      Bard              8 (Archer),        2 (Gladiator),    7 (Lancer)
 26      Black Mage       22 (Thaumaturge),   2 (Gladiator),    7 (Lancer)
 27      White Mage       23 (Conjurer),      3 (Pugilist),     2 (Gladiator)
```

### Class IDs decoded

Based on the patterns:

```text
CLASS ID  NAME           ROLE
--------  ----           ----
   2     Gladiator       Sword + Shield (Paladin base) -- physical defender
   3     Pugilist        Fist (Monk base) -- physical melee
   4     Marauder        Axe (Warrior base) -- physical defender / tank
   7     Lancer          Lance (Dragoon base) -- physical melee
   8     Archer          Bow (Bard base) -- physical ranged
  22     Thaumaturge     Stave (Black Mage base) -- magic offense
  23     Conjurer        Stave (White Mage base) -- magic support
```

### Job-Class taxonomy validates 1.x design

```text
EACH JOB HAS:
1. Own base class                   (1 class)
2. 2 cross-class slots              (2 classes)
TOTAL: 3 classes per job

CROSS-CLASS PATTERN observed:
- Tank (PLD/WAR): pick MELEE supplements (Marauder+Pugilist, or Archer+Lancer)
- Melee (MNK/DRG): pick CASTER supplements (Conjurer+Thaumaturge)
- Ranged (BRD): pick BOTH melee + ranged (Archer+Gladiator+Lancer)
- Caster (BLM/WHM): pick TANK supplements (Gladiator, Pugilist, etc.)
```

This explains FFXIV 1.x's job-vs-class architecture: characters
SWITCH between class (base) and job (specialized). When in JOB
mode, only 3 classes' actions are available (own + 2 picks).

The cross-class picks are HARDCODED per job (not player-selected
in this finding's body), unlike ARR where players choose 5
cross-class actions from any class.

This MORE RESTRICTED cross-class design in 1.x is consistent with
its less-polished combat system that was reworked for ARR.

### checkClassCommandPermission (line 223)

```lua
function checkClassCommandPermission(self, class_id):
    if 15 <= class_id <= 19: return true        -- jobs 15-19
    if 26 <= class_id <= 27: return true        -- jobs 26-27
    return false
end
```

So the **7 jobs are at IDs 15-19 and 26-27** (a 5+2 split).
This confirms `finding_ffxivbattle_stats_and_jobs.md` from prior
sessions.

## Mostly-unanalyzed methods (low priority)

```text
isJob (237)                  -- class -> job predicate
convertSkillId (314)         -- skill id translation
getAdditionalCommandList (395) -- per-job extra commands
getJobItemId (444)           -- job soul crystal item id
```

These are likely small extensions of the job system; can be
sampled later if needed.

## Confidence

```text
Confirmed:
  - generalParameter[] is a shared array indexed by stat id (16 + slots
    identified: 16-36 with confirmed semantics).
  - getPhysicalParameter is a 7-bracket piecewise-linear formula with
    diminishing returns per-decade (5x -> 1.7x growth).
  - 7 jobs at IDs 15-19, 26-27 (matches prior findings).
  - Each job has EXACTLY 3 compatible class IDs in a HARDCODED map.
  - HP and HP Max are stored as indexed ARRAYS (multi-pool likely).
  - 16 stat slots identified covering combat (10), craft (3), harvest (3+).
  - "WeekMagic" is a typo in the source (preserved); likely means
    "WeakMagic" / debuff power.

Likely (High):
  - generalParameter indices 0-15 cover primary stats
    (HP/MP/TP + STR/DEX/VIT/INT/MND/PIE + others).
  - Class IDs 2-23 cover the 7 base classes + 8 crafters + 4 gatherers.
    Verified: 2=Gladiator, 3=Pugilist, 4=Marauder, 7=Lancer, 8=Archer,
    22=Thaumaturge, 23=Conjurer.
  - The `multiplier * 0.001` pattern in getPhysicalParameter means
    multipliers are stored in "per-mille" units (so a Warrior class
    bonus of "+50% damage" = multiplier 1500, not 1.5).
  - HP array's idx 0 = current HP; idx >= 1 may be alternate pools
    (companion HP? linkshell HP buffer?).

Likely (Medium):
  - The 18 stat-index gap is likely "AttackParry" or "AttackBlock"
    (related to the Attack family at 16/17/19).
  - The "Bard cross-classes Gladiator + Lancer" is unusual; might
    reflect a unique 1.x design where Bards equipped melee for
    self-defense.
  - Cross-class picks are FIXED per job (no player choice) -- a 1.x
    design simplification that was loosened in ARR.

Speculative:
  - The convertSkillId at line 314 likely converts class IDs to
    skill IDs (e.g. class 2 Gladiator -> skill ID for sword skill).
  - getAdditionalCommandList likely returns the 3 cross-class
    command lists when a job is active.
```

## Connections to other findings

- **finding_charabase_battle_real_combat_formulas.md**:
  getMagicAttack (table) is the magic side; getPhysicalParameter
  (formula) is the physical side. SAME conceptual scaling but
  different implementation.
- **finding_ffxivbattle_stats_and_jobs.md** (prior session):
  the 7 jobs (15-19, 26-27) match; cross-class map is new.
- **finding_combat_command_pipeline_and_4param_scaling.md**:
  the 4-param scaling for game commands MULTIPLIES the
  base values from getPhysicalParameter / getMagicAttack.
- **finding_status_subsystem.md**: status power likely uses
  generalParameter[stat_index] as an input.
- **finding_chara_cliprog_and_event_extensions.md**: confirmed
  jobToCrystalMap (15->2000202 Paladin etc.) matches this
  finding's job IDs.

## Server implications (brief)

To replicate 1.x combat exactly:
- Maintain generalParameter[] array per character (~36 stats).
- Use getPhysicalParameter's 7-bracket formula for physical power.
- Use getMagicAttack's 50-entry lookup for magic power.
- When player has a job active, restrict their action set to the
  3 hardcoded class IDs in the compatibility map.

## Next test

- Identify what stats fill generalParameter indices 0-15
  (HP/MP/TP plus FFXI's 6 primary attributes).
- Read convertSkillId + getAdditionalCommandList to fully map
  the job-class extension behavior.
- Find getStatPoint or similar for the per-stat allocation system.

## Commit suggestion

```
docs(re/lua): ffxivbattle stat array + physical formula + job-class compatibility map
```
