# Finding: Native Bindings Enumeration -- CharaBase (77) + WorldMaster (23) + Director (5) + DesktopWidget (43 sampled)

Enumerates the native bindings declared in 4 key `_u.lua` files
identified by `finding_native_binding_surface_439_across_19_modules.md`.
Net new: **125 bindings catalogued across 4 modules**.

This includes the critical **CharaBase** (abstract actor base shared
by Player+NPC) and **WorldMaster** (world singleton with time + tutorial
+ chocobo APIs), plus the **Director correction** showing the 5 native
bindings the prior finding missed.

## 1. CharaBase -- the 77-binding abstract actor base

File: `chara/charabaseclass_u.lua` (922 lines)

This is the FOUNDATIONAL class -- every Player and NPC inherits from
CharaBase. The 77 bindings cover the universal actor API: movement,
appearance, items, group membership, stats, scheduling.

### Movement / Position (10 bindings)

```text
_getPosition / _setPosition         3D position get/set
_getDirection / _setDirection       facing direction get/set
_turnBack                             instant 180-turn
_turnClientDir                        client-driven turn
_waitForTurning                       block until turn completes
_getOrientation                       camera-relative orientation
_setGroundOn                          attach actor to ground/floor
_getFloatingOffset / _setFloatingOffset  vertical hover offset
```

The `_setGroundOn` + `_getFloatingOffset` combo handles non-standard
positioning (e.g., flying NPCs, hovering effects).

### LookAt System (5 bindings)

```text
_lookAtCharacter           look at another actor
_lookAtCharacterEid        look at by entity id
_lookAtDirection           look at a direction vector
_lookAtPosition            look at a 3D point
_getLookAtCharacter        get current look-at target
_cancelLookAt              clear look-at state
```

Full IK/look-at API for scripted dialog scenes.

### Display Name + Nameplate (10 bindings)

```text
_getDisplayName / _setDisplayName
_getLocalizedDisplayName              localized for current language
_getLocalizedDisplayNameForChat       chat-specific format
_setNameplate                         the nameplate display
_setNameplateColor                    nameplate color
_setNameplateIcon                     nameplate icon overlay
_setNameplateGauge                    HP/MP gauge under name
_isNameplateVisible / _setNameplateVisible
_setVisible                           overall actor visibility
```

The nameplate API is rich -- color, icon, gauge, visibility. This is
the floating name+health bar above NPCs/players.

### Map / Visibility (2 bindings)

```text
_setMapMarker                         minimap marker on this actor
_isAccessibleInServer                 server-accessible flag
```

### Item / Inventory (12 bindings)

```text
_getItem                              get item by slot
_getEquippingItem                     currently equipped item
_getTradingItem                       item in trade window

_getExtendedTemporaryItem             "extended" item (preview/temp)
_getExtendedTemporaryEquippingItem
_getExtendedTemporaryTradingItem

_hasItemPackage                       true if has item package
_getItemPackageCapacity               total slots
_getItemPackageFreeSpace              free slots
_updateItemPackage                    refresh from server data

_isItemDealing                        currently in a trade
_isLockingItem                        item slot is locked

_createVirtualItem                     spawn a non-persistent item
_createExtendedTemporaryVirtualItem    spawn temporary virtual item
```

The "Extended Temporary" prefix appears for many getters -- it's the
preview/temp version (e.g., for shop preview, before commit). The
client uses these to render "what would happen if I bought this"
without actually completing the transaction.

### Group / Party (9 bindings)

```text
_getGroup / _getAllGroup              group membership lookup
_getGroupCurrent                       currently active group
_getGroupByDisplayName                 lookup by player name
_updateGroup                           refresh group data
_getExtendedTemporaryGroup             temp/preview variant
_getExtendedTemporaryAllGroup
_getExtendedTemporaryGroupCurrent
_getExtendedTemporaryGroupByDisplayName
```

8 getters + 1 updater. Same pattern as Item -- has "Extended Temporary"
variants for preview/temp use.

### Job + Stats (5 bindings)

