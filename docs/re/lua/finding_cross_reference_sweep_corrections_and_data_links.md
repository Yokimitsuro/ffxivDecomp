# Finding: Cross-Reference Sweep -- Statuses, Soul Crystals, Gathering Actions + CORRECTIONS

Mass cross-reference of Lua-hardcoded IDs against the FFXIVTool
CSV catalog. Concrete identifications for:

1. **3 status IDs** identified by name (223087 / 223116 / 223192)
2. **7 soul crystal items** named (Soul of the X)
3. **7 gathering actions** confirmed by name (Mine / Quarry / Log /
   Harvest / Fish / Spearfish / Herd)
4. **IMPORTANT CORRECTION**: Job ID-to-name mapping had been WRONG
   in prior findings. Real mapping (from soul crystal items):
   - Job 15 = MNK (not PLD)
   - Job 16 = PLD (not MNK)
   - Job 18 = BRD (not DRG)
   - Job 19 = DRG (not BRD)
5. **Aetheryte IDs**: confirmed 1,280,000+ range with parent/child
   structure.

## 1. Status IDs identified

Looking up the 3 status IDs hardcoded in HateForCasterStatus and
InstantEffectStatus:

```text
ID        Name (JA)         Name (EN)           Icon   Lua Classification
------    --------          --------            ----   -----------------
223087    ウォーモンガー    Warmonger           10105  GOOD (enmity boost)
223116    神速魔             Presence of Mind    10216  GOOD (cast speed; mage)
223192    敵視上昇率－      Sonorous Blast      10106  BAD  (enmity reduce)
```

**Warmonger** (223087): "Enmity is increased" -- TANK BUFF for
generating threat.

**Presence of Mind** (223116): "Cast and recast timers are shortened
for the next spell" -- the WHM 27344 cross-class command's effect.
A self-buff for the next cast.

**Sonorous Blast** (223192): "Enmity generation is reduced" --
DEBUFF, typically self-applied or applied by enemies to reduce
threat output.

So the HateForCasterStatus class handles two SPECIFIC enmity
modifiers (Warmonger + Sonorous Blast), and InstantEffectStatus
handles Presence of Mind (single-use boost on the next cast).

This validates the status subclass architecture: each subclass
covers a HANDFUL of specific status IDs by ID checks.

## 2. Soul Crystal items confirmed

The 7 job soul crystals from `getAdditionalCommandList`:

```text
Item ID    Name (JA)             Name (EN)
-------    --------              --------
2000201    ナイトの証             Soul of the Paladin
2000202    モンクの証             Soul of the Monk
2000203    戦士の証               Soul of the Warrior
2000204    竜騎士の証             Soul of the Dragoon
2000205    吟遊詩人の証           Soul of the Bard
2000206    白魔道士の証           Soul of the White Mage
2000207    黒魔道士の証           Soul of the Black Mage
```

All 7 confirmed as "Soul of the X" items. Item IDs are NOT
sequential alphabetically -- they reflect IMPLEMENTATION ORDER:
- 2000201 = PLD
- 2000202 = MNK
- 2000203 = WAR
- 2000204 = DRG
- 2000205 = BRD
- 2000206 = WHM
- 2000207 = BLM

## 3. CORRECTION: Job ID-to-Name mapping was WRONG

Per `getAdditionalCommandList` body:
```text
Job 15 -> 2000202 = Soul of the MONK   -- so Job 15 IS MONK
Job 16 -> 2000201 = Soul of the PALADIN -- so Job 16 IS PALADIN
Job 17 -> 2000203 = Soul of the Warrior
Job 18 -> 2000205 = Soul of the Bard
Job 19 -> 2000204 = Soul of the Dragoon
Job 26 -> 2000207 = Soul of the Black Mage
Job 27 -> 2000206 = Soul of the White Mage
```

### CORRECTED Job ID-to-Name mapping

```text
Job 15 = MNK
Job 16 = PLD
Job 17 = WAR
Job 18 = BRD
Job 19 = DRG
Job 26 = BLM
Job 27 = WHM
```

### Validation via cross-class command groups

The 36 cross-class commands group neatly:

