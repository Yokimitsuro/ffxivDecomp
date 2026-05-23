# FFXIVTool Table Catalog

Auto-generated from `data/client_exports/ffxivtool/decode_csv/*.csv`.
Generator: `tools/build_ffxivtool_catalog.ps1` + `tools/render_ffxivtool_catalog_md.ps1`.
Raw data: `docs/data/ffxivtool_table_catalog.csv` (machine-readable).

**Total tables:** 803

## Server-relevance distribution

| Relevance  | Files |
|------------|-------|
| cosmetic  | 3 |
| critical  | 164 |
| later  | 11 |
| useful  | 625 |

Definitions:

- **critical** -- server must import to drive core flows (zone entry, NPC spawn, item ops, commands, quests, shops, leves, etc.).
- **useful** -- server can use for gameplay correctness (gear stats, text, achievements). Often referenced by IDs from critical tables.
- **later** -- system / boot / debug tables. Not blocking for v0.
- **cosmetic** -- texture/variant tables. Pure client visuals.

## Category distribution

| Category | Files | Relevance |
|----------|-------|-----------|
| gear_etc | 175 | useful |
| text_localization | 60 | useful |
| gear_grandcompany | 57 | useful |
| gear_other | 56 | useful |
| npc_populace | 55 | critical |
| gear_common | 48 | useful |
| gear_world | 40 | useful |
| gear_spellcraft | 24 | useful |
| item | 14 | critical |
| instance_content | 11 | critical |
| system | 11 | later |
| gear_class_mnk | 10 | useful |
| passive_guildleve | 10 | critical |
| gear_class_whm | 10 | useful |
| guildleve | 10 | critical |
| gear_class_drg | 10 | useful |
| gear_class_pld | 10 | useful |
| gear_class_blm | 10 | useful |
| event_object | 10 | critical |
| gear_class_war | 10 | useful |
| gear_class_brd | 10 | useful |
| zone | 9 | critical |
| gear_class_hrv | 6 | useful |
| gear_class_gld | 6 | useful |
| gear_class_wvr | 6 | useful |
| gear_class_wdk | 6 | useful |
| gear_class_lnc | 6 | useful |
| gear_class_min | 6 | useful |
| gear_class_thm | 6 | useful |
| quest | 6 | critical |
| gear_class_cnj | 6 | useful |
| command | 6 | critical |
| gear_class_arc | 6 | useful |
| map | 6 | critical |
| gear_class_acn | 6 | useful |
| gear_class_alc | 6 | useful |
| gear_class_cul | 6 | useful |
| player_meta | 6 | critical |
| gear_class_fsh | 6 | useful |
| gear_class_exc | 6 | useful |
| gear_class_gla | 6 | useful |
| shop | 5 | critical |
| aetheryte | 4 | critical |
| gear_neck | 4 | useful |
| actor_class | 3 | critical |
| gear_variants | 3 | cosmetic |
| craft_harvest | 3 | critical |
| facility | 2 | critical |
| hamlet | 2 | critical |
| request_leve | 1 | critical |
| retainer | 1 | critical |
| achievement | 1 | useful |

## Critical tables (full listing)

These tables drive core server behavior and should be imported first.

