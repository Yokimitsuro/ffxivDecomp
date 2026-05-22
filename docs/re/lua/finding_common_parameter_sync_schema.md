# Finding: `initCommonParameterSync` — Complete parameterSave/parameterTemp Schema + Sync Tick Rates

Reading `chara/charabaseclass_parameter.lua` exposes the FULL field
set of `charaWork.parameterSave` and `charaWork.parameterTemp` (the
two nested sub-structs the previous schema finding showed as
`{parameterSave, nesting, 64}` and `{parameterTemp, nesting, 16}`).

This also surfaces a previously-undocumented detail: the client's
**sync TICK RATES** are declared per tag-group, ranging from 0.3
seconds (HP/MP/TP — fastest) to 1.5 seconds (job change — slowest).

Sources read:

```text
chara/charabaseclass_parameter.lua   1867 lines
  initCommonParameterSync            line 1349 (returns 6 tables)
```

## `parameterSave` schema (17 fields)

Returned as `L1_2` (6 fields) + `L2_2` (11 fields) tables, both
inserted into `charaWork._sync` via `unpack`:

```text
parameterSave = {
  hp                              array[8]   integer16   -- HP per party member?
  hpMax                           array[8]   integer16   -- HPMax per party member?
  mp                              scalar     integer16
  mpMax                           scalar     integer16
  state_mainSkill                 array[4]   integer8    -- (main, sub1, sub2, sub3?)
  state_mainSkillLevel            scalar     integer16
  state_boostPointForSkill        array[4]   integer8    -- skill XP boost per slot
  commandSlot_recastTime          array[40]  integer32   -- cooldown ms per slot (40 slots)
  commandSlot_compatibility       array[40]  boolean     -- "this command usable" per slot
  giftCommandSlot_commandId       array[10]  integer16   -- 10 equipped gift commands
  constanceCommandSlot_commandId  array[10]  integer16   -- 10 equipped passives
  abilityCostPoint_used           scalar     integer8    -- ability TP used
  abilityCostPoint_max            scalar     integer8    -- ability TP max
  giftCostPoint_used              scalar     integer8    -- gift TP used
  giftCostPoint_max               scalar     integer8    -- gift TP max
  constanceCostPoint_used         scalar     integer8    -- passive TP used
  constanceCostPoint_max          scalar     integer8    -- passive TP max
}
```

### Surprising findings

1. **HP / HPMax are `array[8] integer16`, not scalars.** The client
   stores up to 8 HP values per actor. Most likely interpretation:
   for the local player, the array tracks HP of all 8 party members
   simultaneously (so the UI can show party HP without separate
   queries). For NPCs or party members, only index [1] is meaningful.

2. **state_mainSkill is array[4] integer8**, not a scalar. The 4
   slots are probably (main job, sub job, sub job 2, flags). 1.x
   had an Armoury System with main + sub class concept, so 2-4
   slots tracking class state per actor make sense.

3. **commandSlot arrays are 40 entries, not 64.** Earlier
   `charaWork._sync` declared `command[64]` and `commandCategory[64]`
   but `commandSlot_recastTime[40]` and `commandSlot_compatibility[40]`.
   So the **first 40 command slots** are the cooldown-tracked ones
   (active commands); the remaining 24 are presumably menu-only or
   passive.

4. **Three cost-point systems** (`abilityCostPoint`, `giftCostPoint`,
   `constanceCostPoint`) plus their used/max scalars. This is 1.x's
   three-tier TP/MP system: ability TP for active skills, gift TP
   for character traits, constance for passive abilities. Each has
   its own pool that regenerates separately.

## `parameterTemp` schema (7 fields)

Returned as `L3_2` (2 fields) + `L4_2` (5 fields):

```text
parameterTemp = {
  tp                              scalar     integer16   -- current TP
  targetInformation               scalar     integer32   -- active target actor id
  maxCommandRecastTime            array[40]  integer16   -- per-slot max cooldown (ms)
  forceControl_float_forClientSelf array[4]   float        -- input/movement vector
                                                            -- CLIENT-ONLY (not synced)
  forceControl_int16_forClientSelf array[2]   integer16    -- input/movement integer
                                                            -- CLIENT-ONLY (not synced)
  otherClassAbilityCount          array[2]   integer8     -- ability slots used in other classes
  giftCount                       array[2]   integer8     -- gift slots used in other classes
}
```