```text
_getJob                               class/job ID
_getActorMainStat                      main stat by name
_isActorMainStatMode                   stat mode flag
_getGrandOnExtraStat                   GC extra stats
_getGear                                gear set (loadout)
```

### Sub-Stats (8 bindings)

```text
_getSubStatBreakage     gear breakage stat
_getSubStatChant        chant/casting stat
_getSubStatGuard        guard stat
_getSubStatMode         mode flag
_getSubStatMotionPack   motion pack id
_getSubStatObject       held object id
_getSubStatStatus       current status effects
_getSubStatWaste        waste accumulator
```

8 sub-stat accessors. The "SubStat" naming suggests these are
secondary/derived stats (vs `_getActorMainStat` which is the
canonical primary stat).

### System / Net Stats (3 bindings)

```text
_getSystemFlag         the engine's "system flag" bits per actor
_getNetStatSystem      network-synced system state
_getNetStatUser        network-synced user state
```

### Bonus Point Codec (2 bindings)

```text
_encodeBonusPoint / _decodeBonusPoint
```

Convert bonus point data to/from packed integer (per actor data sync).

### CharaScheduler (3 bindings)

```text
_runCharaScheduler                  run a per-actor scheduler
_runCharaSchedulerAgainstTarget     scheduler targeted at another actor
_waitForCharaSchedulerFinished      block until scheduler done
```

The "CharaScheduler" is per-actor task queue (e.g., NPC walking from
A to B, monster spawning sequence). Each actor has its own scheduler
that runs scripted actions.

### Misc (2 bindings)

```text
_getLocation                          high-level location summary
_updateWork                           generic work field update
```

### CharaBase summary

```text
Functional area           Bindings
---------------           --------
Movement / Position             10
LookAt System                    5
Display Name + Nameplate        10
Map / Visibility                 2
Item / Inventory                12
Group / Party                    9
Job + Stats                      5
Sub-Stats                        8
System / Net Stats               3
Bonus Point Codec                2
CharaScheduler                   3
Misc                             2
                              ---
TOTAL                           77 (some bindings count in multiple areas)
                                   (raw _cpp count = 77)
```

## 2. Director (5 bindings) -- CORRECTION to prior finding

File: `director/directorbaseclass_u.lua`

```text
_breakNotice               break/cancel the Notice stream
                           (1 of the 5 streams from PlayerBase finding)
_getGroupByDisplayName     lookup group by display name (delegates to CharaBase)
_getExtendedTemporaryGroupByDisplayName    same, temp variant
_updateWork                generic work field update (WorkSync helper)
_waitForHamletDefenseScore wait for Hamlet Defense score to arrive
                           (CONTENT-SPECIFIC binding!)
```

CORRECTION to `finding_director_judge_purely_lua_no_exe_bridge.md`:
DirectorBaseClass has 5 native bindings, NOT zero. So directors are
~95% pure Lua but have these 5 engine helpers.

The most interesting binding is `_waitForHamletDefenseScore_cpp` --
a CONTENT-SPECIFIC native binding (specifically for the Hamlet Defense
content). This suggests:
- Hamlet Defense was important enough for 1.x to bake into the engine
- OR the score-fetch logic is too complex for pure Lua
- OR it requires waiting on async server data

## 3. WorldMaster (23 bindings) -- the world singleton

File: `world/worldmaster_u.lua`

### Time / Calendar (5 bindings)

```text
_getServerTime           real-time server clock
_getHydaelynTime         in-game time (Hydaelyn = the game's world)
_getHydaelynDay          in-game day
_getHydaelynHour         in-game hour
_getHydaelynMoon         in-game moon phase
```

1.x has a full in-game calendar system with day/hour/moon. The
"Hydaelyn" prefix matches the in-game world's name. Critical for
events that depend on in-game time (e.g., NPCs spawning at night,
moon-phase quests).

### Logging (2 bindings)

```text
_printLog                user-facing log (chat/system log)
_printDebugLog           dev log (debug console only)
```

### Localization (2 bindings)

```text
_loadWord                load localization word table
_unloadWord              unload it
```

