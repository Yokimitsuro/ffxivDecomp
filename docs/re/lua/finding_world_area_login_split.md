# Finding: WorldMaster + AreaBaseClass Lua + Login Is C++-Only

Maps the Lua side of the world / area subsystem. The key
architectural finding is that **the login / character select / chara
creation flow has NO Lua scripting** — it is implemented entirely in
native C++ (with Lobby channel opcodes as the wire protocol). The
Lua corpus starts at world entry.

## The Lua corpus top-level structure

```text
lua/decompiled/src/
+-- 0p635/              judge
+-- 1q5x/               item
+-- 39x569q9/           gamedata
+-- 3svpu/              group
+-- 3yv89y_p.lua        global_p
+-- 61s57qvs/           director
+-- 658p3/              debug
+-- 729s9/              chara
+-- 7vxx9w6/            command
+-- 7vxx9w6658p335s/    commanddebugger
+-- 97qvs89r57y9rr.lua  actorbaseclass
+-- 9s59/               area
+-- n1635q/             widget
+-- nvsy6/              world
+-- rlrq5x/             system  (just utilities)
+-- rq9qpr/             status
+-- tp5rq/              quest
```

**NO directory for login / lobby / phase / charaSelect.** Confirmed by
grepping for `Login`, `Phase`, `CharaSelect`, `CharaMake`, etc. across
the entire Lua corpus -- the only hits are gameplay references, not
login phase implementations.

So the FFXIV 1.x client login pipeline (LobbyConnection +
LobbyLoginOperation + the 8 Lobby outbound opcodes documented in
`finding_complete_3channel_opcode_inventory.md`) is **100% native
C++**. No Lua scripting is involved until the client has entered the
world and the Zone channel is active.

This is a clean architectural separation:

```text
PRE-WORLD (Lobby channel)            POST-WORLD (Zone + Chat channels)
=========================            =================================
LobbyLoginOperation_*                AreaBaseClass + ZoneMaster*
- account auth                       - zone simulation
- service select                     - actor lifecycle
- chara list                         - command execution
- chara create                       - quest progression
- chara delete                       - chat
- world handoff                      - status effects
[opcodes 0x1F5/0x05/0x06/             [opcodes 0x12D-0x135 outbound;
 0x0B/0x0F/0x1F6 outbound;             ~60 inbound dispatch entries]
 + paired ACKs]                       
                                      
ALL NATIVE C++                       LUA + NATIVE BRIDGES
```

## WorldMaster Lua (the global game-state actor)

Three Lua files:

```text
nvsy6/nvsy689r57y9rr.lua          worldbaseclass.lua          1 line (stub)
nvsy6/nvsy6x9rq5s.lua             worldmaster.lua             121 lines, 7 methods
nvsy6/nvsy6x9rq5s_5o5wq.lua       worldmaster_event.lua       309 lines, 10 methods
nvsy6/vq25s9s59.lua               otherarea.lua               1 line (stub)
```

### WorldMaster (121 lines, 7 methods)

```text
LIFECYCLE:
  _onInit                      class init
  _onReceiveDataPacket         inbound data handler (generic)

TIME / CLOCK:
  getServerTimeWithDebugOffset  authoritative server time
  calcJSTWeekAndDay             Japan Standard Time week + day
  getJSTWeekAndDay              cached JST week/day
  getJSTWeekPastTimes           past JST timestamps in the week

UTILITY:
  createCutScene                cutscene actor factory
```

WorldMaster is the **service actor for global game state**. It holds
the authoritative server time, calculates JST-based weekly cycles
(used for content rotation), and produces CutScene actor instances
on demand.

JST (Japan Standard Time) is hardcoded as the canonical reference
clock -- consistent with FFXIV being developed and operated by Square
Enix in Japan. Server implementations must serve JST-aligned times
for content rotation to match retail behavior.

### WorldMaster_event (309 lines, 10 methods)

The companion module exposes broadcast / Q&A helpers + game-state
timers:

```text
TIME-OF-DAY:
  isHydaelynNight             check whether Hydaelyn is in night phase

GAME TIMERS:
  getGuildleveTime            seconds until next guildleve refresh
  getBoostTime                rested experience boost time remaining
  getAnimaTime                anima (teleport energy) regen time

BROADCAST CHANNELS:
  say                         server "says" something (chat A-style)
  notify                      server notification
  alert                       server alert (high-priority)

PROMPTS (Q&A to player):
  ask                         generic Q/A prompt
  askRestrictChoices          Q/A with restricted choice set
  askMultipleTextMacro        multi-template Q/A
```

The 3 broadcast channels (say/notify/alert) correspond to 3
different priorities for server-pushed text. The server picks the
appropriate channel based on message importance.

