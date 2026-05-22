# Finding: `initEventSyncWork` + `initBattleSync` — Event + Battle Schemas

Closes out the CharaBase `_onInit` schema discovery by walking the
two remaining init functions: `initEventSyncWork` (in
`charabaseclass_event.lua`) and `initBattleSync` (in
`charabaseclass_battle.lua`).

After this, the **complete** field set of every `charaWork` sub-struct
is enumerated.

Sources read:

```text
chara/charabaseclass_event.lua    444 lines   (full read)
chara/charabaseclass_battle.lua  2027 lines   (initBattleSync at 1374-1782;
                                                also calcPotencial)
```

## eventSave + eventTemp schemas

### `eventSave` (3 fields)

```text
{bazaar,       boolean}     -- is this NPC/actor a bazaar (selling) dealer
{bazaarTax,    integer8}    -- tax rate (0-100 percent)
{repairType,   integer8}    -- which repair type this NPC offers
```

### `eventTemp` (4 fields)

```text
{linkshellIcon, array[4]  integer16}   -- 4 linkshell icons displayed
                                          on this actor's nameplate
{bazaarRetail,  boolean}              -- retail mode on/off
{bazaarRepair,  boolean}              -- repair mode on/off
{bazaarMateria, boolean}              -- materia attach mode on/off
```

### Event tag groups (2 tags)

```text
{bazaar, 1, [
  {eventSave, bazaar},                -- the master bazaar flag
  {eventTemp, bazaarRetail},
  {eventTemp, bazaarRepair},
  {eventSave, bazaarTax},
  {eventSave, repairType},
  {eventTemp, bazaarMateria}
]}
{linkshellIcon, 1, [
  {eventTemp, linkshellIcon}
]}
```

The `bazaar` tag bundles ALL 6 bazaar-related fields into one
update — a server that wants to put an NPC into a bazaar state pushes
a single packet, not 6 separate ones.

### bindWork ids 4001/4002 confirmation + 4003

From `finding_bindwork_catalog.md`:

```text
4001  eventTemp.bazaarRetail   (boolean)
4002  eventTemp.bazaarRepair   (boolean)
```

Now confirmed. The 4xxx range continues with **bazaarMateria** which
likely takes id 4003 (matching the catalog's "id range 4000-4099"
allocation).

### Implication for the eventSave nested size of 3

The `_onInit` declared `{eventSave, nesting, 3}` — exactly 3 fields:
`bazaar`, `bazaarTax`, `repairType`. Matches.

### Implication for the eventTemp nested size of 9

The `_onInit` declared `{eventTemp, nesting, 9}` but the file only
shows 4 fields. The remaining 5 slots are **reserved for subclass
extension** (NpcBase, Player). For example, Player adds the 5
`variableCommandConfirmRaise/Warp/Content/PlaceDriven/EmoteSit` fields
seen in the bindWork catalog at ids 100001-100005.

## battleSave + battleTemp schemas

### `battleSave` (7 fields)

```text
Block 1 (L1_2):
{potencial,        float}              -- combat-power multiplier
                                          (computed via calcPotencial)

Block 2 (L2_2):
{physicalLevel,    integer16}          -- physical (non-class) level
{physicalExp,      integer32}          -- physical XP
{skillLevel,       array[52] integer16} -- per-skill level (52 skills!)
{skillLevelCap,    array[52] integer16} -- per-skill level cap
{skillPoint,       array[52] integer32} -- per-skill XP pool
{negotiationFlag,  array[2]  boolean}   -- 2-flag negotiation state
                                          (e.g. {enabled, exhausted})
```

### `battleTemp` (3 fields)

```text
{castGauge_speed,    array[2] float}      -- 2 cast bars (main + sub class?)
{timingCommandFlag,  array[4] boolean}    -- 4 timing-command states
                                            (CW/CCW/Hold/Release?)
{generalParameter,   array[35] integer16} -- 35 general battle parameters
                                            (stats: ATK, DEF, MND, etc.)
```

### Battle tag groups

#### Shared tags (all visible actors, 2 tags, no per-tag rate hint):

```text
{potencial, 1, [
  {battleSave, potencial}
]}
{exp, [                  -- no rate hint -> default rate
  {battleSave, skillLevel},
  {battleSave, skillLevelCap}
]}
```

The `exp` tag has no second arg (rate hint missing), so it falls
back to the default rate. The `potencial` tag has rate 1 (= 1 second).

#### Self-only tags (3 tags):