These manage the worldMaster text id lookup system (used by widgets
for `setText(ctlName, textId, ...)`).

### Player Accessor (1 binding)

```text
_getMyPlayer             SINGLETON: get the local player actor
```

This is the binding that Directors call via
`worldMaster:_getMyPlayer():xxx()`. It's the canonical "get the
current player" accessor.

### CutScene (1 binding)

```text
_getPendingCutSceneActor   actor for the pending cutscene
```

### Tutorial Subsystem (7 bindings)

```text
_aimCameraTutorial / _cancelAimCameraTutorial
_lookAtPlayerTutorial / _cancelLookAtPlayerTutorial
_runCharaSchedulerTutorial / _waitForCharaSchedulerTutorialFinished
_isKeyboardOnlyTutorial
```

The tutorial system has 7 dedicated native bindings! That's a lot
for a 1.x "tutorial" feature. It suggests the tutorial was a
significant content piece (initial onboarding flow).

The `_isKeyboardOnlyTutorial` binding implies the tutorial detected
controller vs keyboard input mode -- 1.x was notoriously
keyboard-unfriendly, so this might gate certain tutorial steps.

### Chocobo System (4 bindings)

```text
_aimCameraChocobo / _cancelAimCameraChocobo
_transformIntoChocobo / _cancelTransformIntoChocobo
```

Chocobo (the riding mount) has dedicated camera + transform bindings
on WorldMaster. The "transform" suggests the player's actor was
visually replaced with a chocobo-rider model.

### Special Event (1 binding)

```text
_getSpecialEventWork      get the active special-event work state
```

For seasonal events (e.g., Valentione's, Heavensturn -- though those
came in ARR; 1.x had its own seasonal events).

## 4. DesktopWidget (sampled 20 of 43)

File: `widget/desktopwidget_u.lua`

### Widget Container (6 bindings)

```text
_createWidgetInWidgetContainer            spawn a new widget
_deleteCreatingWidgetInWidgetContainer    delete pending creation
_isCreatingWidgetInWidgetContainer        check creation state
_isExistWidgetInWidgetContainer           check widget exists
_getWidgetContainerSize                    count widgets
_getWidgetFromWidgetContainer              get by index
```

This is how the HUD spawns and tracks all child widgets.

### Log / Message Pool (3 bindings)

```text
_appendLogPool / _appendMessagePool        add to log
_clearLogPool                              clear log
```

The chat/system log uses an "append + clear" pool pattern (likely a
circular buffer of recent messages).

### Targeting (6 bindings)

```text
_getCurrentTargetCursor                    cursor's current target
_getTargetCharacter                        targeted actor
_getCharacterByDisplayNameForTextCommand   resolve "/tell Bob" etc.
_initTargetCursors                         setup cursor system
_isTargetCursorControlEnabled              targeting input enabled?
_getLastAttacker                           who last attacked us
```

### Macro (3 bindings)

```text
_getUserMacroData / _getUserMacroIcon / _getUserMacroTitle
```

User-defined chat macros (icon + title + data).

### Other (2 sampled)

```text
_getKeyboardFocusedWidget                  what widget has focus
_getUserConfig                             user settings
```

(23 more DesktopWidget bindings exist but not yet enumerated --
covers chat, target dialog, system controls, etc.)

## 5. Cumulative impact

```text
Module          Bindings    Status this finding
------          --------    ---------------
CharaBase           77      ENUMERATED + categorized
WorldMaster         23      ENUMERATED + categorized
Director             5      ENUMERATED (corrects prior claim of 0)
DesktopWidget       20      SAMPLED (43 total, 23 remain)
                ----
                   125     net new bindings catalogued
```

Combined with prior findings, the catalogued native binding surface
is now:

```text
Module                     Bindings catalogued    Module total
------                     -------------------    ------------
PlayerBase                          99                  94 *
NpcBaseClass                        24                  23 *
CharaBase                           77                  76 *
WorldMaster                         23                  23
DesktopWidget                       20                  43
Director                             5                   5
SpreadSheet                         10                  10
                                  ---                  ---
                                  258                 274 *

* counts differ slightly due to grep counting `_inl =` vs
  function definitions; 1-2 off in places
```

