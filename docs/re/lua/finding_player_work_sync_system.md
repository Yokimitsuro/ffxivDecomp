# Finding: Player `work` Sync System — The Reactive Data Bridge

The `Player` actor's data model (and by extension every actor with
syncable state) uses a **declarative reactive data system** where
each actor declares its data schema via `defineWork()` and the
runtime binds the appropriate slots to a network-sync layer. This
finding pins the full Player schema, the meta-slots `_save / _temp /
_sync / _tag`, and the native binding `_bindWork` that wires
particular fields into the wire.

Sources read this pass:

```text
chara/player/player.lua            (1.6 KB; the concrete Player subclass init)
chara/player/player_work.lua       (13.3 KB; the full Player schema +
                                   guildleve/localleve helpers + aetheryte map +
                                   weather + cutscene replay)
```

(Both are renamed/found via the cipher; on disk: `729s9/uy9l5s/uy9l5s.lua`
and `729s9/uy9l5s/uy9l5s_nvsz.lua`.)

## The full Player schema (corrected and extended)

`defineWork()` returns **five tables**. Each one populates a
different slot of `self.work`:

```lua
local accountFields, scalars, arrays, structs, aliases = self:defineWork()
self.work._save  = accountFields  -- 1: persistent (saved across logouts)
self.work._temp  = scalars         -- 2: transient (per-session only)
self.work._sync  = arrays          -- 3: network-synced (server-pushed updates)
                                   --    (only on the local player; remote
                                   --     players get an empty table here)
self.work._tag   = structs         -- 4: tagged record groupings (cross-field
                                   --    correlation for the sync engine to
                                   --    know which fields belong together)
                                   --    + aliases appended via table.insert
```

### Group 1 (`_save`): account-level persistent fields

Per `playerbaseclass_work.lua` (the parent class):

```text
test_account            string(16)
```

In `Player` (the subclass), this group is empty (the Player subclass
adds no account-level fields).

### Group 2 (`_temp`): transient scalars

```text
weatherNow              integer16
weatherDefault          integer16
cutSceneReplayId        integer32       -- which cutscene the player is
                                           currently replaying
```

(In `playerbaseclass_work.lua` this group also has `test_goodbye`,
omitted in Player.)

### Group 3 (`_sync`): arrays + booleans (network-synced)

```text
guildleveId             array[16] integer16    -- slots 1..8 = guildleve,
                                                  9..16 = localleve (raw id)
guildleveDone           array[16] boolean
guildleveChecked        array[16] boolean
event_achieve_aetheryte array[512] boolean     -- bitmap; index = aetheryteId - 1280000
betacheck               boolean                -- "is this a beta-checked acct?"
```

(Re-confirms the previous finding's offsets; adds `betacheck` and
`cutSceneReplayId`.)

### Group 4 (`_tag`): record groupings + aliases

```text
"guildleve" {1, self, [guildleveId], [guildleveDone], [guildleveChecked]}
   - groups the three guildleve arrays into one logical "guildleve" record
   - the {1, self} prefix is the tag id (1) and the back-pointer to the actor

"betacheck" {1, self, [betacheck]}
   - single-field group for betacheck so it can be addressed as a unit
```

### Group 5 (`aliases`): name remaps

```text
"achieveAetheryte" -> ["event_achieve_aetheryte", "."]
   - alias for "look up event_achieve_aetheryte by aetheryteId offset"
```

The aliases are post-appended into the `_tag` group via `table.insert`.

## The wire-side binding: `_bindWork`

The `Player._onInit` method has the critical line:

```lua
if self:isMyPlayer() then
  self.work._sync = arrays
  self:_bindWork(101001, "work", "guildleveId")
end
```

So **`_bindWork(actorId, structName, fieldName)` is a native binding
that registers a field for network sync**. Three args:

```text
actorId       101001  the sync-source actor id (probably the GuildleveMaster
                      service actor that pushes guildleve updates)
structName    "work"  the local struct on this actor where updates land
fieldName     "guildleveId"  the field within that struct to receive updates
```

When the server pushes a guildleve update for the local player, it
sends an IPC packet that the C++ side dispatches through this binding:
the payload's "field name" matches one of the bound fields, the
runtime updates `self.work.guildleveId[i]` accordingly, and Lua
reactive code can observe the change.