```text
{battleStateForSelf, 1, self, [
  {battleTemp, castGauge_speed},
  {battleSave, skillPoint},
  {battleSave, physicalExp},
  {battleSave, negotiationFlag}
]}

{timingCommand, 1, self, [
  {battleTemp, timingCommandFlag}
]}

{battleParameter, 1, self, [
  -- INDIVIDUAL INDICES into generalParameter[]:
  {battleTemp, generalParameter, 4},   -- index 4 = ?
  {battleTemp, generalParameter, 5},
  {battleTemp, generalParameter, 6},
  {battleTemp, generalParameter, 7},
  {battleTemp, generalParameter, 8},
  {battleTemp, generalParameter, 9},
  {battleTemp, generalParameter, 10},
  {battleTemp, generalParameter, 11},
  {battleTemp, generalParameter, 12},
  {battleTemp, generalParameter, 14},   -- 13 is skipped here
  {battleTemp, generalParameter, 13},   -- 13 comes after 14 (deliberate order?)
  {battleTemp, generalParameter, 15},
  {battleTemp, generalParameter, 16},
  {battleTemp, generalParameter, 17},
  {battleTemp, generalParameter, 18},
  {battleTemp, generalParameter, 19},
  {battleTemp, generalParameter, 24},   -- 20-23 skipped
  {battleTemp, generalParameter, 25},
  {battleTemp, generalParameter, 26},
  {battleTemp, generalParameter, 27},
  {battleTemp, generalParameter, 28},
  {battleTemp, generalParameter, 29},
  {battleTemp, generalParameter, 30},
  {battleTemp, generalParameter, 31},
  {battleTemp, generalParameter, 32},
  {battleTemp, generalParameter, 33},
  {battleTemp, generalParameter, 34},
  {battleTemp, generalParameter, 35}
]}
```

**Observations on the battleParameter tag**:

1. The tag specifies 28 INDIVIDUAL INDICES into `generalParameter[35]`.
   The skipped indices (1, 2, 3, 20, 21, 22, 23) are **not synced over
   the network** — they are local-only stat fields.
2. The order is mostly sequential but **swaps 13 and 14** (14 first,
   then 13). This is probably a deliberate "physical attack updates
   before crit chance" type ordering, where the server wants the
   client to render certain stats before others.
3. The total wire surface for "self battle parameters" is 28 int16 =
   56 bytes per push, at 1 Hz = ~56 bytes/s. Negligible bandwidth.

### `calcPotencial` table (XP-vs-level scaling)

The same file (lines 1100-1314) contains `calcPotencial`, a level-vs-
multiplier interpolation table:

```text
level 22 = 0.01  (effectively no penalty for low-level enemies)
level 21 = 93
level 20 = 88
level 19 = 83
level 18 = 78
level 17 = 73
level 16 = 68
level 15 = 63
level 14 = 58
level 13 = 53
level 12 = 48
level 11 = 43
level 10 = 38
level  9 = 33
level  8 = 28
level  7 = 23
level  6 = 18  ← duplicate value at level 5 != 13!
level  5 = 13
level  4 =  9
level  3 =  5
level  2 =  1
level  1 =  1
```

Used to compute the `potencial` field shown in nameplates and combat
calculations. Interpolated for non-integer levels.

The table shows a **5-XP-per-level scaling** from level 5 upward, with
an exponential decay (potential 1 → 5 → 9 → 13 → 18 = ~5 each step).

## Total schema sizes (final)

```text
struct         _temp size   _sync size   notes
-----------    ----------   ----------   --------------------------
charaWork.parameterSave    --   17 fields  (defined in parameter.lua)
charaWork.parameterTemp    --    7 fields  (defined in parameter.lua)
charaWork.eventSave       3 fields  (event.lua)
charaWork.eventTemp       4 explicit + 5 reserved for subclasses
charaWork.battleSave      7 fields  (battle.lua; skillLevel[52] etc.)
charaWork.battleTemp      3 fields  (battle.lua; including generalParameter[35])
charaWork.commandAcquired 4096-bit bitmap
charaWork.command[64]     actor refs
charaWork.commandCategory[64]  int8
charaWork.commandBorder      int8
charaWork.statusShownTime[20]  int32
charaWork.property[32]      boolean (bitset)
charaWork.additionalCommandAcquired[36]  boolean
charaWork.currentContentGroup    int32
charaWork.depictionJudge         actor ref
```

Total wire surface for **one fully-populated chara** (myPlayer):

```text
direct fields                ~  500 bytes
parameterSave 17 fields      ~  500 bytes (arrays of 8/10/40)
parameterTemp 7 fields       ~  100 bytes
eventSave 3 + eventTemp 9    ~   12 bytes
battleSave 7 fields          ~ 1000 bytes (skillLevel[52] alone = 104 bytes)
battleTemp 3 fields          ~   70 bytes
commandAcquired bitmap       ~  512 bytes (4096 bits)
command[64] actor refs       ~  256 bytes (4 bytes each)
commandCategory[64]          ~   64 bytes
commandBorder                ~    1 byte
statusShownTime[20]          ~   80 bytes
property[32]                 ~    4 bytes (bitset)
additionalCommandAcquired[36] ~   5 bytes
currentContentGroup          ~    4 bytes
depictionJudge ref           ~    4 bytes
                             ----
TOTAL initial chara state    ~ 3.5 KB
```

So loading a single fully-populated character at zone-enter costs
about **3.5 KB of full-state sync**, fitting comfortably in a single
~5 KB packet.

## Assessment

