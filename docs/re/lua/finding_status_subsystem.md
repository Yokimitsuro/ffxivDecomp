# Finding: Status (Buff/Debuff) Subsystem -- Class-Per-Status Architecture

Maps the FFXIV 1.x status effect subsystem. 158 Lua files in
`status/` directory (cipher-decoded). Architecture is
CLASS-PER-STATUS: each status effect has its own Lua subclass of
`StatusBaseClass`. The bulk are 8-line declarations (sheet-driven
defaults); ~30 have non-trivial behavior overrides.

## Directory map

```text
lua/decompiled/src/rq9qpr/             (= status/)
+-- rq9qpr89r57y9rr.lua                StatusBaseClass            793 lines
+-- 65o/                               (= dev/) 10 stubs
+-- [~145 status subclass files]       (typically 8-50 lines each)
```

Total: **158 status subclass files** + 1 base class.

## StatusBaseClass (793 lines, ~30 methods)

The abstract parent providing the full status interface.

```text
IDENTITY:
  getStatusId                         the status id (matches status.csv row)
  getStatusData                       sheet data row

CLASSIFICATION (orthogonal flags):
  isShownStatus                       displayed on UI
  isHiddenStatus                      not displayed
  isBadStatus                         debuff
  isGoodStatus                        buff
  isNeutralStatus                     neutral (neither buff nor debuff)

BEHAVIOR FLAGS:
  isRemovedFromDeath                  cleared when target dies?
  isRemovedAtChangeMainSkill          cleared when target changes class?
  canRegist                           target can resist?  (typo: "Regist" = "Resist")
  canLifeAdjust                       duration scales with caster stat?
  canStartOnDead                      can apply to dead targets?

OBJECT REF + ORDERING:
  getObjectClassId                    linked ObjectBase actor class (for vfx)
  getProcessPriority                  dispatch priority for stacking resolution

COMPATIBILITY / STACKING (3-way):
  getStatusCompatibility              base compat check
  getStatusCompatibilityByHand        manually-applied variant
  getStatusCompatibilityWithAdjust    level-adjusted variant

LEVEL / POWER SCALING (under-level + over-level penalty):
  getStatusLevelAdjust                base scaling
  getStatusPowerAdjustForHighLevelUse high-level downscale (when caster > target)
  getStatusLifeAdjustForHighLevelUse  high-level duration downscale
  getStatusPowerAdjustForLowLevelUse  low-level boost (when caster < target)
  getStatusLifeAdjustForLowLevelUse   low-level duration boost
  getStatusPowerLevelAdjustGrow       growth curve for power
  getStatusLifeLevelAdjustGrow        growth curve for life
  getStatusPowerAtSheet               sheet-driven base power
  getStatusLifeAtSheet                sheet-driven base life

LIFECYCLE:
  _onInit
  _onFinalize

UI:
  getStatusIcon                       UI icon resource
```

## Status mechanics (architecture)

Every status has TWO core metrics:

```text
POWER:  intensity / damage value of the effect
LIFE:   duration in ticks/seconds
```

Both adjust at runtime based on a complex pipeline:

```text
INPUT:                    base values from status.csv
+ caster's stat power
+ caster vs target LEVEL DIFFERENCE
+ growth curves (power + life independently)
+ compatibility-based stacking modifiers

OUTPUT:                   final POWER and LIFE applied to the target
```

The under-level / over-level penalty system mirrors the under-level
DAMAGE penalty documented in `finding_chara_cliprog_and_event_extensions.md`:

```text
HIGH-LEVEL USE   (caster > target): power & life are REDUCED
LOW-LEVEL USE    (caster < target): power & life are BOOSTED
                                     (the target gets effects buffed
                                      against an under-leveled caster?
                                      actually likely the opposite --
                                      the CASTER applying status to
                                      a higher-level target sees a
                                      penalty)
```

## Classification taxonomy (orthogonal)

```text
VISIBILITY:                      MORAL:
  isShownStatus  (UI visible)     isBadStatus
  isHiddenStatus (UI hidden)      isGoodStatus
                                  isNeutralStatus

So 6 combinations: { shown / hidden } x { bad / good / neutral }.
```

The base class defaults are typically "shown" + "neutral"; subclasses
override.

## Compatibility / stacking system

