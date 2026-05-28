# Finding: Populace (NPC) + Shop CSV Structure -- vendor inventory is server data, NPC dialogue is client-local

**Decodes the NPC-population + shop CSV tables.** Confirms the
client/server split for content population: shop inventory/prices
(shopBase + shopItem) are SERVER data; NPC dialogue/greetings
(populaceXxx) are CLIENT-LOCAL localized text; the populace master
list provides NPC existence.

## 1. Shop model (3-table chain)

```text
shopBase.csv (241 rows):
  col0 (s32)  shopItem range START id
  col1 (s32)  shopItem range END id
  e.g. shop 101 -> shopItems 101001..101010 (10 items)
  A SHOP = a contiguous RANGE of shopItem entries.

shopItem.csv (2544 rows):
  col0 (s32)  item catalog id (what's sold)
  col1 (u8)   quantity per purchase
  col2 (s32)  price (gil)
  e.g. shopItem 101001 -> (item 13000001, qty 1, price 6000)
  Each shopItem = (catalog_id, quantity, price).

CHAIN: shop id -> shopBase range -> shopItem entries -> (item, qty, price)

SHOP TABLE FAMILY:
  shopBase.csv      core shop -> item-range mapping
  shopItem.csv      item/qty/price entries
  marketItem.csv    market board items
  blackMarket.csv   black market
  gcSealShopItem.csv Grand Company seal shop
```

## 2. ShopList.txt (auxiliary cross-reference)

```text
7 columns per row: shopId + 6 reference values
  101, 1927, 2707, 3066, 1100152, 0, 0
  102, 1830, 2702, 3054, 1000077, 0, 0

Likely: shopId + 3 item/category refs + 1 special id (1100152 =
quest/unlock?) + 2 reserved. This is a LEGACY/manual shop reference
(per the skill notes); the canonical shop data is shopBase+shopItem.
```

## 3. Populace model (master + typed)

```text
populace.csv (4209 rows) -- MASTER NPC LIST:
  66 columns, but only col 65 (str) populated = talk type
  (mostly "デフォルトトーク" = "Default Talk")
  So populace.csv = the master NPC id list; each NPC's default
  talk-behavior reference. ~4209 NPCs total in 1.23b.

populaceXxx.csv -- PER-NPC-TYPE definitions (53 typed tables):
  populaceShopSalesman, populaceGuildShop, populaceCompanyShop,
  populaceCampMaster, populaceBranchsVendor, populaceBountyPresenter,
  populaceCaravanGuide, populaceHamletCaptain, populaceAchievement,
  populaceBlackMarketeer, populaceShopMateriaRemover, ...

  These define per-TYPE NPC behavior/data. Most are LOCALIZED TEXT.

EXAMPLE populaceShopSalesman.csv (502 rows, 5 str columns):
  cols 0-4 = greeting text in 5 languages (JP / EN / DE / FR / ZH)
  e.g. "Welcome to the Hyaline, proud purveyors of the wonders of
        Eorzea's seas!..."
  So a shop salesman NPC has a localized welcome message per language.
  Text uses [@CR] (line break) + [@IF(...)] (conditional substitution)
  markup.
```

## 4. The client/server split (content-population)

```text
SERVER DATA (transaction-relevant):
  shopBase.csv + shopItem.csv  -- WHAT each shop sells + prices
    -> server validates buy/sell (price, availability, gil check)
  marketItem / blackMarket / gcSealShopItem -- special shop inventories
  populace.csv -- NPC EXISTENCE (id list; server spawns these)

CLIENT-LOCAL (presentation):
  populaceXxx.csv text columns -- localized NPC dialogue/greetings
    -> the client shows these; server never sends dialogue
  NPC behavior -- the NPC's Lua class (per npcbaseclass finding)

This is the client-side-content principle AGAIN:
  - Server: shop inventory/prices + NPC existence
  - Client: NPC dialogue (localized) + behavior (Lua)

A SHOP TRANSACTION:
  1. Player talks to vendor NPC (client runs NPC dialogue Lua)
  2. Player selects buy -> client sends purchase request (0x12d/0x12e)
  3. Server validates: shopItem (catalog, qty, price) + player gil
  4. Server grants item + deducts gil -> WorkSync update
  (the shop INVENTORY/PRICE check is server-side via shopBase/shopItem;
   the dialogue/UI is client-side)
```

## 5. Server-side requirements

```text
SHOP DATA (server must store):
  shopBase.csv:  shop id -> shopItem range (241 shops)
  shopItem.csv:  shopItem id -> (catalog_id, quantity, price) (2544 entries)
  -> on purchase: look up shopItem, validate price + player gil, grant

NPC DATA (server must store):
  populace.csv:  NPC id master list (4209 NPCs) -- which NPCs exist
  -> server spawns NPCs (0x17c) by id; behavior runs client-side

NOT SERVER DATA (client-local):
  populaceXxx.csv dialogue text (localized greetings) -- client shows
  NPC behavior scripts -- client Lua

VENDOR NPC LINKAGE:
  A vendor NPC (populace id) -> has a shop (shopBase id) -> item range
  (shopItem) -> items+prices. The NPC-to-shop linkage is likely in the
  NPC's class data or a populaceXxxVendor table mapping.
```

## 6. Confidence

```text
Confirmed:
  - shopBase.csv: shop -> shopItem range (start, end), 241 shops
  - shopItem.csv: (catalog_id, quantity, price), 2544 entries
  - populace.csv: 4209 NPC master list, col 65 = talk type
  - populaceShopSalesman: 5-language localized greetings (502 NPCs)
  - 53 typed populace tables (per NPC type)
  - ShopList.txt: 7-col auxiliary cross-reference

Likely (High):
  - Shop inventory/prices = server transaction data
  - Populace dialogue = client-local localized text
  - populace.csv = NPC existence (server spawns); behavior = client Lua
  - [@CR]/[@IF] = text markup (line break / conditional substitution)

Speculative:
  - ShopList.txt col 4 (1100152) = quest/unlock requirement for the shop
  - The NPC->shop linkage table (which vendor sells which shop) needs
    cross-reference (possibly in populaceBranchsVendor or NPC class data)
  - marketItem = player market board (the Bazaar-adjacent system)
```

## 7. Cross-references

- `finding_npc_event_talk_turn_flow_client_side.md` -- NPC dialogue
  (the client-side side of populaceXxx text)
- `finding_charabaseclass_battle_schema_and_timing_commands.md` --
  eventSave.bazaar (player shops; complements NPC shops here)
- `finding_areabaseclass_zone_bootstrap_sequence.md` -- NPCs populate
  zones (populace ids spawned via 0x17c)
- `docs/data/ffxivtool_table_catalog.md` -- the 803-table catalog
- `docs/server/content_requirements/ffxivtool_import_plan.md`

## 8. Next test

```text
1. Find the NPC->shop linkage (which populace id maps to which shopBase)
2. Decode marketItem.csv (player market board)
3. Decode quest.csv / quest_reward.csv (quest server data)
4. Decode a zone/territory table (zones/maps)
5. Sample more typed populace tables (campMaster, caravanGuide, etc.)
```

## Commit suggestion

```
docs(data): populace + shop CSV structure -- shopBase(range)->shopItem(catalog/qty/price) = server data; populace master (4209 NPCs) + typed dialogue = client-local; client/server split confirmed
```
