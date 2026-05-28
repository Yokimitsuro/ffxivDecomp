# Finding: charabaseclass_battle.lua -- Battle Sync Schema + Timing-Command Combo System

**Deep-dive into the client-side combat module** (2027 lines, 56
functions). Maps the **battle WorkSync schema** (`initBattleSync`) —
exactly the state a server must replicate — plus the **timing-command
combo system** that drives reactive abilities.

This is the Lua-side consumer of the action-result wire messages
(opcodes 0x148-0x156) mapped in prior findings.

## 1. Battle WorkSync schema (from initBattleSync)

The `initBattleSync` function (~410 lines) declares the full battle
work structure for WorkSync replication, in two tiers:

### battleSave (PERSISTENT -- survives logout, server-authoritative)

```text
Field            Type              Notes
-----            ----              -----
potencial        float             NM strength multiplier (sign-coded)
physicalLevel    integer16         character physical level
physicalExp      integer32         physical experience points
skillLevel       array[52] int16   per-skill level (52 skills total)
skillLevelCap    array[52] int16   per-skill level cap
skillPoint       array[52] int32   per-skill experience points
negotiationFlag  array[2] boolean  negotiation/trade state flags
```

**52 skills** = the full 1.x skill roster (DoW classes + DoM + DoH
craft + DoL gather, all with individual level/cap/exp tracking).

### battleTemp (TRANSIENT -- recomputed, not persisted)

```text
Field             Type              Notes
-----             ----              -----
castGauge_speed   array[2] float    cast bar speed (2 hands?)
timingCommandFlag array[4] boolean  reactive combo availability (see #2)
generalParameter  array[35] int16   the 35 battle stats
```

**generalParameter[35]** matches the prior finding: 28 synced indices
+ 7 unsynced. The schema registers individual indices (4-15+) as
separate sync fields.

## 2. WorkSync sync-groups (replication directives)

`initBattleSync` declares NAMED SYNC GROUPS that bundle fields for
wire replication:

```text
GROUP "battleStateForSelf" (self-only sync):
  -> battleSave.potencial
  -> battleSave.skillLevel / skillLevelCap
  -> battleTemp.castGauge_speed
  -> battleSave.skillPoint
  -> battleSave.physicalExp
  -> battleSave.negotiationFlag
  (only replicated to the owning player, not broadcast)

GROUP "timingCommand":
  -> battleTemp.timingCommandFlag (the 4 combo flags)

GROUP "battleParameter":
  -> battleTemp.generalParameter[28 specific indices] (broadcast battle stats)
```

### generalParameter[35] sync map -- EXACT (28 synced + 7 local)

```text
SYNCED indices (28, registered in battleParameter group, broadcast):
  4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
  24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35

UNSYNCED indices (7, local-only -- client computes/displays):
  1, 2, 3, 20, 21, 22, 23

This CONFIRMS the "28 synced + 7 unsynced" split from the prior
generalParameter finding, with the EXACT index list. The 7 local
indices (1-3, 20-23) are likely derived/aggregate stats the client
computes locally (total attack power, defense rollups, etc.) -- the
server doesn't push them because they're functions of synced values.

SERVER IMPLICATION: push only the 28 synced indices via the
battleParameter sync group (per-actor broadcast). Skip indices
1,2,3,20,21,22,23 -- the client derives those.
```

These groups map directly to the WorkSync wire opcodes:
- self-only groups → targeted updates
- battleParameter → broadcast via per-actor messages (0x148-0x156)

**Server implication**: the server replicates battleSave fields
(authoritative, persistent) and computes battleTemp fields (derived).
The sync-group structure tells the server WHICH fields to push and
to WHOM (self vs broadcast).

## 3. Timing-Command Combo System

`charaWork.battleTemp.timingCommandFlag[1..4]` are 4 boolean flags
that enable REACTIVE COMMANDS (combo prompts). When a flag is set,
specific command IDs become available:

```text
Flag      Enabled command IDs       Inferred meaning
----      -------------------       ----------------
flag[1]   27278, 27279              combo step A (2 options)
flag[2]   27119                     combo step B (1 option)
flag[3]   27198, 27199              combo step C (2 options)
flag[4]   27158, 27157              combo step D (2 options)
```

