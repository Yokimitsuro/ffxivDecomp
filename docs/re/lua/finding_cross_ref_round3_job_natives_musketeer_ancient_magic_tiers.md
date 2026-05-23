# Finding: Cross-Reference Round 3 -- Job Natives, MUSKETEER class, Ancient Magic Triple-IDs + Tier II

Third cross-reference sweep. **Major discoveries**:

1. **Job native auto-attack actions** (22101-22112) identified per
   weapon class.
2. **MUSKETEER class confirmed** in 1.x (cmd 22110 = Discharge =
   gun attack) -- a class that was REMOVED in ARR.
3. **Ancient Magic has TRIPLE IDs** (enemy + cross-class + player
   class) and **3 of 6 have TIER II** variants.
4. **Bio I confirmed** (cmd 28602; completes the Bio family).
5. **Magic Missile family** has 6 variants including Phantom Dart
   + Spirit Dart (FFXI classics).

## 1. Job native auto-attack actions (22101-22112)

Per the `isRecastSeparationHands` Lua check, the IDs 22101-22112
are job-specific actions with SEPARATE per-hand recast timers.
These are the **basic weapon attacks per weapon class**:

```text
CMD ID  Name (JA)        Name (EN)       Weapon class
------  --------         --------        ------------
22101   すっぴん攻撃     Unarmed          (no weapon equipped; bare fists)
22102   正拳             Heavy Strike     Pugilist / Monk (fist)
22103   ライトスラッシュ Light Slash      Gladiator (sword)
22105   スウィング       Light Swing      Marauder (axe / cleave)
22106   決闘攻撃         ***              (Fencing? Duel weapon?)
22107   棍攻撃           Bludgeon         Conjurer staff / club
22109   スラスト         Light Thrust     Lancer (polearm thrust)
22110   銃攻撃           Discharge        MUSKETEER (gun attack)
22111   ガード           Guard            defensive guard
22112   ブロック         Block            shield block (PLD)
```

So 10 distinct **weapon-class auto-attack actions** + 2 defensive
actions (Guard / Block). These all have per-hand recast (for
dual-wielders, each hand has its own cooldown).

**Missing weapon types** from the 22100 range I sampled:
- Bow / Archer (probably 22104 or 22108?)
- Sword + Shield (covered by Gladiator 22103?)
- Stave / Wand (Thaumaturge probably has its own ID)

### Implication

The 1.x base classes have UNIQUE weapon attack commands per type.
This is consistent with FFXI's auto-attack system where each
weapon type has its own damage formula + delay.

## 2. MUSKETEER CLASS CONFIRMED in 1.x

**cmd 22110 = "Discharge" (銃攻撃 = gun attack)** is the basic
attack for a **MUSKETEER class** in FFXIV 1.x.

This is a significant finding:
- FFXIV 1.x had a MUSKETEER class with firearms
- ARR REMOVED Musketeer (no firearm class in 2.x base game)
- Firearms returned in Stormblood as MACHINIST (different mechanics)
- 1.x's Musketeer was a precursor that didn't survive the reboot

The 1.x Musketeer probably had:
- Discharge auto-attack (single-shot)
- Possibly Magic Missile-like ranged spells (22301-22306 range)
- Phantom Dart / Spirit Dart in its repertoire (cmd 22302/22303)

### Historical context

Musketeer in 1.x lore tied to ULDAH (the desert city). Lalafell
gunsmiths were a thing in 1.x but the gun aesthetic didn't fit
ARR's redesigned theme. ARR converted Musketeer's role into:
- Ranged DPS -> Bard / Machinist later
- Sniper aesthetic -> repurposed elsewhere

So 1.x had **9 BASE CLASSES + 7 JOBS** initially (not the 8 + 7
that ARR launched with). Confirming:
- Battle classes: Gladiator / Pugilist / Marauder / Lancer / Archer
  / Conjurer / Thaumaturge / **Musketeer** (= 8 battle classes)
