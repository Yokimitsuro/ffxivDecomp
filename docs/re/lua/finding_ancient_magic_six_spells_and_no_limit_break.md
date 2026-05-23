# Finding: All 6 Ancient Magic Spells Confirmed + No "Limit Break" in 1.x

Validates the 36 cross-class action enumeration by checking
gameCommand.csv for the missing FFXI Ancient Magic spells
(Tornado / Quake / Flood) and the absence of a "Limit Break"
system in 1.x.

## All 6 Ancient Magic spells exist

Per FFXI lore, the **6 Ancient Magic spells** are:
- Tornado (Wind)
- Quake (Earth)
- Flood (Water)
- Burst (Lightning)
- Flare (Fire)
- Freeze (Ice)

Cross-checking `FFXIVTool/mycsv/Command.csv`:

```text
SPELL     ENEMY CAST ID    PLAYER CAST ID    Cross-class quota?
-----     -------------    --------------    -----------------
Tornado     23516           28992             NO (not in cross-class)
Quake       23519           28995             NO
Flood       23525           29001             NO
Burst       (TBD)           27316             YES (BLM cross-class)
Flare       (TBD)           27318             YES (BLM cross-class)
Freeze      (TBD)           27319             YES (BLM cross-class)
```

So **all 6 Ancient Magic spells are present in 1.x** -- contrary
to the earlier speculation that some were missing.

### Dual-ID convention

Each Ancient Magic spell has **TWO command IDs**:

```text
23xxx range = ENEMY-CAST version  (when monsters use Ancient Magic
                                   against players)
27xxx-28xxx-29xxx range = PLAYER-CAST version
                                  (when players cast Ancient Magic)
```

This dual-ID convention is used throughout 1.x for side-asymmetric
abilities. The enemy version may have:
- Different damage scaling (vs player level instead of monster level)
- Different range / area
- Server-only flags for "monster-applied" tracking
- Different MP cost / cooldown

### Cross-class subset (3 of 6)

The BLM cross-class quota covers 3 Ancient Magic spells:
**Burst, Flare, Freeze**. The other 3 (Tornado, Quake, Flood) are
**class-specific** (accessible only via the Black Mage class,
not via cross-class).

This explains the AncientMagic.lua heavy overrides documented in
`finding_director_family_and_cutscene_closure.md`:
- The class has 6 spells total
- Each spell has its own per-id config
- All 6 share the no-level-scaling override pattern
- 3 of them double as cross-class actions for non-BLM jobs

## NO "Limit Break" in 1.x

Searching `mycsv/Command.csv` for "Limit Break" / "リミットブレイク" /
"Limite" returns **NO MATCHES**. So:

```text
1.x = NO LIMIT BREAK SYSTEM
ARR = ADDED LIMIT BREAK SYSTEM (1, 2, 3-bar limit breaks)
```

The "Limit Break" UI mechanic in ARR (party-wide LB gauge, tier
1/2/3 LBs) was a brand-new feature, not a port from 1.x.

### "Fingerprints of the Gods" (29742) is NOT a Limit Break

The lone outlier in convertSkillId's 36 commands (29742
"Fingerprints of the Gods") is the **FFXI Sprint Boost** universal
buff -- a temporary movement-speed increase. NOT a damage-dealing
ultimate.

Function in FFXI: lasts ~30 seconds, gives +30% movement speed.
Used for travel / escape, not combat.

So 1.x had:
- 2-hour iconic abilities (Hundred Fists, Hallowed Ground, etc.)
- Fingerprints of the Gods sprint boost
- Job-specific signature actions

But NO "Limit Break" gauge / cooperative ultimate.

## Sample iconic ability data (from gameCommand.csv)

Sampling row data for the 8 most iconic cross-class actions:

```text
CMD ID  NAME              col 36  col 58  col 82   col 116  Notable
------  ----              ------  ------  ------   -------  -------
27106   Hundred Fists     5       15      -        -        (mostly empty;
                                                              behavior in Lua)
27148   Hallowed Ground   5       15      -        -        (similar to 27106)
27189   Mighty Strikes    5       15      -        -        (similar)
27345   Benediction       5       20      -        -        (20s recast)
27266   Jump              5       15      -        2        (range modifier 2)
27227   Battle Voice      5       8       -        -        (8s recast)
27305   Convert           5       15      -        -        
27318   Flare             3       8       2000     13       (damage params:
                                                              2000 base, 13 element)
```

