# Finding: StatusBaseClass -- Status Effect Engine (5-param model, level-adjust potency, compatibility/stacking; client computes, server tracks ids)

**Maps the status effect base mechanics** — StatusBaseClass, the engine
for all 158 status scripts (buffs/debuffs). Status potency/duration are
**computed client-side** from status.csv + a level-adjust growth formula;
the server only tracks WHICH statuses are active (the compact status-list
wire opcodes 0x14f/0x150).

StatusBaseClass (rq9qpr89r57y9rr.lua, 875 lines, 41 functions).

## 1. Status classification

```text
getStatusId / getStatusData    identity + status.csv row
getStatusIcon                  display icon
getObjectClassId               actor class id

isShownStatus / isHiddenStatus      visible in the 16-slot UI list?
isBadStatus / isGoodStatus / isNeutralStatus   debuff / buff / neutral

REMOVAL RULES:
  isRemovedFromDeath           cleared when actor dies
  isRemovedAtChangeMainSkill   cleared when switching class/job
  canStartOnDead               can apply to a dead actor
  canRegist                    can be applied (registration check)
  canLifeAdjust                duration can be adjusted

getProcessPriority             status application/tick order
```

## 2. The 5-parameter status model

Every status has 5 parameters (read from status.csv via *AtSheet):

```text
getStatusParam1AtSheet   Param1   effect-specific value
getStatusParam2AtSheet   Param2   effect-specific value
getStatusParam3AtSheet   Param3   effect-specific value
getStatusPowerAtSheet    Power    effect MAGNITUDE (e.g. +X attack, X dmg/tick)
getStatusLifeAtSheet     Life     DURATION

The 5 params drive the status effect. Power = magnitude, Life =
duration, Param1/2/3 = additional effect-specific values (e.g.
proc chance, tick interval, target count).
```

## 3. Level-adjust potency (the key formula)

Status potency scales by the LEVEL GAP between the command's level
and the caster's skill level -- same growth-curve formula as the
item level-adjust (prior finding):

```text
getStatusCompatibilityWithAdjust(self, baseValue, param, highAdjust,
                                 lowAdjust, caster, command, ...)

  cmdLevel    = command:getCommandLevel()
  skillLevel  = caster:getStateMainSkillLevel()
  highCap, lowCap = command:getCommandLevelAdjustLevelMax()

  # Clamp effective level by adjust caps
  if cmdLevel > skillLevel:        # OVER-level use (high-level cmd, low skill)
    effLevel = cmdLevel - min(highCap, cmdLevel - skillLevel)
  elif cmdLevel < skillLevel:      # UNDER-level use
    effLevel = cmdLevel + min(lowCap, skillLevel - cmdLevel)

  growAtCmd = skill:getGrowData(cmdLevel, param)   # growth curve value
  growAtEff = skill:getGrowData(effLevel, param)

  ratio    = baseValue / growAtCmd
  adjusted = growAtEff * ratio

  # Blend by adjust weights
  if over-level:  value -= (value - adjusted) * highAdjust
  elif under-level: value += (adjusted - value) * lowAdjust

  return value

getStatusLevelAdjust -> 0.7 (default adjust factor)

Per-level-tier adjust functions:
  getStatusParam{1,2,3}AdjustForHighLevelUse / ForLowLevelUse
  getStatusPowerAdjustForHighLevelUse / ForLowLevelUse
  getStatusLifeAdjustForHighLevelUse / ForLowLevelUse
  getStatusParam{1,2,3}LevelAdjustGrow
  getStatusPowerLevelAdjustGrow / getStatusLifeLevelAdjustGrow

So both POWER (magnitude) and LIFE (duration) scale with level via
the growth curve -- under-leveling a status weakens + shortens it.
```

## 4. Compatibility / stacking

```text
getStatusCompatibility(self, ?, caster, subFlag, ...)      [192]
  - resolves caster's main skill (or sub-skill if subFlag==2)
  - delegates to the compatibility lookup

getStatusCompatibilityByHand(self, existing, ?, hand, ...)  [216]
  - blends with an existing status value:
    result = compat - (1 - compat) * existing
  - this is the STACKING formula: how a new application combines
    with an existing instance of the (compatible) status

Compatibility governs whether statuses STACK, REFRESH, or CONFLICT.
The "by hand" variant accounts for which weapon hand applied it
(dual-wield / two-handed status sourcing).
```

## 5. Connection to the wire (status-list opcodes)

