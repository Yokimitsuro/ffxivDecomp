---
name: ffxiv-1x-server-decomp
version: 0.4.0
description: Use this skill when reverse engineering Final Fantasy XIV 1.0 / 1.23b client EXE binaries with Ghidra MCP, Lua scripts/bytecode, and FFXIVTool static data exports in order to document client behavior, packet formats, opcode meanings, client state machines, EXE-Lua-data relationships, and server/content requirements for a compatible MeteorReborn-style server.
---

# FFXIV 1.x Server Decomp Skill

## Mission

Analyze Final Fantasy XIV 1.0 / 1.23b client behavior using three evidence sources:

1. **Native EXE analysis through Ghidra MCP**
2. **Lua script / Lua bytecode analysis**
3. **FFXIVTool static client data exports**

The goal is to understand what the client expects from a compatible server:

- login / lobby / world / zone flows
- packet layouts and opcodes
- EXE packet dispatch and serialization behavior
- Lua-driven client behavior and UI/state transitions
- actor/session/character state
- zone entry and scene loading sequence
- script calls into native functions
- server responses required to make the client progress
- static client data required to populate a compatible server database
- relationships between client data tables, Lua behavior, and native EXE packet/state handling

This is an interoperability research skill. It is not a request to recreate or redistribute proprietary source code.

Prefer:

- concise pseudocode summaries
- function roles and cautious names
- packet/struct layouts with confidence labels
- EXE ↔ Lua cross-references
- EXE/Lua ↔ static data table cross-references
- call graphs
- state-machine notes
- server implementation requirements
- server content/database import requirements
- committed Markdown findings

Do **not** output large proprietary decompiled source dumps. Do **not** help bypass DRM, account systems, payments, anti-cheat, authentication, or online service protections. Do **not** create cheating, botting, exploit, or live-service abuse functionality. Focus on documenting client behavior needed for a lawful compatible server implementation.

---

# Local Project Configuration

This skill expects the research repository to contain a local configuration file. The assistant must look for this file before starting work:

```text
config/project.local.yml
```

This file is intentionally local-only and must not be committed. It may contain machine-specific paths such as:

```yaml
repo:
  url: "https://github.com/Yokimitsuro/ffxivDecomp.git"
  local_path: "."

game:
  root: "E:\\Program Files (x86)\\SquareEnix\\FINAL FANTASY XIV"
  exe_search_patterns:
    - "*.exe"
  lua_search_patterns:
    - "*.lua"
    - "*.luac"
    - "*.lub"

tools:
  unluac_jar: "tools/local/unluac.jar"

ffxivtool:
  local_tool_dir: "tools/local/ffxivtool"
  exports_dir: "data/client_exports/ffxivtool"
  decode_csv: "data/client_exports/ffxivtool/decode_csv"
  mycsv: "data/client_exports/ffxivtool/mycsv"
  raw_csv: "data/client_exports/ffxivtool/raw_csv"
  shoplist: "data/client_exports/ffxivtool/ShopList.txt"
  ignore_temp: true
```

Required behavior:

1. If `config/project.local.yml` exists, read it before making assumptions about paths.
2. If it does not exist, copy or adapt `config/project.local.example.yml`.
3. Never commit `config/project.local.yml`, `tools/local/unluac.jar`, game binaries, extracted proprietary assets, or full decompiled source dumps.
4. Use the configured `game.root` only as an input location. Findings must go into the research repository, not inside the game install directory.
5. Use `tools.unluac_jar` only for Lua bytecode owned/provided by the user. Preserve the original bytecode and write decompiled output under `lua/decompiled/`.

Before any EXE, Lua, or static data task, report:

```text
Config loaded: yes/no
Repo local path:
Game root:
unluac.jar path:
FFXIVTool exports path:
Ghidra MCP connected: yes/no/unknown
```

---

# Required Output Shape

Every substantial answer must include:

```text
Confirmed:
Likely:
Speculative:
Next test:
Commit suggestion:
```

Never present guesses as facts.

Confidence values:

- `Confirmed`
- `High`
- `Medium`
- `Low`
- `Speculative`

---

# Core Workflow

## Step 0: Verify Context

Before working, confirm:

```text
Research repo/worktree:
Current branch:
Target type: EXE / Lua / EXE-Lua correlation / FFXIVTool data / packet / server requirement / content import requirement
Loaded Ghidra program, if EXE work:
Binary name:
Architecture:
Image base:
Target address/function/opcode/script:
Lua source or bytecode path, if Lua work:
FFXIVTool export path/table, if data work:
Requested output:
```

Do not assume the binary, address, script path, repo, or branch.

---

## Step 1: Claim a Work Unit

A work unit can be:

- one native EXE function
- one opcode handler
- one packet builder/parser
- one Lua file
- one Lua function
- one EXE ↔ Lua bridge call
- one event name / script command
- one state-machine transition
- one call chain
- one client flow, such as character select or zone entry
- one FFXIVTool export folder
- one static data table
- one table relationship
- one content/database import requirement
- `ShopList.txt` or one vendor/shop data group

Create a claim note before starting:

```text
CLAIMED:
Target:
Type: EXE / Lua / Correlation / FFXIVToolData / Packet / Server / ContentImport
Reason:
Starting hypothesis:
Expected output:
Repo/worktree:
```

Example:

```text
CLAIMED:
Target: FUN_0048A120
Type: EXE
Reason: possible zone packet dispatcher
Starting hypothesis: dispatches incoming zone packets by opcode
Expected output: finding with role, xrefs, packet notes, and server implication
Repo/worktree: meteor-reborn-research
```

Example for Lua:

```text
CLAIMED:
Target: lua/ui/loading_state.lua
Type: Lua
Reason: script may control loading screen transitions
Starting hypothesis: waits for native zone-ready event before hiding loading UI
Expected output: script summary, native calls, event names, server implication
Repo/worktree: meteor-reborn-research
```

If another agent is already working on the same target, do not duplicate work unless the user explicitly asks.

---

## Step 2A: EXE Decompilation with Ghidra MCP

Use this path for native code.

Before naming anything, collect evidence from Ghidra MCP:

1. function signature
2. decompiled output
3. disassembly if decompiler output is unclear
4. callers
5. callees
6. strings referenced
7. constants used
8. data references
9. switch/dispatch patterns
10. nearby functions
11. xrefs to networking imports or packet helpers
12. xrefs to Lua APIs, script loaders, or event dispatchers

Do not rename based on vibes.

Record:

```text
Address:
Original name:
Current hypothesis:
Evidence:
Confidence:
Server relevance:
```

For packet/network functions, track:

```text
Input buffer:
Output buffer:
Packet length:
Opcode / command id:
Source id:
Target id:
Actor/entity/session id:
Endian assumptions:
Read offsets:
Write offsets:
Receive path:
Send path:
State fields modified:
Lua bridge/event calls:
```

---

## Step 2B: Lua Analysis / Lua Decompilation

Use this path for Lua files, Lua bytecode, extracted scripts, UI scripts, event scripts, or client gameplay scripts.

First classify the Lua input:

```text
Lua type: source / bytecode / unknown
Lua version if known:
File path:
Hash/checksum if useful:
Readable source available: yes/no
Decompiler/tool used, if bytecode:
```

If the Lua is source, analyze directly.

If the Lua is bytecode, decompile only when the user has the files and has asked for analysis. Keep tool usage transparent. If decompilation output is noisy, preserve uncertainty and avoid pretending it is exact source.

For each Lua file/function, identify:

```text
Purpose:
Entry points:
Functions defined:
Events handled:
Native/engine calls:
Network-related calls:
State variables:
UI/loading flags:
Zone/actor/character references:
Packet/opcode names or IDs:
Strings useful for EXE search:
Server-side implication:
```

Do not paste whole Lua files unless they are tiny and the user explicitly needs it. Prefer behavioral summaries and small snippets only when necessary.

Important Lua questions:

```text
Does this script wait for a server event?
Does it call into native EXE functions?
Does it register event handlers?
Does it define packet names, command names, or state constants?
Does it gate loading screen completion?
Does it spawn UI based on actor/zone/character state?
Does it expect a specific order of events?
```

---

## Step 2C: EXE ↔ Lua Correlation

Use this path when a finding in EXE references Lua, or Lua references native behavior.

Always try to correlate:

```text
Lua string/function/event name -> EXE string xrefs
Lua native call name -> EXE import/export/wrapper/xref
Lua state variable -> EXE structure/field candidate
Lua event handler -> EXE event dispatcher
Lua packet name/opcode -> EXE packet dispatch table
Lua loading transition -> EXE state flag or callback
```

Correlation output format:

```text
Lua evidence:
EXE evidence:
Bridge hypothesis:
Confidence:
Server implication:
Next test:
```

A correlation can be useful even if incomplete.

---

## Step 2D: FFXIVTool Client Data Export Analysis

Use this path for static client data exported by FFXIVTool Data Ver.13.03.01.0 for FFXIV patch `2012.09.19.0001` / 1.23b.

Expected export layout:

```text
data/client_exports/ffxivtool/
├─ decode_csv/
├─ mycsv/
├─ raw_csv/
└─ ShopList.txt
```

Local-only FFXIVTool files may exist here:

```text
tools/local/ffxivtool/
├─ ffxivtool.exe
├─ ffxivtool.ini
└─ temp/
```

Rules:

1. Treat `data/client_exports/ffxivtool/` as static client data.
2. Treat `tools/local/ffxivtool/` as local tooling only.
3. Never commit `ffxivtool.exe`, `ffxivtool.ini`, `temp/`, or `*.tmp`.
4. Ignore all temporary files generated by FFXIVTool.
5. Do not decompile FFXIVTool unless specifically needed to understand an unknown export format.
6. Prefer analyzing exported CSV/TXT files first.
7. Do not inspect hundreds of tables manually. Always generate an automated catalog first.
8. Compare `raw_csv`, `decode_csv`, and `mycsv` before deciding which export is canonical for server import.
9. Treat `ShopList.txt` as legacy/manual shop or vendor reference data until proven otherwise.

### Export Folder Working Hypotheses

These must be verified by comparing table counts, headers, row counts, columns, and sample rows:

```text
raw_csv    = closest to raw client table values
decode_csv = decoded/human-readable export, usually best starting point for server import
mycsv      = FFXIVTool custom/export format, possibly user-adjusted or easier to browse
ShopList.txt = auxiliary shop/vendor list, not generated temporary data
```

### Automated Catalog First

Before deep analysis, produce an automated catalog with:

```text
filename
export source: raw_csv / decode_csv / mycsv / ShopList
row count
column count
detected type/header rows
non-empty column count
likely category
server relevance: critical / useful / later / cosmetic / unknown
notes
```

Required catalog outputs:

```text
docs/data/ffxivtool_export_overview.md
docs/data/ffxivtool_table_catalog.csv
docs/data/ffxivtool_table_catalog.md
docs/server/content_requirements/ffxivtool_import_plan.md
```

### Server Relevance Classification

Classify each table as one of:

```text
critical
useful
later
cosmetic
unknown
```

Prioritize tables related to:

```text
zones
maps
territories
actors
NPCs
BNPCs
items
commands
actions
shops
quests
levequests
events
player appearance
classes
jobs
spawn data
```

For each important table, document:

```text
Table name:
Export source:
Row count:
Column count:
Detected type/header row:
Likely category:
Server relevance:
Important columns:
Related tables:
Server-side use:
Unknowns:
Next test:
```

### Canonical Import Decision

When comparing export folders, determine:

```text
Which folder is most readable?
Which folder preserves original IDs best?
Which folder has the most complete rows/columns?
Which folder should be canonical for server DB import?
Which folder should be kept as raw verification reference?
Where do Command and Item exports fit if they are separate from SSD exports?
How does ShopList.txt relate to shop/vendor tables?
```

### FFXIVTool Data Output Rule

Every useful FFXIVTool data finding must end with:

```text
Client data observation:
Server database implication:
Possible import table:
Related EXE/Lua evidence needed:
Unknown fields:
Validation test:
```

---

## Step 3: Build Minimal Server Understanding

For every work unit, answer:

```text
What does the client read?
What does the client write/store?
What does the client call next?
What state must be set for the client to continue?
Does this depend on a packet?
Does this depend on Lua event/state?
Does this depend on a native EXE callback?
What must a compatible server send, store, or simulate?
Does this depend on static client data from FFXIVTool exports?
Which data table likely provides the referenced ID/name/object/content?
What remains unknown?
```

Convert findings into server requirements:

```text
Client-side observation:
Server-side implication:
Minimum server behavior:
Required fields:
Unknown fields:
Packet ordering requirement:
Static data/database requirement:
Validation test:
```

---

## Step 4: Iterate, But Know When to Stop

Stop immediately if the work unit is understood enough to be useful for server implementation.

For this skill, “match achieved” means one or more of:

```text
EXE function role identified with High/Confirmed confidence
Lua script purpose identified with High/Confirmed confidence
Opcode handler identified
Packet format documented enough to implement a test server response
Call chain from recv -> dispatch -> handler understood
Call chain from handler -> outgoing packet builder understood
Lua event/state transition identified
EXE -> Lua or Lua -> EXE bridge documented
Client loading/state transition identified
Struct offsets documented with confidence
Server-side behavior requirement extracted
Static client data table classified and cataloged
Content/database import requirement extracted
raw_csv/decode_csv/mycsv relationship documented
Shop/vendor data relationship documented
```

Time limit:

```text
Do not spend more than 10 minutes on a single EXE function, Lua function, or individual data table without producing a finding or catalog entry.
```

Stop iterating if:

```text
Only variable names are changing
The same hypothesis keeps oscillating
Decompiler output is misleading and no new evidence is found
The function requires a caller/callee to be understood first
The Lua decompiler output is too noisy to improve locally
The work is blocked by unknown struct layout
The work is blocked by unknown virtual call target
The next action is broader call-graph or script search, not more local edits
The table has been classified and has no immediate server relevance
The table requires EXE/Lua correlation before more meaning can be inferred
Only localization/cosmetic data is present
```

When stuck, write a partial finding. Partial progress is valid.

---

## Step 5: Commit Findings — Required, Do Not Skip

