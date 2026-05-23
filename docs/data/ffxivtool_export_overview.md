# FFXIVTool Client Data Export Overview

This document captures what the FFXIVTool exports under
`data/client_exports/ffxivtool/` are, how the three subfolders
differ, where they came from, and which one should be considered
canonical for a MeteorReborn-style server import.

## Source

- **Tool:** FFXIVTool Data Ver.13.03.01.0
- **Client patch:** FFXIV 1.23b (`2012.09.19.0001`)
- **Tool binary + temp/ini live under** `tools/local/ffxivtool/`
  and are not committed (see `.gitignore`).

## What is in the export root

```
data/client_exports/ffxivtool/
├── decode_csv/        803 files  --  CANONICAL for server import
├── mycsv/               2 files  --  Item + Command denormalized convenience views
├── raw_csv/           803 files  --  Binary-fidelity reference (template tokens kept opaque)
└── ShopList.txt         1 file   --  Compact legacy shop-table summary (auxiliary)
```

All three CSV folders use the same FFXIVTool 2-line header layout:

```
row 0: , 0, 1, 2, 3, ...                <-- column index header
row 1: , s32, str, s32, bool, ...       <-- per-column type header
row 2+: actual data rows
```

## raw_csv vs decode_csv

`raw_csv` and `decode_csv` have:

- identical filename sets (803 == 803, perfect set match)
- identical row counts per file
- identical schemas (row 0/1 are byte-identical for every file checked)
- identical IDs in column 0 for every row
- **different content** in string columns that contain game text
  templates (475 of 803 files differ in byte length)

The difference is one of **template token decoding**, not of data.

### Concrete example — `worldMaster.csv` row 10101

```
raw_csv:
  éÿ(ÿxtx/displayNameéë,-%ÿ#éÿ(ÿxtx/displayNameéë, ...

decode_csv:
  [@IF($E9(7),[@SHEET(xtx/displayName,$E9(7),0)],$EB(2))],
  [@2D([@IF($E9(7),[@SHEET(xtx/displayName,$E9(7),1)],$EB(2))])], ...
```

The client's text engine consumes a custom byte-token language
for runtime text composition (`SHEET(...)` for cross-table
lookups, `IF(...)` for conditional text, `@CR` for line break,
icon refs, color refs, gender/plural switches, etc.).

- `raw_csv` keeps that language in its **raw byte representation**.
- `decode_csv` lossless-decodes it to a **printable token form**
  that's identical in meaning but human-readable.

A binary round-trip raw -> decode -> raw is in principle
possible because the token grammar is deterministic.

### What the server actually needs

Almost all of this text data is **NOT pushed by the server**.
The client owns the sheets locally and renders text from row id
+ runtime variable bindings. The server pushes IDs and binding
values; the client expands the templates.

So strings are only directly useful to the server for:

- admin tools (item search, NPC search by name, shop listings)
- log readability
- localization of system-pushed strings (e.g. mail, error msgs)

Both folders give the **same row IDs**, which is the part the
server actually transmits.

## mycsv: denormalized convenience views

`mycsv` contains only 2 files:

```
Item.csv     142 columns,  8522 data rows,  5.3 MB
Command.csv  140 columns,  3335 data rows,  1.1 MB
```

These are **denormalized joins** that FFXIVTool produces over
the most-queried tables:

- `mycsv/Item.csv` joins: `itemData.csv` + `xtx_itemName.csv`
  + per-slot stat columns. (8522 rows vs 8405 in itemData,
  i.e. some rows present in xtx_itemName but not itemData are
  included for completeness.)
- `mycsv/Command.csv` joins: `command.csv` + `gameCommand.csv`
  + `xtx_command.csv`. (3335 rows vs 1664 + 1613 in the source
  tables -- some commands are present in only one source.)

These are convenience views for browsing / admin tooling. They
must **not** be used as the import source of truth, because they
collapse the normalized schema. The server DB should mirror the
normalized tables (`itemData`, `xtx_itemName`, `command`,
`gameCommand`, `xtx_command`) and reconstruct any joined view
in SQL.

## ShopList.txt: legacy compact shop reference

A small 3.5 KB plain-text file with 7-column space-padded rows
in 4 blocks separated by blank lines.

Schema (deduced; not yet confirmed against EXE/Lua):

```
<shop_id>, <col1>, <col2>, <col3>, <col4>, <col5>, <col6>
```

ID block structure suggests grouped vendor families:

```
Block 1: ids   101..118   (18 rows)   --  ?  city / starter vendors
Block 2: ids 1001..1019   (19 rows)   --  ?  one vendor group
Block 3: ids 2001..2022   (22 rows)   --  ?  one vendor group
Block 4: ids 3001..3022   (22 rows)   --  ?  one vendor group
Block 5: id    4001        (1 row)    --  ?  one outlier
```

The numbers inside each row look like item IDs / NPC IDs / SSD
shop bindings. This is a hand-maintained or legacy aggregation
file -- not a generated CSV. It complements but does NOT
replace `shopBase.csv` / `shopItem.csv` / `gcSealShopItem.csv` /
`marketItem.csv` / `populaceCompanyShop.csv` /
`populaceGuildShop.csv` / `populaceShopSalesman.csv` /
`populaceShopMateriaRemover.csv` / `populaceItemRepairer.csv`
in the CSV exports.

Likely interpretation (Speculative, needs EXE/Lua correlation):

- col 0: shop id (a 1xxx, 2xxx, 3xxx group)
- col 1-3: linked SSD row ids (probably shopBase / shopItem refs)
- col 4: item id (only set for block 1)
- col 5-6: unused / future

The shop subsystem belongs to the negotiation/event family (see
`docs/re/lua/finding_negotiation_judge.md` and related), and
the canonical sources are the normalized shop CSVs. ShopList.txt
should be kept as **secondary / verification** data.

## Decision: canonical source for server import

```
PRIMARY canonical:   data/client_exports/ffxivtool/decode_csv/
FIDELITY reference:  data/client_exports/ffxivtool/raw_csv/
CONVENIENCE views:   data/client_exports/ffxivtool/mycsv/
AUXILIARY reference: data/client_exports/ffxivtool/ShopList.txt
```

Reasons:

1. `decode_csv` and `raw_csv` carry the **same numeric IDs and
   the same row structure**. Either works for ID-based import.
2. `decode_csv` is **human-readable**, which makes import scripts,
   data validation, and diff inspection dramatically easier.
3. Server only transmits IDs + numeric/bool/short string fields;
   it does not push template-encoded text. Decoded tokens are
   strictly a debugging/admin win.
4. If a future need arises to render exact client-style text
   server-side (e.g. for a logged-out web UI), `raw_csv` is
   still available, and the token grammar is documented well
   enough that re-encoding decoded -> raw is feasible.
5. `mycsv` is a derived join, not a source. Re-deriving the join
   in SQL is trivial.

## Confidence

```
Confirmed:
  - raw_csv and decode_csv have identical filename sets, row counts,
    and column schemas (verified programmatically).
  - decode_csv expands FFXIVTool text-template tokens to printable
    form ([@IF...], [@SHEET...], [@CR], etc.).
  - mycsv contains only Item.csv (8522 rows, 142 cols) and
    Command.csv (3335 rows, 140 cols), both denormalized joins.
  - ShopList.txt is 7-column plain text, 4 numerical blocks +
    1 outlier row, with grouped ID ranges 1xx / 1xxx / 2xxx /
    3xxx / 4xxx.

Likely (High):
  - decode_csv string expansion is lossless w.r.t. row IDs and
    non-text columns. Any consumer that only reads numeric IDs
    gets identical results from raw or decoded.
  - mycsv joins were generated by FFXIVTool in a single pass and
    are not maintained as primary data; the source-of-truth is
    the normalized tables.

Likely (Medium):
  - ShopList.txt id ranges 1xxx / 2xxx / 3xxx correspond to
    Maelstrom / Twin Adder / Immortal Flames grand-company
    shops; block 4001 may be a special vendor.
  - col 4 in block 1 (101..118) holds an item id that is the
    "featured" / required item for that shop entry.

Speculative:
  - ShopList.txt may have been manually edited at some point by
    the user / extractor as a vendor cross-check before the full
    SSD shop tables were exported. The format is too compact and
    too regular to be a tool-generated artifact.
```

## Next test

- Pick 3 ids in `ShopList.txt` and locate them in
  `shopBase.csv` / `shopItem.csv` / `populaceShopSalesman.csv`
  to confirm the column meaning of cols 1-3.
- Confirm row 0 of `worldMaster.csv` raw vs decode is byte-equal
  outside of template tokens (i.e. confirm the decoder is lossless).
- Spot-check 10 random rows of `itemData.csv` between raw and
  decode to confirm zero numeric differences.

## Commit suggestion

```
docs(data): document FFXIVTool export structure and canonical source decision
```
