# Finding: The "~625 gear-variant tables" are LOCALIZED TEXT, not gear stats (import-plan correction)

**Corrects the import plan's Phase 6 hypothesis.** The plan classified
~625 "useful" tables (acn/gla/blm0j1/gcu/com/wld/...) as "gear stat
blocks" needing decode for defense/magic-defense values. Empirical
sweep of all 803 decode_csv tables proves this is WRONG: **704 of 803
tables are pure localized TEXT** (`id + 5 str` = JP/EN/DE/FR/ZH).
There are **NO per-class gear-stat variant tables**. Gear stats live
ONLY in the 5 already-decoded SpreadSheet tables.

## 1. The empirical split (all 803 decode_csv tables)

```text
Classification by type-header (row 2 of every CSV):
  704 tables  ALL-STR (id + 5x str)         = localized text (CLIENT-LOCAL)
   99 tables  HAVE NUMERIC cols (s8/s16/s32/u8/float/bool) = data

The 704 text tables ALL share the exact same shape:
  row0:  ,0,1,2,3,4
  row1:  ,str,str,str,str,str
  row2+: id, JP, EN, DE, FR, ZH

This is the SAME pattern as populaceXxx (prior finding) -- 5-language
localized dialogue. NOT stat data.
```

## 2. What the 704 text tables actually are (by family)

```text
Family (prefix)        Count  Content
---------------        -----  -------
etc*                    175   misc/scenario quest dialogue
com*                     45   common quest dialogue (com0g1 = adventurer guild)
wld*                     40   world/regional quest dialogue
spl*                     24   spellcraft/magic quest dialogue
man*                     21   MAIN SCENARIO dialogue (Minfilia/Waking Sands/Scions)
gcu* / gcl* / gcg*    19+19+19 Grand Company text (NOT uniform/linkpearl/gauntlet GEAR)
blm/brd/drg/mnk/        70   JOB QUEST dialogue (7 jobs x 10 stages 0j1..1j0)
  pld/war/whm (x10 ea)        e.g. pld0j1 = Paladin job quest (free paladin/Marasaja)
acn/alc/arc/bsm/cnj/   114   CLASS GUILD quest dialogue (DoW/DoM/DoH/DoL)
  cul/exc/fsh/gla/gld/        19 classes x {200,300,306,400,500,506} stages
  hrv/lnc/min/pgl/tan/        e.g. gla200 = Coliseum welcome (Gladiator guild)
  thm/wdk/wvr (x6 ea)         exc200 = Limsa pirate guild (Marauder)
sum* / trl* / noc*    9+6+4   summon / trial / misc text
populace*                53   NPC dialogue (prior finding)
+ named text tables           raidFst/Roc/Sea/Wil dungeon text, etc.

VERIFIED: all 270 class+job family files (acn..wvr + 7 jobs) are
100% uniform `id + 5x str`. Zero numeric columns anywhere.

CLASS-CODE -> 1.x discipline (from dialogue content):
  DoW: gla(Gladiator) pgl(Pugilist) arc(Archer) lnc(Lancer) exc(Marauder/pirate)
  DoM: cnj(Conjurer) thm(Thaumaturge) acn(Arcanist)
  DoH: bsm(Blacksmith) gld(Goldsmith) wvr(Weaver) tan(Leatherworker)
       wdk(Carpenter) alc(Alchemist) cul(Culinarian)
  DoL: min(Miner) hrv(Botanist) fsh(Fisher)
  Suffix {200,300,306,400,500,506} = quest stage/tier within the guild line
JOB-CODE (1.21+ jobs): pld war mnk drg brd whm blm; suffix 0j1..1j0 = 10 quest stages
```

## 3. The 99 real data tables (the actual server data)

```text
GEAR STATS (the ONLY gear data -- already decoded):
  itemData, equipment, weapon, armor, accessory, materia, itemColor, equipSet
  -> 5-sheet composition + 4-param scaling (prior item findings)

GEAR VISUAL VARIANTS (cosmetic; the literal "var" tables):
  var_equip (32,279 rows, 111 cols)  per-equipment-graphic DYE/COLOR map
       70+ f16 (value 1000 = 1.0 color/scale multipliers per material zone)
       + 16 bool (dyeable channel flags) + 16 f16 + 3 s32 (texture refs)
  var_wep   (1,439 rows, 204 cols)   per-weapon-graphic dye/color map
  var_tex_path (31 rows, 25 cols)    texture path index
  -> COSMETIC (dye system / visual), NOT stat data. Server doesn't need.

CALC TABLES (decoded -- the server calc model):
  status, command, gameCommand, gameCommandBasic, compatibility, exp_BPCost

CONTENT/POPULATION (decoded + adjacent):
  shopBase, shopItem, marketItem, blackMarket, gcSealShopItem,
  quest, quest_reward, quest_new_reward, questcategory, quest_marker,
  guildleve, guildlevePack, guildleve_UI, passiveGL_craft/icon/type,
  achievement, emote, recipe, negotiationItem, request, facility,
  itemGcExSupply, itemHamletSupply

WORLD/ZONE:
  2Dmap_actor_data/data/marker/piece, aetheryte, aetheryte_2Dmap,
  actorclass, actorclass_graphic, actorclass_mapObj, mapNavi_data,
  regionParam, zoneGroupParam, _zoneParam, _region, cutReplay

SOCIAL/GC: gcRank, memberRank, communityMember, tribe, hamletDefScore

NAME LOOKUPS (xtx_* with grammar metadata; ~18 in data bucket):
  xtx_itemName, xtx_placeName, xtx_displayName, xtx_quest, xtx_status,
  xtx_title, xtx_text_jobName/raceName/skillName/...
  -> localized NAME tables w/ s8 gender/declension cols (DE/FR grammar);
     referenced by [@SHEET(xtx/itemName,id,col)] markup in dialogue.
     CLIENT-LOCAL (presentation), though technically "data"-shaped.

SYSTEM/UI/BOOT: key_config*, _layout, _movie, _item, _group, _quest,
  boot_charaLook/charaTemp/skillequip, _boot_error_type,
  _worldMasterLogCategory, debugCommand, test_* (2 dev tables)
```

