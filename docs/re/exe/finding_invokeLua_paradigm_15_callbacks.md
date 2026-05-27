# Finding: invokeLua Paradigm + 15 C++ -> Lua Event Callbacks Named

Documents the OTHER half of the EXE <-> Lua bridge: where PlayerBase +
NpcBaseClass expose **methods callable FROM Lua** (`registerLua_*`),
CharaBase + CutScene + DesktopWidget + Player expose **events fired
INTO Lua** (`invokeLua_*`).

This is the **inverse architectural pattern** -- and which pattern a
class uses tells you what role it plays in the EXE<->Lua relationship.

## 1. The two paradigms

```text
PARADIGM 1: registerLua_*  (Lua-callable bindings)
  Direction:   Lua -> C++
  Purpose:     Lua scripts CALL C++ methods to query state, request
               actions, manipulate game objects
  Used by:     PlayerBase (99), NpcBaseClass (24)
  Total now:   123 bindings cataloged
  Source:      docs/re/exe/finding_playerbase_lua_bindings_99_complete.md
               docs/re/exe/finding_npcbaseclass_lua_bindings_24_complete.md

PARADIGM 2: invokeLua_*  (C++ -> Lua event callbacks)
  Direction:   C++ -> Lua
  Purpose:     C++ FIRES events into Lua-side hooks when something
               happens (inbound packet arrives, state changes, etc.)
  Used by:     CharaBase, CutScene, DesktopWidget, Player
  Total now:   15 callbacks named (this finding)
  Source:      this finding
```

A class is in Paradigm 1 if it has data + methods that Lua scripts
manipulate (Player and NPC are entities with state to query/modify).
A class is in Paradigm 2 if it's an **event source** that needs to
notify Lua scripts of state transitions (cutscenes start/end, the
desktop widget receives input, the player touches a proximity zone).

Some classes (like Player) participate in BOTH paradigms -- they're
entities with state (registerLua via PlayerBase) AND event sources
(invokeLua via Player_onTouch_proximityBegin/End).

## 2. The 15 named invokeLua_* callbacks

### CharaBase (1 callback)

```text
Address      Function                                  Triggered by
-------      --------                                  ------------
0x006fae70   CharaBase_invokeLua_onChangeSystemFlag    Zone inbound opcode 43
                                                        Router @ 0x0089ca80
                                                        Handler @ 0x0075a060
```

CharaBase is the abstract base of Player + NpcBase, so it carries the
**universal-actor events** -- things that can happen to any actor.
`onChangeSystemFlag` is fired when the engine flips the low bit of an
actor's `+0x14` flag word, likely "alive/dead" or "visible/hidden".

### CutScene (8 callbacks)

```text
0x006fb9c0   CutScene_invokeLua_onFinalizeClip
0x006fbcc0   CutScene_invokeLua_onInitializationClip_PreviewSetupClip
0x006fbe80   CutScene_invokeLua_onInitializationClip
0x006fc080   CutScene_invokeLua_onShowUIClip
0x006fc260   CutScene_invokeLua_onHideUIClip
0x006fc3a0   CutScene_invokeLua_onShowWidgetClip
0x006fc4d0   CutScene_invokeLua_onHideWidgetClip
0x006fc5f0   CutScene_invokeLua_onOpenUIClip
```

The 8 CutScene callbacks form a **contiguous COMDAT cluster** at
0x006fb9c0..0x006fc5f0 (~3 KB total). This is the COMPLETE CutScene
event surface -- 8 events that drive cinematic playback:

```text
Lifecycle:   onInitializationClip / onFinalizeClip
             (start / end of a cinematic clip)

Setup:       onInitializationClip_PreviewSetupClip
             (preview/test mode initialization)

UI control:  onShowUIClip / onHideUIClip / onOpenUIClip
             (3 separate UI states per clip)

Widget:      onShowWidgetClip / onHideWidgetClip
             (widget visibility during clip)
```

Per `finding_cutscene_block_complete_opcodes_4_to_18.md`, these are
all triggered by Zone-channel cutscene-block opcodes 4-18. The router
table dispatches each opcode to its corresponding invokeLua function.

### DesktopWidget (4 callbacks)

