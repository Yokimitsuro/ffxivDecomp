# Finding: Command CSV Trio Structure (command / gameCommand / gameCommandBasic)

**Documents the 3 command-definition CSV tables** the server needs for
command validation + potency calculation. These are the tables
CommandBase + CommonJudge load; they define every action/ability/
weaponskill/spell/system command.

## 1. The command CSV trio

```text
Table               Rows   Cols   Role
-----               ----   ----   ----
command.csv         1662   ?      command identity + base definition
gameCommand.csv     1611   140    command effect/scaling/targeting params
gameCommandBasic.csv 1611  120    command basic params (category/cost/level)

command.csv has slightly more rows (1662 vs 1611) -- it's the master
command list; gameCommand/gameCommandBasic are the gameplay-param
sidecars keyed by the same command ids.

Command id ranges (per the CSV preloader finding's filters):
  12xxx  system commands (12002, 12003, 12004 = first rows)
  21xxx  NPC commands
  24xxx  action commands
  26xxx  special
  30xxx+ generic
```

## 2. gameCommand.csv structure (140 columns)

```text
Sparse table; active column groups (from type header + sample rows):

  col 36  s32    ? (0)
  col 38  s32    command sub-type (0 or 2 -- 12004 has 2)
  col 53  s16    -1 (sentinel)
  col 54-56 float  0, 1, 1  (scaling factors? cast/recast multipliers)
  col 57  bool   false (a flag)
  col 64-67 float  cast/recast/timing values
  col 68  s32    -1 (target/effect id sentinel)
  col 73  bool   false
  col 82  bool   false
  col 84  s32    effect-table start

  *** PAIRED EFFECT BLOCK: cols ~84-115 ***
  An alternating (s32, float) repeating structure (~16 pairs):
    (type0, val0), (type1, val1), ... 
    Sample 12004: 0,1,1,-1,0,-1,0,-1,0,-1,0,1,0,1,1,-1,0,...
  This is the COMMAND EFFECT/SCALING TABLE -- pairs of
  (effect_type_id, magnitude) that define what the command does.
  -1 = unused slot. The 4-param scaling (per combat findings) lives here.

  col 137/138/139  bool  trailing flags (false)
```

## 3. gameCommandBasic.csv structure (120 columns)

```text
Even sparser; active columns:
  col 37  s32   base category (sample = 30000 -- a command-class base id)
  col 39  s32   0
  col 40  u8    1 (a count/level?)
  col 41  s32   1
  col 70  float  ? (timing)
  col 105/106 s16  0, 0 (param pair)
  col 119 s8    0 (trailing)

gameCommandBasic holds the BASIC per-command params: category base
(col 37 = 30000-band), small counts/levels (cols 40/41), and a
trailing param pair. Likely: command category, GCD/cast group,
basic level requirement.
```

## 4. Relationship to the engine (CommandBase + judge)

```text
Per the CommandBase finding:
  - command:getCommandData() reads command.csv
  - CommonJudge loads gameCommand + gameCommandBasic (calc data)
  - command level + the 5 judge categories use these tables

Per the combat findings:
  - The "4-param scaling" for command potency comes from the
    gameCommand.csv paired effect block (cols 84-115)
  - Command cast/recast timing from cols 54-67
  - Command category/level from gameCommandBasic

So the command trio provides:
  command.csv         -> WHAT command exists (id, name ref, type)
  gameCommand.csv     -> WHAT it does (effect pairs, scaling, targeting)
  gameCommandBasic.csv -> basic params (category, level, cost group)
```

## 5. Server-side requirements

```text
The command trio is the server's AUTHORITATIVE ACTION DEFINITION:

1. command.csv: master command list (id -> exists + type)
2. gameCommand.csv: per-command effect table
   - effect pairs (type, magnitude) in cols 84-115
   - cast/recast timing (cols 54-67)
   - targeting params
3. gameCommandBasic.csv: category + level + cost

ON RECEIVING a command (0x12d):
  - look up command id in command.csv (valid? type?)
  - validate via judge category (level from gameCommandBasic,
    targeting from gameCommand)
  - compute effect from gameCommand effect pairs + level-adjust
    (the same growth-curve as status, via compatibility.csv)
  - apply result, send action result (0x148/0x149)

This + status.csv + itemData.csv form the core SERVER CALCULATION
TABLES. All use the level-adjust growth model.
```

## 6. Confidence

```text
Confirmed:
  - 3 command tables: command (1662 rows), gameCommand (1611, 140 cols),
    gameCommandBasic (1611, 120 cols)
  - gameCommand has a paired (s32,float) effect block in cols 84-115
  - gameCommandBasic col 37 = category base (30000-band)
  - Command id ranges (12xxx system .. 30xxx+ generic)
  - These are CommandBase/CommonJudge's calc tables

Likely (High):
  - cols 84-115 paired block = command effect/scaling table (4-param)
  - cols 54-67 = cast/recast/timing
  - gameCommandBasic = category + level + cost group
  - -1 values = unused effect slots / sentinels

Speculative (exact column semantics need Lua reader cross-reference):
  - Precise effect-pair encoding (effect_type ids)
  - The cast vs recast vs GCD column split
  - command.csv's own column layout (not sampled here)
```

## 7. Cross-references

- `finding_commandbaseclass_action_model.md` -- CommandBase reads these
- `finding_judge_system_data_and_depiction_layer.md` -- CommonJudge loads them
- `finding_status_csv_column_structure.md` -- sibling calc table (status)
- `finding_combat_command_pipeline_and_4param_scaling.md` -- the 4-param
  scaling that the effect block (cols 84-115) feeds
- `finding_itemData_columns_decoded` (in QUICK_REFERENCE) -- itemData cols 43-68
- `docs/server/content_requirements/ffxivtool_import_plan.md`

## 8. Next test

```text
1. Cross-reference the gameCommand effect block with the combat
   potency-reading Lua (charabaseclass_battle / command scripts)
2. Decode command.csv's own columns
3. Decode compatibility.csv (the growth curves)
4. Map the effect-pair type ids (cols 84-115) to effect categories
5. Decode itemData remaining columns (beyond 43-68)
```

## Commit suggestion

```
docs(data): command CSV trio structure (command/gameCommand/gameCommandBasic) -- gameCommand effect block cols 84-115 (paired type/magnitude), gameCommandBasic category col 37; server action-definition tables
```
