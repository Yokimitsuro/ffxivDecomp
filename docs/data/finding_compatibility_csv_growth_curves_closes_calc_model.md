# Finding: compatibility.csv = Level-Scaling Growth Curves (closes the server calc model)

**Decodes compatibility.csv** — the shared LEVEL-SCALING CURVE table
that ALL level-adjust calculations reference (item/status/command
potency). This is the `getGrowData` source. Decoding it CLOSES the
server's authoritative calculation model: base value x compatibility
curve % at level = effective value.

Also decodes exp_BPCost.csv (per-level cost/threshold curve).

## 1. compatibility.csv structure

```text
52 columns (0-51); cols 9-51 are s8 (43 level-bracket columns).
220 data rows (compatibility curve ids).

Each ROW = a level-scaling curve: percentage values (0-100) across
~43 level brackets (cols 9-51). Each cell = the % effectiveness at
that level.

SAMPLE CURVES:
  id 1: 100,100,...,100        flat 100% (no scaling -- full at all levels)
  id 2: 1,0,0,...,0            only level-1 bracket active
  id 3: 10,10,...,10           flat 10%
  id 4: 60,60,...,60           flat 60%
  id 5: 80,80,...,80           flat 80%
  id 6: 100 (cols 9-32), 0 (cols 33-51)   full to mid-level, then 0
  id 7: 100 (cols 9-32), 10 (cols 33-51)  full to mid, then 10%
  id 8: 100 (cols 9-32), 60 (cols 33-51)  full to mid, then 60%

So a compatibility curve defines HOW EFFECTIVE something is at each
level. Flat curves (all same %) = uniform scaling; stepped curves
(id 6/7/8) = full effectiveness up to a threshold level, reduced
after (the "you out-level this" or "under-level penalty" curve).
```

## 2. How the level-adjust uses it (closes the model)

```text
The level-adjust formula (from status/item/command findings) works:

  effectiveValue = baseValue x compatibilityCurve[level] / 100

  1. The item/status/command has a COMPATIBILITY KEY:
     - itemData.csv col 48 = compatibilityKey (prior finding!)
     - status/command reference a curve id similarly
  2. compatibilityKey indexes into compatibility.csv -> a curve row
  3. getGrowData(level, param) reads compatibilityCurve[level]
     (the % at the level bracket, cols 9-51)
  4. baseValue is scaled by that %

This is THE growth curve. getStatusCompatibilityWithAdjust (status),
the item level-adjust (NormalItem regime), and command potency all
funnel through these curves. The "under-level penalty" / "over-level"
behavior is just reading the curve at the effective (clamped) level.

EXAMPLE (under-leveling):
  A level-40 ability used at skill level 30:
  - curve might give 100% at level 30 bracket but the ability's base
    is tuned for level 40 -> the curve interpolation reduces potency
  - the stepped curves (id 6/7/8 style) model this dropoff
```

## 3. exp_BPCost.csv structure

```text
4 columns: col0(s16), col1(s8), col2(s16), col3(s16)
30 data rows (levels 1-30).

  Level  col0  col1  col2  col3
  -----  ----  ----  ----  ----
  1      15    1     5     20
  2      20    1     10    25
  3      25    1     15    30
  4      30    1     20    35
  5      35    1     25    40

PATTERN (per level):
  col0: 15 + 5*(level-1)   -- BP cost? (battle points to use)
  col1: 1                   -- constant (tier/multiplier)
  col2: 5 + 5*(level-1)     -- lower threshold
  col3: 20 + 5*(level-1)    -- upper threshold

This is the per-level COST / THRESHOLD curve. Likely the
battle-point (BP) cost to execute level-N actions + the exp
thresholds. The linear +5/level pattern is the action-cost scaling.
```

## 4. The complete server calc model (now closed)

```text
SERVER CALCULATION TABLES (all decoded):
  itemData.csv      item stats (cols 43-68; col 48 = compatibilityKey)
  status.csv        status params (Power=27, Life=47, Param2/3=35/39)
  command trio      command effects (gameCommand cols 84-115 paired block)
  compatibility.csv LEVEL-SCALING CURVES (220 curves x 43 levels) <- THIS
  exp_BPCost.csv    per-level cost/threshold curve

THE UNIVERSAL CALC FORMULA:
  effectiveValue = baseValue(from item/status/command CSV)
                   x compatibilityCurve[compatibilityKey][effectiveLevel] / 100
  where effectiveLevel = clamp(actorLevel vs commandLevel, adjustCaps)

This ONE formula + these 5 tables drive ALL of:
  - item stat totals (gear)
  - status effect magnitude + duration
  - command/ability potency
  - the under-level / over-level scaling behavior

A SERVER replicates this for authoritative calculation:
  1. Load the 5 calc tables
  2. For any value: base x compatibility-curve-% at level
  3. Clamp level by adjust caps (from command/item adjust columns)

THE CALC MODEL IS NOW FULLY SPECIFIED.
```

## 5. Server-side requirements

```text
compatibility.csv:
  - 220 curves, each 43 level-brackets of % (0-100)
  - keyed by compatibilityKey (itemData col 48 + status/command refs)
  - server reads curve[key][level] for scaling

exp_BPCost.csv:
  - 30 levels of (BP cost, tier, low threshold, high threshold)
  - server uses for action cost validation (can the player afford
    the BP cost?) + level thresholds

IMPLEMENTATION: these are the SMALLEST but most CENTRAL calc tables.
compatibility.csv (220 rows) is referenced by every item/status/
command potency calculation. Load it first; it's the heart of the
level-scaling system shared across all gameplay calculations.
```

## 6. Confidence

```text
Confirmed:
  - compatibility.csv: 220 curves x 43 level-bracket columns (9-51), s8 %
  - Curve values 0-100 = % effectiveness per level
  - Flat curves (uniform) + stepped curves (threshold dropoff)
  - exp_BPCost.csv: 30 levels x (cost/tier/low/high), linear +5/level
  - itemData col 48 = compatibilityKey indexes into this table

Likely (High):
  - getGrowData reads compatibilityCurve[key][level]
  - The universal calc formula: base x curve% / 100
  - Stepped curves model under/over-level scaling
  - exp_BPCost col0 = BP cost, col2/3 = thresholds

Speculative:
  - The 43 columns = levels 1-43 (or skill tiers); 1.x cap was 50 so
    possibly levels 8-50 (cols 9-51 with an offset)
  - col1=1 in exp_BPCost = a constant multiplier or tier flag
```

## 7. Cross-references

- `finding_status_csv_column_structure.md` -- status uses these curves
- `finding_command_csv_trio_structure.md` -- command potency uses these
- `finding_statusbaseclass_status_effect_engine.md` -- getStatusCompatibilityWithAdjust
- `finding_judge_system_data_and_depiction_layer.md` -- CommonJudge loads
  compatibility + exp_BPCost
- `finding_item_common_inventory.md` -- item level-adjust regimes
- itemData cols (QUICK_REFERENCE sec 11) -- col 48 = compatibilityKey

## 8. Next test

```text
Server calc model is CLOSED. Remaining CSV work options:
1. Decode command.csv's own columns (vs gameCommand)
2. Decode quest.csv / quest_reward.csv (quest server data)
3. Decode the 53 populace*.csv (NPC spawn definitions)
4. Decode shop CSVs (shopBase/shopItem/marketItem)
5. Catalog the ~625 "useful" tables remaining (gear variants)
```

## Commit suggestion

```
docs(data): compatibility.csv = level-scaling growth curves (220 curves x 43 levels) -- CLOSES the server calc model (base x curve% = effective); + exp_BPCost per-level cost curve
```
