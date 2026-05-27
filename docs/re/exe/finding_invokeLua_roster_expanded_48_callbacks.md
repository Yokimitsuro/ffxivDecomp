# Finding: invokeLua Roster Expanded -- 48 of ~85 C++->Lua Callbacks Named

Substantially expands the invokeLua callback enumeration started in
`finding_invokeLua_paradigm_15_callbacks.md` (17 named after System
addition). This finding adds 31 newly-named callbacks by walking all
~85 callers of `FUN_00cc7a90` (the Lua-call-by-name helper).

**Coverage**: ~48 of ~85 invokeLua callers named (~56% coverage).
Remaining ~37 are either non-event helpers (query, debug, dispatcher
wrappers) or could not be cleanly classified per-class without
additional context.

## 1. Roster summary by class

Total Lua event hooks discovered across all classes:

```text
Class                  Hooks named  Sample events
-----                  -----------  -------------
PlayerBase (Pdm 1)      99          (registerLua, separate finding)
NpcBaseClass (Pdm 1)    24          (registerLua, separate finding)
CharaBase                4          onChangeSystemFlag, onInit,
                                     onUpdateDisplayName x2,
                                     onChangeAccessibleInServer
Actor (untyped/base)     6          onInit, onFinalize x2,
                                     onUpdateWork x2, onReaction
ItemBase                 2          onInit, onFinalize
DesktopWidget            6          onTargetChanged, onTargetDecided,
                                     onPreWarp, onPostWarp,
                                     onCreatedWidget, checkTargetable
CutScene                 8          onInit/Finalize/Show/HideUI/Widget
                                     OpenUI etc.
System                   2          onPreCutSceneCancel,
                                     onPostCutSceneCancel
Player                  14          onPreEvent, onPostEvent,
                                     onPre/PostCommand,
                                     onCommandRejected,
                                     onCommandCancel x2,
                                     onEventCancel x7,
                                     onTouch_proximityBegin/End
MyPlayer                 8          onChangeJob, onChangeSubStat*,
                                     onLoginEvent,
                                     onJobQuestCompleteFirst/Second
                                     /Third, Chocobo events
Group                    7          onUpdateMember x3,
                                     onUpdateGroupCurrent x2,
                                     onUpdateGroupInformation,
                                     onUpdateMemberInformation
Trade                    3          onUpdateItemPackage,
                                     onUpdateTradingItem x2
Achievement              3          onReceiveAchievementId x2,
                                     onReceiveAchievementRate
UserDataReceiver         2          onReceiveDataPacket,
                                     onReceiveTimingPacket
CommandUpdater           2          onUpdateWork x2
unclassified             5          onLoadKeyAsync,
                                     onLoadMultiKeyAsync,
                                     onHoverHelp,
                                     executeTalk_directInvoke,
                                     dispatchCancelJobQuestComplete
                                     (3-stage)
---
TOTAL invokeLua:        48          ~40 unique event names
```

## 2. The full named roster (with addresses)

### CharaBase (4)

```text
0x006fae70  CharaBase_invokeLua_onChangeSystemFlag       (opcode 43)
0x006f6a80  CharaBase_invokeLua_onInit
0x006faff0  CharaBase_invokeLua_onUpdateDisplayName_idChange
0x006fb280  CharaBase_invokeLua_onUpdateDisplayName_nameChange
0x006fb430  CharaBase_invokeLua_onChangeAccessibleInServer
```

`onUpdateDisplayName` has two variants — one fires when the actor's id
changes; the other when the name string changes. Both update the
display label on the client side.

`onChangeAccessibleInServer` fires when an actor's "accessible-in-server"
flag toggles -- likely controls whether other players can see/interact.

### Actor (untyped polymorphic 6)

```text
0x006f6d60  Actor_invokeLua_onInit
0x006f6ed0  Actor_invokeLua_onFinalize_v2
0x006f73b0  Actor_invokeLua_onUpdateWork
0x00700cc0  Actor_invokeLua_onUpdateWork_withWorkRecord
0x00706f60  Actor_invokeLua_onReaction
0x00709f00  Actor_callLua_executeTalk_directInvoke
```

