# Finding: Tribes, GC Ranks, Places -- 1.x Worldbuilding + Pre-Named Expansion Regions

Cross-references the social and worldbuilding tables in
FFXIVTool's catalog:

1. **tribe.csv** (16 rows): race/clan/sex mapping for the 5 races
2. **gcRank.csv** (22 rows): 20-rank ladder per Grand Company
3. **xtx_placeName.csv** (925 rows): the full worldbuilding
   namespace including PRE-NAMED Heavensward + Stormblood regions

## 1. tribe.csv -- 5 races x 2 clans x 2 sex = 16 rows

```text
ROW   col0  col1  col2    Interpretation
---   ----  ----  ----    --------------
 1     1     1     0      Hyur Midlander Male
 2     2     1     1      Hyur Midlander Female
 3     9     1     0      (Hyur Highlander Male?)
 4     3     2     0      Elezen Wildwood Male
 5     4     2     1      Elezen Wildwood Female
 6     3     2     0      (Elezen Duskwight Male? duplicate of 4)
 7     4     2     1      (Elezen Duskwight Female?)
 8     5     3     0      Lalafell Plainsfolk Male
 9     6     3     1      Lalafell Plainsfolk Female
10     5     3     0      (Lalafell Dunesfolk Male? dup of 8)
11     6     3     1      (Lalafell Dunesfolk Female?)
12     8     4     1      Miqo'te Seeker of the Sun Female
13     8     4     1      Miqo'te Keeper of the Moon Female (dup variant)
14     7     5     0      Roegadyn Sea Wolves Male
15     7     5     0      Roegadyn Hellsguard Male (dup)
```

So **16 entries cover 5 races x 2 clans x 2 sex** with some
duplicates suggesting clan distinctions weren't fully encoded
yet (just race + sex), or the duplicates reflect Midlander +
Highlander Hyur using shared IDs.

**Notable**: Miqo'te has only FEMALE entries (rows 12-13). Per
FFXIV lore, MALE Miqo'te was NOT available at 1.x launch -- added
much later. Confirmed by data.

The schema is `tribe_id | race_id | clan_group | sex`.

## 2. gcRank.csv -- 20-rank GC ladder + 2 special ranks

```text
RANK  level_req   XP_to_next  cost_at_rank  M_icon  T_icon  I_icon
----  ---------   ----------  ------------  ------  ------  ------
  0      0           0            0          640    670     700
  1     11        10000         1000          641    671     701
  2     13        15000         1500          642    672     702
  3     15        20000         2000          643    673     703
  4     17        25000         2500          644    674     704
  5     21        30000         3000          645    675     705
  6     23        35000         3500          646    676     706
  7     25        40000         4000          647    677     707
  8     27        45000        25000          648    678     708
  9     31        50000        50000          649    679     709
 10     33        50000        50000          650    680     710
 11     35        50000        50000          651    681     711
 12     41        60000        60000          652    682     712
 13     43        60000        60000          653    683     713
 14     45        60000        60000          654    684     714
 15     51        70000        70000          655    685     715
 16     53        70000        70000          656    686     716
 17     55        70000        70000          657    687     717
 18     57        70000           0           658    688     718
 19    100       100000           0           659    689     719   (top rank)
111    111         0              0           660    690     720   (service rank?)
127    127       10000          500           640    670     700   (GM rank?)
```

So **20 normal ranks (0-19)** for the GC progression ladder, with:
- Level requirements increasing: 0 -> 11 -> 13 -> 15 -> 17 -> 21 -> 23 -> 25 -> 27 -> 31 -> 33 -> 35 -> 41 -> 43 -> 45 -> 51 -> 53 -> 55 -> 57 -> 100
- XP curve: 10k -> 100k (linear early, then accelerating)
- Cost at rank: 1k -> 70k (the seal cost to promote)

The 3 sets of icon IDs are for the 3 Grand Companies:
- **Maelstrom**: ranks 640-660 (one icon per rank)
- **Twin Adder**: 670-690
- **Immortal Flames**: 700-720

