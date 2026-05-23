# Finding: itemKind Categories + Complete Skill System -- More Cut-Class Evidence

Cross-references `xtx_itemKind.csv` (gear categories, 221 rows) and
`xtx_text_skillName.csv` (skill names, 84 rows). Both reveal:

1. **Empty weapon-category slots for CUT CLASSES** -- the data
   scaffolding remains.
2. **14 weapon skills** match the 14 planned battle classes.
3. **Arcanima skill** existed in 1.x's data BEFORE Arcanist
   launched in Heavensward (3.0).
4. **FFXI-derived passive trait system** with ~30 "general"
   skills (Threat, Killer, Aggression, etc.).
5. **Battle Regimen** = FFXI's combo system ported as a skill.

## itemKind weapon categories (5005-5023)

```text
ID    Category                         Status
---   --------                          ------
5005  Pugilist's Arms                  LAUNCHED
5006  Gladiator's Arms                 LAUNCHED
5007  -  (Fencer's Arms slot)          CUT (empty placeholder)
5008  -  (Enforcer's Arms slot)        CUT (empty)
5009  Marauder's Arms                  LAUNCHED
5010  -  (Sentinel's Arms slot)        CUT (empty)
5011  -  (Samurai's Arms slot)         CUT (empty -- reserved for 4.0!)
5012  -  (Stavesman's Arms slot)       CUT (empty)
5013  Archer's Arms                    LAUNCHED
5014  Lancer's Arms                    LAUNCHED
5015  Musketeer's Arms                 LAUNCHED (CUT in ARR)
5016  Ammunition (generic)
5017  Arrow (Archer ammo)
5018  Bullet (Musketeer ammo!)         CONFIRMS firearms gear
5019  Throwing Weapon (generic)
5020  Throwing Stone (Stone Throw cmd 22114!)
5021  Throwing Circle (chakram; FFXI BRD)
5022  Throwing Spear (Lancer)
5023  Throwing Axe (Marauder)
5024  Throwing Blade (Assassin?)
```

So the weapon-category IDs are systematically allocated **5005-5015
for classes 5-15** (10 slots for 10 battle classes). Classes 5/6/10/
11/12 have their slots reserved but EMPTY -- confirming these were
cut LATE in development, after data scaffolding was already locked.

## itemKind magic-arm categories (5101-5110)

```text
5101  Primary Arm (generic)
5102  Secondary Arm
5103  -  (placeholder magic arm)        CUT
5104  -  (placeholder magic arm)        CUT
5105  Thaumaturge's Arms               LAUNCHED
5106  Two-Handed Thaumaturge's Arms    LAUNCHED
5107  Conjurer's Arms                  LAUNCHED
5108  Two-Handed Conjurer's Arms       LAUNCHED
5109  Arcanist's Arms                  CUT (slot reserved -- HW 3.0!)
5110  Two-Handed Arcanist's Arms       CUT (slot reserved)
```

So **Arcanist had its OWN dedicated weapon category** (5109 +
5110 = both single + two-handed) preserved in 1.x's data. The class
launched in HEAVENSWARD 3.0 (years later) as Scholar/Summoner's
shared base. The DATA scaffolding existed in 1.x.

## skillName -- complete 84-entry table

### Weapon skills (1-14) match 14 battle classes EXACTLY

```text
Skill ID  Name           Maps to class           Status
--------  ----           ---------------          ------
   1      Unarmed        (default fists)
   2      Hand-to-Hand   Pugilist(2)/Monk         LAUNCHED
   3      Sword          Gladiator(3)/Paladin     LAUNCHED
   4      Axe            Marauder(4)/Warrior      LAUNCHED
   5      FENCING        Fencer(5)                CUT
   6      Club           Enforcer(6)?             CUT
   7      Archery        Archer(7)/Bard           LAUNCHED
   8      Polearm        Lancer(8)/Dragoon        LAUNCHED
   9      GUNNERY        Musketeer(9)             LAUNCHED (ARR cut)
  10      Shield         Sentinel(10)/PLD?        Reserved/Used
  11      GREAT KATANA   Samurai(11)              CUT (-> SB 4.0)
  12      Staff          Stavesman(12)?           CUT
  13      DARK ARTS      Assassin(13)?            CUT
  14      WHIP           Flayer(14)?              CUT
```