This is **a different wire mechanism** from the `_onReceiveDataPacket`
dispatch documented elsewhere. `_bindWork` is for **persistent
synced state** (long-lived fields the server keeps authoritatively),
while `_onReceiveDataPacket` is for **transient events** (notifications,
dialogs, completions).

Both layers coexist on the same Zone channel.

## Player concrete class flag-checks (worth pinning)

The Player class adds several worldview-related accessors:

```lua
Player:isWorldEndTerm()        -> true (always; 1.x = pre-2.0 shutdown)
Player:isBeta()                -> self.work.betacheck
Player:isMaskUnderDevelop()    -> not self.work.betacheck
Player:isMaskForChina()        -> false (region check; this build is not CN)
Player:isRegionalleve(id)      -> id < 120000
Player:isCompanyleve(id)       -> 20000 <= id <= 29999
```

`isWorldEndTerm = true` is interesting — the 1.23b build is hardcoded
to behave as if it is in the "world ending" phase (which is the
in-game story state right before the 1.x->2.0 reset). A test server
that wants to drive non-end-term content cannot do so via Player
alone; the flag is a literal return true.

## Guildleve / Localleve slot model

Pinned from the helper methods:

```text
Guildleve slots:  1..8       (raw id)
Localleve slots:  9..16      (id stored as raw; UI displays as id + 120000)

Helper method        guildleve variant       localleve variant
-------------------  ----------------------  -------------------------
get*ID(slot)         getGuildleveID()        (same; switches on slot)
isHavingById         isHavingGuildleveById   isHavingLocalleveById
isDoneById           isDoneGuildleveById     isDoneLocalleveById
isCheckedById        isCheckedGuildleveById  isCheckedLocalleveById
isUnusedById         isUnusedGuildleveById   isUnusedLocalleveById
isClearedById        isClearedGuildleveById  isClearedLocalleveById
getIndexById         getGuildleveIndexById   (none; same array)
```

So a player can hold up to **8 guildleves + 8 localleves = 16
simultaneous leves**. This matches the `[16]` array size in
the `_sync` group.

## `getActiveGLKindIcon(id)` — leve category icon resolver

A switch over the leve id range that picks the **icon id** to render:

```text
id range          icon  what it represents (best-guess by range)
----------------  ----  ---------------------------------------
1000..1099        535   DoH (Disciple of the Hand) tier 1
1100..1199        536   DoH tier 2
1200..1299        537   DoH tier 3
3200..3399        597   DoL (Disciple of the Land) - mining
4000..4199        597   DoL - mining (alt range)
4800..4999        597   DoL - mining (alt range)
3400..3599        598   DoL - botanist
4200..4399        598   DoL - botanist (alt)
5000..5199        598   DoL - botanist (alt)
3600..3799        599   DoL - fisher
4400..4599        599   DoL - fisher (alt)
5200..5399        599   DoL - fisher (alt)
20800..21599      527   Company leve - DoH? (range starts at 20000 = "company")
21600..22399      529   Company leve - DoL?
22400..23159      528   Company leve - mixed?
default           596   generic / unknown leve
```

So **leve id ranges encode both the class type and the "regional vs
company" distinction**. A server emitting leves must respect these
ranges or the UI will mis-icon them.

```text
1xxx       = DoH regional (Crafter)
3xxx-5xxx  = DoL regional (Gatherer)
20000-29999 = Company leve (any class)
120000+    = Localleve (added offset at display time)
```

## Aetheryte achievement bitmap (already known; re-confirmed)

```text
event_achieve_aetheryte  array[512]  boolean
  Index = aetheryteId - 1280000
  Aetheryte id range: 1280000 .. 1280511
```

So **up to 512 aetherytes per client**. Server-side aetheryte
discovery flags map directly onto this bitmap.

## How the work-sync system fits with the dispatch findings

```text
[ZoneClient receives IPC packet]
  |
  v
[C++ PacketProcessor decodes the IPC payload]
  | examines opcode
  v
+--- if opcode is "actor data update" ----+
|                                          |
|   look up bound field for opcode +       |
|   target actor                           |
|   write update into actor.work[field]    |
|   (raises Lua reactive update if any     |
|   observers; otherwise just data         |
|   change)                                |
|                                          |
+------------------------------------------+
                  |
+--- if opcode is "transient event" -------+
|                                          |
|   push packetType (string or number) +   |
|   payload to actor:_onReceiveDataPacket  |
|   (Lua side handles fan-out to widgets   |
|   via DesktopWidget methods)             |
|                                          |
+------------------------------------------+
                  |
+--- if opcode is "general notification" --+
|                                          |
|   push numeric notifId +                 |
|   payload to player:_onReceiveDataPacket |
|   (numeric path; subtype enum 1..10)     |
|                                          |
+------------------------------------------+
```