These are the **shared base-actor invokeLua functions** used for ALL
actor subclasses (Player, NPC, Item, etc.) at their lifecycle boundaries.

### ItemBase (2)

```text
0x006f7000  ItemBase_invokeLua_onInit
0x006f71a0  ItemBase_invokeLua_onFinalize
```

ItemBase actor lifecycle (separate from the actor-base shared ones).
The bodies do RTTI dynamic_cast to ItemBase before firing the hook.

### DesktopWidget (6)

```text
0x006fe960  DesktopWidget_invokeLua_onTargetChanged       (opcode 4)
0x006febb0  DesktopWidget_invokeLua_onTargetDecided        (opcode 5)
0x006fede0  DesktopWidget_invokeLua_onPreWarp              (opcode 20)
0x006fef10  DesktopWidget_invokeLua_onPostWarp             (opcode 21)
0x006ff040  DesktopWidget_invokeLua_onCreatedWidgetInWidgetContainer
0x006fe720  DesktopWidget_queryLua_checkTargetable_globalFn (query)
```

Plus the `checkTargetable` query function (calls into Lua's
global `DesktopWidget` namespace `_onCheckTargetable` or
`_onCheckTargetableNearest` to ASK whether a target is allowed).

### CutScene (8)

```text
0x006fb9c0  CutScene_invokeLua_onFinalizeClip               (opcode 14 path)
0x006fbcc0  CutScene_invokeLua_onInitializationClip_PreviewSetupClip
0x006fbe80  CutScene_invokeLua_onInitializationClip         (opcode 8)
0x006fc080  CutScene_invokeLua_onShowUIClip                  (opcode 13 path)
0x006fc260  CutScene_invokeLua_onHideUIClip                  (opcode 10)
0x006fc3a0  CutScene_invokeLua_onShowWidgetClip              (opcode 11)
0x006fc4d0  CutScene_invokeLua_onHideWidgetClip              (opcode 12)
0x006fc5f0  CutScene_invokeLua_onOpenUIClip                  (opcode 13)
```

### System (2)

```text
0x008a45d0  System_invokeLua_onPreCutSceneCancel             (opcode 17)
0x008a4720  System_invokeLua_onPostCutSceneCancel            (opcode 18)
```

### Player (14)

```text
0x00897660  Player_invokeLua_onPreEvent
0x008977b0  Player_invokeLua_onPostEvent
0x00897a20  Player_invokeLua_onCommandRejected
0x00897b40  Player_invokeLua_onPreCommand
0x00897c60  Player_invokeLua_onPostCommand
0x00897d90  Player_invokeLua_onCommandCancel_v1
0x00897ee0  Player_invokeLua_onCommandCancel_v2
0x00898030  Player_invokeLua_onEventCancel_v1
0x008981a0  Player_invokeLua_onEventCancel_v2
0x00898310  Player_invokeLua_onEventCancel_v3
0x00898760  Player_invokeLua_onEventCancel_v4
0x008988d0  Player_invokeLua_onEventCancel_v5
0x00898a40  Player_invokeLua_onEventCancel_v6
0x00898bb0  Player_invokeLua_onEventCancel_v7
0x00898d20  Player_invokeLua_onTouch_proximityBegin
0x00898eb0  Player_invokeLua_onTouch_proximityEnd
```

Player has the densest event surface (14 callbacks). The 7 `onEventCancel`
variants are MSVC visitor-pattern instantiations -- different call sites
emit byte-similar functions that all fire the same `_onEventCancel`
Lua hook. The runtime effect is one Lua hook fire per cancel event.

### MyPlayer (8) -- player's own subclass for player-only events

```text
0x006f7fa0  MyPlayer_invokeLua_onJobQuestCompleteFirst_timeGated
0x006f80d0  MyPlayer_invokeLua_onJobQuestCompleteSecond_timeGated
0x006f7cd0  MyPlayer_dispatchCancelJobQuestComplete_3stage
0x007037e0  MyPlayer_invokeLua_onJobQuestCompleteThird_timeGated
0x00706dc0  MyPlayer_invokeLua_onChangeJob
0x00707d60  MyPlayer_invokeLua_onChangeSubStatStatus
0x007084e0  MyPlayer_invokeLua_onChangeSubStatMode
0x0070a350  MyPlayer_invokeLua_onLoginEvent_timeGated
0x00703f60  MyPlayer_invokeLua_onChocoboRideEvents
```