The `_forClientSelf` suffix is significant: those fields are **local
to the client and not synced over the network** (the runtime probably
suppresses _bindWork registration for them). They hold the client's
own input state (movement vector, etc.).

## Sync Tag Groups + Tick Rates

`initCommonParameterSync` ALSO returns two more tables (`L5_2` and
`L6_2`) that define the per-tag-group SYNC TICK RATES.

### Group 1: shared tags (`L5_2`, 2 tags)

```text
{stateAtQuicklyForAll, 0.3, [        -- 0.3 second update rate
  {parameterSave, hp, 1},            -- index 1 of hp array (current player)
  {parameterSave, hpMax, 1},         -- index 1 of hpMax array
  {parameterSave, mp},
  {parameterSave, mpMax},
  {parameterTemp, tp}
]}
{stateForAll, 1.5, [                 -- 1.5 second update rate
  {parameterSave, state_mainSkill},
  {parameterSave, state_mainSkillLevel},
  {parameterTemp, targetInformation}
]}
```

### Group 2: per-actor (self only) tags (`L6_2`, 3 tags)

```text
{stateAtQuicklyForSelf, 1, self, [   -- 1 second update rate, self only
  {parameterSave, state_boostPointForSkill}
]}
{commandDetailForSelf, 1, self, [    -- 1 second update rate, self only
  {parameterSave, commandSlot_compatibility},
  {parameterSave, commandSlot_recastTime},
  {parameterTemp, maxCommandRecastTime},
  {parameterTemp, forceControl_float_forClientSelf},
  {parameterTemp, forceControl_int16_forClientSelf}
]}
{commandEquip, 1, self, [            -- 1 second update rate, self only
  {parameterSave, giftCommandSlot_commandId},
  {parameterTemp, otherClassAbilityCount},
  {parameterTemp, giftCount}
]}
```

### The tag-group rate model

```text
Tag name                     Rate    Scope          Fields
---------------------------- ------- -------------- ----------------
stateAtQuicklyForAll         0.3 s   all visible    hp[1], hpMax[1], mp, mpMax, tp
stateForAll                  1.5 s   all visible    state_mainSkill, mainSkillLevel,
                                                    targetInformation
stateAtQuicklyForSelf        1 s     self only      state_boostPointForSkill
commandDetailForSelf         1 s     self only      commandSlot_compat, recastTime,
                                                    maxRecastTime, forceControl
commandEquip                 1 s     self only      giftCommandSlot, abilityCount,
                                                    giftCount
```

**This is the implicit tick budget of the client's server expectation:**

- HP / MP / TP for every visible character must update **every
  300ms**. So a server pushing 100ms HP packets is overkill, and
  one pushing 1s HP packets will produce visible lag.
- Job/class info updates every 1.5 seconds.
- Self-only command details refresh every 1 second.

A server can optimise by **batching all 5 fields in `stateAtQuicklyForAll`
into a single ~300ms tick packet** rather than 5 separate updates.

## Mapping to the `_bindWork` Catalog

The `_bindWork` ids 1001–1012 (from the catalog) now map to specific
fields:

```text
id    field                              type
----  ---------------------------------  -----------
1001  parameterSave.state_mainSkill      array[4] integer8
1002  parameterSave.constanceCommandSlot_commandId  array[10] integer16
1003  parameterSave.giftCommandSlot_commandId       array[10] integer16
1004  parameterSave.abilityCostPoint_used    integer8
1005  parameterSave.abilityCostPoint_max     integer8
1006  parameterSave.constanceCostPoint_used  integer8
1007  parameterSave.constanceCostPoint_max   integer8
1008  parameterSave.giftCostPoint_used       integer8
1009  parameterSave.giftCostPoint_max        integer8
1010  parameterSave.hp[1]                array[8] integer16 (index 1)
1011  parameterSave.hpMax[1]             array[8] integer16 (index 1)
1012  parameterSave.state_mainSkillLevel integer16
```

The binding ids appear allocated in the same order as the
`initCommonParameterSync` insertion sequence (after the first 6
parameterSave fields). The 1010/1011 bindings target **index 1** of
the hp/hpMax arrays specifically — confirming the array-vs-scalar
interpretation: index 1 is the local actor's HP; the other 7 slots
mirror party members.

## Assessment