So the C++ PacketProcessor has at least **THREE distinct dispatch
paths** for game-side packets:

1. **Sync-update path**: writes into actor.work[boundField] (silent
   state update).
2. **Event path**: invokes actor:_onReceiveDataPacket(packetType, ...)
   with one of the three string types or a number.
3. **Notification path**: a sub-case of (2) but specific to
   notifications, where the payload type is always numeric.

A server has to satisfy all three depending on what state it wants
to change on the client.

## Assessment

```text
Confirmed:
  - Player's data model uses defineWork() returning 5 tables (account,
    scalars, arrays/sync, struct-tags, aliases) which are stored under
    self.work._save / _temp / _sync / _tag.
  - _bindWork(actorId, structName, fieldName) is a native binding that
    registers a field for server-driven updates. For the local player,
    101001 is bound for "guildleveId" (the GuildleveMaster service).
  - Guildleve slot model: 1-8 = guildleve, 9-16 = localleve (id + 120000
    at UI time). Maximum 16 simultaneous leves.
  - Leve id ranges encode class (DoH 1000-1299, DoL 3200-5399) and
    region (regional <120000, company 20000-29999, local +120000).
  - Aetheryte bitmap is 512 booleans indexed by id - 1280000.
  - isWorldEndTerm = true is hardcoded in 1.23b (story state at the
    1.x->2.0 reset).

Likely (High):
  - actorId 101001 in _bindWork is the GuildleveMaster system actor.
    Following the pattern of 310001=WorldMaster, 320013=ChocoboRider,
    24301=InstanceRaid, this id is in the "system service" band.
  - There are many more _bindWork calls in other actor classes (chara,
    npc, retainer, etc.). Each one declares a "subscribe me to updates
    for X from system actor Y" relationship.

Likely (Medium):
  - The "1.x->2.0 reset" hardcoded isWorldEndTerm makes 1.23b the
    *final* build of 1.x; a server that wants to drive non-end-term
    content (e.g. earlier 1.x patches' state) cannot do so without
    binary-patching this flag.
  - The "_tag" group with id 1 marks structs as "primary record
    grouping" -- if there were id 2, it would mean a secondary grouping
    (parent/child relationship). Not observed yet.

Speculative:
  - The actorId 101001 might also be the field that drives the
    Guildleve panel UI's "current leve" indicator. Worth checking
    against the leve panel widget.

Next test:
  - Grep the corpus for other _bindWork callsites to enumerate every
    bound field <-> actorId pair. That gives the complete list of
    server-driven sync points.
  - Find the C++ side of _bindWork (FUN_006xxxxx region; similar
    pattern to _executeCommand binding). Pinning it confirms which IPC
    opcode delivers each sync update.

Commit suggestion:
  docs(re/lua): Player work sync system + full schema + leve ranges
```

## Server implication

A server that wants to push state into the local player has TWO
distinct mechanisms:

1. **For persistent state**: send a sync update packet that the C++
   PacketProcessor matches to a `_bindWork`-registered field. The
   client silently updates `self.work.<field>`. No UI side-effect
   unless something else observes the change.

2. **For transient events**: send a packet that decodes to one of the
   three string-typed packetTypes (`"requestedData"`, `"attention"`,
   `"data"`) OR a numeric notif subtype. The client fans out to a
   DesktopWidget rendering method.

For the guildleve example specifically:

- A new guildleve assignment goes via mechanism (1): write the new
  leve id into `self.work.guildleveId[slot]`. The Guildleve panel
  widget observes the change and re-renders.
- A leve completion notification goes via mechanism (2): send a
  numeric notif id (probably 2 = "tutorial success" reusing or similar)
  + the completed leve's text id. The PublicEffectWidget shows the
  visual.
- A leve list refresh (the player opened the History panel) goes
  via "requestedData" + subKey `"glHist"` (already documented).