| File | Category | Rows | Cols | Has text |
|------|----------|-----:|-----:|:--------:|
| `actorclass.csv` | actor_class | 7984 | 7 |  |
| `actorclass_graphic.csv` | actor_class | 7831 | 48 |  |
| `actorclass_mapObj.csv` | actor_class | 158 | 50 |  |
| `aetheryte.csv` | aetheryte | 118 | 16 |  |
| `aetheryte_2Dmap.csv` | aetheryte | 118 | 22 |  |
| `aetheryteChild.csv` | aetheryte | 60 | 6 | yes |
| `aetheryteParent.csv` | aetheryte | 235 | 6 | yes |
| `command.csv` | command | 1662 | 36 |  |
| `debug.csv` | command | 38 | 6 | yes |
| `debugCommand.csv` | command | 151 | 8 | yes |
| `emote.csv` | command | 55 | 5 |  |
| `gameCommand.csv` | command | 1611 | 141 |  |
| `gameCommandBasic.csv` | command | 1611 | 121 |  |
| `craftJudge.csv` | craft_harvest | 28 | 6 | yes |
| `harvestJudge.csv` | craft_harvest | 75 | 6 | yes |
| `recipe.csv` | craft_harvest | 7 | 16 |  |
| `beaconFortGateGimmick.csv` | event_object | 8 | 6 | yes |
| `bookShelf.csv` | event_object | 81 | 6 | yes |
| `elevatorStandard.csv` | event_object | 36 | 6 | yes |
| `gimmickExitRect.csv` | event_object | 6 | 6 | yes |
| `gimmickPoisonCure.csv` | event_object | 6 | 6 | yes |
| `gimmickTerminal.csv` | event_object | 2 | 6 | yes |
| `gimmickWarp.csv` | event_object | 9 | 6 | yes |
| `objectBed.csv` | event_object | 15 | 6 | yes |
| `objectEventDoor.csv` | event_object | 3 | 6 | yes |
| `occupancyGuideStandard.csv` | event_object | 57 | 6 | yes |
| `chocoboCaravanGuard.csv` | facility | 11 | 6 | yes |
| `facility.csv` | facility | 6 | 10 |  |
| `guildleve.csv` | guildleve | 624 | 64 |  |
| `guildleve_UI.csv` | guildleve | 624 | 80 |  |
| `guildlevePack.csv` | guildleve | 107 | 2 |  |
| `guildleveWarpPoint.csv` | guildleve | 5 | 6 | yes |
| `passiveGL_craft.csv` | guildleve | 169 | 45 |  |
| `passiveGL_icon.csv` | guildleve | 169 | 7 |  |
| `passiveGL_type.csv` | guildleve | 5 | 9 |  |
| `privateGLBattleSweepEpic.csv` | guildleve | 2 | 6 | yes |
| `privateGLBattleSweepEpicInTime.csv` | guildleve | 5 | 6 | yes |
| `privateGLBattleSweepEscort.csv` | guildleve | 16 | 6 | yes |
| `hamletDefScore(2).csv` | hamlet | 78 | 8 | yes |
| `hamletDefScore.csv` | hamlet | 75 | 3 |  |
| `instanceRaidGuideAurumVale.csv` | instance_content | 20 | 6 | yes |
| `instanceRaidGuideCuttersCry.csv` | instance_content | 30 | 6 | yes |
| `InstanceRaidHamletDefense.csv` | instance_content | 28 | 6 | yes |
| `raidDungeonBarrier.csv` | instance_content | 4 | 6 | yes |
| `raidDungeonExit.csv` | instance_content | 9 | 6 | yes |
| `raidDungeonLight.csv` | instance_content | 3 | 6 | yes |
| `raidDungeonPoster.csv` | instance_content | 10 | 6 | yes |
| `raidDungeonWarp.csv` | instance_content | 4 | 6 | yes |
| `raidFst0Dungeon03.csv` | instance_content | 7 | 6 | yes |
| `raidFst0Dungeon03Guide.csv` | instance_content | 60 | 6 | yes |
| `raidRoc0Dungeon01Guide.csv` | instance_content | 60 | 6 | yes |
| `_item.csv` | item | 8403 | 5 | yes |
| `accessory.csv` | item | 278 | 132 |  |
| `armor.csv` | item | 3599 | 130 |  |
| `equipment.csv` | item | 4875 | 141 |  |
| `equipSet.csv` | item | 19 | 34 |  |
| `itemColor.csv` | item | 511 | 6 |  |
| `itemData.csv` | item | 8403 | 142 |  |
| `itemGcExSupply.csv` | item | 79 | 3 |  |
| `itemHamletSupply.csv` | item | 33 | 4 |  |
| `materia.csv` | item | 66 | 81 |  |
| `materiaBook.csv` | item | 52 | 6 | yes |
| `negotiationItem.csv` | item | 50 | 4 |  |
| `objectItemStorage.csv` | item | 13 | 6 | yes |
| `weapon.csv` | item | 1161 | 143 |  |
| `2Dmap_actor_data.csv` | map | 19 | 4 | yes |
| `2Dmap_data.csv` | map | 307 | 18 |  |
| `2Dmap_marker.csv` | map | 634 | 19 | yes |
| `2Dmap_piece.csv` | map | 98 | 7 |  |
| `mapNavi_data.csv` | map | 427 | 19 |  |
| `mapObjPortDoor.csv` | map | 9 | 6 | yes |
| `populace.csv` | npc_populace | 4208 | 67 | yes |
| `populaceAchievement.csv` | npc_populace | 123 | 6 | yes |
| `populaceBlackMarketeer.csv` | npc_populace | 19 | 6 | yes |
| `populaceBountyPresenter.csv` | npc_populace | 35 | 6 | yes |
| `populaceBranchsVendor.csv` | npc_populace | 28 | 6 | yes |
| `populaceCampMaster.csv` | npc_populace | 71 | 6 | yes |
| `populaceCampSubMaster.csv` | npc_populace | 61 | 6 | yes |
| `populaceCaravanAdviser.csv` | npc_populace | 17 | 6 | yes |
| `populaceCaravanGuide.csv` | npc_populace | 43 | 6 | yes |
| `populaceCaravanManager.csv` | npc_populace | 64 | 6 | yes |
| `populaceChocoboLender.csv` | npc_populace | 109 | 6 | yes |
| `populaceCompanyBuffer.csv` | npc_populace | 16 | 6 | yes |
| `populaceCompanyGLPublisher.csv` | npc_populace | 42 | 6 | yes |
| `populaceCompanyGuide.csv` | npc_populace | 71 | 6 | yes |
| `populaceCompanyOfficer.csv` | npc_populace | 88 | 6 | yes |
| `populaceCompanyShop.csv` | npc_populace | 140 | 6 | yes |
| `populaceCompanySupply.csv` | npc_populace | 7 | 6 | yes |
| `populaceCompanyWarp.csv` | npc_populace | 97 | 6 | yes |
| `populaceCutScenePlayer.csv` | npc_populace | 101 | 6 | yes |
| `populaceFactionGLWorker.csv` | npc_populace | 356 | 6 | yes |
| `populaceFlyingShip.csv` | npc_populace | 31 | 6 | yes |
| `populaceGLKeyPerson.csv` | npc_populace | 32 | 6 | yes |
| `populaceGMEventSage.csv` | npc_populace | 14 | 6 | yes |
| `populaceGMEventSageCryer.csv` | npc_populace | 12 | 6 | yes |
| `populaceGMEventTelepoGateIn.csv` | npc_populace | 5 | 6 | yes |
| `populaceGMEventTelepoGateOut.csv` | npc_populace | 4 | 6 | yes |
| `populaceGMEventTelepoLure.csv` | npc_populace | 4 | 6 | yes |
| `populaceGMEventTelepoReception.csv` | npc_populace | 21 | 6 | yes |
| `populaceGMEventTelepoTownCryer.csv` | npc_populace | 4 | 6 | yes |
| `populaceGMEventTownReporter.csv` | npc_populace | 24 | 6 | yes |
| `populaceGuildlevePublisher.csv` | npc_populace | 119 | 6 | yes |
| `populaceGuildShop.csv` | npc_populace | 129 | 6 | yes |
| `populaceHalloweenTrans.csv` | npc_populace | 751 | 6 | yes |
| `populaceHamletBreeder.csv` | npc_populace | 22 | 6 | yes |
| `PopulaceHamletCaptain.csv` | npc_populace | 39 | 6 | yes |
| `populaceHamletPushEvent.csv` | npc_populace | 51 | 6 | yes |
| `populaceHamletSupply.csv` | npc_populace | 2 | 6 | yes |
| `populaceItemRepairer.csv` | npc_populace | 102 | 6 | yes |
| `populaceLinkshellManager.csv` | npc_populace | 132 | 6 | yes |
| `populaceMenuMan.csv` | npc_populace | 1 | 6 | yes |
| `populaceNMReward.csv` | npc_populace | 83 | 6 | yes |
| `populaceNMRushGuide.csv` | npc_populace | 34 | 6 | yes |
| `populacePassiveGLPublisher.csv` | npc_populace | 33 | 6 | yes |
| `populaceRequestWarden.csv` | npc_populace | 147 | 6 | yes |
| `populaceRetainerManager.csv` | npc_populace | 178 | 6 | yes |
| `populaceShopMateriaRemover.csv` | npc_populace | 25 | 6 | yes |
| `populaceShopSalesman.csv` | npc_populace | 501 | 6 | yes |
| `populaceSpecialEventCryer.csv` | npc_populace | 49 | 6 | yes |
| `populaceSumFes.csv` | npc_populace | 49 | 6 | yes |
| `populaceSwimSuit2011.csv` | npc_populace | 38 | 6 | yes |
| `populaceTownCryer.csv` | npc_populace | 183 | 6 | yes |
| `populaceValentMaster.csv` | npc_populace | 117 | 6 | yes |
| `populaceWaveAttack.csv` | npc_populace | 22 | 6 | yes |
| `populaceWaveAttackCryer.csv` | npc_populace | 107 | 6 | yes |
| `populaceYukata.csv` | npc_populace | 34 | 6 | yes |
| `pgAeth.csv` | passive_guildleve | 220 | 6 | yes |
| `pgConv.csv` | passive_guildleve | 372 | 6 | yes |
| `pgHaml.csv` | passive_guildleve | 1 | 6 | yes |
| `pgHarvestPointEncounter.csv` | passive_guildleve | 9 | 5 | yes |
| `pgl200.csv` | passive_guildleve | 136 | 6 | yes |
| `pgl300.csv` | passive_guildleve | 114 | 6 | yes |
| `pgl306.csv` | passive_guildleve | 103 | 6 | yes |
| `pgl400.csv` | passive_guildleve | 94 | 6 | yes |
| `pgl500.csv` | passive_guildleve | 111 | 6 | yes |
| `pgl506.csv` | passive_guildleve | 90 | 6 | yes |
| `cutReplay.csv` | player_meta | 614 | 17 | yes |
| `exp_BPCost.csv` | player_meta | 29 | 5 |  |
| `gcRank.csv` | player_meta | 22 | 10 |  |
| `memberRank.csv` | player_meta | 5 | 7 |  |
| `status.csv` | player_meta | 399 | 60 |  |
| `tribe.csv` | player_meta | 16 | 4 |  |
| `_quest.csv` | quest | 246 | 29 |  |
| `quest.csv` | quest | 735 | 57 |  |
| `quest_marker.csv` | quest | 7889 | 15 | yes |
| `quest_new_reward.csv` | quest | 500 | 209 |  |
| `quest_reward.csv` | quest | 1264 | 7 |  |
| `questcategory.csv` | quest | 48 | 3 |  |
| `request.csv` | request_leve | 103 | 25 |  |
| `ordinaryRetainer.csv` | retainer | 999 | 6 | yes |
| `blackMarket.csv` | shop | 27 | 11 |  |
| `gcSealShopItem.csv` | shop | 402 | 10 |  |
| `marketItem.csv` | shop | 20 | 30 |  |
| `shopBase.csv` | shop | 240 | 3 |  |
| `shopItem.csv` | shop | 2543 | 4 |  |
| `_zoneParam.csv` | zone | 111 | 2 |  |
| `dftFst.csv` | zone | 801 | 6 | yes |
| `dftLak.csv` | zone | 187 | 6 | yes |
| `dftRoc.csv` | zone | 73 | 6 | yes |
| `dftSea.csv` | zone | 801 | 6 | yes |
| `dftSrt.csv` | zone | 4 | 6 | yes |
| `dftWil.csv` | zone | 801 | 6 | yes |
| `regionParam.csv` | zone | 6 | 4 |  |
| `zoneGroupParam.csv` | zone | 42 | 7 |  |