## 4. The xtx markup system (why dialogue refs names)

```text
The text tables embed runtime markup resolved client-side:
  [@SHEET(itemData,11000556,41)]          read itemData col 41 (color tier)
  [@SHEET(xtx/itemName,11000556,4)]       localized item name (JP)
  [@SHEETEN/DE/FR(xtx/itemName,...)]       language-specific name + grammar
  [@STRING($EB(1))]  [@SPLIT(...)]         player name / first-name split
  [@IF($E9(4), gladiatrice, gladiateur)]   gender-conditional text (FR/DE)
  [@CR] [@COLOR(#..)] [@SWITCH(...)]        formatting / conditional color

This is a CLIENT-SIDE template engine: dialogue text + name lookups +
player-context substitution, all resolved in the client. The server
never assembles or sends this text.
```

## 5. Implication: the server's data requirement is SMALLER than thought

```text
WRONG (import plan Phase 6): "~625 useful tables = gear stat blocks,
  needed for gameplay correctness (defense/magic-defense per class)."

CORRECT: those ~625 tables are localized TEXT (dialogue/names). The
server needs NONE of them. Gear stats are FULLY contained in the 5
SpreadSheet tables (itemData/equipment/weapon/armor/accessory) already
decoded.

SERVER DATA SCOPE (revised):
  - ~40 genuine data tables (calc + content-population + world/zone),
    critical ones already decoded
  - + 5 gear-stat sheets (decoded)
  - NOT: 704 text tables, var_* cosmetics, xtx_* name lookups,
    key_config/boot/test/dev tables

This is the CLIENT-SIDE-CONTENT PRINCIPLE confirmed AGAIN (6th layer):
the bulk of the 803-table corpus is client-local localized content
(dialogue), not server data. The server stores ~45 tables; the client
holds the other ~750 (text + cosmetic + name + UI config).
```

## 6. Confidence

```text
Confirmed:
  - 704 of 803 decode_csv tables are pure `id + 5x str` localized text
  - 99 tables have numeric columns (the data tables)
  - ALL 270 class/job family files (acn..wvr x6 + 7 jobs x10) are 100%
    uniform 5x str -- ZERO gear-stat columns
  - gcu/gcl/gcg/com/wld/spl/noc/sum/trl families are ALL str (text)
  - var_equip/var_wep/var_tex_path are f16/bool/s32 cosmetic dye/color maps
  - Gear stats exist ONLY in itemData/equipment/weapon/armor/accessory

Likely (High):
  - var_equip f16=1000 values = color/scale multipliers (1.0 in permille)
    + 16 bool = dyeable channels (the 1.x dye/glamour visual system)
  - Class suffix {200..506} = quest stage/tier; job 0j1..1j0 = 10 stages
  - xtx_* s8 columns = grammatical gender/declension for DE/FR rendering

Speculative:
  - exc = Marauder guild (pirate dialogue, Limsa) vs man = main scenario
  - etc* (175) exact sub-categorization (scenario vs side-quest dialogue)
  - Precise var_equip column->material-zone mapping
```

## 7. Cross-references

- `docs/server/content_requirements/ffxivtool_import_plan.md` -- Phase 6
  CORRECTED by this finding (gear-stat hypothesis refuted)
- `finding_populace_and_shop_csv_structure.md` -- same `id + 5x str`
  text pattern (populaceXxx); shop = the real data
- `finding_quest_csv_structure_closes_content_data.md` -- quest defs/rewards
  (data) vs quest dialogue (these text tables)
- `finding_item_common_inventory.md` + itemData cols (QUICK_REFERENCE 11) --
  the 5 gear-stat sheets = the ONLY gear data
- `finding_npc_event_talk_turn_flow_client_side.md` -- client shows this
  dialogue (xtx markup engine)
- `docs/data/ffxivtool_table_catalog.md` -- the 803-table catalog

## 8. CONTENT-DATA SWEEP TRULY COMPLETE

```text
The full 803-table corpus is now accounted for:
  704 localized TEXT tables  -> CLIENT-LOCAL (dialogue/quest/GC/names);
                                server needs NONE
   99 DATA tables            -> ~45 server-relevant (calc + content +
                                world; critical decoded), rest are
                                cosmetic (var_*) / name (xtx_*) / UI / dev

There is NO remaining "gear-variant decode" backlog -- it was a
mis-scope. The server's data requirement is the ~45 tables already
identified, with the 5 calc tables + 5 gear sheets as the core.
```

## Commit suggestion

```
docs(data): CORRECTION -- the ~625 "gear-variant" tables are localized TEXT (704/803 are id+5xstr dialogue), NOT gear stats; gear data lives only in the 5 decoded sheets; var_* = cosmetic dye maps; refutes import-plan Phase 6
```