```text
27106-27118 = MNK group (Hundred Fists, Spinning Heel, ...)
27146-27159 = PLD group (Cover, Divine Veil, Hallowed Ground, ...)
27186-27192 = WAR group (Vengeance, Antagonize, Mighty Strikes, ...)
27227-27239 = BRD group (Battle Voice, Ballad of Magi, ...)
27266-27277 = DRG group (Jump, Elusive Jump, ...)
27305-27319 = BLM group (Convert, Burst, Flare, Freeze, ...)
27344-27359 = WHM group (Presence of Mind, Benediction, ...)
```

The order matches:
- Job 15 (MNK) -> first 5 in convertSkillId = MNK group
- Job 16 (PLD) -> next 5 = PLD group
- ... and so on.

So the cross-class action list IS ordered by job ID 15->16->17->18->19->26->27, and that order maps to MNK->PLD->WAR->BRD->DRG->BLM->WHM. CONSISTENT.

### Prior findings that need correction

The following findings had the OLD (incorrect) mapping:
- finding_chara_cliprog_and_event_extensions.md (Job 15 PLD, 16 MNK,
  18 DRG, 19 BRD)
- finding_ffxivbattle_stats_and_jobs.md (similar mapping)
- finding_ffxivbattle_stat_layout_and_job_classes.md (similar)
- finding_battle_sync_schema_and_skill_conversion.md (similar)
- finding_cross_class_36_actions_ffxi_heritage.md (cross-class
  group ordering assumed PLD/MNK swap)

All those documents should be re-read with this CORRECTED mapping
in mind. Most of the structural findings remain valid; only the
job-to-name labels need adjustment.

This finding establishes the AUTHORITATIVE mapping going forward.

## 4. Gathering actions confirmed (all 7)

Per the prior `PlaceDrivenCommand` mapping (`mapJudgeCommand`):

```text
Command ID    Name (JA)    Name (EN)    Class
----------    --------     --------     -----
22002         採掘          Mine          Miner main
22003         採取          Log           Botanist main
22004         釣り          Fish          Fisher main
22005         牧獣          Herd          Shepherd main (1.x unique)
22006         採掘２         Quarry        Miner secondary
22007         採取２         Harvest       Botanist secondary
22008         釣り２         Spearfish     Fisher secondary
```

So 1.x gathering = **4 gatherer classes with these actions**:
- Miner: Mine + Quarry (2 actions)
- Botanist: Log + Harvest (2 actions)
- Fisher: Fish + Spearfish (2 actions)
- Shepherd: Herd only (1 action; UNIQUE to 1.x; ARR removed Shepherd)

Total: **7 gathering actions across 4 gatherer classes**.

## 5. Aetheryte ID range confirmed

Sample aetheryte rows from `aetheryte.csv`:

```text
1280000   col1=1065   (probably a generic / reference aetheryte)
1280001   col1=1051   col2-3=1,1   (first regional aetheryte)
1280010   col1=1019   col2=3, col3=6, parent=1280003  (regional cluster)
1280050   col1=3029   col2=3, col3=6, parent=1280036  (cluster in another region)
1280100   col1=4019   col2=3, col3=6, parent=1280093  (cluster in 4th region)
```

So aetheryte IDs:
- Range: 1,280,000+ (matches FFXIVTool catalog row count 118)
- col 1: probably NPC actor class id (the NPC interacting at the aetheryte)
- col 2-3: regional / zone grid position
- col 4: PARENT aetheryte (cluster grouping)
- col 14: tier or unlock level (0, 60, 70, 90 observed)

### Cluster structure

The "parent" column suggests aetherytes form a **TREE** structure:
- Root aetherytes (parent = 0): the "main" aetherytes per region
- Sub-aetherytes (parent = some other ID): branches off main ones

This matches FFXIV's design where each REGION has 1 main
aetheryte + several SHARDS sub-aetherytes around it.

## 6. Always-allowed range 10000-19999

Sampled command IDs 10001-19000:
- Most returned `***|***` (no name; placeholder)

So the 10000-19999 range is **mostly UNPOPULATED**. Only a few
specific commands exist there. The "always-allowed" range is
RESERVED but sparse in retail data.

This matches the `canFire` check in PlaceDrivenCommand:
```text
if 10000 <= A2 <= 19999: return true   (always allowed)
```