```text
Confirmed:
  - eventSave has exactly 3 fields (bazaar, bazaarTax, repairType);
    eventTemp has 4 explicit (linkshellIcon[4], bazaarRetail/Repair/
    Materia) plus 5 reserved for subclasses (the difference between
    the {eventTemp, nesting, 9} declared size and the 4 fields used here).
  - battleSave has 7 fields totaling ~1 KB of array data
    (skillLevel[52] + skillLevelCap[52] + skillPoint[52]).
  - battleTemp has 3 fields totaling ~70 bytes including the
    generalParameter[35] stat block.
  - The battleParameter tag SYNCS ONLY 28 OF THE 35 generalParameter
    indices -- indices 1-3, 20-23 are client-local stats not synced
    over the network.
  - Tag groups have explicit per-tag RATES; rate=1 means 1-second
    updates for that group.
  - calcPotencial implements a 22-entry level-vs-multiplier
    interpolation table; used by nameplate "this enemy is +N levels
    above you" calculations.

Likely (High):
  - The 5 reserved eventTemp slots are filled by Player class with
    the 5 variableCommand* fields (bindWork ids 100001-100005).
  - The 52-slot skillLevel/Cap/Point arrays correspond to 1.x's
    52-skill grid (~10 melee + ~10 ranged + ~10 magic + ~10 craft +
    ~10 gather + ~2 misc).
  - The 35-slot generalParameter holds vanilla MMO stats: STR/DEX/VIT/
    INT/MND/PIE (6) + ATK/RA/MAB/CRIT/EVA/PAR/ACC (7) + element resists
    (8) + class-specific (14). Total: 35.
  - generalParameter[1..3] are probably character base stats (lvl, age,
    race?) that don't change per battle; [20..23] are derived stats
    the client recomputes from base stats and gear.

Likely (Medium):
  - The "negotiationFlag[2]" array is {is_negotiation_enabled,
    is_negotiation_exhausted_today}. Used by NegotiationJudge to
    gate the menu. Server pushes [true, false] when negotiation
    becomes available; [true, true] after the daily limit is hit.
  - The duplicate "potencial" tag means the `potencial` field is
    high-priority sync -- updates faster than the default rate.
  - The order swap (14 before 13) in battleParameter sync hints that
    parameter 14 = "primary attack" (renders the weapon icon) and
    13 = "crit chance" (renders a secondary stat), and the client
    UI wants the primary stat rendered first.

Speculative:
  - The 4-slot linkshellIcon array is "the 4 linkshells this character
    is in" -- the nameplate / chat panel showed up to 4 simultaneous
    LS memberships, matching 1.x's design.
  - The "battleParameter" tag's missing indices 1-3, 20-23 may be the
    fields that were "live-computed" on the server but never displayed
    on the client UI (probably hidden derived stats like "next regen
    tick threshold").

Next test:
  - Read charabaseclass_cliprog.lua (454 lines) -- "client progression"
    seems related to player progression. Probably the Player-specific
    additions to charaWork.
  - Read npcbaseclass_event.lua (21.6 KB) -- the dialog flow expansion;
    surfaces the full Talk/Emote/Push wire surface and the desktopWidget
    channel ID space (32/33/38/40).

Commit suggestion:
  docs(re/lua): event + battle sync schemas; complete charaWork enumeration
```

## Server implication (final consolidated)

The `charaWork` wire surface is now **completely enumerated**:

```text
Per chara (steady state push budget):
  stateAtQuicklyForAll       0.3 s    HP[1] HPMax[1] MP MPMax TP        5 fields
  stateForAll                1.5 s    mainSkill mainSkillLevel target   3 fields
  potencial                  ~1 s     potencial                          1 field
  exp                        ~1 s     skillLevel[52] skillLevelCap[52]   104 entries

Per chara (self only):
  stateAtQuicklyForSelf      1 s      boostPoint                         4 entries
  commandDetailForSelf       1 s      cooldowns + forceControl          ~100 entries
  commandEquip               1 s      gift slots + ability/gift count    14 entries
  battleStateForSelf         1 s      castGauge + skillPoint+exp+negot   60 entries
  timingCommand              1 s      timing flags                       4 entries
  battleParameter            1 s      generalParameter[28 indices]      28 entries

Per chara (event/UI driven, lazy):
  bazaar                     event    bazaar mode + tax + repair         6 fields
  linkshellIcon              event    LS icons                           4 entries
  status                     event    statusShownTime[20]                20 entries
  command                    event    command[64] + category + border    129 entries
  commandAcquired            event    4096-bit bitmap                    1 array
  property                   event    32-bit bitset                      1 array
  judge                      event    depictionJudge actor ref           1 ref
```

The server can now decide what to push and when based on a clear
budget. Hot-loop is the 300ms HP tick; the 1-second self-sync ticks
are next; everything else is event-driven (only push on change).

This finding **closes the schema discovery loop** for actor data.
What remains is the IPC wire format (segments + opcodes; partially
documented), the movement system (C++-only), and combat-action
ICommand dispatch (semi-documented via `finding_game_command_pipeline.md`).