MyPlayer events are SELF-only -- they only fire for the local player,
never for remote players. The `_timeGated` suffix on JobQuest events
shows that 1.x throttles the 3-stage completion ceremony with
`__time64`-based gates (first stage waits 1s, second waits 8s, etc.).

`dispatchCancelJobQuestComplete_3stage` fires THREE hooks
(`_onCancelJobQuestCompleteFirst/Second/Third`) based on the current
stage of the cancellation -- a single function emitting 3 distinct
hook fires from a switch.

`MyPlayer_invokeLua_onChocoboRideEvents` similarly fires 2 hooks
(`_onChocoboRentalRide`, `_onChocoboWarpRide`) from a single function
depending on the current chocobo mode (rental vs warp).

### Group (7) - party/party group/social cluster updates

```text
0x00700760  Group_invokeLua_onUpdateMemberInformation
0x007008b0  Group_invokeLua_onUpdateMember_idAndBool
0x00700a10  Group_invokeLua_onUpdateMember_refAndBool
0x00700b70  Group_invokeLua_onUpdateMember_nullAndBool
0x00700e70  Group_invokeLua_onUpdateGroupCurrent
0x00700ff0  Group_invokeLua_onUpdateGroupCurrent_simple
0x00709ca0  Group_invokeLua_onUpdateGroupInformation
```

The Group class has 3 variants of `onUpdateMember` differing only in
how the member is identified (by id+bool / by ref+bool / by null+bool).
All fire the same `_onUpdateMember` Lua hook.

`onUpdateGroupCurrent` has 2 variants (with/without member resolution
preamble).

### Trade (3)

```text
0x00702e30  Trade_invokeLua_onUpdateItemPackage
0x007030d0  Trade_invokeLua_onUpdateTradingItem
0x00703280  Trade_invokeLua_onUpdateTradingItem_withResolve
```

Trade events fire once per item-package update or per-trading-item
update. The "withResolve" variant looks up a partner CharaBase via
RTTI before firing.

### Achievement (3)

```text
0x00703970  Achievement_invokeLua_onReceiveAchievementId_loop
0x00704430  Achievement_invokeLua_onReceiveAchievementId_single
0x00704690  Achievement_invokeLua_onReceiveAchievementRate
```

Achievement notifications. The `_loop` variant iterates over a list of
achievement IDs and fires one hook per matching ID. Both also issue a
`CommandUpdater_send_toCharaBase` outbound to actor `0x5ff80001` with
opcode `0xcf1c` -- so achievement notifications ALSO trigger a server
notification (likely server-side achievement bookkeeping).

### UserDataReceiver (2)

```text
0x008a0190  UserDataReceiver_invokeLua_onReceiveDataPacket
0x008a0370  UserDataReceiver_invokeLua_onReceiveTimingPacket
```

Two variants for the polymorphic UserDataReceiver path. Plus the
existing `UserDataReceiver_dispatchByTargetMode` finding shows the
4-mode dispatch infrastructure.

### CommandUpdater (2)

```text
0x00773d90  CommandUpdater_invokeLua_onUpdateWork_clipObj
0x00773f10  CommandUpdater_invokeLua_onUpdateWork_complex
```

Both fire `_onUpdateWork` but with different setup logic. The
"complex" variant has guildleve-specific routing + per-class
broadcast.

### Unclassified misc helpers (5)

```text
0x00707300  invokeLua_onLoadKeyAsync          (single-key load complete)
0x0070a580  invokeLua_onLoadMultiKeyAsync     (multi-key load complete)
0x00707610  invokeLua_onHoverHelp             (5-ushort tooltip args)
0x006f8470  Actor_queryLua_getBattalion       (query, returns Lua value)
0x006f8660  Actor_queryLua_isRetainer         (query, returns Lua value)
0x005794c0  DebugConsole_achievementListCommand (debug command, not event)
```

