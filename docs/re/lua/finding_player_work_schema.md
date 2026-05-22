# Finding: `Player.work` Schema — The Per-Player-Class Extension Struct

The `Player` class adds a NEW struct (`work`, not `playerWork`) on top
of CharaBase's `charaWork`. This struct holds **player-class-specific
data**: guildleves, weather, cutscene, beta flag, and aetheryte
achievements.

The `_sync` portion is **myPlayer-only** — other players don't sync
the Player.work struct (other players get an empty `_sync = {}`).

Sources read:

```text
chara/player/player.lua             79 lines  (Player class concrete file)
chara/player/player_work.lua       699 lines  (the work module)
  defineWork                       line 532-651
```

## `Player.work` schema

`Player:defineWork()` returns 5 tables that fill in `work._save`,
`work._temp`, `work._sync`, `work._tag`, and append-to-charaWork-tag.

### `work._save` (empty initially)

```text
[]    -- populated as server pushes
```

### `work._temp` (3 fields)

```text
{weatherNow,        integer16}   -- current zone weather id
{weatherDefault,    integer16}   -- default weather for the zone
{cutSceneReplayId,  integer32}   -- active cutscene replay id
```

### `work._sync` (5 fields, myPlayer only)

```text
{guildleveId,             array[16]  integer16}  -- 16 leve slots
                                                    (8 regional + 8 local)
{guildleveDone,           array[16]  boolean}    -- "this leve has been
                                                    completed today"
{guildleveChecked,        array[16]  boolean}    -- "this leve has been
                                                    accepted/checked out"
{event_achieve_aetheryte, array[512] boolean}    -- 512 aetheryte
                                                    achievement flags
{betacheck,               boolean}                -- beta build flag
```

### `work._tag` (2 tags for the regular sync set)

```text
{guildleve, 1, self, [
  {guildleveId},
  {guildleveDone},
  {guildleveChecked}
]}
{betacheck, 1, self, [{betacheck}]}
```

### `work._tag` extras (1 nested-path tag)

```text
{achieveAetheryte, [
  {event_achieve_aetheryte, "."}    -- "." = nested array
]}
```

Same `"."` syntax as charaWork's `{commandAcquired, "."}` tag — marks
the field as a flat bit-array that the runtime indexes individually
when applying updates.

## `_bindWork` registration in `Player:_onInit`

After populating `work._sync` for myPlayer, Player registers exactly
one bindWork id:

```text
_bindWork(101001, "work", "guildleveId")
```

So the guildleve array is the only field that gets a direct binding
id channel. Other Player.work fields (cutscene, weather, aetheryte
achievements) sync via the tag-group mechanism instead.

## ID space conventions surfaced

### Guildleve ID space

```text
guildleveId[1..8]    -- regional guildleve ids (raw)
guildleveId[9..16]   -- local guildleve ids (stored raw; displayed as
                        id + 120000)
isRegionalleve(id)   -- returns (id < 120000)
isCompanyleve(id)    -- returns (20000 <= id <= 29999)
                        Company-issued leves were in the 20000-29999 range
```

### Aetheryte ID space

```text
event_achieve_aetheryte[1..512]    -- the 512-flag aetheryte bitmap

server pushes aetheryte id A
  -> index = A - 1280000
  -> work.event_achieve_aetheryte[index] = true
```

So **aetheryte IDs start at 1280000**. The 512-slot bitmap covers ids
1280000 to 1280511 — enough for all aetheryte stones in 1.x (the
game had ~150 aetherytes, so the 512-slot bitmap is over-provisioned).

### GL-Kind icon mapping (from `getActiveGLKindIcon`)

```text
id range          icon
1000..1099        535  (battle? craft?)
1100..1199        536
1200..1299        537
3200..3399        597
4000..4199        597
4800..4999        597
3400..3599        598
4200..4399        598
5000..5199        598
3600..3799        599
4400..4599        599
5200..5399        599
20800..21599      527
21600..22399      529
22400..23159      528
other            596
```

These icon ids feed the leve-kind label in the leve menu. The 3
icons 535/536/537 are probably (battle, gather, craft) tiers; 597-599
are class-specific; 527-529 are company-leve categories.