The 3 prompt variants (`ask` / `askRestrictChoices` /
`askMultipleTextMacro`) are coroutine-yielding (per the modal-UI
pattern documented in
`finding_negotiation_bazaar_widget_family.md`). The server can
suspend client coroutines until the player responds, then read the
answer.

## AreaBaseClass Lua (the zone simulator)

```text
9s59/9s5989r57y9rr.lua            areabaseclass.lua          439 lines, 16 methods
9s59/9s5989r57y9rr_y9lvpq.lua     areabaseclass_layout.lua   94 lines
9s59/kvw5/kvw589r57y9rr.lua       zonebaseclass.lua          35 lines (small base)
9s59/kvw5/kvw56549pyq.lua         zonedefault.lua            8 lines (stub)
9s59/kvw5/[43 zonemaster*.lua]    per-zone subclasses        ~10-50 lines each
```

### AreaBaseClass (439 lines, 16 methods)

```text
IDENTITY:
  getZoneName                returns zone name string

ZONE TYPE PREDICATES:
  isNormalZone               public zone (open world)
  isJailZone                 jail / punishment zone
  isInstanceRaid             instance raid zone
  isEntranceDesion (sic)     entrance-decision zone (typo preserved)

STATE MANAGEMENT:
  initWork                   work schema definition
  getTempWork / setTempWork  ephemeral state (lost on warp)
  getSaveWork / setSaveWork  persistent state (across warps / sessions)

LIFECYCLE:
  _onInit
  create                     factory method
  prepareSpreadSheet         load sheet data
  _onLoop                    per-tick callback
  processLoop                main per-tick logic
  _onFinalize                cleanup on warp out
```

So a zone is a **stateful actor with its own loop**. Each tick:
1. `_onLoop` fires (frame-rate driven)
2. `processLoop` runs the zone's per-tick logic

The 4-way zone type taxonomy (Normal / Jail / InstanceRaid /
EntranceDecision) covers the major content kinds in 1.x:

- **Normal**: open-world zones (cities, fields, dungeons that aren't
  instances).
- **Jail**: punishment zones (player imprisonment for GM enforcement
  or quest narrative).
- **InstanceRaid**: instanced dungeon / raid content.
- **EntranceDecision**: zones that gate entry to other zones (lobby
  rooms before story instances).

### Per-zone subclasses (43 files)

The 43 `kvw5x9rq5s*.lua` (decoded: `zonemaster*.lua`) files cover
specific zone implementations. Sample decoded names:

```text
zonemasterjail              jail zones (likely the dungeon brig)
zonemasterjointest          test-only join-test zone
zonemasterharvesttest       harvest skill test zone
zonemasterguildlevetest     leve test zone
zonemastercrafttest         crafting test zone
zonemasterequiptest         equipment test zone
zonemasterfsff0 / fstF0     forest zone variants (Black Shroud region)
zonemastersrt/sea/wil/roc/lak/fst  region-specific zones (the 6 regions
                                    from the dft* FFXIVTool tables)
... (43 total)
```

So **each zone in 1.x has its own Lua subclass** of AreaBaseClass.
This explains the deep zone behavior customization in 1.x:
- Per-zone weather rules
- Per-zone time-of-day modifiers
- Per-zone NPC schedules
- Per-zone unique mechanics (e.g. Jail zone disables most actions)

## System utilities (rlrq5x/)

```text
rlrq5x/658p3.lua             debug.lua          standard debug printing
rlrq5x/658p3_pq1y1ql.lua     debug_utility.lua  extra debug utilities
rlrq5x/q98y5.lua             table.lua          table helpers (similar to Lua's table)
rlrq5x/rqs1w3.lua            string.lua         string helpers (similar to Lua's string)
rlrq5x/x9q2.lua              math.lua           math helpers (similar to Lua's math)
rlrq5x/rlrq5x89r57y9rr.lua   systembaseclass.lua  base for system services
```

NOT INTERESTING for server implementation -- these are just
language-level utility libraries.

## OtherArea (vq25s9s59.lua, 1 line)

Effectively empty. Probably an abstract placeholder for non-current
zones referenced by warp / teleport logic.

## Server-side implications

```text
1. LOGIN FLOW IS C++:
   A server implementation must handle the 8 Lobby outbound opcodes
   (per finding_complete_3channel_opcode_inventory.md) NATIVELY
   on the server side. There is no scripting layer to fall back on.
   The client expects specific binary responses for each Lobby
   request opcode; the server must produce them byte-perfect.

2. WORLDMASTER NEEDS A SERVER AVATAR:
   The server must simulate a WorldMaster instance whose state
   syncs to all connected clients. Key state:
     - Authoritative time (JST-aligned)
     - Weekly cycle position (for content rotation)
     - Guildleve / Boost / Anima timers
     - Active broadcast channels (say/notify/alert queues)
     - Pending Q/A prompts (per-player coroutine state)

3. ZONE SIMULATION:
   The server must instantiate the appropriate AreaBaseClass subclass
   for each loaded zone. The 43 per-zone classes define
   zone-specific tick logic that the server's zone runner must
   honor. For server bring-up, the minimal set is the 6 regional
   zones (fst/sea/wil/lak/roc/srt) + at least one jail + entrance
   decision zones for content gating.

4. STATE PERSISTENCE:
   AreaBaseClass exposes getSaveWork / setSaveWork as the
   persistence API. The server's database schema needs per-zone
   persistent state buckets keyed by zone id, distinct from
   per-actor playerWork.

5. JST CLOCK:
   The server must use Japan Standard Time as its canonical clock
   (or apply a JST offset to its native UTC time). Content
   rotation, daily resets, weekly resets all key on this clock.
```

