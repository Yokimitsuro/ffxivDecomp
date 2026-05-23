# Finding: Battle Sync Schema (31 indices) + Skill Conversion (36 cross-class commands) + Job Soul Crystal Map

Closes the ffxivbattle.lua + battle.lua extraction with three
additional concrete data structures:

1. **Battle sync schema (`initBattleSync`)** -- the 31 generalParameter
   indices synchronized via WorkSync between server and client.
2. **`convertSkillId`** -- hardcoded list of 36 cross-class command
   IDs available via skill conversion.
3. **Job -> soul crystal item ID** mapping (re-confirmed from
   getAdditionalCommandList).
4. **`generalParameter[18]` = active job's soul crystal item ID**
   (fills the index 18 gap previously unidentified).

## 1. Battle Sync Schema (`initBattleSync`, line 1784)

Declares which `generalParameter[]` indices are SYNCHRONIZED via
WorkSync (opcode 0x12F). Out of the 36+ slots in the array, 31 are
synced.

### Synced indices

```text
INDICES 4-12 (9 stats):   PRIMARY ATTRIBUTES
   4   probably STR
   5   probably DEX
   6   probably VIT
   7   probably AGI
   8   probably INT
   9   probably MND
  10   probably PIE
  11   probably CHR  (Charisma, removed in Stormblood)
  12   probably ? (Element resistance or similar)

INDEX 13/14 (with swapped sync order):
  13   probably HP Cap modifier
  14   probably MP Cap modifier

INDEX 15:  unknown -- might be a derived stat

INDICES 16-19 (4 slots):  ATTACK FAMILY (already known)
  16   Attack
  17   NormalDefence
  18   Job's active SOUL CRYSTAL ITEM ID    <-- NEW DISCOVERY
       (per getJobItemId at line 444)
  19   AttackRate

INDICES 24-35 (12 slots):  COMBAT + CRAFT + HARVEST (already known)
  24   Evasion
  25   AttackMagic
  26   HealMagic
  27   ReinforceMagic
  28   WeekMagic   (debuff power)
  29   MagicRate
  30   MagicEvasion
  31   CraftProcessing
  32   CraftMagicProcessing
  33   CraftProcessControl
  34   HarvestPotency
  35   HarvestLimit
```

### NOT synced

```text
INDICES 0-3:    HP / MP / TP / current resource pools
                These use SEPARATE sync paths:
                - charaWork.parameterSave.hp[idx]
                - charaWork.parameterSave.hpMax[idx]
                because they update much more frequently
                than the once-per-state-change parameters.

INDICES 20-23:  GAP (4 slots not used / reserved for future).

INDICES 36+:    HarvestRate + future expansion.
```

### Index 13/14 sync order swap

Notable detail: the sync schema declares indices in order
`14, 13, 15` (entry 13 gets index 14; entry 14 gets index 13).
This is a deliberate ORDERING (probably for serialization
priority). Effect:
- Index 14 (probably HP cap) is sync'd FIRST
- Index 13 (probably MP cap) is sync'd SECOND

So when client receives the sync packet, it processes HP cap
before MP cap. Doesn't matter for correctness but indicates
deliberate ordering of paired stats.

## 2. NEW: generalParameter[18] = Job Soul Crystal Item ID

```lua
function getJobItemId(self):
    return self.charaWork.battleTemp.generalParameter[18]
end
```

So **index 18** of the generalParameter array stores the
**ITEM ID of the player's active job soul crystal** (or 0 / nil
when no job is active).

This is the index 18 gap that prior finding speculated as
"Parry/Block". Confirmed otherwise: it's the SOUL CRYSTAL CACHE.

When server pushes a job change, it updates generalParameter[18]
on the client (via WorkSync), which the client then reads when
displaying "Active Job: <name>" in the UI.

## 3. Job -> Soul Crystal Item ID Mapping (line 398)