## Player schema summary

`Player.work` total wire surface (myPlayer only):

```text
work._temp (always available):
  weatherNow         2 bytes
  weatherDefault     2 bytes
  cutSceneReplayId   4 bytes

work._sync (myPlayer only):
  guildleveId[16]              32 bytes
  guildleveDone[16]             2 bytes (bitmask)
  guildleveChecked[16]          2 bytes (bitmask)
  event_achieve_aetheryte[512] 64 bytes (bitmask)
  betacheck                     1 byte

TOTAL ~110 bytes per myPlayer init push
```

## PlayerBaseClass connection

```text
inheritance:
  ActorBaseClass
  └─ CharaBaseClass         (charaWork: parameter/event/battle/etc)
     └─ PlayerBaseClass     (playerWork: variableCommand* fields)
        └─ Player           (work: guildleve + weather + aetheryte +
                              betacheck + cutScene)
```

Each level adds a new struct. So a Player actor has FOUR data sub-
structs:

```text
player.charaWork    -- from CharaBaseClass; all the 1xxx/2xxx/3xxx
                       binding fields
player.playerWork   -- from PlayerBaseClass; the 100xxx variableCommand
                       binding fields
player.work         -- from Player class; guildleve / aetheryte /
                       weather / cutscene
```

(Plus actor's base movement / position state from ActorBaseClass,
which lives in C++ memory, not Lua tables.)

## Assessment

```text
Confirmed:
  - Player.work is a NEW struct (not playerWork) added by the Player
    concrete class. 5 sync fields + 3 temp fields.
  - guildleveId array is 16 entries: [1..8] regional, [9..16] local
    (with id + 120000 transform on display).
  - aetheryte achievements use 512-bit bitmap at offset 1280000.
  - Only 1 _bindWork id registered in Player: 101001 for guildleveId.
    The rest sync via tag groups.

Likely (High):
  - The 512-bit aetheryte bitmap is over-provisioned (1.x had ~150
    aetherytes). Subsequent patches were expected to add more.
  - The guildleveDone/Checked flags are time-window flags (reset
    daily / on a timer) -- so the server pushes them after the daily
    reset to clear them.
  - The "betacheck" flag is probably the beta-version verification
    used during 1.x's open beta in 2010. Stayed in the live build
    code post-release as a no-op.

Likely (Medium):
  - The 4 GL-kind icon groups (535/536/537 + 597/598/599 + 527/528/529)
    map to leve categories: maybe (Combat, Gathering, Crafting) per
    tier? The 597-599 trio is repeated 3 times across non-contiguous id
    ranges, suggesting the same 3 categories across different stat tiers.

Speculative:
  - The cutSceneReplayId is for rewatching cutscenes; an int32 field
    suggests up to ~4 billion possible cutscene ids, way over-spec'd
    for 1.x's small cutscene library.

Next test:
  - Read playerbaseclass.lua (3020 lines) for the playerWork schema.
    This is the parent of Player and adds the 100xxx variableCommand*
    bindings. Will surface the remaining 100001-100007 catalog ids
    and probably more.

Commit suggestion:
  docs(re/lua): Player.work schema (guildleve / aetheryte / weather /
                betacheck); ID conventions (leve 120000, aetheryte 1280000)
```

## Server implication

A server bringing up a Player actor pushes:

1. `Player._onInit` runs on the client when the server announces
   "player actor X exists" -- the client calls `defineWork()` to
   establish the schema.
2. For **myPlayer specifically**, the server must push:
   - `work.guildleveId[1..16]` via binding 101001 (raw ids; displayed
     with the +120000 transform for slots 9-16)
   - `work._tag.guildleve` bundle for done/checked state updates
   - `work.weatherNow` + `weatherDefault` via the temp-struct sync
   - `work.event_achieve_aetheryte[*]` via the achieveAetheryte tag
   - `work.betacheck` once at login (probably false in retail)
3. For **other players**, no Player.work sync needed -- they sync
   through charaWork (parameterSave + parameterTemp) only.

This is **the smallest sub-struct of the actor system**, but
illustrates the design pattern: each class subclass owns its own
sync sub-struct, and only contributes fields it manages.
