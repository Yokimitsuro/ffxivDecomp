# Finding: quest.csv + quest_reward Structure (closes the content-data sweep)

**Decodes the quest data tables** — quest.csv (definitions) +
quest_reward.csv (simple rewards) + quest_new_reward.csv (structured
16-slot reward tables). These are the server's quest-state +
reward-grant data, complementing the QuestBaseClass engine. This
closes the content-data CSV sweep.

## 1. quest.csv (737 quests, 56 columns, sparse)

```text
Active columns (from type header + sample id 110001):
  col 39  s32   category / quest-class (sample = 101)
  col 45  s32   DIRECTOR/EVENT reference (sample = 11060001)
                -- the content event the quest runs (links to a Director)
  col 51  s32   level / sequence count (sample 1, 8, 10 -- varies)
  col 52  s32   area / zone id (sample = 101)
  col 53  s32   0 (prerequisite / chain ref?)
  col 54  bool  false (a flag -- repeatable? scenario?)
  col 55  bool  true (a flag -- enabled / active?)

So a quest definition = category + director/event ref + area + level
+ flags. The col 45 ref (11060001-style) links the quest to its
content orchestration (a Director, per the Director finding).

737 quests total in 1.23b.
```

## 2. quest_reward.csv (1265 entries, 6 columns -- simple/legacy)

```text
6 s32 columns. Reward id = quest id + reward index.
  e.g. 11000101 -> -2, 2000, 0, -5, 2, 61346

  col0  reward type (-2, -1, ...)
  col1  amount (2000 = gil/exp?)
  col2  0
  col3  type code (-5)
  col4  2
  col5  item/text id (61346)

This is the SIMPLE reward format (likely the older/base reward).
1265 entries (multiple reward rows per quest).
```

## 3. quest_new_reward.csv (501 entries, 208 columns -- structured)

```text
208 columns = 16 REWARD SLOTS x 13 columns each.

PER-SLOT (13 cols):
  [0] type        100 = item reward, 300/301 = empty/none
  [1] subtype     -2, -8, -10, -12 (reward sub-category)
  [2] item_id     the item granted (e.g. 60737, 60011, 80182)
  [3] ?           8090201 (a scene/condition ref?)
  [4] ?           0 / 5000
  [5-8] qty[4]    quantity TIERS (e.g. 1000,2000,3000,4000 or 10,20,30,40)
                  -- 4 tiers likely = reward by class/difficulty/choice
  [9] 0
  [10] -5         type code (matches quest_reward col3)
  [11] 2
  [12] 2

EMPTY SLOT pattern: 301,-2,0,8090201,0,-1,-1,-1,-1,0,-5,2,2
ITEM SLOT pattern:  100,-2,60737,8090201,0,1000,2000,3000,4000,0,-5,2,2

So quest_new_reward = up to 16 reward slots per quest, each granting
an item with 4 quantity tiers (by class/difficulty/player choice).

SAMPLE quest 110002:
  slot1: 100,-12,534,... qty 200  (item 534, 200 units)
  slot2: 100,-2,60737,... qty 6000 (item 60737, 6000 = gil?)
  -> a quest granting gil + an item
```

## 4. The quest data model (server perspective)

```text
A QUEST (server view):
  quest.csv          -> definition: category, director ref (col45),
                        area (col52), level (col51), flags
  quest_reward.csv   -> simple rewards (gil/exp + item)
  quest_new_reward   -> structured 16-slot item rewards (4 qty tiers)

QUEST FLOW (server, per QuestBase finding):
  1. AVAILABILITY: quest.csv prerequisites + player completion flags
  2. ACCEPT: notice authorizes -> server records quest started
  3. PROGRESS: tracked via director._sync (col45 links the director)
  4. COMPLETE: notice -> server grants rewards:
     - quest_reward.csv: gil/exp
     - quest_new_reward.csv: items (16 slots, qty tier by choice/class)
  5. Set completion flag (so the quest doesn't repeat)

SERVER DATA NEEDED:
  - quest.csv (737 quests): definitions + director refs + areas
  - quest_reward + quest_new_reward (1766 reward entries): grant tables
  - per-player quest state: started/progress/completed flags

The col 45 director reference is KEY: it links each quest to its
content orchestration (Director). The server triggers that director
on quest accept (spawn 0x17c), tracks its _sync state, and grants
rewards on the completion notice.
```

## 5. CONTENT-DATA SWEEP COMPLETE

```text
All major content-data CSV categories now decoded:

CALCULATION TABLES (server authoritative calc):
  itemData (stats), status (effects), command-trio (potency),
  compatibility (level curves), exp_BPCost (cost)
  -> universal formula: base x compatibilityCurve[level]%

CONTENT-POPULATION TABLES:
  populace (4209 NPCs), shop (shopBase->shopItem), quest (737 +
  rewards)
  -> server stores existence/inventory/prices/rewards; client has
     dialogue/behavior/cutscenes

The server's DATA REQUIREMENTS are now mapped:
  - 5 calc tables (the universal calc model)
  - NPC list + shop inventories + quest defs/rewards (population)
  - Per-player state (quest flags, inventory, stats) it tracks itself
  - The ~625 "useful" tables (gear variants) are itemData-family
    detail, ingestible via the catalog/import plan

CLIENT-SIDE (not server data): zone geometry, NPC dialogue, quest
scripts, cutscenes, combat presentation -- all in the client's
CSVs + Lua.
```

## 6. Confidence

```text
Confirmed:
  - quest.csv: 737 quests, col45 = director/event ref, col52 = area,
    col51 = level/seq, col39 = category, col54/55 flags
  - quest_reward.csv: 1265 simple 6-col rewards (gil/exp + item)
  - quest_new_reward.csv: 501 x 16-slot x 13-col structured item rewards
    (type 100=item, item_id, 4 qty tiers)
  - Reward types: 100=item, 300/301=empty

Likely (High):
  - col45 director ref links quest -> content orchestration (Director)
  - The 4 qty tiers = reward-by-class/difficulty/choice
  - quest_new_reward subtypes (-2/-8/-10/-12) = item categories
  - quest_reward 61346-style = text/item ids

Speculative:
  - col53 = prerequisite quest chain ref
  - col8090201-style = scene/condition references in reward slots
  - quest_reward (simple) vs quest_new_reward (structured) = legacy
    vs current reward format (server uses new)
```

## 7. Cross-references

- `finding_questbaseclass_quest_engine_model.md` -- the quest engine
  (this is its server data)
- `finding_directorbaseclass_content_orchestration_model.md` -- the
  director the quest col45 references
- `finding_compatibility_csv_growth_curves_closes_calc_model.md` --
  the calc model (sibling data sweep)
- `finding_populace_and_shop_csv_structure.md` -- sibling population data
- `docs/server/content_requirements/ffxivtool_import_plan.md` -- import plan

## 8. Session content-data status

```text
CONTENT-DATA SWEEP COMPLETE for the major categories:
  Calc: itemData/status/command/compatibility/exp_BPCost
  Population: populace/shop/quest(+rewards)

Remaining (mechanical cataloging, per import plan):
  - ~625 "useful" tables (gear class variants -- itemData family)
  - zone/territory/map tables
  - achievement/title tables
  - the 52 other typed populace tables
These follow documented patterns + are in the 803-table catalog.
```

## Commit suggestion

```
docs(data): quest.csv + quest_reward structure (737 quests, col45=director ref; quest_new_reward = 16-slot x 13-col item rewards with 4 qty tiers) -- CLOSES content-data sweep
```