## Confidence

```text
Confirmed:
  - The Lua corpus has NO login/lobby/phase/charaSelect directory.
  - WorldMaster has exactly 7 base methods + 10 event methods.
  - AreaBaseClass has 16 methods including a 4-way zone-type
    predicate set.
  - 43 per-zone Lua subclasses exist.
  - System utilities (rlrq5x/) are not gameplay code.

Likely (High):
  - All login-flow C++ code is inside the Lobby channel handlers
    documented in finding_complete_3channel_opcode_inventory.md.
  - The 4 zone-type predicates cover all zone categories that exist
    in 1.x (no 5th category like "PVP zone" or "Battleground").
  - The Hydaelyn night/day check (isHydaelynNight) drives time-of-day
    visual + spawn-rate effects on the server side.

Likely (Medium):
  - Each zone-master Lua file overrides at least one of
    processLoop, _onInit, _onFinalize, or one of the work
    initialization methods. Without reading all 43 files,
    detailed enumeration of per-zone behavior is mechanical.
  - The "say / notify / alert" channels correspond to inbound chat
    opcodes 35 / 36 / 57 (or similar) -- the 4-variant chat block
    documented in finding_chat_block_command_notifications.md.

Speculative:
  - The "Hydaelyn" reference (isHydaelynNight) is the in-world name
    for the planet FFXIV is set on. Confirmed by the FFXIV setting
    -- this isn't a server-implementation detail, just a flavor
    reference.
  - The 43-zone Lua count tracks the 1.x release zone count;
    additional zones added in later patches (1.20, 1.22, 1.23)
    might have their own Lua files in the corpus too.
```

## Architectural summary

```text
THE 1.x CLIENT LIFE-CYCLE (server-perspective):

  [client connects to Lobby channel]
                |
                v
  +-----------------------------------+
  | LOBBY (C++ only, no Lua):         |
  | - LOBBY_LOGIN_REQUEST  (0x1F5)    |
  | - SERVICE_LOGIN_REQUEST (0x05)    |
  | - GAME_LOGIN_REQUEST    (0x06)    |
  | - PUT_CHARA_MAKE_DATA   (0x0B)    |
  | - CHARA_MAKE_REQUEST    (0x1F6)   |
  | - ACKs (0x03/0x04)                |
  +-----------------------------------+
                |
                v
        world handoff
                |
                v
  [client switches to Zone + Chat channels]
                |
                v
  +-----------------------------------+
  | WORLD ENTRY (C++ + Lua):          |
  | - Zone handshake (version 0x3C6B) |
  | - WorldMaster:_onInit             |
  | - AreaBaseClass:create / _onInit  |
  | - Player actor spawn (WorkSync)   |
  | - SUBSCRIBE bindings (0x135)      |
  +-----------------------------------+
                |
                v
  +-----------------------------------+
  | GAMEPLAY (Lua-heavy):             |
  | - AreaBaseClass:_onLoop / tick    |
  | - WorldMaster.event timers        |
  | - Command dispatch (0x12D)        |
  | - WorkSync updates (0x12F)        |
  | - Chat / events / quests          |
  +-----------------------------------+
                |
                v
  +-----------------------------------+
  | WARP (C++ + Lua):                 |
  | - DesktopWidget._onPreWarp (op 20)|
  | - AreaBaseClass:_onFinalize       |
  | - new AreaBaseClass:_onInit       |
  | - DesktopWidget._onPostWarp (op 21)|
  +-----------------------------------+
```

## Next test

- Force-disassemble the LobbyLoginOperation thunks (out-of-MCP)
  to identify the specific inbound opcodes the server must send
  in response to each outbound login opcode.
- Sample 5-10 per-zone Lua files to see what they typically
  override -- this gives a per-zone customization surface.
- Look at the WorldMaster's `say` / `notify` / `alert` bodies to
  confirm which inbound chat-block opcode each pushes (probably
  mapping to chat A/B/D or to a specific Command-update tag).

## Commit suggestion

```
docs(re/lua): map WorldMaster + AreaBaseClass; confirm login is C++-only
```