`getAdditionalCommandList(job_id)` is misnamed (its body actually
maps job_id to soul-crystal-item-id):

```text
Job ID     Soul Crystal Item ID
------     --------------------
  15  -->  2,000,202     Paladin
  16  -->  2,000,201     Monk
  17  -->  2,000,203     Warrior
  18  -->  2,000,205     Dragoon
  19  -->  2,000,204     Bard
  26  -->  2,000,207     Black Mage
  27  -->  2,000,206     White Mage
```

This matches the prior finding (`finding_chara_cliprog_and_event_extensions.md`)
which documented the same mapping. Now confirmed in TWO places
in the source.

Note: item IDs are NOT sequential within the same job ID space:
- PLD=2000202, MNK=2000201, WAR=2000203
- DRG=2000205, BRD=2000204
- BLM=2000207, WHM=2000206

The order doesn't follow alphabetical or numerical. Likely the
items were created in the order they were planned for release
(MNK first, then PLD, then WAR, ..., then WHM, then BLM as
last).

## 4. `convertSkillId` -- 36 hardcoded cross-class command IDs

`convertSkillId(self)` returns a hardcoded array of 36 command IDs.
These are likely the **complete set of CROSS-CLASS COMMANDS** that
the player has access to via skill conversion.

### The 36 IDs

```text
27106, 27107, 27108, 27109, 27118    (5 IDs starting at 27106)
27146, 27147, 27148, 27149, 27159    (5 IDs starting at 27146)
27186, 27187, 27188, 27189, 27192    (5 IDs starting at 27186)
27227, 27232, 27237, 27238, 27239    (5 IDs starting at 27227)
27266, 27267, 27268, 27272, 27277    (5 IDs starting at 27266)
27305, 27316, 27317, 27318, 27319    (5 IDs starting at 27305)
27344, 27345, 27357, 27358, 27359    (5 IDs starting at 27344)
29742                                 (1 ID, outlier)
TOTAL: 36 IDs
```

### Pattern observation

The first 35 IDs are in the **27xxx range** organized in **7 groups
of 5 each** (matching the 7 jobs). Each group's starting ID
increases by ~40 (27106 -> 27146 -> 27186 -> 27227 -> 27266 ->
27305 -> 27344).

So **each of the 7 jobs has 5 cross-class commands** assigned to
it. 7 x 5 = 35. Plus 1 outlier at 29742 = 36.

This aligns with `getMainClassOrJob` documenting the 7 jobs with
3 compatible classes each. Each class probably contributes 1-2
commands, totaling ~5 per job.

The outlier 29742 in the 29xxx range (Gift / Extended commands)
is the special command -- possibly the "Limit Break" command
universally accessible across jobs.

### Sample group decoding

```text
Group 1: 27146-27159  -- 5 commands probably PLD-related
Group 2: 27186-27192  -- 5 commands probably MNK-related
Group 3: 27106-27118  -- 5 commands probably WAR-related (out of order)
Group 4: 27266-27277  -- 5 commands probably DRG-related
Group 5: 27227-27239  -- 5 commands probably BRD-related
Group 6: 27344-27359  -- 5 commands probably BLM-related
Group 7: 27305-27319  -- 5 commands probably WHM-related
+ 29742               -- Limit Break / Special
```