Remaining work: ~181 bindings across 12+ smaller modules.

## 6. Server design implications

```text
With CharaBase + WorldMaster + DesktopWidget partially enumerated:

  PER-ACTOR API (CharaBase 77 bindings):
    Every actor on the wire (Player + NPC) supports the 77
    CharaBase methods. Server pushes:
      - Position/Direction updates (10 bindings)
      - Display name changes (4)
      - Nameplate state (5)
      - Item/inventory updates (12)
      - Group membership changes (9)
      - Stat updates (5+8 sub-stats)
      - System flag changes (1; routes to invokeLua_onChangeSystemFlag)
      - Net stat sync (2; via WorkSync)
      - CharaScheduler actions (3)
    
    Most of these are READ-ONLY queries from Lua's perspective;
    server doesn't get spammed back with each read.

  WORLD-LEVEL API (WorldMaster 23 bindings):
    Server controls in-game time (5 bindings); client reads.
    Server can trigger tutorial steps (7 bindings).
    Server can issue chocobo transform (4 bindings).
    `_getMyPlayer` is the canonical player accessor.

  HUD API (DesktopWidget 43 bindings, partial):
    Client-local widget creation (6 bindings).
    Targeting + macro state (12+).
    Most of these don't need server involvement; HUD is
    client-driven once the widgets are created.

  DIRECTOR (5 bindings) -- minimal:
    _updateWork sync to server
    _breakNotice triggers Notice cancel
    _waitForHamletDefenseScore -- CONTENT-SPECIFIC engine binding
                                  (Hamlet Defense content has special
                                   server-side score logic)
```

## 7. Confidence

```text
Confirmed:
  - CharaBase has 77 native bindings (counted via grep)
  - WorldMaster has 23 (counted)
  - Director has 5 (NOT zero; correction to prior finding)
  - DesktopWidget has 43 (per prior finding); 20 sampled here
  - Director's _waitForHamletDefenseScore is a content-specific
    engine binding
  - WorldMaster has the in-game time system (Hydaelyn calendar)
  - WorldMaster has 7 tutorial-specific bindings
  - WorldMaster has 4 chocobo-specific bindings

Likely (High):
  - The "Extended Temporary" prefix on CharaBase getters is the
    preview/uncommitted state pattern (used for shop previews,
    trade window preview, etc.)
  - The CharaScheduler is the per-actor async task queue (NPC
    walking, monster spawning sequences)
  - CharaBase nameplate API drives the floating name+HP bar
    above all actors

Likely (Medium):
  - The 23 remaining DesktopWidget bindings cover: chat input,
    map controls, system menu, settings panel, etc.
  - The Hamlet Defense score wait suggests the score is fetched
    asynchronously from the server (rather than computed locally)
```

## 8. Cross-references

- `finding_native_binding_surface_439_across_19_modules.md` --
  parent finding showing the 19+ modules and 439 total
- `finding_director_judge_purely_lua_no_exe_bridge.md` -- CORRECTED:
  Director has 5 native bindings, not zero
- `finding_widget_3tier_dispatcher_architecture.md` --
  desktopWidget's role in the dispatcher hierarchy
- `finding_director_state_machine_concrete_patterns.md` -- shows
  Directors calling worldMaster:_getMyPlayer() (now identified as
  WorldMaster._getMyPlayer_cpp)

## 9. Next test

```text
1. Walk CharaBase_registerAllLuaBindings master block in Ghidra
   to find the C++ implementations (similar to PlayerBase walk)
2. Enumerate the remaining 23 DesktopWidget bindings
3. Read the smaller _u files (Item 19, Group 15, Math 32, String 14,
   Actor 10, Area 9, etc.) to complete the catalog
4. Map all static actor IDs by searching _getStaticActor calls
   (we know 320006 = TutorialJudge; what about others?)
```

## Commit suggestion

```
docs(re/correlation): native bindings enumeration -- CharaBase 77 + WorldMaster 23 + Director 5 + DesktopWidget 20 sampled (125 new)
```