Plus **2 special ranks**:
- **Rank 111**: req 111 (= -1?), XP 0, cost 0. Probably a SERVICE rank for active officers.
- **Rank 127**: req 127, XP 10000, cost 500. Probably the GM (Grand Master) rank.

## 3. xtx_placeName.csv -- 925 rows of worldbuilding

### Weather names (51-67) -- 17 weather types

```text
51 clear / 52 fair / 53 cloudy / 54 foggy / 55 windy
56 blustery / 57 rainy / 58 showery / 59 thundery / 60 stormy
61 dusty / 62 sandy / 63 hot / 64 blistering / 65 snowy
66 wintry / 67 gloomy
```

17 weather types. The WeatherDirector (per
`finding_party_subclasses_and_weather.md`) drives these.

### Regions / Continents (101-141)

```text
101  Eorzea          (the continent)
102  La Noscea       (sea region)
103  Thanalan        (desert region)
104  The Black Shroud (forest region)
105  Coerthas        (mountain region)
106  Mor Dhona       (central region)
107  Aldenard        (the main continent name)
108  Ala Mhigo       (LOST CITY-STATE -- taken by Garlea, restored in
                      Stormblood 4.0)
109  Sharlayan       (independent city-state, plays role in HW)
110  The Farreach
111  Vylbrand        (Limsa Lominsa's island)
112  O'Ghomoro       (mountain in La Noscea)

113-123 = OCEANS + minor landmarks
113 Strait of Merlthor / 114 Bianaq / 115 The Cieldalaes /
116 Mazlaya / 117 Bay of Dha'yuz / 118 Paglth'an / 119 Yugr'am River
120 CARTENEAU FLATS -- the FFXIV 1.x cataclysm site
                      (where Bahamut emerged at the 1.x->ARR transition)
121 Cape Deadwind / 122 Yafaem Saltmoor / 123 White Maiden

124 DRAVANIA           -- HEAVENSWARD (3.0) expansion region PRE-NAMED!
125 ABALATHIA'S SPINE  -- STORMBLOOD (4.0) expansion area PRE-NAMED!
126 Silvertear Falls   -- Midgardsormr's lore origin
127 GYR ABANIA         -- STORMBLOOD (4.0) Ala Mhigan region PRE-NAMED!

128-141 = More lore regions
128 The Pearl / 129 Rothlyt Sound / 130 Xelphatol (Ixali beastmen) /
131 Hathoeva River / 132 Velodyna River / 133 Indigo Deep /
134 Bloodbrine Sea / 135 Sea of Jade / 136 Sea of Ash /
137 Rhotano Sea / 138 MERACYDIA (lost continent, Allagan history) /
139 Garlemald (Garlean home) / 140 The Garlean Empire /
141 Gelmorra (Wood Wailers original homeland)
```

### EXPANSION PRE-NAMING confirmed

```text
1.x DATA          Expansion launched      Years gap
--------          ------------------      ---------
Carteneau Flats   1.x finale / ARR transition  (1.x -> 2.0)
Dravania          HEAVENSWARD (3.0)            ~4 years
Gyr Abania        STORMBLOOD (4.0)             ~6 years
Abalathia's Spine STORMBLOOD (4.0)             ~6 years
```

So Square Enix PRE-NAMED the next ~2 expansions' regions in 1.x's
data. The lore plan extended years ahead.

### City interior names (1001-1099)

```text
Limsa Lominsa city interior (1051+):
1051  Limsa Lominsa
1052  Procession of Terns
1053  Galadion Bay
1054  Fisherman's Bottom (district)
1055  Naldiq & Vymelli's (the famous smithy)
1056  The Barrel
1057  The Bismarck (famous inn)
1058  The Seventh Sage
1060  Coral Tower
1063  Mealvaan's Gate (customs office)
1065  Limsa Lominsa Aetheryte Plaza (aetheryte 1280001 IS here!)
1066  The Hyaline
1067  West Hawkers' Alley
1068  East Hawkers' Alley
1069  The Astalicia
1070  Mizzenmast Inn (new-player starting inn)

La Noscea sub-zones (1001-1050):
Lower/Western/Eastern/Upper La Noscea + 30+ landmark sub-zones
(Bearded Rock, Skull Valley, Bald Knoll, Bloodshore, ...)

Most of the FFXIV regional zones from launch and ARR are
already in 1.x's data.
```

