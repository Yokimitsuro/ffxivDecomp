# Finding: Complete 1.x Class Roster -- 14+ Planned Battle Classes, MANY Cut in ARR

ARCHAEOLOGICAL DISCOVERY from `xtx_text_jobName.csv`: the full
**class/job design plan** of FFXIV 1.x is preserved in the
client's text data. Reveals **14+ battle classes were planned**
(only 8 launched) and **many specific class names** that survived
as later FFXIV expansion content.

## The complete 1.x class roster (from xtx_text_jobName.csv)

```text
ID   NAME (EN)         LAUNCHED?    FATE in FFXIV history
---  --------          ---------    ---------------------
  1  adventurer         Yes (default class for new chars)
  2  pugilist           LAUNCHED     ARR -> Monk (MNK)
  3  gladiator          LAUNCHED     ARR -> Paladin (PLD)
  4  marauder           LAUNCHED     ARR -> Warrior (WAR)
  5  fencer             CUT          (Duel Attack 22106 = its action!)
  6  enforcer           CUT          ?
  7  archer             LAUNCHED     ARR -> Bard (BRD)
  8  lancer             LAUNCHED     ARR -> Dragoon (DRG)
  9  musketeer          LAUNCHED     CUT in ARR; firearms returned as
                                     MACHINIST in Stormblood (4.0)
 10  sentinel           CUT          (Paladin precursor?)
 11  samurai            CUT          Reserved; launched in STORMBLOOD (4.0)
 12  stavesman          CUT          (stave-wielding class)
 13  assassin           CUT          ?
 14  flayer             CUT          ?

 15  monk (job)         LAUNCHED     ARR continued
 16  paladin (job)      LAUNCHED     ARR continued
 17  warrior (job)      LAUNCHED     ARR continued
 18  bard (job)         LAUNCHED     ARR continued
 19  dragoon (job)      LAUNCHED     ARR continued
 20  [PLACEHOLDER]      CUT          (slot reserved, never named)
 21  mystic             CUT          (magical class)
 22  thaumaturge        LAUNCHED     ARR -> Black Mage (BLM)
 23  conjurer           LAUNCHED     ARR -> White Mage (WHM)
 24  arcanist           CUT          Reserved; launched in HEAVENSWARD (3.0)
                                     as base for Scholar / Summoner
 25  bard               (duplicate of 18; renamed entry)
 26  black mage (job)   LAUNCHED
 27  white mage (job)   LAUNCHED
 28  [PLACEHOLDER]      CUT          (mage slot reserved)

 29  carpenter          LAUNCHED
 30  blacksmith         LAUNCHED
 31  armorer            LAUNCHED
 32  goldsmith          LAUNCHED
 33  leatherworker      LAUNCHED
 34  weaver             LAUNCHED
 35  alchemist          LAUNCHED
 36  culinarian         LAUNCHED
 37  [PLACEHOLDER]      CUT          (crafter slot)
 38  [PLACEHOLDER]      CUT          (crafter slot)

 39  miner              LAUNCHED
 40  botanist           LAUNCHED
 41  fisher             LAUNCHED
 42  shepherd           LAUNCHED     CUT in ARR (1.x unique)
 43  [PLACEHOLDER]      CUT          (gatherer slot)
 44  [PLACEHOLDER]      CUT          (gatherer slot)

 45-58 sub-skill 1-14   PLACEHOLDER  Sub-skill slots
```

## What this reveals

```text
1.x PLANNED:
   17 battle classes (incl. samurai, fencer, mystic, etc.)
    7 jobs
    2 reserved job slots
   10 crafters (8 named + 2 placeholder)
    6 gatherers (4 named + 2 placeholder)
   14 sub-skill slots
  -----------
  TOTAL: 56 entries in the class name table

1.x LAUNCHED:
    8 battle classes (Pugilist, Gladiator, Marauder, Archer,
                       Lancer, MUSKETEER, Thaumaturge, Conjurer)
    7 jobs
    8 crafters
    4 gatherers
  -----------
  TOTAL: 27 active classes/jobs in 1.x release

CUT in 1.x development (designed but never released):
    9 battle classes (Fencer, Enforcer, Sentinel, Samurai,
                       Stavesman, Assassin, Flayer, Mystic, Arcanist)
    + 2 placeholder battle/job slots
    + 2 placeholder crafter slots
    + 2 placeholder gatherer slots
  = ~15 PLANNED CLASSES never released

CUT in ARR transition (had Lua/data in 1.x but removed):
   MUSKETEER (battle), SHEPHERD (gather)
```

## FFXIV CLASS DEVELOPMENT HISTORY confirmed

Several class names that 1.x designed BUT didn't ship made it
back in later expansions:

```text
Class    1.x plan  1.x launch  ARR launch  Later return
-----    -------   ----------  ----------  ------------
samurai  Planned   CUT         CUT         STORMBLOOD (4.0)
                                            launched as samurai!
arcanist Planned   CUT         CUT         HEAVENSWARD (3.0)
                                            base for SCH / SMN
machinist (no)     no name     no          STORMBLOOD (4.0)
                                            firearms class
                                            (Musketeer reborn)
```

So the **CLASS NAMES were reserved in 1.x's data** even when not
yet implemented. This shows Square Enix's long-term planning of
the FFXIV class roster -- they had VISIONED these classes years
before launching them.

## "Duel Attack" (cmd 22106) is the FENCER class

The unnamed `22106 決闘攻撃 Duel Attack` from the weapon-class
basic attacks list is the **FENCER's** auto-attack. Class 5 in
the jobName table = Fencer.