Three-way variant of the same predicate. The base check
(`getStatusCompatibility`) decides whether status X can coexist with
already-applied status Y. The "ByHand" variant differs when the new
status was manually applied (e.g. via consumable). The "WithAdjust"
variant accounts for level-adjusted effective level.

So stacking has 3 orthogonal considerations:
1. Default compat
2. Manually-applied compat (sometimes more lenient)
3. Level-adjusted compat (a stronger version can overwrite a weaker
   one of the same effect line)

## Subclass distribution

```text
158 files total, broken down by size:
  ~120 files of  8 lines    SHEET-ONLY classes (just declare the
                            class name; default behavior from base)
  ~30 files of   15-50 lines OVERRIDE classes (specific ID-driven
                             behavior)
  ~10 files in dev/          DEVELOPMENT stubs (test statuses)
  Some larger (50+ lines)    a few feature-rich statuses
```

So the architecture pattern is:
1. **One Lua class per status effect** (extreme OOP)
2. **Sheet-driven defaults** -- most classes just exist as the
   instantiation type; behavior comes from status.csv columns
3. **Targeted overrides** -- when a status needs special behavior,
   its subclass overrides 1-3 specific predicates
4. **Hardcoded status IDs** -- subclasses pin specific IDs in their
   overrides (e.g. `if id == 223116 then ...`)

## Confirmed status ID samples (from subclass bodies)

```text
ID 223087   HateForCasterStatus -- declared Good (positive enmity for caster)
ID 223116   InstantEffectStatus -- declared Bad + removed on class change
ID 223192   HateForCasterStatus -- declared Bad (negative enmity for caster)
```

So the 223xxx range covers enmity/instant-effect statuses. Per
FFXIVTool's `status.csv` (399 rows), status IDs range from 0 to at
least 253003 (sparse). The ID space is NOT contiguous -- it's
organized in topical blocks:

```text
PROBABLE ID BLOCKS (Speculative; needs more sampling):
  0           default / null status
  ~100xx      icon-only / UI-only
  ~200xx      generic combat statuses
  ~22xxxx     enmity / hate statuses
  ~25xxxx     special effects (negative col 41 indicates "rare" tier)
```

## status.csv schema (partial, 59 columns)

```text
col 0       row id (status id)
col 26      icon id (col type s32; values 231 = generic, 10120/121 = specific)
col 32      maybe POWER or DURATION (s32)
col 41      bonus/tier indicator (negative for special, e.g. -3)
col 46      maybe level or max stack (s32, often 60)
col 53-58   bool/byte flags (8 columns)
```

Full column meanings require cross-reference with each subclass
override (each override reads from specific columns); mechanical
work that's not yet done.

## Notable status subclasses (samples)

```text
FoodStatus                    rq9qpr/4vv6rq9qpr.lua            8 lines
HateForCasterStatus           rq9qpr/29q54vs79rq5srq9qpr.lua  46 lines
                              (2 ID-specific predicate overrides)
HateForTargetStatus           rq9qpr/29q54vsq9s35qrq9qpr.lua  (parallel)
HateControlStatus             rq9qpr/29q57vwqsvyrq9qpr.lua     8 lines
InstantEffectStatus           rq9qpr/1wrq9wq54457qrq9qpr.lua  36 lines
IconOnlyStatus                rq9qpr/17vwvwylrq9qpr.lua        8 lines
HijackStatus                  rq9qpr/21097zrq9qpr.lua         15 lines
EvasionStatus                 rq9qpr/5o9r1vwrq9qpr.lua        15 lines
EquipmentWeaknessStatus       rq9qpr/5tp1ux5wqn59zw5rrrq9qpr.lua  (parallel)
GrandCompanyStatus            rq9qpr/3s9w67vxu9wlrq9qpr.lua   (parallel)
... 150+ more
```

## Server implications

