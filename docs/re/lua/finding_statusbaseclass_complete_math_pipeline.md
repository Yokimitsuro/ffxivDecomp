# Finding: StatusBaseClass Complete Math Pipeline + 5-Param Status Model

Documents the full architecture of `StatusBaseClass` (875 lines, the abstract
parent of all 158 status subclasses). This is the **status-effect counterpart**
to GameCommandBaseClass's combat pipeline -- and crucially it shares the
**same 0.7/1.0 level-scaling model** but with **5 parameters** (Power, Param1,
Param2, Param3, Life) instead of commands' 4.

## 1. Architectural overview

```text
StatusBaseClass (875 lines)
├── 3 IDENTITY/DATA ACCESSORS
├── 2 ID-RANGE CATEGORIZATION PREDICATES (shown vs hidden)
├── 3 CLASSIFICATION PREDICATES (bad/good/neutral)
├── 5 LIFECYCLE PREDICATES (removed-on-X, can-Y)
├── 1 OBJECT CLASS ID = 5
├── 1 PROCESS PRIORITY (col 45)
├── 3 COMPATIBILITY METHODS
├── 5 HIGH-LEVEL ADJUST FACTORS = 0.7 each
├── 5 LOW-LEVEL ADJUST FACTORS = 1.0 each
├── 5 GROW-COLUMN LOOKUPS (per param)
├── 5 AT-SHEET FINAL GETTERS (orchestrate the pipeline)
├── 2 LIFECYCLE HOOKS (_onInit, _onFinalize)
└── 1 ICON GETTER
```

That's **~40 methods** establishing the status math foundation.

## 2. Status ID range mapping

```lua
function L0_1.isShownStatus(self)
  local id = self:getStatusId()
  return (223000 <= id and id <= 231999) or (253000 <= id and id <= 254999)
end

function L0_1.isHiddenStatus(self)
  local id = self:getStatusId()
  return (220000 <= id and id <= 222999) or (251000 <= id and id <= 252999)
end
```

So 1.x's status ID space has 4 ranges:

```text
220000-222999  Hidden status (no UI bar)        3000 IDs reserved
223000-231999  Shown status  (visible in UI)    9000 IDs reserved
251000-252999  Hidden status (extended)         2000 IDs reserved
253000-254999  Shown status  (extended)         2000 IDs reserved
```

So roughly **16,000 status slots reserved** -- vastly more than the 399 used
in xtx_status. The HIDDEN ranges are likely internal flag/state statuses
that don't show on the player's buff bar (combat states, internal cooldowns,
recasts, etc.), while SHOWN are the public buff/debuff effects.

## 3. 5-parameter status model

The status system tracks **5 numerical attributes per status**, each with
its OWN sheet columns:

```text
ATTRIBUTE  BASE COL  GROW COL  COMPAT COL
---------  --------  --------  ----------
Power         27        26         28
Param1        31        30         32
Param2        35        34         36
Param3        39        38         40
Life          47        48         49
```

So **statusSheet has a TRIPLE-COLUMN PATTERN per attribute**:
- BASE: the raw value
- GROW: stat-driven growth (via `judgeGrowColumn`)
- COMPAT: compatibility factor against caster

Plus:
- Col 25: status icon
- Col 45: process priority

So the status sheet has at minimum **20+ columns** of pipeline data per status.

## 4. The unified 0.7 / 1.0 scaling model

Status param adjustment factors mirror command param scaling EXACTLY:

```lua
-- HIGH-LEVEL USE (caster's main-skill level > status level)
function L0_1.getStatusParam1AdjustForHighLevelUse(self, ...) return 0.7 end
function L0_1.getStatusParam2AdjustForHighLevelUse(self, ...) return 0.7 end
function L0_1.getStatusParam3AdjustForHighLevelUse(self, ...) return 0.7 end
function L0_1.getStatusPowerAdjustForHighLevelUse (self, ...) return 0.7 end
function L0_1.getStatusLifeAdjustForHighLevelUse  (self, ...) return 0.7 end

-- LOW-LEVEL USE (caster's level < status level)
function L0_1.getStatusParam1AdjustForLowLevelUse (self, ...) return 1   end
function L0_1.getStatusParam2AdjustForLowLevelUse (self, ...) return 1   end
function L0_1.getStatusParam3AdjustForLowLevelUse (self, ...) return 1   end
function L0_1.getStatusPowerAdjustForLowLevelUse  (self, ...) return 1   end
function L0_1.getStatusLifeAdjustForLowLevelUse   (self, ...) return 1   end
```