## Useful tables (grouped)

### achievement (1 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `achievement.csv` | 746 | 21 |

### gear_class_acn (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `acn506.csv` | 84 | 6 |
| `acn400.csv` | 78 | 6 |
| `acn500.csv` | 62 | 6 |
| `acn300.csv` | 52 | 6 |
| `acn306.csv` | 46 | 6 |
| `acn200.csv` | 39 | 6 |

### gear_class_alc (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `alc300.csv` | 108 | 6 |
| `alc400.csv` | 87 | 6 |
| `alc200.csv` | 83 | 6 |
| `alc506.csv` | 79 | 6 |
| `alc500.csv` | 75 | 6 |
| `alc306.csv` | 68 | 6 |

### gear_class_arc (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `arc300.csv` | 98 | 6 |
| `arc500.csv` | 92 | 6 |
| `arc400.csv` | 82 | 6 |
| `arc200.csv` | 79 | 6 |
| `arc506.csv` | 79 | 6 |
| `arc306.csv` | 77 | 6 |

### gear_class_blm (10 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `blm0j6.csv` | 101 | 6 |
| `blm0j1.csv` | 75 | 6 |
| `blm0j3.csv` | 46 | 6 |
| `blm0j4.csv` | 37 | 6 |
| `blm0j5.csv` | 27 | 6 |
| `blm0j2.csv` | 20 | 6 |
| `blm0j9.csv` | 1 | 6 |
| `blm1j0.csv` | 1 | 6 |