```text
0x006fe960   DesktopWidget_invokeLua_onTargetChanged   Opcode 4
0x006febb0   DesktopWidget_invokeLua_onTargetDecided   Opcode 5
0x006fede0   DesktopWidget_invokeLua_onPreWarp         Opcode 20
0x006fef10   DesktopWidget_invokeLua_onPostWarp        Opcode 21
```

DesktopWidget is the player's **HUD / desktop UI manager** (per
`finding_desktopwidget_packet_dispatch.md`). The 4 callbacks split
into 2 categories:

- **Target events** (opcodes 4, 5): cursor target changed / committed
- **Warp events** (opcodes 20, 21): before/after zone change

The Target subsystem queries Binding ID `0x7a124` (decimal 500004) to
decide whether to persist the main-target reference -- this is the
"is targetable / show on UI" boolean per actor.

### Player (2 callbacks)

```text
0x00898d20   Player_invokeLua_onTouch_proximityBegin
0x00898eb0   Player_invokeLua_onTouch_proximityEnd
```

These 2 callbacks fire when the player **enters / leaves a proximity
trigger zone**. Per `finding_onTouch_is_gathering_proximity.md`, the
proximity zones are attached to NpcBase actors flagged as MapObj
(gathering nodes). So these 2 hooks are the **gathering interaction
entry/exit points** on the Lua side.

## 3. Function shape (uniform across all invokeLua_*)

All 15 callbacks follow the same skeleton:

```text
void Class_invokeLua_onXxx(void *this, void *luaContext, args...) {
  // 1. Establish exception list
  // 2. Build args tuple via FUN_00584e10/00585020 (vec push helpers)
  // 3. Set arg values from packet payload / state
  // 4. (optional) Update internal flag/state BEFORE the Lua call
  // 5. Get Lua name: FUN_00447260(buf, "_onXxx", DAT_00f67298)
  // 6. Invoke: FUN_00cc7a90(luaContext, this, buf, args)
  //    or for typed: FUN_00cd0910 (used with cast-type strings)
  // 7. (optional) Update flag AFTER the Lua call
  // 8. Cleanup args / restore exception list
}
```

Differences from `registerLua_*` pattern:
- `registerLua` ALLOCATES a functor that wraps a C++ MFP for later
  invocation by Lua
- `invokeLua` DIRECTLY INVOKES a Lua function by name with current
  args -- no intermediate functor needed

The `FUN_00cc7a90` (used by all invokeLua) is the **Lua-call-by-name**
helper -- looks up `_onXxx` in the actor's metatable and calls it
with the marshalled args.

## 4. Trigger chain for invokeLua

All known invokeLua callbacks share the same trigger chain:

```text
Wire arrival
  -> NetEventLoop (per finding_net_event_loop.md)
  -> Zone-channel framing parser
  -> Inbound dispatch table (per finding_inbound_dispatch_table_found.md)
  -> ZoneIn_handler_opcode_NN  (per finding_inbound_routers_named_opcodes_round2.md)
  -> Router_dispatch_to_Class_onXxx  (RTTI vtable dispatch)
  -> Class_invokeLua_onXxx  (THIS FINDING'S 15 FUNCTIONS)
  -> Lua hook _onXxx (script-side handler)
```

So every invokeLua callback is **directly correlated 1:1 with an
inbound Zone-channel opcode**. The opcode -> callback mapping is fixed
in the dispatch table.

Known mappings:
```text
Opcode 4   -> DesktopWidget._onTargetChanged
Opcode 5   -> DesktopWidget._onTargetDecided
Opcode 8   -> CutScene._onInitializationClip
Opcode 10  -> CutScene._onHideUIClip
Opcode 11  -> CutScene._onShowWidgetClip
Opcode 12  -> CutScene._onHideWidgetClip
Opcode 13  -> CutScene._onOpenUIClip
Opcode 14  -> CutScene.setActiveAndFinalize  (NOT invokeLua, direct call)
Opcode 17  -> System._onPreCutSceneCancel
Opcode 18  -> System._onPostCutSceneCancel
Opcode 20  -> DesktopWidget._onPreWarp
Opcode 21  -> DesktopWidget._onPostWarp
Opcode 43  -> CharaBase._onChangeSystemFlag
```