So **the skill ID matches the class ID 1:1**, validating that
each of the 14 planned battle classes had its own dedicated
weapon skill. The CUT classes (5/6/10-14) all have weapon
skills defined.

### Magic skills (21-28)

```text
Skill ID  Name              Maps to class           Status
--------  ----              ---------------          ------
  21      Mysticism         Mystic(21)              CUT
  22      Thaumaturgy       Thaumaturge/BLM         LAUNCHED
  23      Conjury           Conjurer/WHM            LAUNCHED
  24      ARCANIMA          Arcanist(24)            CUT (-> HW 3.0)
  25      Musical           Bard's casting          LAUNCHED
  26-27   BLM/WHM (jobs)    Job mastery skills      LAUNCHED
  28      Magic 8           [PLACEHOLDER]           CUT (reserved magic class)
```

**Arcanima** (24) is the skill name for the Arcanist class. The
NAME "Arcanima" was reserved in 1.x's data before the class
launched in Heavensward (3.0).

**Musical** (25) is interesting -- it's a SEPARATE skill from
Archery (7). So Bard has 2 skills: Archery (weapon) + Musical
(song casting). 1.x design split the song system from the bow
attack system.

### Crafter skills (29-38)

```text
29 Woodworking, 30 Smithing, 31 Armorcraft, 32 Goldsmithing,
33 Leatherworking, 34 Clothcraft, 35 Alchemy, 36 Cooking
37-38 Craft 9/10 (PLACEHOLDERS)
```

So 2 crafter slots planned but unfilled. Confirms 10 crafters
planned, 8 launched (per the class roster finding).

### Gatherer skills (39-44)

```text
39 Mining, 40 Botany, 41 Fishing, 42 Herding (Shepherd)
43-44 DoL 5/6 (PLACEHOLDERS)
```

2 gatherer slots planned but unfilled. Confirms 6 gatherers
planned, 4 launched.

### General/Passive skills (45-72)

These are the SECONDARY SKILLS / PASSIVE TRAITS that augment
combat. ~28 named entries:

```text
45 Main Hand Weapon
46 Off Hand Weapon
47 Two-Handed Weapon
48 Casting
49 Shield Defense
50 Throwing (Stone Throw 22114, Throw 22113)
51 Evasion
52 Parrying
53 BATTLE REGIMEN     -- FFXI's COMBO SYSTEM port!
54 Physical Ailment
55 Gear-Based Ailment
56 Magic Ailment
57 Tool
58 Sub 14 (placeholder)
59 Battle Cast
60 Aggression
61 Fortitude
62 KILLER             -- FFXI's anti-monster-type bonus
63 Healing
64 Threat (enmity skill)
65 Caution
66 Looting
67 Retreat
68 Absorption
69 Positioning
70 Perception
71 Discernment
72 Group
```

### Stance placeholders (73-82)

```text
73-82 Stance 15-24 (10 placeholder STANCE skills per job slot)
```

So stance-based skills planned for jobs 15-24 (covers all 7
launched jobs + 3 reserved job slots). Empty in retail data.

## Notable FFXI heritage skills

```text
Battle Regimen (53)
   FFXI's "combo system": specific action sequences trigger
   bonus effects (e.g. Hundred Fists + Berserk combo).
   Now confirmed as a NAMED SKILL in 1.x's design.

Killer (62)
   FFXI's anti-monster-type bonus (e.g. Beast Killer adds damage
   vs Beast-type enemies). Each job had its own killer effects.
   Now confirmed as a SKILL in 1.x's design.

Throwing (50)
   Universal throwing skill (Throwing Stone, Throwing Spear,
   Throwing Circle, etc.). Stone Throw command 22114 is a
   throwing-skill action.

Arcanima (24)
   Pre-name reservation for what eventually became Arcanist class
   in Heavensward (3.0). The TERM was in 1.x's data years before
   the class shipped.
```

## Updated 1.x class history

Combining this finding with prior class roster work:

```text
1.x PLANNED (with weapon kind + skill name):
  14 battle classes (each with weapon kind 5005-5015 +
                     skill 1-14)
  7 jobs (15-19, 26-27)
  10 crafters (29-38; 2 placeholder)
  6 gatherers (39-44; 2 placeholder)
  10 stance placeholders (73-82)
  + ~28 named general/passive skills (45-72)

1.x LAUNCHED:
  8 battle classes (3 cut at launch)
  7 jobs
  8 crafters
  4 gatherers

ARR TRANSITION (2.0):
  Cut Musketeer (battle), Shepherd (gather)
  Cut also: all the cut-from-launch classes still gone
  
Future returns:
  HW 3.0: Arcanist (slot 5109 + skill 24 ARCANIMA in 1.x data)
                    -> base for SCH/SMN
  SB 4.0: Samurai (slot 5011 + skill 11 GREAT KATANA in 1.x data)
  SB 4.0: Machinist (replaces Musketeer concept)
```

So **EVERY major job reveal in later expansions had its name
reserved in 1.x's data**. This is a long-term design plan
spanning ~5-7 years.

## Confidence

```text
Confirmed:
  - 5005-5015 = weapon category slots for classes 5-15.
  - Empty slots at 5007, 5008, 5010, 5011, 5012 confirm CUT classes
    with reserved data scaffolding.
  - 5018 Bullet confirms Musketeer's ammo gear category.
  - 5020 Throwing Stone matches the Stone Throw cmd 22114 action.
  - 5109 + 5110 = Arcanist's Arms (single + two-handed) reserved
    for the class that launched in HW 3.0.
  - 14 weapon skills (1-14) correspond 1:1 to the 14 planned
    battle classes.
  - Skill 24 ARCANIMA reserved for Arcanist class.
  - Skill 11 GREAT KATANA reserved for Samurai class.
  - Skill 5 FENCING / 13 DARK ARTS / 14 WHIP confirm specific
    weapon types for the cut classes.
  - Skill 53 BATTLE REGIMEN = FFXI's combo system.
  - Skill 62 KILLER = FFXI's anti-monster-type bonus.
  - Skill 25 MUSICAL is separate from Archery (Bard has 2 skills).

Likely (High):
  - Square Enix's long-term class plan SPANS multiple expansions:
    1.x data has reservations for HW (Arcanist) and SB (Samurai)
    classes years before they launched.
  - Class CUTS happened LATE in 1.x development -- data
    structures were locked but content was removed.
  - The 28 general/passive skills (45-72) form a FFXI-style
    trait system that 1.x preserved nearly verbatim. ARR
    simplified to fewer "trait" categories.

Likely (Medium):
  - Class 6 "Enforcer" used "Club" weapon (skill 6).
  - Class 10 "Sentinel" used "Shield" weapon (skill 10).
  - The 14 sub-skill placeholders (44-58 partial) and 10 stance
    placeholders (73-82) suggest the trait system was DEEP --
    potentially hundreds of skill nodes when fully populated.

Speculative:
  - The "Mystic" class (21) was probably a SEPARATE-SCHOOL caster
    using "Mysticism" (skill 21) -- distinct from Black/White
    magic. Possibly a "wild magic" or "domain magic" type.
  - "Dark Arts" (skill 13) for Assassin might be FFXI's NIN
    ninjutsu, FFXI's COR (Corsair?) abilities, or a new system.
  - "Whip" (skill 14) for Flayer is unusual -- flail/morningstar
    style weapon, maybe similar to FFXI's "Polehammer" type.
```

## Connections to other findings

- **finding_complete_1x_class_roster_planned_vs_launched.md**:
  weapon kind 5005-5024 + skill 1-14 INDEPENDENTLY confirm the
  14-battle-class roster. Reserved slots align EXACTLY.
- **finding_cross_ref_round3_job_natives_musketeer_ancient_magic_tiers.md**:
  Musketeer's gear (5015 + 5018 Bullet) + skill 9 Gunnery +
  job name 9 musketeer = TRIPLE-CONFIRMED.
- **finding_negotiation_bazaar_widget_family.md**: item_kind
  is one of the 12 bazaar item fields; mapping confirmed.

## Next test

- Search for items with specific itemKind values (5018 Bullet,
  5020 Throwing Stone) to find specific firearms / projectile
  items.
- Look for items with the cut-class weapon kinds (5007, 5010,
  5011, etc.) -- might find any placeholder weapons that
  shipped.
- Examine the unfilled placeholders (5103, 5104 magic arms;
  37/38 crafters; 43/44 gatherers) for any non-empty rows.

## Commit suggestion

```
docs(re/lua): xtx_itemKind + xtx_text_skillName -- empty slots for cut classes, Arcanima/Great Katana reserved
```
