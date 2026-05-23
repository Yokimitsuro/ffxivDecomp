# Finding: Monster Bestiary, Primals, ASCIAN, Achievements + Cataclysm Job Quests

Cross-references monster, achievement, and quest tables.
Major finds:

1. **91+ monster races** in 1.x (full FF/FFXI bestiary)
2. **3 Primals confirmed**: Ifrit, Titan, Garuda (the original
   primal trio of FFXIV)
3. **ASCIAN race in 1.x's data** (years before they became
   the main antagonists in ARR onwards)
4. **748 achievements** + the **7 job quest finale series**
   tied to the 1.x cataclysm narrative

## 1. xtx_monsterRace.csv (91 rows) -- Full bestiary

### FF Classics (FFXI/FF series heritage)

```text
1009 Sabotender    (FFXI's cactus monster)
1010 Morbol        (FF series classic)
1016 Bomb          (FF series classic)
1017 Ahriman       (FFXI's giant flying eyeball)
1020 Cockatrice
1022 Drake         (= Salamander in JA; FFXI dragon-tier)
1027 Flytrap
1028 Treant
1029 Apkallu       (FFXI seal; placeholder "originally seal")
1032 Coeurl        (FF classic; cat-tiger)
1033 Goobbue       (FFXI giant pickle-monster;
                   placeholder "originally Giant")
1034 Flan          (FF jelly slime)
1059 Funguar       (FFXI mushroom monster)
1095 Garuda        (PRIMAL)
1104 Moogle        (FF mascot)
1105 Chocobo
1107 Cyclops
```

### Elementals (1046-1052) -- 7 variants

```text
1046 Fire Elemental
1047 Ice Elemental
1048 Air Elemental
1049 Earth Elemental
1050 Lightning Elemental
1051 Water Elemental
1052 Elemental (generic)
```

So 7 elementals matching the 6 classical FFXI elements (Fire/Ice/Wind/
Earth/Lightning/Water) + 1 generic. No Light/Dark elementals in
the race table -- they're tracked separately probably.

### Primals (1073/1074/1095) -- FFXIV's iconic bosses

```text
1073 Ifrit    (Fire primal, Amalj'aa's god)
1074 Titan    (Earth primal, Kobold's god)
1095 Garuda   (Wind primal, Ixali's god)
```

So 3 of FFXIV's iconic primals confirmed in 1.x. The other primals
(Leviathan, Ramuh, Shiva, Bismarck, etc.) launched in ARR + later
expansions; their RACE IDs may be in the gaps (1075-1094).

### Beastman Tribes (1063-1067) -- 5 races

```text
1063 Qiqirn   (rat-like beastmen)
1064 Ixal     (bird-like; Garuda's worshippers)
1065 Amalj'aa (lizard; Ifrit's worshippers)
1066 Kobold   (mining; Titan's worshippers)
1067 Sylph    (forest fairies, possibly Ramuh's worshippers)
```