Any useful improvement must be recorded.

Progress is progress.

Commit a finding if you improved any of these:

```text
EXE function name/category
Lua script/function purpose
Lua event name or state variable meaning
EXE-Lua bridge relationship
Opcode meaning
Packet field
Struct offset
Call graph
State transition
Send/receive relationship
Relevant string/xref
Server implementation requirement
Static data table category/relevance
Server content/database import requirement
FFXIVTool export relationship
Shop/vendor data relationship
```

Before committing, verify location:

```bash
pwd
git status
git branch --show-current
```

Verify:

```text
Expected repo/worktree:
Expected notes folder:
Expected branch:
```

Never write findings into the wrong repo.

Recommended paths:

```text
docs/re/exe/finding_<address_or_name>.md
docs/re/lua/finding_<script_or_function>.md
docs/re/correlation/finding_<lua_exe_bridge>.md
docs/packets/packet_<opcode_or_name>.md
docs/server/requirement_<flow_or_packet>.md
docs/data/ffxivtool_export_overview.md
docs/data/ffxivtool_table_catalog.csv
docs/data/ffxivtool_table_catalog.md
docs/server/content_requirements/ffxivtool_import_plan.md
```

Commit examples:

```bash
git add docs/re/exe/finding_FUN_0048A120.md
git commit -m "docs: document EXE packet dispatch candidate"
```

```bash
git add docs/re/lua/finding_loading_state.md docs/re/correlation/finding_loading_event_bridge.md
git commit -m "docs: document Lua loading state bridge"
```

```bash
git add docs/data/ffxivtool_export_overview.md docs/data/ffxivtool_table_catalog.csv docs/server/content_requirements/ffxivtool_import_plan.md
git commit -m "docs: catalog FFXIVTool client data exports"
```

If only notes were updated, commit notes.

Do not leave useful reverse-engineering work only in chat.

---

# Naming Rules

Use cautious names.

Good EXE names:

```text
pkt_maybe_handle_0001_keepalive
pkt_dispatch_zone_opcode
net_send_subpacket
zone_maybe_send_player_init
zone_maybe_send_actor_spawn
char_load_selected_character
lua_maybe_dispatch_event
lua_maybe_call_native_binding
ui_maybe_set_loading_complete
```

Good Lua note names:

```text
lua_loading_state_maybe_waits_for_zone_ready
lua_event_maybe_on_actor_spawn
lua_ui_maybe_handles_world_entry
lua_native_call_maybe_send_command
```

Bad names:

```text
HandleHeartbeatConfirmed
SendFinalZoneCompletePacket
LoadEverythingCorrectly
ThisDefinitelyUnlocksWorld
```

Do not use confirmed names unless proven.

---

# Packet Investigation Rules

When analyzing packets, always track:

```text
opcode / command id
direction
payload length
header fields
source id
target id
session id
actor id
endianness
read offsets
write offsets
receive path
send path
Lua event/callback triggered
client state changes
server-side implication
confidence
```

Observed MeteorReborn-style log example:

```text
[Zone] RECV src=0x00000006 tgt=0x00000006 op=0x0001 len=24 hex=49B2FC1B0000000000000000000000000000000000000000
```

Working hypothesis until proven in code:

```text
op=0x0001 may be heartbeat / keepalive
len=24
first uint32 may be client tick/timestamp
remaining payload appears zero
src/tgt may be actor or session id
```

This is not confirmed until matched against EXE/Lua evidence.

---

# Recommended Initial Targets for Server Creation

Do not start with the whole client. Start with server-critical flows:

```text
1. network receive loop
2. packet header parser
3. packet dispatcher
4. send packet builder
5. Lua event dispatcher / native bridge
6. character select response handling
7. world handoff handling
8. zone connection/session setup
9. player init packet handling
10. actor spawn handling
11. loading complete / zone-ready state
12. static client data catalog from FFXIVTool exports
13. Item and Command data, if exported separately
14. zones/maps/territories data
15. NPC/actor/shop/quest/levequest/event data
```

For FFXIVTool exports, first catalog and prioritize:

```text
Item
Command
zone/map/territory tables
NPC/actor tables
shop/vendor tables
quest/levequest tables
event/object tables
text/localization tables
```

For Lua, first search for strings and functions related to:

```text
login
world
zone
area
actor
chara
character
player
spawn
loading
ready
event
packet
command
server
session
```

---

# Safety Boundaries

Allowed:

- interoperability analysis for a compatible server
- EXE function summaries from Ghidra MCP
- Lua behavior summaries and small illustrative snippets
- packet documentation
- opcode naming
- struct reconstruction
- EXE-Lua correlation notes
- debugging client/server protocol behavior
- explaining call graphs and state machines
- writing test server requirements
- cataloging exported static client data
- creating server database/content import plans from user-provided CSV/TXT exports