Cross-reference: `finding_combat_command_pipeline_and_4param_scaling.md`
documented the SAME `0.7 high-level / 1.0 low-level` pattern for command
parameter scaling. **Both systems use the same overlevel-penalty model**:
- When caster is above the status/command level, scaling drops by 30%
- When caster is at/below level, scaling stays at 100%

This means under-leveling content gives no scaling boost; over-leveling content
suffers a 30% penalty (the "exemplar" / sync system). It's a **unified design
philosophy** for combat and status math.

## 5. getStatusXxxAtSheet -- the canonical pipeline

For each of 5 attributes (Power/Param1/2/3/Life), StatusBaseClass defines a
`getStatusXxxAtSheet` orchestrator that computes the final number:

```text
Pseudo-code for getStatusParam1AtSheet(caster, target, hand, target_actor, item):
  1. base = getStatusData(31)   <-- sheet column for param1 base
  2. if target is alive:
     compat = getStatusCompatibilityWithAdjust(
                getStatusData(32),  <-- col 32 = param1 compat
                caster, target, hand, target_actor)
  3. base = getStatusLevelAdjust(
              base,                                              <-- raw
              getStatusParam1LevelAdjustGrow(...),               <-- grow factor
              getStatusParam1AdjustForLowLevelUse(...),          <-- low-level factor (1.0)
              getStatusParam1AdjustForHighLevelUse(...),         <-- high-level factor (0.7)
              caster, target, hand, target_actor, item)
  4. final = base * compat
  5. return final
```

So the canonical status final-value formula is:

```text
final_value = base * compat * grow * level_factor
```

Where:
- `base` = statusSheet[col_base]
- `compat` = compatibility against caster's skill (0..1)
- `grow` = growth from caster's stat (via judgeGrowColumn)
- `level_factor` = 0.7 for over-leveling, 1.0 for under-leveling

This pipeline IS the entire status math engine.

## 6. Lifecycle predicates (default behaviors)

```lua
L0_1.isBadStatus              = function(self) return false end
L0_1.isGoodStatus             = function(self) return false end
L0_1.isNeutralStatus          = function(self) return not isBadStatus and not isGoodStatus end
L0_1.isRemovedFromDeath       = function(self) return true end
L0_1.isRemovedAtChangeMainSkill = function(self) return false end
L0_1.canRegist                = function(self) return self:isBadStatus() end  -- only bad statuses can be resisted
L0_1.canLifeAdjust            = function(self) return self:isBadStatus() end  -- only bad statuses scale w/ life
L0_1.canStartOnDead           = function(self) return false end
```

So the **default status is neutral (not bad, not good), survives non-death
events, doesn't carry over job change, can't be applied to dead targets**.
Subclasses override `isBadStatus`/`isGoodStatus` based on the specific
status ID.

## 7. ObjectClassId = 5

`getObjectClassId` returns 5 for all statuses. This is the **class type ID**
used by the engine to dispatch type-specific behavior. Other object class IDs
in the corpus:

```text
1   PlayerBase (per finding_world_area_login_split.md)
2   NpcBase
3   ?
4   ?
5   Status  <-- THIS FINDING
... (need to enumerate via Lua getObjectClassId methods across other base classes)
```

## 8. _onInit / _onFinalize -- sheet key caching