(+ 2 more -- see `ffxivtool_table_catalog.csv`)

### gear_class_brd (10 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `brd0j1.csv` | 67 | 6 |
| `brd0j6.csv` | 45 | 6 |
| `brd0j4.csv` | 34 | 6 |
| `brd0j5.csv` | 26 | 6 |
| `brd0j2.csv` | 26 | 6 |
| `brd0j3.csv` | 24 | 6 |
| `brd0j9.csv` | 1 | 6 |
| `brd1j0.csv` | 1 | 6 |

(+ 2 more -- see `ffxivtool_table_catalog.csv`)

### gear_class_cnj (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `cnj300.csv` | 129 | 6 |
| `cnj400.csv` | 108 | 6 |
| `cnj306.csv` | 105 | 6 |
| `cnj200.csv` | 96 | 6 |
| `cnj506.csv` | 43 | 6 |
| `cnj500.csv` | 39 | 6 |

### gear_class_cul (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `cul506.csv` | 160 | 6 |
| `cul500.csv` | 140 | 6 |
| `cul400.csv` | 124 | 6 |
| `cul200.csv` | 107 | 6 |
| `cul306.csv` | 102 | 6 |
| `cul300.csv` | 98 | 6 |

### gear_class_drg (10 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `drg0j1.csv` | 50 | 6 |
| `drg0j6.csv` | 41 | 6 |
| `drg0j4.csv` | 40 | 6 |
| `drg0j5.csv` | 28 | 6 |
| `drg0j3.csv` | 27 | 6 |
| `drg0j2.csv` | 24 | 6 |
| `drg0j9.csv` | 1 | 6 |
| `drg1j0.csv` | 1 | 6 |