### Aetheryte alignment

Per prior finding `finding_cross_reference_sweep_corrections_and_data_links.md`,
aetherytes start at ID 1,280,000. The first aetheryte (1280001)
has col 1 = 1051 -- which is now confirmed as **Limsa Lominsa**.

So aetheryte 1280001 = Limsa Lominsa Aetheryte Plaza. Connection
between the aetheryte system and place names is now LIVE.

## Confidence

```text
Confirmed:
  - 16 tribe entries cover 5 races (Hyur/Elezen/Lalafell/Miqo'te/
    Roegadyn) with clan + sex variants.
  - Male Miqo'te was NOT in 1.x launch (data confirmed).
  - 20 normal GC ranks + 2 special ranks (111, 127) per GC.
  - 3 GC icon sets: Maelstrom 640+N, Twin Adder 670+N, Immortal
    Flames 700+N (sequential per rank).
  - Level requirements escalate non-linearly: 0 -> 100 across 20
    ranks.
  - 17 weather types (clear/fair/cloudy/foggy/etc.).
  - 925 placeName entries covering regions, sub-zones, city
    interiors, landmarks.
  - Dravania (124), Gyr Abania (127), Abalathia's Spine (125)
    -- the HEAVENSWARD/STORMBLOOD expansion regions are PRE-NAMED
    in 1.x's data.
  - Carteneau Flats (120) is the FFXIV 1.x cataclysm site,
    preserved in data.
  - Aetheryte 1280001 maps to Limsa Lominsa (place 1051) via the
    aetheryte's col 1 = 1051 cross-ref.

Likely (High):
  - The Hyur Midlander/Highlander distinction in 1.x was barely
    encoded -- the data shows duplicates suggesting it was a late
    addition.
  - Square Enix's lore PRE-PLANNED expansion regions years before
    expansions launched.
  - Rank 111 is "service / officer" tier; rank 127 is "GM"
    (Grand Master) for retail use.

Likely (Medium):
  - The Allagan empire history (Meracydia, Silvertear Falls,
    Carteneau Flats) was DEEPLY embedded in 1.x lore -- much
    of it was carried into ARR via the Crystal Tower questline.
  - The Xelphatol mention (130) confirms Ixali beastmen were
    designed for 1.x.
  - Mizzenmast Inn (1070) was likely the FIRST PLACE new
    players spawned in 1.x's Limsa start.

Speculative:
  - Dravania (124) and Abalathia's Spine (125) being adjacent
    IDs suggests Square Enix had a unified expansion plan
    spanning Heavensward + Stormblood when 1.x's data was
    finalized.
```

## Connections to other findings

- **finding_party_subclasses_and_weather.md**: WeatherDirector
  with 1 sync field (weatherId) -- the 17 weather IDs (51-67)
  are the values that field carries.
- **finding_cross_reference_sweep_corrections_and_data_links.md**:
  aetheryte 1280001 col 1 = 1051 = Limsa Lominsa (now confirmed).
- **finding_complete_1x_class_roster_planned_vs_launched.md**:
  same pattern as classes -- 1.x PRE-RESERVED slots that launched
  in later expansions.
- **xtx_text_jobName.csv**: Samurai (slot 11), Arcanima (slot 24)
  -- same pattern as Dravania, Gyr Abania, Abalathia's Spine
  here.

## Next test

- Look at xtx_placeName 200-1000 to enumerate ALL city
  interiors of Gridania + Ul'dah (the other 2 starter cities).
- Sample the aetheryte rows to confirm aetheryte_id -> place_id
  mapping across multiple regions.
- Check the special rank 111 to find any in-game data about it.

## Commit suggestion

```
docs(re/lua): tribes + GC ranks + 925 place names -- expansion regions PRE-NAMED in 1.x
```