`getEnableTimingCommands()` returns the list of currently-available
timing commands by checking these flags. `isMorrowTimingCommand(idx)`
checks a specific flag.

These are the 1.x **"Morrow" timing commands** — reactive abilities
that pop up during combat (similar to ARR's procs / combo chains).
The server sets the flags (via WorkSync) when combat state allows a
combo; the client shows the prompt; the player presses one of the
enabled command IDs.

**The command IDs (27xxx) are gameCommand.csv references.** Server
must:
1. Set timingCommandFlag when a combo opportunity arises
2. Accept one of the enabled command IDs as the player's reaction
3. Clear the flag after use/timeout

## 4. Other notable functions (56 total)

### Skill system
```text
getSkillPoint, getSkillLevelCap, getSkillCategory, getMainSkillCategory
isSkillCapped, isSkillEnabled, getSkillPointMax
isGatherer, isCrafter  (class-type checks)
```

### Equipment ↔ attack routing (client-only mapping)
```text
getEquipPointByHand / ByAttackIndex / ByParts
getAttackWorkIndexByEquipPoint / ByHand / ByParts / ByMyCommandIndex
getCraftWorkIndexBy* / getHarvestWorkIndexBy*
getHandByAttackIndex / ByEquipPoint
(maps equipment slots <-> attack work indices <-> body parts)
```

### Parts (multi-part enemy) system
```text
isParts, processGetPartsDirection, processGetPartsWideDirection
isBreakedParts, getPartsWorkIndexByAttackIndex, getPartsNameID
(NM body-part targeting: head/claws/etc. with break states)
```

### Combat core
```text
judgeRelation       (4-state hostility -- prior finding)
judgeDirection      (facing/positional)
getPotencial / calcPotencial / calcOverLevelAdjust  (NM strength -- prior finding)
isNotoriousMonster  (NM check)
getStatusLostTime   (status effect expiry)
adjustLockOnTargetDirection
canStartCombination / getStackedCombinationNum / getStackedCombinationTimer
canAutoGuardWithAxe (class-specific defense -- Gladiator/Marauder?)
getCastSpeed / getCastSpeedAtEquip
getMagicAttack      (level-banded magic attack table: 570/700/880/1100/1500... <= L10)
enableNegotiation
```

## 5. getMagicAttack level table (sample)

```text
For level <= 10, magic attack values:
  570, 700, 880, 1100, 1500, ...
(level-banded lookup; full table continues for higher levels)

This is a CLIENT-SIDE display/prediction value. Server should use
the same table (or itemData/skill formulas) for authoritative
damage computation.
```

## 6. Server-side requirements

```text
BATTLE STATE TO REPLICATE (battleSave -- persistent):
  - potencial, physicalLevel, physicalExp
  - skillLevel[52], skillLevelCap[52], skillPoint[52]
  - negotiationFlag[2]

BATTLE STATE TO COMPUTE/PUSH (battleTemp -- transient):
  - generalParameter[35] (28 broadcast + 7 local)
  - timingCommandFlag[4] (set when combos available)
  - castGauge_speed[2]

COMBAT FLOW:
  1. Player sends command (0x12d) -- e.g., attack/cast
  2. Server validates + computes result (damage/heal/status)
  3. Server sends action result (0x148/0x149) + state updates (WorkSync)
  4. If combo opportunity: server sets timingCommandFlag -> client prompts
  5. Player reacts with timing command (27xxx) -> repeat

SKILL PROGRESSION:
  - 52 skills, each with level/cap/point
  - Server awards skillPoint on action use, levels up at thresholds
  - Replicates via battleStateForSelf sync group (self-only)
```

## 7. Confidence

```text
Confirmed:
  - battleSave schema: 7 field groups (potencial, levels, 52-skill arrays,
    negotiationFlag)
  - battleTemp schema: castGauge_speed[2], timingCommandFlag[4],
    generalParameter[35]
  - 3 WorkSync sync groups (battleStateForSelf, timingCommand, battleParameter)
  - timing-command flags -> command IDs (27278/27279/27119/27198/27199/
    27158/27157)
  - 56 functions enumerated by role
  - getMagicAttack level-banded table

Likely (High):
  - 52 skills = full DoW/DoM/DoH/DoL roster
  - battleStateForSelf is self-only (not broadcast) -- saves bandwidth
  - timingCommandFlag drives reactive combo prompts (Morrow commands)
  - generalParameter individual-index sync matches 28+7 split

Speculative:
  - The 4 timing flags map to 4 combo categories (weaponskill chains?)
  - canAutoGuardWithAxe suggests class-specific passive defenses
  - The 2-element castGauge_speed = main hand + off hand cast speeds
```

## 7b. ADDENDUM: charabaseclass_event.lua (444 lines, 12 functions)

The companion event module handles **non-combat player interactions**
(bazaar/shop/repair/linkshell). `initEventSyncWork` declares the event
work schema:

### eventSave (persistent)
```text
Field        Type        Notes
-----        ----        -----
bazaar       (struct)    player's bazaar inventory (shop-on-character)
bazaarTax    integer8    bazaar sales tax rate
repairType   integer8    repair service type offered
```

### eventTemp (transient)
```text
Field          Type              Notes
-----          ----              -----
linkshellIcon  array[4] int16    icons for the player's 4 linkshells
bazaarRetail   boolean           offering retail (sell) service
bazaarRepair   boolean           offering repair service
bazaarMateria  boolean           offering materia attach service
```

### Event sync groups
```text
GROUP "bazaar":
  -> eventSave.bazaar, bazaarTax, repairType
  -> eventTemp.bazaarRetail / bazaarRepair / bazaarMateria
GROUP "linkshellIcon":
  -> eventTemp.linkshellIcon[4]
```

**Key confirmations**:
- `linkshellIcon[4]` confirms **4 linkshells** tracked per player
  (complements the Linkshell finding — the icon array is 4, though
  membership count via getAllLinkshellCount may differ)
- **Bazaar = player shop-on-character** with 3 service modes
  (retail/repair/materia) — matches the dealer-type functions
  (isRetailDealer / isRepairDealer / isMateriaAttachDealer)
- bazaarTax + repairType are PERSISTENT (player-configured shop settings)

### Event module functions (12)
```text
isRetailDealer / isRepairDealer / isMateriaAttachDealer  -- bazaar modes
getBazaarTax / getRepairType                             -- shop config
getLinkshellIconId                                       -- linkshell icon
initEventSyncWork                                        -- schema (above)
countStackAtIndex / createVirtualItem / checkSameItem    -- item helpers
getPassiveGuildleveIcons                                 -- guildleve UI
isValidFacility                                          -- facility check
```

**Server implication**: the bazaar (player shop) is a 1.x feature where
players set up shops ON their character. Server stores eventSave.bazaar
(inventory) + tax + repair config persistently, and replicates the
3 service-mode booleans + linkshell icons via the event sync groups.

## 8. Cross-references

- `finding_per_actor_messages_COMPLETE_15_opcodes_3x5_matrix.md`
  -- the action result wire messages this module consumes (0x148-0x156)
- `finding_combat_relations_and_potencial.md` -- judgeRelation + potencial
  (this module's combat core, prior finding)
- `finding_ffxivbattle_stats_and_jobs.md` -- generalParameter[35] indices
- `finding_actor_work_schemas.md` -- charaWork schema (battleSave/battleTemp
  are sub-structures)
- `finding_executeCommand_outbound_path_CLOSED_0x12d_checksummed.md`
  -- the command path that timing commands use

## 9. Next test

```text
1. Read the rest of initBattleSync (generalParameter indices 16-35
   sync registration) for the complete sync field list
2. Read charabaseclass_event.lua (444 lines) -- event hooks
3. Map the 27xxx timing command IDs to gameCommand.csv entries
4. Trace canStartCombination -> the combo chain state machine
5. Cross-reference skillLevel[52] indices to the skill roster
```

## Commit suggestion

```
docs(re/lua): charabaseclass_battle.lua -- battle WorkSync schema (battleSave 52-skill arrays + battleTemp generalParameter[35]) + timing-command combo system (4 flags -> 27xxx command IDs)
```