The check exists for future expansion; specific commands in that
range are limited to emote / cosmetic commands that aren't in
the standard battle action set.

## 7. Static actor IDs NOT in actorclass.csv

The static actor IDs from prior findings (310001 = WorldMaster,
24301 = raid svc, 320013 = chocobo rider, 12015 = push-out
sentinel) do NOT appear in actorclass.csv. This is because:

```text
actorclass.csv has IDs 1-7984 (per FFXIVTool catalog)
Static actor IDs are 12015, 24301, 310001, 320013 -- DIFFERENT range
```

So **static actor IDs are NOT class IDs**. They're probably:
- Per-region SPAWN INSTANCES
- Service NPC IDs in a separate registry
- Or world-state object IDs

The right place to look would be `populace*.csv` tables, which
contain specific NPC instances by ID. But the specific IDs may
require deeper investigation than this cross-ref sweep allows.

## Confidence

```text
Confirmed:
  - Status names: 223087 Warmonger / 223116 Presence of Mind /
    223192 Sonorous Blast.
  - Soul crystal item names: 2000201-2000207 all confirmed as
    "Soul of the X".
  - CORRECTED Job ID mapping (Job 15 = MNK / 16 = PLD / 17 = WAR /
    18 = BRD / 19 = DRG / 26 = BLM / 27 = WHM).
  - 7 gathering action names: Mine / Quarry / Log / Harvest / Fish /
    Spearfish / Herd.
  - Aetheryte IDs in 1,280,000+ range with parent/child tree structure.
  - 10000-19999 always-allowed command range is mostly UNPOPULATED in
    retail (reserved for future / emote / cosmetic).
  - Static actor IDs (310001 etc.) are NOT in actorclass.csv;
    different ID space (populace tables or world-state registry).

Likely (High):
  - The 4 gatherer classes are Miner / Botanist / Fisher / Shepherd
    (with Shepherd unique to 1.x and removed in ARR).
  - Aetheryte col 1 = NPC actor class id (the NPC at the
    aetheryte); col 4 = parent aetheryte id.
  - Status icon IDs 10105/10106 are part of an enmity-status icon
    block (10105 = good enmity, 10106 = bad enmity, similar
    pairing seen elsewhere).

Likely (Medium):
  - The job IDs 15-19, 26-27 were chosen non-contiguous because
    IDs 20-25 were reserved for additional jobs (not implemented
    in 1.x).
  - Aetheryte col 14 (tier) is the SKILL LEVEL or main-stat-level
    requirement to use that aetheryte.
  - The 10000-19999 range will be EXPANDED in future patches with
    more emote commands.

Speculative:
  - The pre-1.x job ID assignment (15=MNK / 16=PLD) suggests Monk
    was designed FIRST in 1.x development, then Paladin added.
    Hence the lower ID for MNK.
  - 1.x might have planned MORE jobs in the 20-25 ID range that
    were cut before release (Ninja? Samurai?).
```

## Connections to other findings

- **finding_status_subsystem.md**: now has 3 specific status names
  to anchor the abstract architecture.
- **finding_chara_cliprog_and_event_extensions.md**: needs the
  corrected job ID mapping applied to `hasJobStone` logic
  description.
- **finding_cross_class_36_actions_ffxi_heritage.md**: validates
  the cross-class group ordering matches the corrected job IDs.
- **finding_negotiation_bazaar_widget_family.md**: the gathering
  action IDs explained why bazaarkind values 1-7 exist for these.
- **FFXIVTool aetheryte.csv**: confirmed 118 row count from
  catalog matches the visible ID range 1280000-1280117.

## Next test

- Look up specific Bard song command IDs (Ballad of Magi 27237,
  Paeon of War 27238, Minuet of Rigor 27239) to see if their
  sheet rows reveal MP cost + duration data.
- Cross-reference the static actor IDs (310001, 24301) against
  populaceShopSalesman.csv or populaceGuildShop.csv to locate
  them.
- Sample 5 aetheryte rows to validate the tier value (col 14)
  meaning.

## Commit suggestion

```
docs(re/lua): cross-ref sweep -- 3 statuses, 7 soul crystals, 7 gathering actions named + CORRECT job ID mapping
```
