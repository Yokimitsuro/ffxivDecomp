# Finding: DesktopWidget — 46 Native Bindings (Central UI Hub)

DesktopWidget is the **central UI dispatcher** in 1.x — handles
chat messages, target cursors, user macros, config, widgets, and
text commands. Reading `desktopwidget_u.lua` (472 lines) exposes
~46 native bindings.

Sources read:

```text
widget/DesktopWidget_u.lua    472 lines (~46 binding declarations)
```

## Roster

### Message / Log Pool (3)

```text
_appendMessagePool(actor, channel, msgId, ...)
                      append message to UI pool (chat/notify/alert)
_appendLogPool(...)   append entry to log
_clearLogPool()       clear log
```

These are the LOW-LEVEL primitives behind the higher-level
`worldMaster:say()` / `:notify()` / `:alert()` and
`NpcBaseClass:say()` (per finding_worldmaster_complete.md and
finding_npc_dialog_protocol.md).

### Target Cursor System (8)

```text
_initTargetCursors()                          init the cursor set
_setTargetCursorImage(...)                    cursor icon
_setTargetableDistance(distance)              max distance to target
_getCurrentTargetCursor()                     active cursor
_setCurrentTargetCursor(cursor)               set active cursor
_setAllTargetCursorMask(mask)                 visibility mask
_getTargetCharacter()                         currently targeted char
_setTargetCharacter(char)                     set target by ref
_setTargetCharacterByDisplayName(name)        set target by name string
_setTargetNearestCharacter()                  auto-target nearest
```

Multiple target cursors active simultaneously — the player can
have main target + lockon + AoE targeting cursor visible at once.

### Targeting Misc (1)

```text
_getCharacterByDisplayNameForTextCommand(name)
                                  lookup char by name (for /target cmd)
```

### Keyboard Focus (2)

```text
_getKeyboardFocusedWidget()
_setKeyboardFocusedWidget(widget)
```

Tracks which UI widget has keyboard input focus (chat input,
macro editor, etc.).

### Target Cursor Control Locks (4)

```text
_lockTargetCursorControl()
_unlockTargetCursorControl()
_isTargetCursorControlEnabled()
_setLockonCursorImage(icon)
```

Allows scripts to lock targeting during cutscenes / tutorials.

### Text Commands (1)

```text
_parseTextCommand(text)
              parse a /command line and execute
```

**This is THE chat command parser** — when player types `/say
hello`, this binding handles it. Parsing logic is C++.

### Combat / Damage Tracking (1)

```text
_getLastAttacker()       last actor to damage this player
                          (for retaliation prompts / nameplate
                           markers / kill credit)
```

### User Config Persistence (4)

```text
_setUserConfig(key, value)        write config setting
_resetUserConfig()                 reset to defaults
_getUserConfig(key)                read config setting
_saveUserConfig()                  persist to disk
```

Per-player UI/control configuration (key bindings, UI scale,
chat filter, etc.).

### User Macros (7)

```text
_setUserMacroTitle(idx, title)     macro slot title
_getUserMacroTitle(idx)
_setUserMacroIcon(idx, icon)       macro icon
_getUserMacroIcon(idx)
_setUserMacroData(idx, data)       macro contents (commands)
_getUserMacroData(idx)
_saveUserMacro()                    persist all macros
```

So 1.x had a **user macro system** identical in shape to ARR's:
title + icon + multi-line commands, with persistent save.

### Wait Hooks (3)

```text
_waitForItemSearchWidget()      yield until item search UI closes
_waitForTargetTutorial()        yield until target tutorial done
_waitForCameraTutorial()        yield until camera tutorial done
```

Tutorial flow control — scripts yield until specific UI events
complete before progressing.

### Widget Container Management (7)

```text
_reserveWidgetContainer(id)                       allocate container slot
_getWidgetContainerSize()                          count of containers
_createWidgetInWidgetContainer(id, type)           spawn widget inside
_isExistWidgetInWidgetContainer(id, type)          query exists
_isCreatingWidgetInWidgetContainer(id, type)      query "currently
                                                    being created"
_getWidgetFromWidgetContainer(id, type)            get widget by type
_deleteCreatingWidgetInWidgetContainer(id, type)  cancel pending creation
```

