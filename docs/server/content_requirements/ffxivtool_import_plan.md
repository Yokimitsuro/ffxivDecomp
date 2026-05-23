# FFXIVTool Content Import Plan

Plan for ingesting the FFXIVTool exports (FFXIV 1.23b client patch
`2012.09.19.0001`) into a MeteorReborn-style server database.

Inputs:

```
data/client_exports/ffxivtool/decode_csv/   (canonical, 803 tables)
data/client_exports/ffxivtool/raw_csv/      (fidelity reference, 803 tables)
data/client_exports/ffxivtool/mycsv/        (derived: Item + Command joins)
data/client_exports/ffxivtool/ShopList.txt  (auxiliary shop reference)
```

Rationale for picking `decode_csv` as the canonical source is in
`docs/data/ffxivtool_export_overview.md`.

Catalog of all 803 tables is in
`docs/data/ffxivtool_table_catalog.csv` (machine) and
`docs/data/ffxivtool_table_catalog.md` (human).

## Overall scope

```
Total tables:     803
Critical tables:  164  (~82,100 data rows)
Useful tables:    625  (~64,200 data rows)
Later tables:      11  (system / boot / debug)
Cosmetic tables:    3  (texture / variant data)
```

The MVP server needs only the **critical** tables. The **useful**
tables are needed for gameplay correctness (gear stats, status
effects, achievements, localized text) but the server flows can
boot without them.

## Common FFXIVTool CSV layout

All 803 CSV files use the same 2-line header convention:

```
row 0:   ,0,1,2,3,...               <-- column index header
row 1:   ,s32,str,s32,bool,...       <-- column type header
row 2+:  ID, col0, col1, col2, ...   <-- data rows
```

Type tags observed: `s8`, `s16`, `s32`, `u8`, `u16`, `u32`,
`float`, `bool`, `str`, empty (= unused).

Empty columns at the end of the header row are unused fields in
this client revision but kept for column-index alignment with
other tables / future patches.

## Import phases

Each phase produces a working slice of server behavior.

### Phase 0 - Schema scaffolding

Goal: empty DB schema mirroring the FFXIVTool table names + column
shapes, with primary keys on column 0.

Steps:

1. Auto-generate a CREATE TABLE statement per CSV by reading row 0
   + row 1 of each file. Column types map as:

   ```
   s8/s16/s32 -> INTEGER
   u8/u16/u32 -> INTEGER (unsigned-checked)
   float      -> REAL
   bool       -> INTEGER (0/1)
   str        -> TEXT
   ""         -> drop column from DB (it is unused)
   ```

2. Primary key: column 0 (numeric ID). Composite keys not used
   anywhere in the 803-table corpus we have observed.

3. Naming: keep FFXIVTool's table base name unchanged (`itemData`,
   `populaceShopSalesman`, etc.) so future re-imports diff cleanly.

### Phase 1 - Critical: zones, maps, regions

```
zone (9):  dftFst, dftSea, dftWil, dftLak, dftRoc, dftSrt,
            regionParam, zoneGroupParam, _zoneParam
map  (6):  2Dmap_data, 2Dmap_marker, 2Dmap_piece, 2Dmap_actor_data,
            mapNavi_data, mapObjPortDoor
aetheryte (4):  aetheryte, aetheryte_2Dmap,
                 aetheryteChild, aetheryteParent
```

Rationale: without these, the server cannot validate zone IDs
when a client connects, cannot teleport, and cannot answer
"where am I" queries.

Key facts:

- `dftFst.csv` (forest), `dftSea.csv` (sea), `dftWil.csv`
  (wilderness) each have ~801 rows. These are the 3 starter
  region master tables.
- `aetheryte.csv` has 118 rows -- the canonical aetheryte roster.
- `_zoneParam.csv` is the parent zone parameter list (111 rows).

### Phase 2 - Critical: actors, NPCs, populace

```
actor_class (3):  actorclass, actorclass_graphic, actorclass_mapObj
npc_populace (55): populaceCompanyShop, populaceGuildShop,
                    populaceFactionGLWorker, populaceShopSalesman,
                    populaceShopMateriaRemover, populaceItemRepairer,
                    populaceRequestWarden, populaceSpecialEventCryer,
                    populaceHamletPushEvent, populaceCaravanReporter,
                    populaceGMEventSage / Cryer / TelepoGateIn /
                    TelepoGateOut / TelepoLure / TelepoReception /
                    TelepoTownCryer / TownReporter,
                    + ~40 more
                    (full list in ffxivtool_table_catalog.md)
```