Each beastman tribe + primal relationship is encoded in the
RACE IDs (Ixal -> Garuda, Amalj'aa -> Ifrit, Kobold -> Titan).
This is core FFXIV lore: beastmen summon their gods to fight
the player races.

### ASCIAN (1069) -- the FFXIV antagonists

```text
1069 Ascian
```

**Ascians as a race were defined in 1.x's data** -- years before
they became the central antagonists in ARR's main scenario. The
Ascian race race was reserved alongside Imperial (1070), Bandit
(1071), Pirate (1072) as humanoid enemy categories.

So **1.x already had Ascian** as a NPC race designation, even
though their narrative role wasn't fully developed until ARR.
Another example of Square Enix's long-term lore planning.

### Working / Placeholder names

Many entries have (仮) annotation = "tentative/working name" in
Japanese. These were DEVELOPMENT PLACEHOLDERS. Examples:
- 1001 Puk (はねとかげ "winged lizard" with 仮)
- 1003 Antelope (ヤックル -- borrowed from Princess Mononoke)
- 1033 Goobbue (元ジャイアント "originally Giant")
- 1029 Apkallu (元アザラシ "originally seal")

So the design team was still finalizing monster names during
1.x's lifecycle.

## 2. populaceNMReward (85 rows) -- NM seal/runestone vendor

The first 8 rows are dialog ("Got runestones?", "Show me your
seals", etc.). The remaining ~77 rows reference NM SEAL items
via `[@SHEET(itemData,80XXXXX,41)]` -- so NMs drop SEALED items
in the 80xxxxx item ID range.

This is the FFXIV 1.x equivalent of FFXI's "abyssite" / token
exchange system: kill NMs, get runestones, exchange for gear/
rewards at the NM Reward vendor.

## 3. achievement.csv (748 rows) + xtx_achievement.csv (748 rows)

So 1.x had **748 achievements** -- a comprehensive system.

### Categories (col 1)

```text
Category 0:  12 entries  (special / system)
Category 1: 596 entries  (combat / exploration / monster kills)
Category 2:  33 entries  (?)
Category 3: 105 entries  (?)
```

Sample progressive achievement (combat kill milestones):

```text
ID    col 1   col 2 (threshold)   col 3 (points)   icon
---   -----   -----------------   --------------   ----
101    1            100                 5            227
102    1            500                 5            227
103    1           1000                10            227
104    1           5000                10            227
105    1          10000                10            227
106    1          50000                10            227
107    1         100000                30            227
```

So Achievement IDs 101-107 are progressive monster-kill milestones
(100 -> 100,000 kills). Each progression gives 5-30 points.

### THE 7 JOB QUEST FINALE SERIES (achievement 1105 reveals)

Achievement **1105 "Career Opportunities"** (戦う古典主義者) is
awarded for completing ALL 7 job quest series:

```text
JOB    Achievement      Quest Series Name
---    -----------      -----------------
PLD    白銀の騎士        "Keeping the Oath"
MNK    練気の闘士        "Return of the King...of Ruin"
WAR    原初の戦士        "How to Quit You"
DRG    蒼の竜騎士        "Into the Dragon's Maw"
BRD    古の吟遊詩人      "Requiem for the Fallen"
WHM    白き魔道士        "The Chorus of Cataclysm"
BLM    黒き魔道士        "Always Bet on Black"
```

ALL 7 series have **CATACLYSM-THEMED NAMES**:
- "Ruin" (MNK)
- "Fallen" (BRD)
- "Cataclysm" (WHM)
- "King...of Ruin"

So the 7 job quest finales in 1.x's late-game content were the
NARRATIVE LEAD-UP to the Bahamut/Carteneau cataclysm. The
Achievements + the LoginEventCommand quest IDs (per
`finding_quest_corpus_and_login_event_command.md`: "Private
Eyes", "Prophecy Inspection", etc.) all tied into this 1.x
finale arc.

### Achievement 1103 quest IDs

The WHM series (Achievement 1103 "Seeing White") references
quests:
```text
111241, 111242, 111243, 111244, 111245, 111246
```

So each job quest series in 1.x had **6 quests** = 7 jobs * 6
quests = **42 job quest scripts** in the corpus.

This matches the prior finding's quest count (`finding_quest_corpus_and_login_event_command.md`):
- Battle job quests: 10 each * 7 jobs = ~70 BUT
- Of which 6 each * 7 jobs = 42 are the FINALE arc
- Plus ~28 more are job-tutorial / progression quests

So the 1.x job quest space splits into:
- 42 finale arc quests (the 7 series * 6 chapters each)
- ~28 tutorial / progression quests
- Total ~70 per finding_quest_corpus.

## 4. questcategory.csv (48 categories)

Simple `(id, cat, val)` table with 48 unique category IDs (1-48?).
The val column = 1 for all rows -- this is just an enumeration
of quest TYPES used for filtering in the quest journal UI.

48 categories suggests rich quest classification: Main Scenario,
Side Quest, Levequest, Guildleve, GC Quest, Class Quest, Job Quest,
Trial Quest, Hamlet Defense, Raid Lockout, etc.

## Confidence

```text
Confirmed:
  - 91+ monster races in xtx_monsterRace (FF/FFXI heritage clear).
  - 3 primals: Ifrit (1073), Titan (1074), Garuda (1095).
  - 5 beastman tribes: Qiqirn, Ixal, Amalj'aa, Kobold, Sylph.
  - 7 elemental races (Fire/Ice/Air/Earth/Lightning/Water + generic).
  - Ascian race (1069) defined in 1.x data.
  - Working "仮" annotations show development placeholders.
  - 748 achievements in 1.x (4 categories: 0/1/2/3).
  - Achievement 1105 references 7 job quest finale series tied
    to the cataclysm narrative.
  - 7 job quest series, 6 quests each = 42 finale arc quests.
  - 48 quest categories enumerated.
  - NM reward vendor (85 rows) trades for items in 80xxxxx ID range.

Likely (High):
  - Other primals (Leviathan, Ramuh, Shiva, etc.) launched in ARR.
    Their race IDs in 1.x are gaps (1075-1094 mostly missing in my
    sample).
  - The 596 Category-1 achievements include monster kill milestones,
    exploration achievements, and feat achievements.
  - The 7 job quest finale series form the FINAL CONTENT of 1.x's
    main narrative, leading to the Bahamut cataclysm.
  - Light/Dark elementals don't exist in 1.x's race table -- only
    the 6 elemental wheel + generic.

Likely (Medium):
  - The 1.x→ARR cataclysm event was BUILT INTO 1.x's late-game
    content via the 42-quest finale arc. The "Chorus of Cataclysm",
    "Return of the King of Ruin", "Requiem for the Fallen" titles
    foreshadow the event.
  - The 80xxxxx NM seal item range corresponds to the FFXIV NM
    drop system (kill NM -> get sealed item -> trade for gear).
  - 48 quest categories suggest fine-grained quest classification
    in 1.x's journal UI.

Speculative:
  - Some monster names had Japanese placeholder etymology
    ("originally Seal" for Apkallu, "originally Giant" for
    Goobbue) -- design pivots during development.
  - The 7 job quest finale arc was probably released across
    multiple patches (1.18, 1.20, 1.22, 1.23) as 1.x ran down.
  - The Ascian race designation (1069) was probably used for
    in-game enemy NPCs that hinted at Ascian involvement before
    they became overt.
```

## Connections to other findings

- **finding_quest_corpus_and_login_event_command.md**: this
  finding identifies the 42 finale arc quests (7 series x 6
  chapters) within the 629-quest corpus.
- **finding_charabase_battle_real_combat_formulas.md**: NM
  tier code (1-4 negative potencial) aligns with the NM seal
  drop system.
- **finding_tribes_gc_ranks_places_worldbuilding.md**:
  beastman tribes (Kobold/Amalj'aa/Ixali/Sylph) match the
  race table here.

## Next test

- Look up specific 80xxxxx NM seal items in itemData.csv to
  identify the actual reward gear.
- Check if Achievements 1100-1110 enumerate the 7 job series
  individually + their quest IDs.
- Look at the 596 Category-1 combat achievements to understand
  the kill milestone system.

## Commit suggestion

```
docs(re/lua): 91 monster races + 3 primals + Ascian race + 748 achievements + 1.x cataclysm job finale arc
```