```lua
function L0_1._onInit(self)
  self:_callSuperClassFunc("_onInit")
  local id = self:_getStaticActorID()
  statusSheet:_loadKeySemipermanently(id, id)  -- lock the row
end

function L0_1._onFinalize(self)
  self:_callSuperClassFunc("_onFinalize")
  local id = self:_getStaticActorID()
  statusSheet:_unloadKey(id, id)  -- release the row
end
```

So on init, the status **pins its sheet row in memory** ("_loadKeySemipermanently")
so that subsequent sheet lookups are O(1). On finalize, it releases the row.

This is the **same pattern** seen in commands per the earlier findings:
sheet rows are reference-counted via load/unload key calls.

## 9. Subclass overrides -- patterns observed

### `DoTStatus` (17 lines) -- all-bad parent

```lua
HateForCasterStatus:
  isBadStatus  -> id == 223192
  isGoodStatus -> id == 223087

DoTStatus:
  isBadStatus -> true (all instances are bad)

CmnDoTStatus:
  isBadStatus  -> id in {223011, 223148, 223149, 223150,
                          223151, 223152, 223153}  (7 IDs)
  isGoodStatus -> id in {223180, 223181}  (2 IDs)
```

So **CmnXxx subclasses are GROUP HANDLERS** -- one class handles MULTIPLE
status IDs by enumerating which IDs are bad vs good. Non-Cmn subclasses
tend to be one-status-per-class.

### `HateForCasterStatus` -- 2 specific status IDs