Rationale: actor spawn packets need actorclass + graphic IDs.
NPC roles (vendor / repairer / leve issuer / etc.) are split
across `populace*` tables -- each NPC role is its own table.

Key facts:

- `actorclass.csv` has 7984 rows -- one row per actor class id.
- `actorclass_graphic.csv` has 7831 rows -- per-class default
  graphic / model / equipment block.
- 55 `populace*` tables. The role of an NPC is encoded by which
  populace table contains its ID, NOT by a field inside a single
  table. (i.e. polymorphism through table membership.)

### Phase 3 - Critical: items, commands, shops

```
item (14):     itemData, _item, itemColor, itemGcExSupply,
                itemHamletSupply, negotiationItem, objectItemStorage,
                weapon, armor, accessory, equipment, equipSet,
                materia, materiaBook
command (6):   command, gameCommand, gameCommandBasic, debugCommand,
                emote, debug
shop (5):      shopBase, shopItem, gcSealShopItem, marketItem,
                blackMarket
craft_harvest (3): recipe, craftJudge, harvestJudge
```

Rationale: items + commands are the two largest critical domains
in the client. Shops connect NPCs to item IDs. Recipes drive
crafting.

Key facts:

- `itemData.csv` is the master item table (8405 rows). All other
  `item*` tables reference it by ID.
- `command.csv` (1664) + `gameCommand.csv` (1613) are command
  master tables. `mycsv/Command.csv` (3335) is the denormalized
  join.
- `shopItem.csv` has 2543 rows -- (shopBase_id, item_id, sort
  order) triples driving the shop UI.

### Phase 4 - Critical: quests, leves, instances

```
quest (6):           _quest, quest, quest_marker, quest_new_reward,
                      quest_reward, questcategory
request_leve (1):    request
guildleve (10):      privateGLBattle*, passiveGL*, guildleve,
                      guildleve_UI, guildlevePack, guildleveWarpPoint
passive_guildleve (10): pgAeth, pgConv, pgHaml,
                         pgHarvestPointEncounter + 6 more
instance_content (11):  instanceRaid*, raidFst, raidRoc, raidSrt,
                         raidDungeonBarrier/Exit/Light/Poster/Warp
```

Rationale: quest / leve / raid systems all have their own
master + reward + marker tables in the export. They reference
items, NPCs, and zones already loaded in earlier phases.

### Phase 5 - Critical: events, facilities, player meta

```
event_object (10):  objectBed, objectEventDoor, objectItemStorage,
                     bookShelf, beaconFortGateGimmick,
                     gimmickExitRect / PoisonCure / Terminal / Warp,
                     elevatorStandard, occupancyGuideStandard
facility (2):       facility, chocoboCaravanGuard
player_meta (6):    status, tribe, gcRank, memberRank,
                     exp_BPCost, cutReplay
retainer (1):       ordinaryRetainer
hamlet (2):         hamletDefScore, hamletDefScore(2)
```

`status.csv` has 399 rows -- the status effect (buff/debuff)
master. `tribe.csv` has 16 rows -- the player race/tribe master.

### Phase 6 - Useful: gear stat blocks

Each gear category lives in its own table family because the EXE
treats slot type as polymorphic dispatch (one table per piece
shape).

```
gear_etc           175 files (most populous category, miscellaneous gear)
gear_grandcompany   57 files (gcu* / gcl* / gcg* = uniform / linkpearl / gauntlet)
gear_other          56 files (man / sum / trl / key / boot / bsm / tan)
gear_common         48 files (com*)
gear_world          40 files (wld*)
gear_spellcraft     24 files (spl*)
gear_class_<job>    Job-specific:
                    blm, brd, drg, mnk, pld, war, whm (10 each, 70 total)
                    acn, alc, arc, cnj, cul, exc, fsh, gla, gld,
                    hrv, lnc, min, pgl, thm, wdk, wvr (6 each, 96 total)
gear_neck            4 files (noc*)
gear_variants        3 files (var_equip / var_wep / var_tex_path) - cosmetic
```

Each gear table holds per-row stat blocks: defense, magic defense,
elemental affinities, slot, level requirement, durability, etc.
The columns are largely numeric.

Server import is straightforward (id-keyed UPSERT) once the item
master from Phase 3 is loaded -- the gear tables are stat extensions
of itemData rows.

### Phase 7 - Useful: text / localization

```
text_localization 60 files: xtx_* + worldMaster
```

Server typically does **not** push these strings -- the client owns
them. Useful for:

- admin tools, log readability, /find by name
- localized strings server may need to send back (mail, errors,
  system messages)

`xtx_quest.csv` is the largest text table (1.4 MB raw, 1.9 MB
decoded). `xtx_itemName.csv` is the second largest (4.3 MB).

### Phase 8 - Useful / later: achievements, system

```
achievement (1):  achievement.csv
system (11):      _group, _layout, _movie, _region, _staffroll,
                   _worldMasterLogCategory, _text_error_type(2),
                   _boot_error_type, var.csv, test* (3 files)
```

`achievement.csv` is needed for the achievement subsystem (~hundreds
of rows). System tables are mostly boot/staff-roll/error-message
metadata.

## Special case: ShopList.txt

Plain-text 7-column file (not CSV). Load into a small auxiliary
table for verification only:

```
table shoplist_reference(
  shop_id          INTEGER PRIMARY KEY,
  ref1, ref2, ref3 INTEGER,
  item_id          INTEGER,
  unused1, unused2 INTEGER
)
```

After loading, cross-check `ref1/ref2/ref3` columns against
`shopBase.csv` ids. If they match, we have a confirmation that
`ShopList.txt` is just a flat shop-id-to-SSD-binding summary.

## Special case: mycsv

Do NOT import as primary. Instead:

- Import the normalized source tables (`itemData`, `xtx_itemName`,
  `command`, `gameCommand`, `xtx_command`).
- Re-create the joined view in SQL as a VIEW (`v_item_full`,
  `v_command_full`) for admin tooling.
- Keep `mycsv/Item.csv` and `mycsv/Command.csv` only as a
  manual sanity-check artifact: when DB joins disagree with mycsv,
  investigate why.

## Re-import / refresh process

```powershell
# 1. (Optional) Re-export from FFXIVTool if the user updates the tool
& "tools/local/ffxivtool/ffxivtool.exe"   # local, NOT committed

# 2. Rebuild the catalog
& .\tools\build_ffxivtool_catalog.ps1
& .\tools\render_ffxivtool_catalog_md.ps1

# 3. Diff the catalog CSV against the previous commit
git diff -- docs/data/ffxivtool_table_catalog.csv

# 4. Re-run the importer (separate work item)
```

## Open questions

```
- The 6 'dft*' zone tables: what does the 6-letter suffix mean?
  (Fst=forest, Sea=sea, Wil=wilderness are clear; Lak/Roc/Srt need
   confirmation.)
- 'var' prefix tables: confirmed to be variant / texture maps?
  (var_equip 32277 rows, var_wep 1437 rows -- these are big)
- `worldMaster.csv` (1.5 MB decoded): single biggest text template
   table. What is it dispatched from -- a single EXE call site or
   a Lua bridge?
- 'pg*' tables (pgAeth, pgConv, pgHaml, ...): "passive guildleve"
   category, but the exact relation to `passiveGL*` tables is
   unverified.
```

## Confidence

```
Confirmed:
  - 803 tables in decode_csv == 803 in raw_csv (identical filename sets).
  - 2-line header convention applies to every file.
  - Critical categories isolate the server-blocking tables.
  - mycsv contains denormalized joins, not primary data.

Likely (High):
  - The 7 jobs (15-19, 26-27 per finding_ffxivbattle_stats_and_jobs.md)
    + the 8 DoH classes (29-36) line up with the per-job gear tables
    (10 each for 7 battle jobs; 6 each for crafters/gatherers/...).
  - Phase 1-5 (critical) are sufficient to take the server from
    "accepting login" to "spawning actors, walking around, opening
    a vendor". Phase 6+ unlock combat correctness and content.

Likely (Medium):
  - `_zoneParam.csv` (111 rows) is the parent ID list for the dft*
    region master tables.
  - `regionParam.csv` (6 rows) lists the 6 starter regions of 1.x.

Speculative:
  - 'gear_etc' (175 files) probably includes vanity, body markings,
    consumable-equipment categories that are not gear stats per se.
```

## Next test

- Generate the auto-CREATE-TABLE SQL for one example category
  (e.g. `aetheryte`, 4 tables) and import. Verify row counts match
  the catalog.
- Smoke-test: server reads `aetheryte.csv` IDs, accepts a teleport
  request from a logged-in client referencing one of those IDs,
  rejects unknown IDs.
- Confirm `worldMaster.csv` row schema by cross-referencing 5
  rows against the EXE `worldMaster` global object (per
  `finding_world_master.md`).

## Commit suggestion

```
docs(server): add FFXIVTool content import plan and catalog
```