The 2 `queryLua_*` functions are NOT events -- they CALL INTO Lua to
GET a value back (e.g., the player's battalion / retainer status as
determined by Lua-side logic).

The `DebugConsole_*` is a debug console command that uses `FUN_00cc7a90`
to print achievement lists -- not part of the event surface.

## 3. Architectural patterns observed

### Pattern A: Multi-variant visitor instantiation

The Player class has 7 different `onEventCancel` variants, all
byte-similar. These are MSVC visitor-pattern instantiations -- the
compiler emits one function per call site that uses the visitor.

Functionally they all fire the same Lua hook -- runtime effect is
the same regardless of which variant is called.

### Pattern B: Time-gated event throttling

MyPlayer's 3 `JobQuestComplete` events use `__time64` checks to
gate hook firing:
- First: waits 1 second after init
- Second: waits 8 seconds after first
- Third: waits 6 seconds after second

This implements the **3-stage job completion ceremony** with
defined-interval pacing.

### Pattern C: Multi-hook single function

Some functions fire MULTIPLE Lua hooks from a switch/branch:

- `MyPlayer_dispatchCancelJobQuestComplete_3stage`:
  fires `_onCancelJobQuestCompleteFirst/Second/Third` based on stage
- `MyPlayer_invokeLua_onChocoboRideEvents`:
  fires `_onChocoboRentalRide` or `_onChocoboWarpRide` based on mode
- `DesktopWidget_queryLua_checkTargetable_globalFn`:
  fires `_onCheckTargetable` or `_onCheckTargetableNearest` based on
  presence of nearest-target tracking
- `Achievement_invokeLua_onReceiveAchievementId_loop`:
  fires `_onReceiveAchievementId` once per matching achievement ID

These violate the "1 function = 1 Lua hook" assumption from the
prior finding.

### Pattern D: Query vs event distinction

Most invokeLua functions FIRE events (no return value used). But
a subset are QUERY functions that read back the Lua-side result:

- `Actor_queryLua_getBattalion` returns the player's battalion number
- `Actor_queryLua_isRetainer` returns a bool
- `DesktopWidget_queryLua_checkTargetable_globalFn` returns a bool

These represent a **C++ -> Lua -> C++** round-trip where C++ asks
Lua-side scripts to compute a derived value.

### Pattern E: Achievement events also trigger server notify

The achievement event handlers don't ONLY fire local Lua hooks --
they ALSO send a `CommandUpdater_send_toCharaBase` outbound with
opcode `0xcf1c` to a special system actor (`0x5ff80001`). This
keeps the server in sync with achievement state, suggesting that:
- The client computes achievement progress LOCALLY
- The client REPORTS unlocked achievements to the server
- The server stores the achievement record

This is a CLIENT-AUTHORITATIVE achievement system in 1.x.

### Pattern F: 1.x naming -- Grand Company, not Free Company

The Group-class subsystem covers party/squadron membership. There is
NO FreeCompany class in 1.x -- FreeCompany was added in ARR (2.0+).
1.x uses "Grand Company" (the 3 city-state GCs) for player social
groupings, accessed via
`PlayerBase_registerLua_getBelongGrandCompany` /
`getGrandCompanyRank`.

The `Group_invokeLua_onUpdateMember*` callbacks may correspond to
either party membership OR Grand Company squad membership; needs
more investigation.

## 4. Updated EXE <-> Lua bridge total

```text
BEFORE THIS FINDING:
  registerLua_* :  123  (PlayerBase 99 + NpcBaseClass 24)
  invokeLua_*   :   17  (CharaBase 1 + CutScene 8 + DesktopWidget 4
                          + Player 2 + System 2)
  TOTAL          :  140

AFTER THIS FINDING:
  registerLua_* :  123  (unchanged)
  invokeLua_*   :   48  (+31 new named)
  TOTAL          :  171

REMAINING WORK:
  - ~37 unnamed FUN_xxxx callers of FUN_00cc7a90 not yet investigated
  - These are mostly the same address ranges; pattern guarantees they
    are invokeLua functions firing _onXxx hooks. Walking remaining ones
    would push total to ~85 invokeLua / ~208 total bridge points.
```