(+ 2 more -- see `ffxivtool_table_catalog.csv`)

### gear_class_exc (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `exc400.csv` | 168 | 6 |
| `exc306.csv` | 149 | 6 |
| `exc300.csv` | 138 | 6 |
| `exc500.csv` | 74 | 6 |
| `exc200.csv` | 73 | 6 |
| `exc506.csv` | 67 | 6 |

### gear_class_fsh (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `fsh300.csv` | 148 | 6 |
| `fsh306.csv` | 100 | 6 |
| `fsh400.csv` | 76 | 6 |
| `fsh506.csv` | 56 | 6 |
| `fsh200.csv` | 54 | 6 |
| `fsh500.csv` | 48 | 6 |

### gear_class_gla (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `gla300.csv` | 177 | 6 |
| `gla306.csv` | 120 | 6 |
| `gla400.csv` | 92 | 6 |
| `gla200.csv` | 69 | 6 |
| `gla500.csv` | 62 | 6 |
| `gla506.csv` | 57 | 6 |

### gear_class_gld (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `gld300.csv` | 113 | 6 |
| `gld500.csv` | 102 | 6 |
| `gld200.csv` | 102 | 6 |
| `gld306.csv` | 78 | 6 |
| `gld506.csv` | 63 | 6 |
| `gld400.csv` | 60 | 6 |

### gear_class_hrv (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `hrv306.csv` | 118 | 6 |
| `hrv300.csv` | 104 | 6 |
| `hrv506.csv` | 87 | 6 |
| `hrv200.csv` | 64 | 6 |
| `hrv400.csv` | 36 | 6 |
| `hrv500.csv` | 25 | 6 |

### gear_class_lnc (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `lnc300.csv` | 160 | 6 |
| `lnc306.csv` | 110 | 6 |
| `lnc400.csv` | 98 | 6 |
| `lnc500.csv` | 93 | 6 |
| `lnc506.csv` | 89 | 6 |
| `lnc200.csv` | 68 | 6 |