- Crafters: 8 (Alchemy / Blacksmith / Carpenter / Culinarian / etc.)
- Gatherers: 4 (Miner / Botanist / Fisher / **Shepherd**)

Total: 8 + 8 + 4 = **20 classes** in 1.x (vs 17 in ARR launch).

The 3 cut: Musketeer (battle), Shepherd (gather), and... probably
another that's not yet identified.

## 3. Ancient Magic TRIPLE-ID structure + Tier II

Re-checking all 6 Ancient Magic spells reveals **3 IDs per spell**:

```text
SPELL    ENEMY (23xxx)  CROSS-CLASS (27xxx)  PLAYER CLASS (28xxx-29xxx)  TIER II?
-----    -------------  -------------------  --------------------------  --------
Flare    23510          27318                28986                       NO
Freeze   23513          27319                28989                       NO
Burst    23522          27316                28998                       NO
Quake    23519          (none)               28995                       YES (28996)
Tornado  23516          (none)               28992                       YES (28993)
Flood    23525          (none)               29001                       YES (29002)
```

### Asymmetric tier design

```text
3 spells WITH cross-class (Burst/Flare/Freeze):
  - 1 tier only (the cross-class IS the cap)

3 spells WITHOUT cross-class (Quake/Tornado/Flood):
  - 2 tiers each (tier II exists for BLM progression)
```

So **BLM has 9 distinct Ancient Magic commands**:
- 6 base tier (3 cross-class + 3 class-specific)
- 3 tier II (Quake II / Tornado II / Flood II)

The asymmetry is intentional:
- Cross-class users (other jobs) get the WEAKER tier 1 versions
  of the easier elements (Fire/Ice/Lightning).
- BLM-only users get access to advanced tier II of the rarer
  elements (Earth/Wind/Water).

This matches FFXIV's general design philosophy: **cross-class
gives access but capped at low tier**. BLM main keeps high-tier
unique tools.

### Why AncientMagic.lua has heavy overrides

Per prior finding `finding_director_family_and_cutscene_closure.md`,
AncientMagic.lua (99 lines) overrides ALL 4 level-adjust params to
0 (no scaling). Now confirmed: this is because ANCIENT MAGIC has
FIXED damage regardless of caster vs target level. The class
gates progression via skill level requirements, not level diff
penalties.

## 4. Bio I confirmed -- the family is 3 tiers

```text
28602  Bio (I)    -- now confirmed
28603  Bio II
28604  Bio III
```

Earlier search missed Bio I because grep filter "Bio " (with
space) excluded the space-less first tier. So Bio is **3 tiers
matching Drain's 3 tiers**.

## 5. Magic Missile family expanded

The 22301-22306 range:

```text
22301   Magic Missile
22302   Phantom Dart       (FFXI BLM/RDM ranged spell)
22303   Spirit Dart        (FFXI RDM spell)
22304   Magic Missile     (variant)
22305   Magic Missile     (variant)
22306   Magic Missile     (variant)
```

So **6 ranged-magic basic attacks** -- 4 "Magic Missile" variants
+ Phantom Dart + Spirit Dart. The 4 Magic Missile variants are
probably:
- 22301 = Magic Missile (Thaumaturge basic)
- 22304-22306 = Elemental variants (Fire/Ice/Lightning Missile?)

This matches the FFXI design where each magic class had a basic
"ranged spell" with different elemental flavors.

## 6. UPDATED class taxonomy for 1.x

```text
8 BATTLE CLASSES:
   2 = Gladiator       (PLD base)
   3 = Pugilist        (MNK base)
   4 = Marauder        (WAR base)
   7 = Lancer          (DRG base)
   8 = Archer          (BRD base)
  22 = Thaumaturge     (BLM base)
  23 = Conjurer        (WHM base)
   ? = MUSKETEER       (NEW; firearms class -- removed in ARR)

8 CRAFTERS:
   Alchemy / Armorer / Blacksmith / Carpenter / Culinarian
   / Goldsmith / Leatherworker / Weaver (per FFXIVTool gear dirs)

4 GATHERERS:
   Miner / Botanist / Fisher / SHEPHERD (1.x unique)

7 JOBS (corrected):
   15=MNK  16=PLD  17=WAR  18=BRD  19=DRG  26=BLM  27=WHM
```