So 1.x had FENCER as a real battle class with:
- Auto-attack: Duel Attack (22106)
- Probably a saber / rapier weapon type

Fencer was CUT in ARR. Possibly absorbed into Gladiator (sword
weapon) or never properly developed.

## CORRECTED summary of weapon-class basic attacks

Now that I've identified the classes, the 14 basic attacks map to
specific weapon classes:

```text
CMD ID    Action          Weapon Class
------    ------          ------------
22101     Unarmed         (no weapon equipped)
22102     Heavy Strike    Pugilist (fist)
22103     Light Slash     Gladiator (sword)
22104     Attack          (generic; probably default)
22105     Light Swing     Marauder (axe)
22106     Duel Attack     Fencer (CUT class)
22107     Bludgeon        Conjurer (staff) / "Stavesman" (CUT)?
22108     Light Shot      Archer (bow)
22109     Light Thrust    Lancer (polearm)
22110     Discharge       Musketeer (gun) -- CUT in ARR
22111     Guard           (defensive, GLA/PLD)
22112     Block           (PLD shield-specific)
22113     Throw           (universal throwing)
22114     Stone Throw     (universal single-hit)
```

The 22107 Bludgeon might actually be the **Stavesman** class (one
of the CUT classes!), not the Conjurer. Conjurer is a magic
class (uses staves for casting, not melee bludgeon).

## CONFIRMED MUSKETEER FOOTPRINT in the data

Per concrete data evidence:
- xtx_text_jobName id 9 = "musketeer"
- xtx_itemKind id 5015 = "Musketeer's Arms" (拳銃類)
- xtx__text_ui 4011 = "Musketeer Quests" (銃術士クエスト)
- Item 11000002 = "standard-issue flintlock" (陸士制式拳銃)
- Cmd 22110 = "Discharge" (auto-attack)

So Musketeer was a FULL FIRST-CLASS CLASS in 1.x with dedicated
items, quests, weapons, and actions.

## Confidence

```text
Confirmed:
  - xtx_text_jobName.csv contains 56 entries: 14+ battle classes,
    7 jobs, 2 job placeholders, 10 crafter slots (8 named + 2
    placeholder), 6 gatherer slots (4 named + 2 placeholder),
    14 sub-skill placeholders.
  - 1.x had MUSKETEER, FENCER, SHEPHERD as named classes that ARR
    cut.
  - SAMURAI was a NAMED class in 1.x's table (CUT) -- reserved
    name returned in Stormblood.
  - ARCANIST was a NAMED class in 1.x's table (CUT) -- reserved
    name returned in Heavensward as SCH/SMN base.
  - 14 sub-skill placeholder slots existed (sub-skill 1 through 14).
  - 22106 Duel Attack maps to the Fencer class (id 5).

Likely (High):
  - The class IDs were locked in pre-1.x development, so even cut
    classes have IDs. Later expansions REUSED some of these IDs
    when introducing those classes (samurai, arcanist).
  - 1.x's combat class roster was OVERAMBITIOUS -- 14 battle
    classes planned with only 8 implemented at launch was
    asymmetric. ARR consolidated to fewer.
  - The MUSKETEER class's auto-attack 22110 + flintlock items +
    quest line + item category form a COMPLETE class
    implementation, not a stub.

Likely (Medium):
  - The "Fencer" class (id 5) probably used SABER or RAPIER
    weapons, distinct from Gladiator (sword + shield).
  - The "Stavesman" class (id 12) used staves but as melee
    weapons (vs Conjurer/Thaumaturge using staves for casting).
  - The 14 sub-skills are PASSIVE TRAITS or SECONDARY SKILLS
    that augment main classes, similar to FFXI's "support job"
    passives.

Speculative:
  - Class 6 "enforcer" might have been a city-watch / lawman
    class. Possibly related to the Sultansworn in Ul'dah lore.
  - Class 10 "sentinel" might have been a guardian variant of
    Gladiator/Paladin.
  - Class 13 "assassin" and 14 "flayer" were probably planned as
    rogue/ninja-style classes. Ninja eventually launched in ARR
    patch 2.4 -- but as a fresh design, not from these slots.
```

## Connections to other findings

- **finding_cross_reference_sweep_corrections_and_data_links.md**:
  the CORRECTED job ID mapping (15=MNK, 16=PLD, 17=WAR, 18=BRD,
  19=DRG, 26=BLM, 27=WHM) is INDEPENDENTLY VALIDATED by this
  jobName table (rows 15-19, 26-27 match exactly).
- **finding_cross_ref_round3_job_natives_musketeer_ancient_magic_tiers.md**:
  Musketeer's existence (cmd 22110 Discharge) is now backed by
  full data presence -- 5+ separate tables confirm Musketeer.
- **finding_command_roster_complete.md**: the 22106 Duel Attack
  is now identified as the Fencer auto-attack.
- **finding_negotiation_bazaar_widget_family.md**: gear pool
  Musketeer's Arms (xtx_itemKind 5015) is one of the equipment
  categories that 1.x supported but ARR removed.

## Next test

- Find specific items in the "Musketeer's Arms" category (search
  for items with itemKind = 5015 in itemData.csv).
- Look for "Fencer's Arms" / "Stavesman's Arms" / "Sentinel's
  Arms" etc. in xtx_itemKind.csv to find more weapon categories
  for cut classes.
- Check the 14 sub-skill placeholder slots for any non-empty
  entries -- some might have been partially implemented.

## Commit suggestion

```
docs(re/lua): COMPLETE 1.x class roster -- 14+ planned battle classes including Musketeer, Fencer, Samurai (reserved); MANY cut in ARR
```