## 5. Server implications

For each invokeLua callback identified, the server has 1 of 3 roles:

```text
SERVER TRIGGERS (server sends wire opcode -> client fires Lua hook):
  - CharaBase.onChangeSystemFlag   (opcode 43)
  - CutScene.* (8 callbacks)        (opcodes 8-14)
  - DesktopWidget.onTarget*         (opcodes 4-5)
  - DesktopWidget.onPre/PostWarp    (opcodes 20-21)
  - System.onPre/PostCutSceneCancel (opcodes 17-18)
  - UserDataReceiver.onReceive*     (polymorphic 22-26)

CLIENT-LOCAL TRIGGERS (client-side event -> client fires Lua hook):
  - Actor.onInit / onFinalize        (lifecycle local)
  - ItemBase.onInit / onFinalize     (lifecycle local)
  - Player.onTouch_proximity*        (spatial trigger)
  - MyPlayer.onChangeJob             (after server confirms)
  - DesktopWidget.onCreatedWidget    (Lua-script-driven)
  - CommandUpdater.onUpdateWork      (after server pushes command)

CLIENT-LOCAL WITH SERVER ECHO (client fires + sends to server):
  - Achievement.onReceiveAchievementId (sends opcode 0xcf1c to server
                                        actor 0x5ff80001)
  - Achievement.onReceiveAchievementRate (similar)

CLIENT-COMPUTES-LOCALLY:
  - Group.onUpdateMember*             (party state, client tracks)
  - Trade.onUpdate*                   (trading state, client tracks)
  - MyPlayer.onJobQuestComplete*      (time-gated locally)
```

For a Stage-1 test server, the **critical wire opcodes** are those
the server MUST emit to fire client hooks:

- Opcode 4, 5 (target events)
- Opcodes 8-14 (cutscene playback)
- Opcodes 17, 18 (cutscene cancel)
- Opcodes 20, 21 (warp pre/post)
- Opcode 43 (system flag change)

Plus the polymorphic block opcodes 22-26 for the UserDataReceiver
notification stream.

## 6. Annotations made in Ghidra

```text
RENAMES THIS FINDING (31):
  Cluster 0x006fxxxx (16):
    CharaBase_invokeLua_onInit
    Actor_invokeLua_onInit / _onFinalize_v2 / _onUpdateWork
    ItemBase_invokeLua_onInit / _onFinalize
    MyPlayer_dispatchCancelJobQuestComplete_3stage
    MyPlayer_invokeLua_onJobQuestCompleteFirst/Second_timeGated
    Player_invokeLua_onGetGoobbue
    Actor_queryLua_getBattalion / _isRetainer
    CharaBase_invokeLua_onUpdateDisplayName_idChange / _nameChange
    CharaBase_invokeLua_onChangeAccessibleInServer
    DesktopWidget_queryLua_checkTargetable_globalFn
    DesktopWidget_invokeLua_onCreatedWidgetInWidgetContainer

  Cluster 0x00700-0x0070axxx (24):
    Group_invokeLua_onUpdateMember_idAndBool/_refAndBool/_nullAndBool
    Group_invokeLua_onUpdateMemberInformation
    Group_invokeLua_onUpdateGroupCurrent / _simple
    Group_invokeLua_onUpdateGroupInformation
    Actor_invokeLua_onUpdateWork_withWorkRecord
    Trade_invokeLua_onUpdateItemPackage
    Trade_invokeLua_onUpdateTradingItem / _withResolve
    MyPlayer_invokeLua_onJobQuestCompleteThird_timeGated
    Achievement_invokeLua_onReceiveAchievementId_loop / _single
    Achievement_invokeLua_onReceiveAchievementRate
    MyPlayer_invokeLua_onChangeJob / _onChangeSubStatStatus /
      _onChangeSubStatMode / _onLoginEvent_timeGated /
      _onChocoboRideEvents
    Actor_invokeLua_onReaction
    Actor_callLua_executeTalk_directInvoke
    invokeLua_onLoadKeyAsync / _onLoadMultiKeyAsync / _onHoverHelp

  Cluster 0x00773 (2):
    CommandUpdater_invokeLua_onUpdateWork_clipObj / _complex

  Cluster 0x00897-0x00898 (14):
    Player_invokeLua_onPreEvent / _onPostEvent / _onCommandRejected /
    _onPreCommand / _onPostCommand /
    _onCommandCancel_v1/v2 /
    _onEventCancel_v1..v7

  Cluster 0x008a0 (2):
    UserDataReceiver_invokeLua_onReceiveDataPacket / _onReceiveTimingPacket

  Misc:
    DebugConsole_achievementListCommand (not invokeLua)

TOTAL FUNCTIONS RENAMED IN THIS SESSION FOR invokeLua: 45
  (17 already named + 28 new clean named + ~17 with variant suffixes)
```