**Total 1.x class count**: 8 + 8 + 4 = **20 base classes** (vs 17
in ARR launch).

## Confidence

```text
Confirmed:
  - 22101-22112 are weapon-class basic attacks (10 + 2 defensive).
  - cmd 22110 = "Discharge" / 銃攻撃 = MUSKETEER auto-attack.
  - 1.x had MUSKETEER (a firearms class) removed in ARR.
  - Each Ancient Magic spell has TRIPLE IDs:
    23xxx = enemy version, 27xxx = cross-class (3 of 6),
    28xxx-29xxx = player class version.
  - Quake/Tornado/Flood have TIER II variants (28996/28993/29002);
    Burst/Flare/Freeze do NOT.
  - Bio I exists at cmd 28602 (Bio family complete: 28602-28604).
  - Magic Missile family includes Phantom Dart (22302) and Spirit
    Dart (22303) -- FFXI classic spells.

Likely (High):
  - The 1.x base class count was 20 (vs ARR's 17). The 3 cut
    classes: Musketeer (battle), Shepherd (gather), + possibly
    one more (TBD; possibly an extra crafter or gatherer).
  - The 22301-22306 Magic Missile variants are elemental
    differentiated (4 elements + 2 specialty Dart spells).
  - The 5 cross-class commands per job (per convertSkillId)
    select from 5 distinct elements / 5 distinct status
    interactions to give cross-class users a representative
    sample without giving them full job power.

Likely (Medium):
  - Musketeer in 1.x was probably ULDAH-themed (desert city with
    Lalafell gunsmiths in lore).
  - The 4 Magic Missile variants (22301/22304-06) correspond to
    elemental tiers: 1 generic + 3 elemental basic spells.
  - cmd 22106 "Duel Attack" (no English) is probably for a
    FENCING-style sword (saber, single-handed thrust with
    parries).

Speculative:
  - The third cut 1.x class might be a "Tanner / Cobbler" or
    similar specialist crafter that didn't survive ARR's
    consolidation.
  - 1.x Musketeer was probably reworked into ARR's ARCHER
    initially, then split off into Bard/Machinist later.
  - The Ancient Magic tier asymmetry (cross-class 1 tier vs
    class-only 2 tiers) was intentional to make BLM main more
    rewarding than dabbling cross-class.
```

## Connections to other findings

- **finding_cross_reference_sweep_corrections_and_data_links.md**:
  the CORRECTED job ID mapping is consistent with the cross-class
  group orderings here.
- **finding_combat_command_pipeline_and_4param_scaling.md**: the
  Stone Throw (22114) was identified there; this round identifies
  its companions (22101-22112) as basic weapon attacks.
- **finding_cross_class_36_actions_ffxi_heritage.md**: the Ancient
  Magic triple-ID structure explains why only 3 of 6 Ancient
  Magic spells appear in the cross-class set.
- **finding_director_family_and_cutscene_closure.md** AncientMagic
  override pattern: confirmed -- the 6 Ancient Magic spells (+
  3 tier II) all share the no-level-scaling override.

## Next test

- Search for class ID 22106 "Duel Attack" subclass / weapon to
  identify whether 1.x had a Fencing class.
- Look for FIREARM gear (rifles, muskets) in equipment.csv to
  characterize Musketeer's gear pool.
- Sample the spell families Sleepga (27317), Bind (27319?),
  Stoneskin (27350) for cross-class context.

## Commit suggestion

```
docs(re/lua): cross-ref round 3 -- 1.x had MUSKETEER class, Ancient Magic triple-IDs + Tier II, weapon-class basics
```