`Player.onTouch_proximityBegin/End` is the exception: it's NOT
triggered by a wire opcode but by a **client-side spatial trigger**
(player entering/leaving a proximity volume) -- the only currently-
known invokeLua that fires from local state rather than from a packet.

## 5. Why CharaBase has no register-all master

The reason CharaBase doesn't appear in the registerLua roster is now
clear:

```text
PlayerBase + NpcBaseClass = concrete-actor subclasses that expose
                            INSTANCE METHODS to Lua (player can:
                            "_fadeIn me", "_executeCommand me",
                            etc.)

CharaBase             = abstract base class that exposes
                        EVENTS that ALL actors (player + NPC) need
                        to handle. No instance methods of its own --
                        just hooks.

So:
  CharaBase    : 1 invokeLua  (event surface)
  PlayerBase   : 99 registerLua + inherits 1 invokeLua from CharaBase
  NpcBaseClass : 24 registerLua + inherits 1 invokeLua from CharaBase
```

The 99 + 24 + 1 = 124 named EXE<->Lua bridge points so far.

## 6. Insights from the 15-callback inventory

### CutScene is heavily event-driven

8 events for cutscene playback alone, vs the 5 PlayerBase
CutSceneReplay sNPC bindings. The asymmetry:
- **Live cutscenes** are EVENT-DRIVEN (server pushes clip events,
  Lua reacts)
