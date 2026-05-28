# FFXIV 1.x Client Reverse-Engineering Research

Reverse-engineering of the **FINAL FANTASY XIV 1.23b** client
(`2012.09.19.0001`) to document what the client expects from a
compatible server. This is **interoperability research only** -- a
reference corpus for lawful compatible-server implementations done by
others. It is **not** a server, and contains no proprietary source
dumps, DRM/auth bypasses, or live-service abuse tooling.

> **Status: research goal complete.** The 1.x client's behavioral,
> network, and data surface is decomposed to the level needed as a
> compatible-server reference. 200+ findings across 246+ commits.

## Start here

| Document | What it is |
|----------|-----------|
| [`docs/re/MASTER_INDEX_1.x_MODEL.md`](docs/re/MASTER_INDEX_1.x_MODEL.md) | Executive summary + session narrative + documentation map |
| [`docs/re/QUICK_REFERENCE.md`](docs/re/QUICK_REFERENCE.md) | Single-page lookup tables for every architectural fact |
| [`docs/re/ghidra_symbol_map.md`](docs/re/ghidra_symbol_map.md) | ~360 named functions (address -> name) + re-import script for a fresh Ghidra analysis of the same binary |

The MASTER_INDEX has the narrative; the QUICK_REFERENCE has the tables.

## What was established

**The architectural principle (confirmed across 7 independent layers):**

> **Content is client-side; the server orchestrates state, triggers,
> and authorization.**
> The client is the rich content engine (zone geometry, NPC dialogue,
> combat formulas, cutscenes, appearance). A compatible server is an
> *orchestrator*: it spawns actors by class, replicates state via
> WorkSync, authorizes actions via notices, and grants rewards. It
> never sends content. This is why the wire protocol is compact and a
> server is feasible.

**The four pillars:**

1. **Wire protocol -- 100% bidirectional.** Inbound game opcodes
   `0x143-0x1a8` (~50 semantically named) + session `0x02-0x11`;
   outbound `0x12d-0x135` + chat. Key opcodes: `0x17c` SPAWN,
   `0x143` DESPAWN, `0x148-0x156` per-actor 3x5 message matrix,
   `0x187`/`0x18b` state batches, `0x12d` player command (CRC32
   integrity), `0x12e` RPC, `0x12f`/`0x135` WorkSync/subscribe.
   The command checksum is standard CRC32 (transport integrity, not
   anti-cheat) -- server-replicable.

2. **13 engine base mechanics.** ActorBase, CharaBase, PlayerBase,
   NpcBase, AreaBase, DirectorBase, QuestBase, StatusBase, CommandBase,
   Judge, ItemBase, GroupBase, WidgetBase/DesktopWidget. The remaining
   ~2600 Lua files are *instances* of these patterns.

3. **Server calculation model -- closed.** Five tables drive all
   item/status/command potency via one formula:
   `effectiveValue = baseValue x compatibilityCurve[key][level] / 100`
   (itemData, status, command-trio, compatibility, exp_BPCost).

4. **Content data -- swept.** All 803 FFXIVTool CSV tables accounted
   for: **704 are client-local localized text** (dialogue/names),
   **99 carry data**, and all server-relevant data tables are decoded
   or characterized. (Notably: the "~625 gear-variant" tables were a
   mis-scope -- they are quest/guild dialogue, not gear stats.)

## Documentation layout

```text
docs/
├─ re/
│  ├─ MASTER_INDEX_1.x_MODEL.md     executive summary + doc map
│  ├─ QUICK_REFERENCE.md            lookup tables
│  ├─ exe/          (90)  native EXE findings (Ghidra MCP analysis)
│  ├─ lua/          (97)  Lua script / engine findings
│  └─ correlation/  (14)  EXE <-> Lua <-> data bridges
├─ data/            (12)  FFXIVTool CSV catalog + column-structure findings
│  └─ ...                 calc model, shop/quest/populace, gear sheets,
│                         actorclass, the text-vs-data correction + audit
├─ packets/          (4)  lobby packet layouts
└─ server/
   └─ content_requirements/  CSV import plan
```

## What a compatible server needs (per this research)

- The wire opcodes above, in both directions (all documented).
- The 5 calc tables + 5 gear-stat sheets (the universal calc model).
- Population data: NPC/actor-class list, shop inventories, quest
  definitions + rewards (~45 server-relevant data tables, all identified).
- Per-player state it tracks itself (quest flags, inventory, stats).
- It does **not** need the 704 localized-text tables, cosmetic dye
  maps, name lookups, or UI/boot config -- those are client-local.

## Optional refinements (not pursued -- diminishing returns)

- Byte-exact WorkPath wire serialization + S->C broadcast opcode
  confirmation (would need a live-client wire capture to validate).
- Full column semantics of minor tables (`2Dmap_*`, `guildleve`,
  `request`) -- decodable on demand.
- Spot-checking individual Lua content instances against the base
  patterns (coverage, not new architecture).

## Scope and safety

Research repository only. Game binaries, Lua bytecode, FFXIVTool, and
`config/project.local.yml` are local-only and never committed. Findings
document client behavior for lawful compatible-server work; they do not
reproduce proprietary source or defeat any protection mechanism.