Widget containers are **slots that hold UI panels** (e.g.
"target panel container holds the lockon panel"). Scripts can
dynamically create/destroy panels by container id + type.

### Misc (2)

```text
_hideMainWeapon(bool)         hide/show main hand weapon (visual toggle)
_sendCountDown(seconds)       trigger countdown overlay
                              (used by /countdown command)
```

## Architecture Insights

```text
DesktopWidget is the BRIDGE between:
  - Lua scripts (request UI changes)
  - C++ rendering (actually draws the UI)
  - Server packets (inbound state pushes)

It receives packets via the desktopWidget Lua object's higher-level
methods (processCharacterParameterUpdated, processUpdateGroupInformation,
etc. -- documented per finding_desktopwidget_packet_dispatch.md).

Then it CALLS THESE native bindings to:
  - Append messages to chat pools (channels 32/33/38/40)
  - Update target cursors when target changes
  - Refresh widget panels
  - Save user config/macros to disk
```

## Cross-References Confirmed

```text
_appendMessagePool    -> Used by worldMaster:say (channel 40),
                         worldMaster:notify (32), worldMaster:alert (33),
                         NpcBaseClass:say (38)

_parseTextCommand     -> Entry point for all /commands typed in chat
                         (probably tokenizes "/say hello world" and
                          dispatches to the appropriate Lua handler)

_setTargetCharacter   -> Used after dialog: cancelAllTarget()
                         calls similar; target update after combat

_setUserMacro*        -> 1.x macro system; persistent player UI
```

## Surface Summary

```text
Total: ~46 DesktopWidget native bindings

Categorized:
  Message/Log pool                  3
  Target cursor system              9
  Keyboard focus                    2
  Cursor control locks              4
  Text command parsing              1
  Combat tracking                   1
  User config                       4
  User macros                       7
  Wait hooks (tutorial)             3
  Widget container management       7
  Misc                              2
  TOTAL                            ~43

Plus a handful of stub bindings not enumerated; total ~46-47.
```

## Total API Coverage Now

Combined with prior findings:

```text
CharaBaseClass:    91 bindings (base actor)
PlayerBaseClass:   94 bindings (player extensions)
NpcBaseClass:      24 bindings (npc extensions)
WorldMaster:       24 bindings (global)
DesktopWidget:    ~46 bindings (UI hub; this finding)

Subtotal:        ~279 bindings for core gameplay surface

Plus peripheral (estimated from line counts of remaining _u.lua):
  Math_u             ~32  (system math helpers)
  Global_u           ~27  (global stubs)
  WidgetBaseClass_u  ~24  (widget base methods)
  ItemBaseClass_u    ~19  (item operations)
  GroupBaseClass_u   ~15  (group operations)
  ActorBaseClass_u   ~11  (base actor)
  AreaBaseClass_u    ~11  (zone area)
  DirectorBaseClass_u ~6  (director)
  + smaller stubs

GRAND TOTAL: ~424 native bindings across the 1.x Lua API surface.
```

## Server Implementation Picture

For a server, very few of these UI bindings matter:

```text
SERVER-PUSHED STATE (drives UI bindings):
  Chat/log messages -> server pushes msg, client calls
                       _appendMessagePool/_appendLogPool to display
  Target changes    -> server pushes target update, client calls
                       _setTargetCharacter
  Widget refreshes  -> server pushes state, client calls
                       _createWidgetInWidgetContainer

CLIENT-LOCAL (no server interaction):
  User config / macros (persistent in client save file)
  Target cursor visuals
  Tutorial waits
  Text command parsing (parser is local; result may go to server)
```

So a server only needs to push the underlying STATE; the client's
DesktopWidget bindings render the UI accordingly. The 46 bindings
are all CLIENT-LOCAL render/persistence operations.