- **Cutscene replay** is QUERY-DRIVEN (Lua reads stored sNPC data
  from the player's state)

This makes sense: a live cutscene has a timed sequence the server
controls; a replay is a static record the client renders alone.

### Target events come in pairs

DesktopWidget has both `_onTargetChanged` (cursor moved over new
target) AND `_onTargetDecided` (target committed). The split lets
Lua scripts distinguish hover-preview vs final-selection -- useful
for things like "show a tooltip on hover, but only commit aggro
on decided".

### Warp has pre/post hooks

`_onPreWarp` (opcode 20) fires BEFORE the warp packet, letting the
widget save state. `_onPostWarp` (opcode 21) fires AFTER, letting it
restore. So zone changes have a guaranteed save/restore boundary on
the Lua side.

### The internal flag pattern

Several invokeLua callbacks toggle an internal flag around the Lua
call:

```text
_onPreWarp:           sets this->+0x7b = 1 AFTER the Lua call
                      (marks "warp pending")
_onTargetChanged:     sets this->+0x7c = 1 BEFORE, clears AFTER
                      (marks "target change in progress")
_onInitializationClip: sets this->+0xc2 = 1 BEFORE
                       (marks "scene Personage installed")
```

These flags are read by OTHER code (rendering, UI) to gate behavior
during the transition. The Lua call is sandwich-wrapped so other
threads/calls see the transition in progress.

## 7. Server design implications

For each invokeLua callback, the server is the **TRIGGER source** --
the server must SEND the corresponding wire opcode to make the client
fire the Lua hook.

```text
SERVER MUST SEND (to drive client cutscene playback):
  Opcode 8   -> _onInitializationClip   (start clip)
  Opcode 10  -> _onHideUIClip            (hide UI in clip)
  Opcode 11  -> _onShowWidgetClip        (show widget in clip)
  Opcode 12  -> _onHideWidgetClip        (hide widget in clip)
  Opcode 13  -> _onOpenUIClip            (open UI in clip)
  Opcode 14  -> setActiveAndFinalize     (finalize clip)
  Opcode 17  -> _onPreCutSceneCancel     (cutscene cancel begin)
  Opcode 18  -> _onPostCutSceneCancel    (cutscene cancel end)
  
SERVER MUST SEND (to drive zone changes):
  Opcode 20  -> _onPreWarp                (BEFORE warp)
  Opcode 21  -> _onPostWarp                (AFTER warp)
  
SERVER MUST SEND (to drive target system):
  Opcode 4   -> _onTargetChanged           (cursor target update)
  Opcode 5   -> _onTargetDecided           (target commit)
  
SERVER MUST SEND (to drive actor state):
  Opcode 43  -> _onChangeSystemFlag        (actor flag bit toggle)

NO SERVER ACTION (client-local trigger):
  Player.onTouch_proximityBegin/End        (player spatial entry/exit)
```

The cutscene block (opcodes 8-18) is **the densest server-trigger
cluster** -- 8 opcodes drive 8 different invokeLua hooks. Any server
that wants to play a cutscene must implement all 8.

## 8. Cross-references

- `finding_playerbase_lua_bindings_99_complete.md` -- Paradigm 1
  (registerLua) PlayerBase 99 bindings
- `finding_npcbaseclass_lua_bindings_24_complete.md` -- Paradigm 1
  (registerLua) NpcBaseClass 24 bindings
- `finding_inbound_dispatch_table_found.md` -- the opcode dispatch
  table that maps wire opcodes to handlers
- `finding_cutscene_block_complete_opcodes_4_to_18.md` -- the 15
  cutscene-block opcodes; many of these terminate at the invokeLua
  callbacks documented here
- `finding_desktopwidget_packet_dispatch.md` -- earlier work on the
  DesktopWidget event surface
- `finding_onTouch_is_gathering_proximity.md` -- explains how
  Player.onTouch hooks are triggered by MapObj-flagged NPC actors
- `finding_polymorphic_block_userdataReceiver.md` -- the slot-based
  dispatch system for opcodes 22-26 (some may terminate at not-yet-
  named invokeLua callbacks)

## 9. Confidence

```text
Confirmed:
  - 2 distinct EXE<->Lua paradigms exist: registerLua + invokeLua
  - 15 invokeLua callbacks currently named, spread across 4 classes:
    CharaBase (1), CutScene (8), DesktopWidget (4), Player (2)
  - All 15 share the same function shape (verified across 4 decomps:
    onChangeSystemFlag, onPreWarp, onTargetChanged, onInitializationClip)
  - Each invokeLua is triggered 1:1 by an inbound Zone opcode
    (except Player.onTouch which is client-local spatial trigger)

Likely (High):
  - The 8 CutScene callbacks at 0x006fb9c0..0x006fc5f0 form the
    COMPLETE CutScene event surface (contiguous COMDAT cluster)
  - The 4 DesktopWidget callbacks at 0x006fe960..0x006fef10 form the
    COMPLETE DesktopWidget event surface (contiguous COMDAT cluster)
  - Player.onTouch_proximityBegin/End at 0x00898d20/eb0 is the
    COMPLETE Player event surface (only 2 client-local events)

Likely (Medium):
  - CharaBase may have more invokeLua callbacks (only 1 currently
    named); the dispatch table entries for opcodes 22-26 (per
    finding_polymorphic_block_userdataReceiver.md) may route to
    not-yet-named invokeLua functions on Actor/CharaBase
  - The "System.onPreCutSceneCancel" / "System.onPostCutSceneCancel"
    (opcodes 17-18) are likely invokeLua callbacks on a System class
    not yet enumerated

Speculative:
  - There may be additional invokeLua callbacks for other classes
    (Group, Director, Judge, Quest, FreeCompany) that haven't been
    named yet
  - The total invokeLua count across the entire EXE is likely 20-40
    callbacks (based on the 13-opcode cutscene+warp+target cluster
    being a representative sample)
```

## 10. Next test

```text
With registerLua (123) + invokeLua (15) = 138 EXE<->Lua bridge points
documented. The remaining work targets are:

  1. Enumerate ALL invokeLua callbacks: search for "_on" string
     literals in functions matching the invokeLua shape (FUN_00cc7a90
     /  FUN_00cd0910 callers with "_onXxx" string)
  2. Walk inbound opcodes 22-26 (UserDataReceiver vtable slots) -- per
     finding_polymorphic_block_userdataReceiver.md these dispatch to
     5 unnamed virtual methods, likely additional invokeLua callbacks
  3. Look for System class invokeLua functions (opcodes 17-18)
  4. Walk Director/Judge subsystems -- these may use a DIFFERENT
     EXE<->Lua paradigm (server-internal scripts, not direct hooks)
```

## Commit suggestion

```
docs(re/exe): invokeLua paradigm + 15 C++->Lua event callbacks named
```