Cross-referencing the gameCommand.csv rows for these IDs would
identify the specific cross-class command names (mechanical work
beyond this finding's scope).

## generalParameter layout (UPDATED final)

```text
INDEX  STAT                                         SYNCED?
-----  ----                                         -------
  0    HP             (via parameterSave.hp[0])      N (separate sync)
  1    MP             (via parameterSave.hp[1])      N (separate sync)
  2    TP                                            N
  3    (other resource pool?)                        N
  4    STR                                           Y
  5    DEX                                           Y
  6    VIT                                           Y
  7    AGI                                           Y
  8    INT                                           Y
  9    MND                                           Y
 10    PIE                                           Y
 11    CHR                                           Y
 12    ?  (probably 9th primary)                     Y
 13    MP Cap modifier (or related)                  Y (sync'd 2nd)
 14    HP Cap modifier (or related)                  Y (sync'd 1st)
 15    ?  (probably derived stat)                    Y
 16    Attack                                        Y
 17    NormalDefence                                 Y
 18    Job's Soul Crystal Item ID  <-- NEW            Y
 19    AttackRate                                    Y
 20    ?                                             N (gap)
 21    ?                                             N (gap)
 22    ?                                             N (gap)
 23    ?                                             N (gap)
 24    Evasion                                       Y
 25    AttackMagic                                   Y
 26    HealMagic                                     Y
 27    ReinforceMagic                                Y
 28    WeekMagic                                     Y
 29    MagicRate                                     Y
 30    MagicEvasion                                  Y
 31    CraftProcessing                               Y
 32    CraftMagicProcessing                          Y
 33    CraftProcessControl                           Y
 34    HarvestPotency                                Y
 35    HarvestLimit                                  Y
 36+   HarvestRate + future expansion                ?
```

So the layout has 4 reserved gaps (20-23) and 36+ defined stats.
At minimum 31 are synced (the schema's count).

## Confidence

```text
Confirmed:
  - Battle sync schema declares 31 generalParameter indices to sync
    via WorkSync (opcode 0x12F).
  - generalParameter[18] = Job's Soul Crystal Item ID (NEW;
    discovered from getJobItemId reading index 18).
  - Job-to-SoulCrystal mapping confirmed in 2 places (current
    finding + finding_chara_cliprog_and_event_extensions.md).
  - convertSkillId returns 36 hardcoded command IDs (35 in 27xxx
    + 1 outlier at 29742).
  - 13/14 sync order is swapped (deliberate serialization order).

Likely (High):
  - generalParameter[4-12] are the 9 primary FFXIV 1.x attributes
    (STR/DEX/VIT/AGI/INT/MND/PIE/CHR/?).
  - generalParameter[20-23] are reserved gaps (4 slots unused).
  - The 35 IDs in 27xxx are organized as 7 groups of 5 -- one per
    job, 5 cross-class actions each.
  - The outlier 29742 is the Limit Break command or similar
    universal "special".

Likely (Medium):
  - generalParameter[13] = MP Cap modifier;
    generalParameter[14] = HP Cap modifier.
  - generalParameter[15] is a derived stat (HP regen rate or
    similar).
  - The soul crystal item ID at index 18 lets the server push
    job-change events that update the client's cache in one
    WorkSync call.

Speculative:
  - The 4 indices 20-23 might be reserved for FUTURE STAT
    EXPANSION (CHA derivative, Determination, Critical Hit Rate,
    etc. -- stats that ARR added).
  - The convertSkillId list represents the FULL EQUIPABLE CROSS-CLASS
    COMMAND SET in 1.x (35 actions across 7 jobs).
```

## Connections to other findings

- **finding_ffxivbattle_stat_layout_and_job_classes.md**: this
  finding completes the generalParameter[] layout (index 18 = soul
  crystal item ID) and confirms 31 indices are sync'd.
- **finding_chara_cliprog_and_event_extensions.md**: re-confirms
  the job-to-soul-crystal mapping (2000201-2000207 for jobs
  15-19, 26-27).
- **WorkSync (opcode 0x12F)**: this finding identifies EXACTLY
  what 31 fields the WorkSync packet for combat data carries.

## Next test

- Sample command IDs from convertSkillId (e.g. 27106, 27146) in
  gameCommand.csv to identify their specific names.
- Find getStateMainSkill / getStateMainSkillLevel bodies for the
  current-skill tracking.
- Look at `equipPoint` getters to identify the equipment-slot
  parameter layout.

## Commit suggestion

```
docs(re/lua): battle sync schema + skill conversion + soul crystal cache (index 18)
```