### gear_class_min (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `min300.csv` | 157 | 6 |
| `min306.csv` | 145 | 6 |
| `min200.csv` | 108 | 6 |
| `min500.csv` | 87 | 6 |
| `min506.csv` | 65 | 6 |
| `min400.csv` | 59 | 6 |

### gear_class_mnk (10 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `mnk0j6.csv` | 100 | 6 |
| `mnk0j3.csv` | 61 | 6 |
| `mnk0j1.csv` | 57 | 6 |
| `mnk0j2.csv` | 43 | 6 |
| `mnk0j5.csv` | 40 | 6 |
| `mnk0j4.csv` | 33 | 6 |
| `mnk0j9.csv` | 1 | 6 |
| `mnk1j0.csv` | 1 | 6 |

(+ 2 more -- see `ffxivtool_table_catalog.csv`)

### gear_class_pld (10 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `pld0j6.csv` | 54 | 6 |
| `pld0j1.csv` | 49 | 6 |
| `pld0j5.csv` | 30 | 6 |
| `pld0j2.csv` | 22 | 6 |
| `pld0j3.csv` | 19 | 6 |
| `pld0j4.csv` | 15 | 6 |
| `pld0j9.csv` | 1 | 6 |
| `pld1j0.csv` | 1 | 6 |

(+ 2 more -- see `ffxivtool_table_catalog.csv`)

### gear_class_thm (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `thm300.csv` | 104 | 6 |
| `thm306.csv` | 87 | 6 |
| `thm200.csv` | 71 | 6 |
| `thm400.csv` | 69 | 6 |
| `thm506.csv` | 1 | 6 |
| `thm500.csv` | 1 | 6 |

### gear_class_war (10 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `war0j6.csv` | 41 | 6 |
| `war0j1.csv` | 41 | 6 |
| `war0j3.csv` | 33 | 6 |
| `war0j2.csv` | 18 | 6 |
| `war0j5.csv` | 16 | 6 |
| `war0j4.csv` | 15 | 6 |
| `war0j9.csv` | 1 | 6 |
| `war1j0.csv` | 1 | 6 |

(+ 2 more -- see `ffxivtool_table_catalog.csv`)

### gear_class_wdk (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `wdk300.csv` | 162 | 6 |
| `wdk306.csv` | 147 | 6 |
| `wdk200.csv` | 98 | 6 |
| `wdk506.csv` | 87 | 6 |
| `wdk400.csv` | 74 | 6 |
| `wdk500.csv` | 64 | 6 |

### gear_class_whm (10 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `whm0j4.csv` | 64 | 6 |
| `whm0j6.csv` | 60 | 6 |
| `whm0j1.csv` | 50 | 6 |
| `whm0j2.csv` | 50 | 6 |
| `whm0j5.csv` | 49 | 6 |
| `whm0j3.csv` | 28 | 6 |
| `whm0j9.csv` | 1 | 6 |
| `whm1j0.csv` | 1 | 6 |

(+ 2 more -- see `ffxivtool_table_catalog.csv`)

### gear_class_wvr (6 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `wvr300.csv` | 101 | 6 |
| `wvr306.csv` | 92 | 6 |
| `wvr400.csv` | 81 | 6 |
| `wvr200.csv` | 79 | 6 |
| `wvr506.csv` | 55 | 6 |
| `wvr500.csv` | 46 | 6 |

### gear_common (48 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `compatibility.csv` | 219 | 53 |
| `com0l6.csv` | 106 | 6 |
| `com0u5.csv` | 96 | 6 |
| `com5l0.csv` | 90 | 6 |
| `com0g5.csv` | 87 | 6 |
| `com0g6.csv` | 81 | 6 |
| `com5u0.csv` | 79 | 6 |
| `com0l5.csv` | 78 | 6 |

(+ 40 more -- see `ffxivtool_table_catalog.csv`)

### gear_etc (175 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `etc106.csv` | 344 | 6 |
| `etc304.csv` | 144 | 6 |
| `etc5l3.csv` | 88 | 6 |
| `etc0g4.csv` | 74 | 6 |
| `etc3g1.csv` | 55 | 6 |
| `etc3u1.csv` | 55 | 6 |
| `etc0u4.csv` | 54 | 6 |
| `etc3l1.csv` | 50 | 6 |