```text
STATUS SYSTEM REQUIREMENTS FOR THE SERVER:

1. STATUS RUNTIME OBJECT:
   Per-target list of active statuses, each with:
     - status_id (uint32)
     - caster_actor_id (uint32 / nil for environmental)
     - applied_at_tick (uint64)
     - duration_ticks (computed LIFE)
     - power_value (computed POWER)
     - is_removed_on_death (bool, from sheet)
     - is_removed_at_class_change (bool, from sheet)
     - process_priority (int8, from sheet)
   
   Status list per actor must be bounded (~30-50 typical max) and
   periodically pruned (expired statuses removed).

2. STATUS APPLY/REMOVE WIRE:
   Per-status apply: the server pushes an inbound event (probably
   one of the unmapped Zone inbound opcodes in 27/39-50 range) with
     (target_actor_id, status_id, power, life)
   Per-status remove: another opcode with (target, status_id).
   
   Both flow into a per-actor Lua _onStatusApply / _onStatusRemove
   hook (TBD; need to confirm via grep).

3. STATUS DAMAGE / EFFECT TICK:
   Bad statuses with damage-over-time apply periodically. The
   server simulates each status's tick on a fixed cadence (probably
   3-second tick per FFXIV's standard tick interval) and pushes
   damage events on each tick.

4. STATUS COMPATIBILITY ENFORCEMENT:
   When the server applies a status, it must check the existing
   status list for compatibility:
     - If existing status with same effect-line: choose the stronger
       (compare power) and replace.
     - If existing status of incompatible kind: deny the new apply
       (or remove the existing, depending on rules).
   The 3 compat variants (default / by-hand / with-adjust) mean
   the server needs 3 decision paths.

5. STATUS LEVEL ADJUSTMENT:
   Server must compute the actual power/life on apply, NOT trust
   the client. The under/over-level penalty system is server-
   authoritative.

6. STATUS PERSISTENCE:
   Some statuses survive disconnect/reconnect; others don't. The
   sheet flags (col 53-58) likely include "save through logout"
   markers. Server must persist appropriate statuses to DB on
   logout and reapply on login.

7. STATUS ICON / UI:
   Server pushes only IDs; client renders icons from local
   `status.csv` data + `getStatusIcon()` Lua hook. Server doesn't
   need to send icon data.
```

## Confidence

```text
Confirmed:
  - StatusBaseClass has 30+ documented method slots covering
    classification, level-scaling, compat, lifecycle, UI.
  - 158 status subclass files exist in the Lua corpus.
  - The bulk (~120 of 158) are 8-line class-name-only declarations.
  - Status has 2 core metrics: POWER + LIFE (intensity + duration).
  - The level-adjust system covers both under-level boost and
    high-level downscale (4 separate methods: power x life x
    high x low).
  - 3-way compat system (default / byHand / withAdjust).
  - Sample status IDs found in subclass bodies: 223087, 223116, 223192.

Likely (High):
  - status.csv 399 rows correspond to most subclass files, with
    some sheet rows NOT having a Lua subclass (defaulting to
    StatusBaseClass behavior).
  - The 223xxx range is one topical block (enmity / hate); the
    full ID space is sparse and topical.
  - Status compatibility is server-authoritative (clients show what
    the server says is active; conflicts are resolved on the server
    side before pushing).

Likely (Medium):
  - The `getProcessPriority` method drives the order of multi-status
    stacking computations. Higher priority statuses resolve first.
  - The `getStatusLifeAdjustGrow` curve is a step-function from sheet
    data (probably 4 segments matching the 4-quarter-of-level
    pattern observed in CharaBaseClass damage scaling).

Speculative:
  - Some statuses (the 8-line declarations) only exist as VFX
    triggers -- they have an ObjectBase class linked via
    getObjectClassId that renders the visual. Behavior is pure
    sheet defaults.
  - The 10 dev/ subclasses are leftover testing artifacts -- they
    may not be reachable from any live status data.
```

## Connections to other findings

- **CharaBaseClass_parameter** (per `finding_charabase_class_complete.md`):
  the playerWork schema has a `status` field — probably a list/array
  of active status IDs per actor.
- **WorkSync (opcode 0x12F)**: the wire mechanism for syncing status
  list changes from server to client.
- **CommandUpdaterBase** (per `finding_chat_block_command_notifications.md`):
  status-related command notifications (e.g. "Slow received") flow
  through the chat A/B/C/D opcodes (35/36/37/57).

## Next test

- Grep for `_onStatusApply / _onStatusRemove / _onStatusUpdate` to
  find the per-actor status lifecycle hooks.
- Sample 5 more mid-size status subclasses (30-50 line range) to
  identify the typical override patterns and what specific status
  IDs they pin.
- Cross-reference 5-10 specific status IDs from the Lua bodies with
  status.csv rows to identify column meanings (icon, duration,
  power, etc.).

## Commit suggestion

```
docs(re/lua): map Status subsystem (StatusBaseClass + 158 subclasses)
```