```text
The status-list wire opcodes (prior finding):
  0x14f  STATUS LIST 16 slots (6B per entry: id + duration + flag)
  0x150  EXTENDED STATUS LIST 32 slots

These carry the COMPACT representation: just (status_id, duration,
flag) per active status. The CLIENT expands each into the full effect:
  - Look up status_id in status.csv (getStatusData)
  - Compute Power/Life via the level-adjust formula
  - Apply the effect (the per-status script logic)

This is the client-side-content principle AGAIN:
  - Server sends: status_id + duration + flag (6 bytes)
  - Client computes: full effect magnitude, visuals, mechanics
  - status.csv + the 158 status scripts are CLIENT-LOCAL

The server NEVER sends effect magnitude -- only which status + how
long. The client derives the rest.
```

## 6. Status subdirectory categories

```text
rq9qpr/65o/           dev/debug statuses
rq9qpr/981y1ql/       ability statuses (from abilities)
rq9qpr/n59uvwrz1yy/   weaponSkill statuses (from weaponskills)
rq9qpr/x9317/         magic statuses (from spells)

So statuses are categorized by SOURCE: ability / weaponskill / magic.
Each of the 158 status scripts is a subclass implementing a specific
buff/debuff's per-tick / on-apply / on-remove logic.
```

## 7. Server-side requirements

```text
STATUS STATE TO TRACK (per actor):
  - active status list (up to 16 primary + 32 extended)
  - per status: id, remaining duration, source, stacks

STATUS WIRE (server pushes):
  - 0x14f/0x150 status lists: (status_id, duration, flag) per slot
  - On apply: add to list + push update
  - On expire/remove: remove from list + push update
  - Server tracks DURATION countdown (Life) authoritatively

WHAT THE SERVER DOESN'T DO:
  - Compute effect magnitude (client does via status.csv + level-adjust)
  - Run per-tick effect visuals (client)
  - The 158 status scripts are client-local

SERVER DATA NEEDED:
  - status.csv: status definitions (Param1/2/3/Power/Life + level-adjust
    columns + classification flags + removal rules)
  - Per-actor active-status tracking

KEY: the server is the DURATION/EXISTENCE authority; the client is the
EFFECT-COMPUTATION engine. Server says "you have status 42 for 30s";
client computes what status 42 does at your level.
```

## 8. Confidence

```text
Confirmed:
  - StatusBaseClass = status engine; 158 status subclasses
  - 5-param model: Param1/2/3 + Power (magnitude) + Life (duration)
  - Level-adjust potency formula (growth-curve, same as item adjust):
    over/under-level use scales Power AND Life
  - Compatibility/stacking: getStatusCompatibility + ByHand blend formula
  - Classification: good/bad/neutral, shown/hidden, removal rules
  - 4 source categories: ability/weaponskill/magic/dev
  - 41 functions enumerated

Likely (High):
  - Status potency computed client-side from status.csv + caster level
  - Wire (0x14f/0x150) carries only id+duration+flag (compact)
  - Server tracks duration authoritatively; client computes effect
  - getProcessPriority orders status ticks (e.g. regen before damage)

Speculative:
  - getStatusLevelAdjust 0.7 = default down-scaling for mismatched level
  - Param1/2/3 semantics vary per status (proc%, tick interval, etc.)
  - "byHand" = dual-wield status sourcing (which weapon applied it)
```

## 9. Cross-references

- `finding_per_actor_messages_COMPLETE_15_opcodes_3x5_matrix.md` --
  0x14f/0x150 status-list wire opcodes (id+duration+flag this expands)
- `finding_charabaseclass_battle_schema_and_timing_commands.md` --
  combat schema (statuses applied during combat)
- `finding_combat_relations_and_potencial.md` -- combat core
- `finding_npc_event_talk_turn_flow_client_side.md` + the
  client-side-content principle (status magnitude is client-local)
- `finding_csv_complete_correlation_132_of_164_critical_mapped.md` --
  status.csv (server status definitions)

## 10. Next test

```text
1. Read a concrete status script (rq9qpr/x9317 magic or 981y1ql ability)
   to see per-tick / on-apply effect logic
2. Map status.csv columns (Param1/2/3/Power/Life + adjust + flags)
3. Trace getGrowData (the growth curve used by level-adjust)
4. Document the compatibility table (which statuses conflict/stack)
5. Move to next base mechanic: item (1q5x) or judge (0p635)
```

## Commit suggestion

```
docs(re/lua): StatusBaseClass status effect engine -- 5-param model (Param1/2/3/Power/Life), level-adjust potency (growth-curve), compatibility/stacking; client computes effect, server tracks id+duration (0x14f/0x150)
```