(+ 167 more -- see `ffxivtool_table_catalog.csv`)

### gear_grandcompany (57 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `gcg701.csv` | 501 | 6 |
| `gcl105.csv` | 396 | 6 |
| `gcl107.csv` | 307 | 6 |
| `gcl104.csv` | 262 | 6 |
| `gcl106.csv` | 212 | 6 |
| `gcl101.csv` | 179 | 6 |
| `gcg102.csv` | 117 | 6 |
| `gcl102.csv` | 103 | 6 |

(+ 49 more -- see `ffxivtool_table_catalog.csv`)

### gear_neck (4 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `noc003.csv` | 130 | 6 |
| `noc000.csv` | 99 | 6 |
| `noc002.csv` | 93 | 6 |
| `noc001.csv` | 68 | 6 |

### gear_other (56 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `boot_skillequip.csv` | 1020 | 23 |
| `man502.csv` | 425 | 6 |
| `man308.csv` | 390 | 6 |
| `man206.csv` | 372 | 6 |
| `man0g1.csv` | 366 | 6 |
| `man300.csv` | 364 | 6 |
| `man0u1.csv` | 360 | 6 |
| `man504.csv` | 326 | 6 |

(+ 48 more -- see `ffxivtool_table_catalog.csv`)

### gear_spellcraft (24 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `spl101.csv` | 203 | 6 |
| `spl102.csv` | 129 | 6 |
| `spl0i1.csv` | 105 | 6 |
| `spl0i2.csv` | 90 | 6 |
| `spl0i3.csv` | 78 | 6 |
| `spl0i4.csv` | 71 | 6 |
| `spl000.csv` | 62 | 6 |
| `spl0g2.csv` | 47 | 6 |

(+ 16 more -- see `ffxivtool_table_catalog.csv`)

### gear_world (40 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `wld0l2.csv` | 31 | 6 |
| `wld0g2.csv` | 29 | 6 |
| `wld0l4.csv` | 24 | 6 |
| `wld0g3.csv` | 24 | 6 |
| `wld0u1.csv` | 22 | 6 |
| `wld0l1.csv` | 21 | 6 |
| `wld0g4.csv` | 20 | 6 |
| `wld0u3.csv` | 19 | 6 |

(+ 32 more -- see `ffxivtool_table_catalog.csv`)

### text_localization (60 files)

| File | Rows | Cols |
|------|-----:|-----:|
| `xtx_itemName.csv` | 8403 | 136 |
| `xtx_displayName.csv` | 5813 | 21 |
| `xtx__text_ui.csv` | 4355 | 6 |
| `worldMaster.csv` | 2321 | 7 |
| `xtx__text_ui(2).csv` | 1821 | 5 |
| `xtx_command.csv` | 1662 | 134 |
| `xtx_placeName.csv` | 923 | 10 |
| `xtx__fixedPhrase.csv` | 758 | 13 |

(+ 52 more -- see `ffxivtool_table_catalog.csv`)

## Later / cosmetic tables

| File | Category | Relevance | Rows | Cols |
|------|----------|-----------|-----:|-----:|
| `var_equip.csv` | gear_variants | cosmetic | 32277 | 112 |
| `var_tex_path.csv` | gear_variants | cosmetic | 29 | 26 |
| `var_wep.csv` | gear_variants | cosmetic | 1437 | 205 |
| `_boot_error_type.csv` | system | later | 57 | 4 |
| `_group.csv` | system | later | 38 | 29 |
| `_layout.csv` | system | later | 173 | 5 |
| `_movie.csv` | system | later | 22 | 8 |
| `_region.csv` | system | later | 61 | 3 |
| `_staffroll.csv` | system | later | 1147 | 4 |
| `_text_error_type(2).csv` | system | later | 85 | 4 |
| `_text_error_type.csv` | system | later | 90 | 4 |
| `_worldMasterLogCategory.csv` | system | later | 1948 | 6 |
| `test_a-ohta__test.csv` | system | later | 10 | 4 |
| `test_sample_clientSheet.csv` | system | later | 5 | 4 |

## How to regenerate

```powershell
& .\tools\build_ffxivtool_catalog.ps1
& .\tools\render_ffxivtool_catalog_md.ps1
```

Both scripts are idempotent and rewrite the catalog files in place.

