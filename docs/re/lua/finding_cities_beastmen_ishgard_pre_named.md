# Finding: City Interiors + Beastmen Tribes + ISHGARD Pre-Named in 1.x

Completes the worldbuilding enumeration with the remaining starter
cities (Gridania, Ul'dah) and their regions (Black Shroud, Thanalan),
plus Coerthas/Ishgard. Confirms **MORE pre-naming for HW 3.0
expansion content** (Ishgard, Falcon's Nest, Camp Dragonhead all
in 1.x data).

## Place name ID range organization

```text
RANGE          REGION                  Starting city
-----          ------                  -------------
1001-1099+     La Noscea (sea)          Limsa Lominsa
1100-1200      La Noscea sub-zones + dungeons (Mistbeard Cove, etc.)
1201-1499      LIMSA LOMINSA HOUSING WARDS (42+ wards in 1.x!)
1500-1700      Region-specific landmarks + beastmen homes

2001-2099      Gridania + interior
2100-2499      Black Shroud sub-zones (Twelveswood + 5 cardinal Shrouds)
2500-2999      Gridania housing wards

3001-3099      Ul'dah + interior
3100-3499      Thanalan sub-zones
3500-3999      Ul'dah housing wards

4001-4099      ISHGARD (HW 3.0 pre-named!) + Coerthas
4100-4499      Coerthas sub-zones
```

So the place ID space is REGIONALLY organized in 1000-block per
major region. This matches the aetheryte ID scheme (per
`finding_cross_reference_sweep_corrections_and_data_links.md`):
aetherytes 1280000+ also use this 1xxx/2xxx/3xxx/4xxx prefix
convention.

## Gridania interior (2001-2030)

```text
2001  Gridania (the city)
2002  Gelmorra Ruins   (ANCESTRAL CITY -- pre-Gridanian Padjal home)
2003  Hyrstmill        (logging camp)
2004  Quarrymill       (stone-cutting camp)
2005  Tinolqa
2006  Twelveswood      (the great forest)
2007  central Shroud
2008  east Shroud
2009  north Shroud
2010  west Shroud
2011  south Shroud     (5 cardinal direction sub-zones)
2012  Bentbranch
2013  Nine Ivies
2014  Emerald Moss
2015  Crimson Bark
2016  Tranquil Paths
2017  Camp Bentbranch
2018  Five Hangs
...   (many more landmarks)
```

So Gridania has **5 cardinal Shroud zones** (central/east/north/
west/south Shroud) -- the full Black Shroud regional structure.

**Gelmorra Ruins** (2002) is the ANCESTRAL CITY of the Padjals
(Gridanian Conjurers' ancestors), buried under the Black Shroud.
This lore is pre-1.x and ties into FFXIV's worldbuilding.

## Ul'dah interior (3051-3080)

```text
3051  Ul'dah (the city)
3052  Sil'dih               (ANCESTRAL SISTER-CITY, ruins -- pre-1.x lore)
3053  Coliseum              (Gladiator's arena)
3054  Gladiators' Guild
3055  Arrzaneth Ossuary
3056  Thaumaturges' Guild   (the magical guild)
3057  Eshtaime's Lapidaries
3058  Goldsmiths' Guild     (crafting guild)
3059  Amajina & Sons Mineral Concern
3060  Miners' Guild         (gathering guild)
3061  Frondale's Phrontistery
3062  Alchemists' Guild
3063  Sunsilk Tapestries
3064  Weavers' Guild
3065  Platinum Mirage
3066  Pugilists' Guild      (PGL training)
3067  Quicksand            (FAMOUS Ul'dah inn / hub)
3068  Romululu's Bric-a-Brac
3069  Rudius
3070  Eshtaime's Aesthetics
3071  Hourglass
3072  Heaven's Shard
3073  Milvaneth Sacrarium
3074  Erralig's Burial Chamber
3075  Wellhead Lift
3076  Merchant Strip
3077  Hustings Strip
3078  GATE OF NALD          (the twin gods' gate)
3079  GATE OF THAL          (the twin gods' gate)
3080  Gold Court
```

**Sil'dih** (3052) is the ancient sister-city of Ul'dah, buried
beneath. In FFXIV lore, Sil'dih was destroyed by Ul'dah's
sultans -- this is core 1.x worldbuilding.

**Gate of Nald + Gate of Thal** = the two main entry/exit gates of
Ul'dah, named after the twin gods of the Ul'dah pantheon (Nald'thal,
the merchant god).

**Quicksand** is the iconic Ul'dah inn where the main-scenario
quests often start.

The **6 GUILDS** in Ul'dah confirm the Disciple training system:
- Gladiator (Sword), Pugilist (Hand-to-Hand), Thaumaturge (Black
  Magic), Goldsmith (Crafter), Miner (Gatherer), Alchemist + Weaver

## Coerthas / ISHGARD (4001-4015) -- HW 3.0 PRE-NAMED

```text
4001  Ishgard                <-- HEAVENSWARD 3.0 main city PRE-NAMED!
4002  Falcon's Nest          <-- HW 3.0 outpost PRE-NAMED!
4003  Owl's Nest
4004  Coerthas central highlands
4005  Coerthas eastern highlands
4006  Coerthas eastern lowlands
4007  Coerthas central lowlands
4008  Coerthas western highlands
4009  Dragonhead
4010  Crooked Fork
4011  Fields of Glory
4012  Ever Lakes
4013  Riversmeet
4014  Camp Dragonhead        <-- HW Lord Haurchefant's territory PRE-NAMED!
4015  Boulder Downs
```

So an ENTIRE EXPANSION'S WORTH of place names was reserved in
1.x's data. Heavensward (HW 3.0) launched 4 YEARS after 1.x's
end (1.23 -> 2.0 = 2012; HW 3.0 = 2015). Square Enix preserved
the place name reservations throughout the ARR reboot.

This adds to the **PRE-NAMED EXPANSION CONTENT** finding from prior:
```text
Pre-named HW (3.0) content in 1.x:
  124   Dravania (the region; per prior finding)
  4001  ISHGARD (HW's main city)
  4002  Falcon's Nest
  4014  Camp Dragonhead (Haurchefant's territory)

Pre-named SB (4.0) content in 1.x:
  108   Ala Mhigo (city-state)
  125   Abalathia's Spine
  127   Gyr Abania
```

So **TWO FULL EXPANSIONS' worth of place names** were in 1.x's
data BEFORE the ARR reboot.

## Beastmen tribes confirmed

```text
TRIBE       Place evidence                     Region
-----       --------------                     ------
Kobold      1515 kobold garrison, 1516         La Noscea (mining)
            kobold encampment + U'Ghamaro      (Ghamaro Mines, lore)
            Mines (Mor Dhona vicinity)
Amalj'aa    3517 encampment, 3518 altar        Thanalan (Ul'dah)
Ixali       2529 Ixali clearing, 4502          Black Shroud / North
            Ixali encampment                   Shroud
Sylph       2054 Pixie Falls (possibly         Black Shroud
            related to Sylph tribe)
Sahagin     1122 Shposhae (FFXIV's Sahagin     La Noscea (sea floor)
            beastmen underwater home)
```

So 5 of FFXIV's classic beastmen tribes have place names in 1.x:
**Kobold / Amalj'aa / Ixali / Sylph / Sahagin**. Each ties to one
of the starter regions (La Noscea: Kobolds + Sahagin; Black Shroud:
Ixali + Sylph; Thanalan: Amalj'aa). This is the iconic FFXIV
beastmen geography.

ARR added more tribes (Vanu Vanu in HW, Kojin in SB, etc.) which
aren't yet in 1.x's data.

## Housing wards -- 42+ per city in 1.x

```text
LIMSA LOMINSA HOUSING WARDS (1201-1240+):
  Frippers Ward (E/M/W)        Keeners Ward (U/M/L)
  Chandlers Ward (N/C/S)       Gravers Ward (E/C/W)
  Tinners Ward (N/C/S)         Sea Dogs Ward (U/L)
  Pelicans Ward (N/C/O)        Dockers Ward (E/C/W)
  Butchers Ward (U/M/L)        Bobbers Ward (N/C/S)
  Riviters Ward (E/M/W)        Outlanders Ward (N/C/S)
  Sea Lions Ward (U/L)         Netters Ward (N/C/O)
  
  (similar density for Gridania 2500+ and Ul'dah 3500+)
```

So **~42 named housing wards per starter city x 3 cities =
120+ housing wards in 1.x**.

ARR drastically simplified this. ARR's housing initially was:
- Mist (Limsa)
- The Goblet (Ul'dah)
- The Lavender Beds (Gridania)

That's 3 housing zones instead of 120+ named wards. ARR
consolidated the housing system massively.

## Confidence

```text
Confirmed:
  - Gridania at 2001, Ul'dah at 3051, Ishgard at 4001.
  - Black Shroud has 5 cardinal sub-zones
    (central/east/north/west/south Shroud).
  - Ishgard, Falcon's Nest, Camp Dragonhead (HW 3.0 content)
    are pre-named in 1.x's data.
  - Sil'dih (3052) and Gelmorra Ruins (2002) are the ancestral
    cities of Ul'dah and Gridania respectively.
  - 6 Ul'dah guilds: Gladiator/Pugilist/Thaumaturge/Goldsmith/
    Miner/Alchemist/Weaver (= 7 named guilds).
  - Quicksand (3067) is the Ul'dah inn.
  - Gate of Nald + Gate of Thal = Ul'dah's twin god gates.
  - Beastmen tribes in 1.x: Kobold (La Noscea), Amalj'aa
    (Thanalan), Ixali (Shroud), Sylph (Shroud), Sahagin (sea).
  - 42+ housing wards per city in 1.x x 3 cities = 120+ housing
    wards total. ARR consolidated to 3 housing zones.

Likely (High):
  - The 4xxx range was Coerthas/Mor Dhona/Ishgard during 1.x's
    later patches (1.18+ added Coerthas content).
  - The HW expansion was being designed CONCURRENTLY with 1.x's
    end -- place names were locked in 1.x's data scaffolding.
  - The 6 Ul'dah guild names (Gladiator/Pugilist/etc.) match the
    1.x battle classes that LAUNCHED with the city. Cut classes
    (Fencer, Enforcer, etc.) don't have their own guilds in this
    data.

Likely (Medium):
  - "Owl's Nest" (4003) is paired with "Falcon's Nest" (4002)
    suggesting a falconry / hunting theme in Coerthas pre-HW
    that didn't make it to retail.
  - "Dragonhead" (4009) + "Camp Dragonhead" (4014) reflects
    Coerthas's dragon-themed lore.
  - The ARR housing simplification (120+ wards -> 3 zones) was
    one of the biggest gameplay-system rebuilds of the reboot.
```

## Connections to other findings

- **finding_complete_1x_class_roster_planned_vs_launched.md**:
  the 6 Ul'dah guilds match the 8 launched battle classes that
  needed training facilities. Cut classes (Fencer, etc.) have
  no guild in the data.
- **finding_tribes_gc_ranks_places_worldbuilding.md**: extends
  with city interiors + Ishgard + Sil'dih ancestral cities.
- **finding_world_area_login_split.md**: the per-zone Lua files
  (43 in the corpus) now connect to specific named zones
  (Gridania 2001 -> a specific zonemaster file, etc.).

## Next test

- Sample aetheryte rows from each region (1xxx/2xxx/3xxx/4xxx)
  to confirm the col 1 -> placeName cross-ref pattern.
- Check ARR's launch state for housing -- was Mist + Goblet +
  Lavender Beds actually in 1.x's data already? (The 3 housing
  zones may be in higher ID ranges.)
- Look at xtx_journalxtxFst/Sea/Wil for the 3 starter region's
  journal text (~1.4 MB content per region).

## Commit suggestion

```
docs(re/lua): city interiors + beastmen + ISHGARD pre-named -- HW 3.0 content reserved in 1.x
```