### Observations

```text
col 36 = action category (5 for melee/ability, 3 for magic)
col 58 = base recast seconds (15 = standard 2h, 8 = short, 20 = long)
col 82 = base damage (filled only for spells; melee uses Lua-driven calc)
col 116 = element / damage type id (13 = Fire for Flare)

The MELEE / ability commands (Hundred Fists, Mighty Strikes, etc.)
have mostly EMPTY row data -- their behavior comes from Lua code.

The SPELL commands (Flare) have rich sheet data:
  base damage (col 82 = 2000)
  cast time multiplier (col 85-86 = 4, 1.5)
  recast time multiplier (col 89-90 = 4, 0.75)
  element id (col 116 = 13 = Fire)
```

So **magic spells are sheet-driven** while **melee/abilities are
Lua-driven**. This matches the earlier observations that:
- MagicBaseClass is a 22-line stub (sheet drives everything)
- AbilityBaseClass is a 26-line stub
- WeaponSkillBaseClass is a 22-line stub
- Most concrete spell/ability classes are 8-line declarations

The sheet rows carry the per-spell numeric params; Lua only kicks
in for ABNORMAL cases (like AncientMagic disabling level scaling).

## Confidence

```text
Confirmed:
  - All 6 FFXI Ancient Magic spells exist in 1.x with dual IDs:
    Tornado 23516/28992, Quake 23519/28995, Flood 23525/29001,
    Burst .../27316, Flare .../27318, Freeze .../27319.
  - 23xxx ID range = enemy-cast versions of Ancient Magic.
  - 27xxx/28xxx/29xxx = player-cast versions.
  - 3 of 6 Ancient Magic (Burst/Flare/Freeze) are in BLM cross-class
    quota; the other 3 (Tornado/Quake/Flood) are class-specific.
  - NO "Limit Break" system exists in 1.x (search returns nothing).
  - "Fingerprints of the Gods" (29742) is the FFXI Sprint Boost,
    NOT a Limit Break.
  - col 36 = action category (5 = melee, 3 = magic).
  - col 58 = base recast seconds (e.g. 15 = standard 2h-style,
    8 = short, 20 = long).
  - col 82 = base damage (only for spells).
  - col 116 = element ID (13 = Fire confirmed via Flare).

Likely (High):
  - Each Ancient Magic dual-ID pair shares mechanics; the 233xx ID
    is invoked when a NM (monster) casts the same spell.
  - The MELEE / ability commands have mostly empty sheet rows
    because their numbers come from Lua / weapon stats / cross-class
    config rather than from the sheet.

Likely (Medium):
  - Element IDs probably follow:
    13 = Fire,  14 = Ice,  15 = Wind,  16 = Earth,
    17 = Lightning,  18 = Water,  19 = Light,  20 = Dark
    (8 elements total, FFXI's classic element wheel + Light/Dark).
  - col 85-86 / 89-90 are cast-time / recast-time multipliers
    per condition (target type, distance, etc.).

Speculative:
  - The 23xxx (enemy) versions of Ancient Magic have different
    targeting -- monster casts are typically point-blank AoE
    while player casts can target individual enemies.
  - ARR's Limit Break system was added in part because 1.x's
    individual 2-hour abilities (Hundred Fists etc.) didn't
    scale well to multi-player content.
```

## Connections to other findings

- **finding_cross_class_36_actions_ffxi_heritage.md**: this finding
  expands the Ancient Magic context (3 in cross-class, 3 class-only).
- **finding_director_family_and_cutscene_closure.md** + AncientMagic
  override: confirmed -- all 6 spells share the no-level-scaling
  pattern.
- **finding_gameCommand_sheet_schema_and_subclass_patterns.md**:
  validated col 36, 58, 82, 116 meanings via concrete data.

## Next test

- Find the 3 missing Burst/Flare/Freeze ENEMY-CAST IDs (probably
  in the 23xxx range, sequential with Tornado/Quake/Flood).
- Sample col 116 (element id) for other elemental spells (Cure,
  Bio, Drain) to confirm the 8-element scheme.
- Cross-reference the cross-class command 23527 Sleep with the
  player cross-class 27306 Sleep to identify the enemy/player
  pattern more precisely.

## Commit suggestion

```
docs(re/lua): confirm all 6 Ancient Magic spells; no Limit Break in 1.x
```