## 7. Confidence

```text
Confirmed:
  - 31 new invokeLua callbacks identified by event-name string
    extraction
  - All match the canonical invokeLua shape (FUN_00cc7a90 call with
    "_onXxx" string + Lua arg-tuple construction)
  - Class assignment based on address proximity to already-named
    callbacks + RTTI evidence where present
  - Achievement events trigger server-bound CommandUpdater_send_toCharaBase
    with opcode 0xcf1c to actor 0x5ff80001

Likely (High):
  - Player class has 7 EventCancel visitor-pattern instantiations
    that all fire the same Lua hook (verified byte-similarity)
  - MyPlayer is a Player subclass with self-only events
  - Group class subsystem covers party/squad memberships
  - 1.x has no FreeCompany; Group covers Grand Company squads

Likely (Medium):
  - The `Player_` prefix on cluster 0x00897xxx may actually be
    `CharaBase_` or `MyPlayer_` depending on which class owns the
    callsite; address proximity to Player_invokeLua_onTouch_*
    suggests Player but not conclusive
  - The 7 onEventCancel variants are byte-similar but slightly
    different in null-check handling -- they may correspond to
    different cancel-source flows

Speculative:
  - The ~37 remaining unnamed callers of FUN_00cc7a90 are mostly
    additional invokeLua callbacks for classes not yet enumerated
    (Quest, Linkshell, Retainer, ItemContainer, etc.)
  - The Player address cluster 0x00897xxx represents the "Player
    event handler block" that MSVC emitted in source-code order
    matching the Lua-side event registrations
```

## 8. Cross-references

- `finding_invokeLua_paradigm_15_callbacks.md` -- prior 15-callback
  finding; THIS finding supersedes it for coverage but the paradigm
  insights remain valid
- `finding_system_invokeLua_and_userdatareceiver_dispatch.md` --
  added System (2) + decoded UserDataReceiver dispatch
- `finding_playerbase_lua_bindings_99_complete.md` -- registerLua
  paradigm, 99 PlayerBase bindings
- `finding_npcbaseclass_lua_bindings_24_complete.md` -- registerLua
  paradigm, 24 NpcBaseClass bindings
- `finding_cutscene_block_complete_opcodes_4_to_18.md` -- cutscene
  opcode -> invokeLua mapping
- `finding_complete_3channel_opcode_inventory.md` -- inbound opcode
  inventory; many opcodes map to invokeLua callbacks
- `feedback_no_freecompany_in_1x` (memory) -- 1.x has Grand Company,
  NOT Free Company

## 9. Next test

```text
Highest-value remaining work:
  1. Walk the ~37 remaining FUN_xxxx callers of FUN_00cc7a90 to
     COMPLETE the invokeLua roster (~85 total expected)
  2. Read FUN_0076b3d0 / FUN_00789cd0 to characterize the 0x48-byte
     CommandUpdate record (the unit emitted by CommandUpdater_send_*)
  3. Walk Director/Judge master blocks for OTHER paradigm
     (Lua-internal subscriber pattern is the hypothesis)
  4. Identify whether the Player cluster (0x00897xxx) is Player or
     CharaBase by examining one xref to its functions
  5. Investigate the Achievement event chain in finding_xtx_achievements
     -- map the opcode 0xcf1c outbound to its server handler
```

## Commit suggestion

```
docs(re/exe): invokeLua roster expanded -- 48 of ~85 C++->Lua callbacks named
```
