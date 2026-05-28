# Finding: status.csv Column Structure (mapped from StatusBase *AtSheet functions)

**Decodes the status.csv column layout** by cross-referencing the
StatusBaseClass `getStatusXAtSheet` functions (which call
`getStatusData(N)` to read column N). This gives the server the exact
column meanings for authoritative status calculation.

## 1. status.csv physical layout

```text
59 columns (index 0-58). 2-line FFXIVTool header:
  row 0: column index header (,0,1,2,...,58)
  row 1: type header (mostly empty; populated: col26=s32, col31=float,
         col42=s32, col47=float, col51=bool, col52=bool, col53=float,
         col54=bool, col55=s8, col56/57/58=bool)
  row 2+: data rows (id, col0..col58)

The table is SPARSE -- most columns are empty in 1.23b. The active
columns cluster in the 26-58 range.

Sample (status id 221000):
  col26=231, col31=0, col42=0, col47=60, col51=true, col52=true,
  col53=-1, col54=true, col55=-1, col56=false, col57=false, col58=false
```

## 2. The 5-parameter column mapping (from *AtSheet functions)

StatusBase `getStatusXAtSheet` functions read these columns via
`getStatusData(N)`:

```text
Param        Base col   Adjust col   (level-adjust grow cols)
-----        --------   ----------   ------------------------
getStatusParam2AtSheet   col 35       col 36
getStatusParam3AtSheet   col 39
getStatusPowerAtSheet    col 27
getStatusLifeAtSheet     col 47
getStatusParam1AtSheet   (col ~31)    (pre-560 fn)

Level-adjust-grow columns (from get*LevelAdjustGrow functions):
  cols 30, 34, 38, 45, 48 (per-param growth references)
  col 26 (s32) = category/icon base (populated = 231 in sample)

NOTE: exact param<->column disambiguation is affected by the
obfuscated assignment order (functions assigned AFTER their body).
The CONFIRMED active column SET is:
  {26, 27, 30, 31, 32, 34, 35, 36, 38, 39, 42, 45, 47, 48}
and the trailing flags {51-58}.
```

## 3. The trailing flag/value columns (51-58)

```text
col 47  float   Life / duration base (sample = 60 -> 60 seconds default?)
col 51  bool    classification flag (isShown? isBad?)
col 52  bool    classification flag
col 53  float   -1 (sentinel; adjust cap or no-value)
col 54  bool    true (canRegist? default-applicable?)
col 55  s8      -1 (sentinel; level/category)
col 56  bool    false (isRemovedFromDeath?)
col 57  bool    false (isRemovedAtChangeMainSkill?)
col 58  bool    false (canStartOnDead?)

The bool flags (51,52,54,56,57,58) map to the StatusBase
classification + removal-rule functions:
  isShownStatus / isBadStatus / isGoodStatus / canRegist /
  isRemovedFromDeath / isRemovedAtChangeMainSkill / canStartOnDead
```

## 4. The level-adjust calculation (recap from StatusBase finding)

```text
Each AtSheet function:
  1. base = getStatusData(baseCol)          # e.g. Power = col 27
  2. adjustBase = getStatusData(adjustCol)   # e.g. col 36 for Param1
  3. apply getStatusCompatibilityWithAdjust(base, ...):
     - scale by (casterLevel vs commandLevel) gap
     - growth-curve interpolation via the grow columns
     - clamp by high/low adjust caps

So the FINAL status value depends on:
  - the base column value (status.csv)
  - the caster's skill level vs the command's level
  - the growth curve (compatibility.csv)
  - the adjust caps

The server must replicate this to compute authoritative status
magnitude/duration.
```

## 5. Server-side requirements

```text
status.csv is a SERVER CALCULATION TABLE (CommonJudge loads it via
the calc-data set). For authoritative status handling:

1. STORE status.csv: 59 columns per status id
   - Active cols: 26-48 (params + adjust + grow) + 51-58 (flags)

2. COMPUTE status magnitude/duration:
   - Read base columns (Power=27, Life=47, Param1-3=31/35/39)
   - Apply level-adjust (caster level vs command level + growth curve)
   - This mirrors the client's getStatusXAtSheet computation

3. TRACK active statuses per actor (the 0x14f/0x150 status lists):
   - push (status_id, duration, flag) -- client expands to full effect

4. CLASSIFICATION (cols 51-58): good/bad, shown/hidden, removal rules
   - server uses these to decide dispel/cleanse/death-removal behavior

KEY: the wire sends only (id, duration, flag); both client AND server
compute the magnitude from status.csv + level. The server is the
authority on WHICH statuses are active + duration; magnitude is
deterministic from the shared table.
```

## 6. Confidence

```text
Confirmed:
  - status.csv has 59 columns, sparse, active in 26-58 range
  - getStatusXAtSheet read via getStatusData(N): cols 27/35/36/39/47 +
    grow cols 30/34/38/45/48
  - Trailing flags 51-58 = classification + removal rules
  - col 47 (float) = Life/duration (sample 60)
  - col 26 (s32) = category/icon (sample 231)

Likely (High):
  - Power=col27, Life=col47, Param2=col35, Param3=col39
  - The bool flags map to isShown/isBad/canRegist/removal functions
  - col 53/55 (-1) = adjust-cap / level sentinels

Speculative (param<->column off-by-one from obfuscated assignment order):
  - Param1's exact base column (pre-560 function, likely col 31)
  - Exact flag-to-function mapping for cols 51-58
```

## 7. Cross-references

- `finding_statusbaseclass_status_effect_engine.md` -- the AtSheet
  functions + level-adjust formula this decodes
- `finding_judge_system_data_and_depiction_layer.md` -- CommonJudge
  loads status-calc CSVs
- `docs/data/ffxivtool_table_catalog.md` -- the 803-table catalog
- `docs/server/content_requirements/ffxivtool_import_plan.md` -- import plan
- `finding_csv_complete_correlation_132_of_164_critical_mapped.md` --
  CSV consumer correlation

## 8. Next test

```text
1. Read getStatusParam1AtSheet (pre-560 fn) for Param1's exact column
2. Decode gameCommand.csv columns (command potency/cost)
3. Decode compatibility.csv (the growth curves used by level-adjust)
4. Cross-reference status.csv ids with the 158 status scripts
5. Document command.csv columns (judge category, level, target type)
```

## Commit suggestion

```
docs(data): status.csv column structure -- 5-param mapping (Power=27, Life=47, Param2=35, Param3=39) + classification flags (51-58); server calc table for authoritative status magnitude
```