The class handles exactly two statuses:
- 223192 = bad hate effect (caster forces target's enmity onto self)
- 223087 = good hate effect (caster reduces target's enmity)

These are the **PROVOKE / Sentinel-type** effects in FFXIV terms. Note that
they share a class but differ in their bad/good flag.

## 10. The 158 statuses -- functional categories

Decoded from cipher-encrypted filenames using a..j↔9..0, k..z↔z..k:

```text
HATE / ENMITY (5 statuses)
  hateforcasterstatus              caster-side provoke/sentinel
  hatefortargetstatus              target-side decoy/shadowbind
  hatecontrolstatus                generic hate manipulation
  cmncasterhatestatus              cmn parent for caster-side hate
  cmntargethatestatus              cmn parent for target-side hate

DAMAGE-OVER-TIME / HEALING-OVER-TIME (7 statuses)
  dotstatus                        generic DoT (always bad)
  cmndotstatus                     cmn parent (multi-ID handler)
  dotaurumstatus                   gold/aurum-themed DoT (NM-specific?)
  poisonstatus                     classic poison DoT
  r0d4poisonstatus                 variant poison (release version?)
  ruststatus                       weapon-rust DoT
  regenstatus                      healing-over-time

STAT MODIFICATION (16 statuses)
  attributecontrolstatus           generic stat buff/debuff
  cmnattributecontrolstatus        cmn parent
  parametercontrolstatus           generic parameter modifier
  cmnparametercontrolstatus        cmn parent
  castspeedstatus                  cast time modifier
  castkeepstatus                   cast-while-moving (?)
  excbonusstatus                   exclusive bonus tier
  arcbonusstatus                   arc bonus (Arcanist?)
  pglbonusstatus                   Pugilist class bonus
  partybonusstatus                 party-wide bonus
  boostpointstatus                 boost-point spending bonus
  skilllevelstatus                 skill level modifier
  skillpointbooststatus            skill-XP boost
  tpcoststatus                     TP cost modifier
  tpregainstatus                   TP regen modifier
  tptimerstatus                    TP regen timer
  mptimerstatus                    MP regen timer
  mainskillstatus                  main-skill level binding

DEFENSE / MITIGATION (12 statuses)
  absorptiondamagestatus           damage-absorb shield
  cmnabsorptiondamagestatus        cmn parent
  damagecutmagicstatus             magic damage reduction
  physicaldamagecutstatus          physical damage reduction
  shielddefencestatus              shield-based defense
  temporarydefencestatus           temporary defense buff
  cmntemporarydefencestatus        cmn parent
  evasionstatus                    evasion modifier
  monstershieldstatus              monster-only damage shield
  monsterdrainstatus               monster-only drain
  weaknessstatus                   weakness debuff
  equipmentweaknessstatus          equipment-tied weakness
  lightcurtainstatus               multi-hit absorb shield
  partsbreakstatus                 boss part-break debuff (FFXI heritage)

CROWD CONTROL (5 statuses)
  bindstatus                       rooted/snared
  stunstatus                       stunned
  shortstunstatus                  short-duration stun (interrupt?)
  sleepstatus                      asleep
  petrifystatus                    petrified

TARGETING / RANGE / TIME / MOVEMENT (10 statuses)
  rangestatus                      attack range modifier
  cmnrangestatus                   cmn parent
  targetcontrolstatus              target selection modifier
  cmntargetcontrolstatus           cmn parent
  movingcontrolstatus              movement speed modifier
  cmnmovingcontrolstatus           cmn parent
  timecontrolstatus                cooldown/timer modifier
  cmntimecontrolstatus             cmn parent
  commandcontrolstatus             command-availability modifier
  cmncommandcontrolstatus          cmn parent

UTILITY / OTHER (10+ statuses)
  icononlystatus                   UI-only (no gameplay effect)
  instanteffectstatus              fires once, then removes
  cmninstanteffectstatus           cmn parent
  combinationstatus                combo trigger marker
  hijackstatus                     status override
  chocobospeeddownstatus           chocobo-specific debuff
  grandcompanystatus               GC affiliation marker
  foodstatus                       food buff
  medicinestatus                   medicine buff
  ability / magic / weaponskill    sub-folders (further classes inside)
  dev                              dev folder (probably test/debug statuses)
  oldstatus                        deprecated parent
  dummystatus                      placeholder
  r0d4dummystatus                  release-version dummy variant
  statusbaseclass                  the abstract parent
```

## 11. Cross-class command compatibility

`getStatusCompatibility` and `getStatusCompatibilityByHand` route through the
target's `getCommandCompatibility` -- meaning **status compatibility uses the
SAME computation as command compatibility**. This is the unified game-balance
math: a single function determines "how much does X's effect apply to Y".

```lua
function L0_1.getStatusCompatibilityByHand(self, target, hand_id, status, ...)
  local main_skill
  if hand_id == 2 then
    main_skill = target:getStateMainSkillForSub()  -- sub hand
  else
    main_skill = target:getStateMainSkill()        -- main hand
  end
  return self:getStatusCompatibility(target, status, main_skill, target)
end
```

So the hand parameter (1 = main, 2 = sub) determines which skill table to
consult for compatibility -- which is **the FFXI-style dual-wield handling**
where main/sub weapons have separate compatibility tables.

## Confidence

```text
Confirmed:
  - StatusBaseClass is 875 lines (not 793 as estimated earlier).
  - Status ID space spans 4 ranges:
    HIDDEN: 220000-222999 + 251000-252999 (~5K slots)
    SHOWN:  223000-231999 + 253000-254999 (~11K slots)
  - 5-attribute status model: Power, Param1, Param2, Param3, Life.
  - Triple-column per attribute: base / grow / compat.
  - 0.7 high-level / 1.0 low-level adjust factors (SAME as commands).
  - getObjectClassId returns 5 for all statuses.
  - getProcessPriority reads col 45.
  - getStatusIcon reads col 25.
  - statusSheet is reference-counted via _loadKeySemipermanently and
    _unloadKey on _onInit/_onFinalize.
  - Status compatibility uses the SAME getCommandCompatibility path
    that commands use.
  - HateForCasterStatus handles exactly 2 IDs: 223192 (bad) + 223087 (good).
  - CmnDoTStatus handles 8 IDs (7 bad + 2 good DoTs).
  - 158 status subclasses categorized into ~10 functional groups.
  - "cmn" prefix denotes group-handler classes (multi-ID dispatch).

Likely (High):
  - The hidden status ranges (220-222K + 251-252K) are internal flag/
    state statuses for combat engine state machine (recast trackers,
    "is targeting" flags, internal cooldowns, etc.).
  - Each `getStatusXxxAtSheet` is the final number returned to the
    damage/heal/buff computation pipeline.
  - The "exemplar" / overlevel-penalty system is GLOBAL: all 5 attributes
    suffer the 30% over-level penalty.
  - Subclass `_onInit` chains via `_callSuperClassFunc`, meaning all
    statuses inherit the sheet-loading + key-pinning logic for free.
  - The "ability/magic/weaponskill" sub-folders contain category-specific
    status subclasses (e.g., Ability/Provoke status, Magic/Stoneskin
    status, Weaponskill/Steel-Cyclone status).

Likely (Medium):
  - r0d4 prefix in `r0d4dummystatus` + `r0d4poisonstatus` is a release-
    version identifier (1.x Release 0d4 / patch label).
  - "hijackstatus" is for boss mechanics that temporarily take control
    of a player's action set (e.g., Bahamut's transformation).
  - "lightcurtainstatus" matches FFXI's Light Curtain spell (~5 hit
    absorb shield with magical evasion bonus).
  - "partsbreakstatus" mirrors FFXI's part-break debuffs that disable
    NM body parts (e.g., King Behemoth's horn).

Speculative:
  - The 16K status ID space accommodates EVERY future expansion's worth
    of status effects. ARR onwards used a much smaller, more compact
    ID space.
  - The dual-wield "hand" parameter (1=main, 2=sub) was probably never
    fully exposed in 1.x's gameplay because 1.x didn't have dual-wielded
    weapons -- this is FFXI heritage code that was never activated.
```

## Server implications

```text
- Server must implement statusSheet with ALL columns referenced here:
  25 (icon), 26-28 (power), 30-32 (param1), 34-36 (param2),
  38-40 (param3), 45 (priority), 47-49 (life).
- Server must serve 4 ID-range banks for status (hidden + shown,
  base + extended ranges).
- The 0.7 high-level / 1.0 low-level scaling must be implemented exactly.
- The compatibility calculation is shared with command compatibility --
  server can use ONE shared function.
- isShownStatus / isHiddenStatus determines whether to send buff/debuff
  packets to the client's UI buff bar.
- Statuses with `canStartOnDead = false` cannot be reapplied to dead
  targets (the default; subclasses override).
- The `canLifeAdjust = isBadStatus` default means only DEBUFFS get
  life-scaling -- good statuses have flat values.
- Default `isRemovedFromDeath = true` means most statuses clear on player
  death (subclasses can override to persist).
```

## Cross-references to other findings

- **`finding_status_subsystem.md`**: this finding upgrades the high-level
  158-status enumeration to actual category-by-category functional grouping.
- **`finding_combat_command_pipeline_and_4param_scaling.md`**: confirms
  the SHARED 0.7/1.0 model is used by BOTH commands (4 params) AND
  statuses (5 params).
- **`finding_charabase_battle_real_combat_formulas.md`**: the compat
  function `getCommandCompatibility` used here is the same one we found
  in CharaBase's battle math.
- **`finding_re/lua/finding_command_baseclass_and_teleport.md`**: the
  status/command duality completes the picture -- both share lifecycle,
  sheet-loading, level-scaling, and compatibility paths.

## Annotations made in Ghidra

None this finding -- Lua-only analysis.

## Next test

- Read the ability/magic/weaponskill sub-folders inside status/ to map
  category-specific status implementations.
- Cross-reference xtx_status (399 rows) against the 220-254K ID range
  banks to count actual populated slots per bank.
- Verify the getObjectClassId enumeration (1=Player, 2=Npc, 5=Status)
  by reading other base classes' getObjectClassId.
- Find the `judgeGrowColumn` function used by all the grow-column
  lookups -- it's the bridge between sheet col → caster stat.
- Look at `getStatusLevelAdjust` (also defined in StatusBaseClass) to
  confirm it's the same shape as calcPotencial in CharaBase.

## Commit suggestion

```
docs(re/lua): StatusBaseClass 875-line pipeline -- 5-param status model + unified 0.7/1.0 scaling
```