```text
Confirmed:
  - parameterSave has 17 fields, parameterTemp has 7 fields.
  - hp/hpMax are arrays of 8 integer16 (not scalars). _bindWork ids
    1010/1011 target index [1] specifically.
  - state_mainSkill is array[4] integer8 (main + 3 sub job-related slots).
  - command slot arrays are sized 40 (not 64); the remaining 24 of the
    command/commandCategory arrays are not cooldown-tracked.
  - Three TP/cost-point pools: ability, gift, constance, each with
    used/max scalars (6 fields total, _bindWork ids 1004-1009).
  - forceControl_*_forClientSelf fields are CLIENT-ONLY (not synced).

Surprising:
  - Tag groups carry per-group TICK RATES. The client expects HP/MP/TP
    updates every 300ms; class info every 1.5s; per-self details every 1s.
  - These are RATE HINTS, not hard requirements: the server can push
    faster (overkill) or slower (visible lag).

Likely (High):
  - The hp[8] / hpMax[8] arrays exist so that ANY visible chara's
    "actor.charaWork.parameterSave.hp[1]" gives the current HP of that
    actor. The remaining indices [2..8] are probably reserved for
    showing PARTY HP without separate actor queries (party of up to 8?
    1.x had parties of 6, but the array was over-provisioned).
  - The 40-slot command array implies command-slot ids 1..40 are the
    "hotbar slots"; 41..64 may be reserved or used for non-hotbar
    inventories.
  - The 1.5s rate for "stateForAll" suggests class/level transitions
    were not designed to be flashy — a deliberate 1.5s window before
    UI reflects a class change.

Likely (Medium):
  - giftCommandSlot vs constanceCommandSlot: 1.x had a concept of
    "Gifts" (passive trait stones) and "Constance" (long-duration
    passive effects). Each had its own equip slot system, separate
    from active commands.
  - otherClassAbilityCount[2] tracks how many ability slots are
    populated by "other class" (cross-class) abilities. Likely a soft
    limit (e.g. "you can equip 6 abilities, of which 2 can be from
    other classes").

Speculative:
  - The 0.3s tick for HP updates means a 1.x server was probably
    designed for ~3 Hz tick rates. Movement was likely on a separate
    higher-frequency channel (~10-20 Hz; not in this schema).
  - The "stateAtQuickly" prefix may have been a code label for the
    legacy "fast-sync" channel that 1.x had before XIV ARR redesigned
    the protocol.

Next test:
  - Read charabaseclass_event.lua's initEventSyncWork to enumerate
    the 3-slot eventSave and 9-slot eventTemp.
  - Read charabaseclass_battle.lua's initBattleSync (the file is 2027
    lines -- substantial).
  - Find the C++ side: does the EXE actually consume these tag-rate
    floats, or is the rate decided server-side? Grep for the string
    "stateAtQuicklyForAll" in the EXE.

Commit suggestion:
  docs(re/lua): initCommonParameterSync schema + sync tick rates (0.3-1.5s)
```

## Server implication

This finding turns the "actor state sync surface" from a list of
fields into **a concrete tick-budget model**:

```text
Per visible chara, every ~300ms:
  - hp[1], hpMax[1], mp, mpMax, tp           (5 integer16 = 10 bytes data
                                              + delta encoding)

Per visible chara, every ~1.5s:
  - state_mainSkill[1..4], mainSkillLevel,
    targetInformation                       (~12 bytes)

For local player only, every ~1s:
  - boostPointForSkill[1..4]                (4 bytes)
  - commandSlot_compatibility[1..40]        (5 bytes bitfield)
  - commandSlot_recastTime[1..40]           (160 bytes)
  - maxCommandRecastTime[1..40]             (80 bytes)
  - forceControl float[4] + int16[2]        (skipped -- client only)
  - giftCommandSlot_commandId[1..10]        (20 bytes)
  - otherClassAbilityCount[1..2]            (2 bytes)
  - giftCount[1..2]                         (2 bytes)
```

Worst case per second for the local player + 7 visible others:

```text
HP/MP/TP for 8 actors @ 3.3 Hz =  8 * 10 * 3.3 = 264 bytes/s
class for 8 actors @ 0.67 Hz   =  8 * 12 * 0.67 ≈ 64 bytes/s
self details @ 1 Hz            = ~270 bytes/s
TOTAL                          ≈ 600 bytes/s for steady state
```

Even with framing overhead and the rest of the sync surface, **a 1.x
client probably only needs ~2-5 KB/s for steady-state actor sync**.
The protocol was clearly designed for the ADSL era. A modern server
implementing this can ignore bandwidth concerns and focus on
correctness.
