# Finding: PlayerBase Lua Bindings -- 39 of ~94 Identified + Named

Substantially expands the PlayerBase Lua API surface documentation by
walking the master block `PlayerBase_registerAllLuaBindings` at
0x00753f90 and decompiling each registrar function to extract:
- Lua-side binding name (literal string)
- Member function pointer thunk address
- Functional category

**Result**: 39 of ~94 PlayerBase bindings now named (~41% coverage), up
from 4 previously documented. Ghidra functions renamed for ongoing
research.

## 1. The discovery that unlocked the batch

The thunk addresses LAB_006de650 through LAB_006de890+ are NOT in an
"unanalyzed region" as previously thought. They ARE defined as labels
(spaced 0x10 = 16 bytes apart per MSVC COMDAT pattern), but Ghidra has
not auto-promoted them to functions. The **REGISTRAR functions that
reference them** are fully decompiled and contain the Lua-side string
literal.

So the binding NAME is recoverable from the registrar even when the
thunk + real body are unanalyzed. This finding documents what's
recoverable without manual force-disassembly.

## 2. The 39 PlayerBase bindings (by category)

### EXECUTE family (3 bindings)

```text
LUA API             REGISTRAR           THUNK            ROLE
-------             ---------           -----            ----
_executeCommand     0x0073f080          LAB_006de650    Player command dispatch
_executeTalk        0x00730960          LAB_006de660    NPC dialog dispatch
_executeEmote       0x00730ab0          LAB_006de670    Emote dispatch
```

The 3 execute APIs are the **front entry points** for player-initiated
actions. Per the Lua decomp, `_executeCommand` is called by
`PlayerBaseClass:command(command, A2..A10)` for every command that
passes `canCommand()` validation. The 11-arg signature handles every
command type:
- "commandRequest" / "commandJudgeMode" / "commandDefault" / "commandWeak"
- "commandForced" / "commandContent" / "widgetCreate" / "macroRequest"

### CAN-EXECUTE family (3 bindings) -- predicates

```text
_canExecuteCommand  0x00730c00          LAB_006de6a0    Validates command
_canExecuteTalk     0x00730d50          LAB_006de6b0    Validates talk
_canExecuteEmote    0x00730ea0          LAB_006de6c0    Validates emote
```

Pure validation predicates. Returns boolean. Called BEFORE the matching
execute. Does NOT touch the wire.

### CANCEL family (5 bindings)

```text
_cancelCommand      0x00730ff0          LAB_006de6d0
_cancelTalk         0x00731140          LAB_006de6e0
_cancelNotice       0x00731290          LAB_006de6f0
_cancelEmote        0x007313e0          LAB_006de700
_cancelPush         0x00731530          LAB_006de710
```

5 cancel variants reveal that **1.x's command system has 5 distinct
streams**: Command (player actions), Talk (NPC dialog), Notice (event
popup), Emote (emotes), Push (NPC push interactions). Each has its
own cancel pathway.

### SERVER CALLBACK family (2 bindings)

```text
_callServerOnCommand  0x0073f1d0        LAB_006de680    Client-initiated request
_doServerOnCommand    0x0073f320        LAB_006de690    Fallback for server-pushed
```

The 2 "callServer" / "doServer" bindings are the **PRIMARY OUTBOUND
wire bridge** for player commands. Per the existing 
`finding_lua_to_exe_command_bridge.md`, both forward to thunks that
build a Zone-channel packet and send it. The exact opcode is in the
unanalyzed region but is HIGHLY LIKELY 0x12e (the 6-arg RPC, 104 bytes,
matching the 11-arg invocation shape).

### BREAK + STATUS PREDICATES (4 bindings)

```text
_breakCommand            0x00731680      LAB_006de720
_isEventPlaying          0x007317d0      LAB_006de730
_isCommandPlaying        0x00731920      LAB_006de740
_countCommandPlaying     0x00731a70      LAB_006de750
```

`_breakCommand` is the "abort current command immediately" hammer.
The 3 predicates report on the current state of the command queue.

### FADE / TRANSITION UI family (8 bindings)

```text
_fadeIn                                     0x00731bc0  LAB_006de760
_fadeOut                                    0x00731d10  LAB_006de770
_waitForFading                              0x00731e60  LAB_006de780
_isFading                                   0x00731fb0  LAB_006de790
_cancelFading                               0x00732100  LAB_006de7a0
_fadeInAfterWarp                            0x00732250  LAB_006de7b0
_resetFade                                  0x007323a0  LAB_006de7c0
_fadeInNowLoadingForNoticeEventJustInArea   0x007324f0  LAB_0071e3f0
```

8 bindings dedicated to **fade transitions** -- the screen fade in/out
machinery that brackets cutscenes, warps, and notice events. The last
one's verbose name (`_fadeInNowLoadingForNoticeEventJustInArea`)
specifically handles the "loading screen for in-area notice events"
case -- a very specific corner case in 1.x's UX flow.

### PLAYER CONTROL family (3 bindings)

```text
_lockPlayerControl       0x00732640      LAB_006de7e0
_unlockPlayerControl     0x00732790      LAB_006de7f0
_isPlayerControlEnabled  0x007328e0      LAB_006de800
```

Locks/unlocks player input during cutscenes, events, or hitstun.

### LOCKON CONTROL family (5 bindings)

```text
_lockLockonControl         0x00732a30    LAB_006de810
_unlockLockonControl       0x00732b80    LAB_006de820
_isLockonControlEnabled    0x00732cd0    LAB_006de830
_setLockonTarget           0x00733210    LAB_006de870
_getLockonTarget           0x00733360    LAB_006de880
```

5 bindings for the LOCK-ON (target lock) system. Setters/getters for
the current locked target + lock toggle.

### CAMERA CONTROL family (3 bindings)

```text
_lockCameraControl         0x00732e20    LAB_006de840
_unlockCameraControl       0x00732f70    LAB_006de850
_isCameraControlEnabled    0x007330c0    LAB_006de860
```

Locks/unlocks camera control (during cutscenes, event camera scripts).

### WORLD STATE family (3 bindings)

```text
_waitForMapLoaded          0x007334b0    LAB_006de890
_setMusic                  0x00733600    LAB_0071e400
_setWeather                0x00733750    LAB_0071e410
```

`_setMusic` and `_setWeather` are the local triggers for music/weather
changes (matched by the PrefaceJudge sub-system documented in
`finding_judge_family_19_classes_and_craft_id_space.md`).

## 3. Pattern recognition

```text
ALL 39 (and presumably all ~94) PlayerBase registrars share the same
shape:

  void FUN_XXXXX(undefined4 param_1, undefined4 *param_2) {
    inputOps  = build_input_StackOperator_vector(...)
    outputOps = build_output_StackOperator_vector(...)
    functor   = Functor_pool_alloc(this, param_1, &THUNK_ADDR, 0, ...)
    FUN_00447260(name, "<_luaApiName>", DAT_00f67298)
    FUN_00cccad0(name, functor, param_2)
  }

Spacing between registrars in the master block:
  Generally 0x150 (336) bytes per registrar
  Sometimes 0x10 (16 bytes) shorter when input/output ops are simpler

Spacing between thunks:
  Always 0x10 (16 bytes) -- one MSVC COMDAT jmp + padding

Thunk addresses are 99% sequential (LAB_006de650, 660, 670, 680, ...).
Occasional jumps to a different range (LAB_0071e3f0, LAB_0071e400)
suggest those thunks live in a separate COMDAT cluster.
```

## 4. Insights from naming patterns

### 5-stream command system

The CANCEL family has 5 entries: Command/Talk/Notice/Emote/Push.
This matches:
- **NpcBase callServerOn{Talk, Emote, Push}** (3 streams from
  finding_lua_to_exe_command_bridge.md)
- **PlayerBase callServerOnCommand** (1 stream)
- Plus **Notice** as a 5th stream (probably the event-popup notification
  system, e.g., "Press [confirm] to continue")

So 1.x's command system was designed around 5 PARALLEL ACTION STREAMS,
each with its own execute / canExecute / cancel / etc. flow.

### Fade system complexity

8 dedicated fade bindings reveals that **screen fade is treated as a
FIRST-CLASS subsystem** in 1.x. Multiple state-tracking calls
(_isFading, _waitForFading, _cancelFading) suggest the fade machinery
runs asynchronously and Lua scripts coordinate around it.

### Three control-lock subsystems

```text
_lockPlayerControl   (input lock for cutscenes/events)
_lockLockonControl   (target-lock toggle during scripted actions)
_lockCameraControl   (camera lock for event camera scripts)
```

These can be locked INDEPENDENTLY. So during a cutscene:
- Player control: usually LOCKED
- Lockon control: locked or unlocked depending on whether the
  cutscene needs to preserve player's lock state
- Camera control: LOCKED (event camera takes over)

### `_set*` setters appear

```text
_setMusic
_setWeather
_setLockonTarget
```

These are write operations to game state from Lua. The opcodes used
by these setters would be in their respective thunk implementations
(unanalyzed). For music + weather, these might be SERVER-broadcast
state (the server tells all clients to switch music/weather), so the
setter probably only WRITES LOCALLY -- not necessarily a wire packet.

## 5. Coverage status

```text
BEFORE this finding:  4 of ~94 PlayerBase bindings documented
                      (_executeCommand, _callServerOnCommand,
                       _doServerOnCommand, _canExecuteCommand)

AFTER this finding:  39 of ~94 documented (~41%)

REMAINING: ~55 bindings still un-extracted
```

The remaining 55 follow the same registrar pattern at addresses
0x007338a0..0x00735d60 + interleaved at 0x0074xxxx + 0x007290e0+
(per the master block listing). Each can be decompiled to extract
the binding name -- this finding stops at ~41% coverage to keep the
analysis tractable. Future batches can resume from registrar 40
(at 0x007338a0) and continue.

## 6. Implications for server design

```text
For a basic test server, the highest-priority bindings are:
  
  WIRE TRAFFIC (must implement):
    _callServerOnCommand   (PRIMARY: every player command goes here)
    _doServerOnCommand     (FALLBACK: secondary command path)
    _executeCommand        (FRONT-END for the above)
    _setLockonTarget       (target lock state)
  
  CLIENT-LOCAL ONLY (server doesn't see):
    _canExecuteCommand / _canExecuteTalk / _canExecuteEmote
    _isEventPlaying / _isCommandPlaying / _countCommandPlaying
    _isFading / _isPlayerControlEnabled / _isLockonControlEnabled / etc.
    _fadeIn / _fadeOut / _waitForFading / _cancelFading / etc.
    _lockPlayerControl / _unlockPlayerControl / etc.
    _waitForMapLoaded
  
  SERVER-PUSHED THEN APPLIED LOCALLY:
    _setMusic              (probably sent via opcode 26+ inbound)
    _setWeather            (matches WeatherDirector machinery)
    _resetFade             (likely fired by Preface judges)

Many of these "_set" / "lock/unlock" / "is*" bindings are LOCAL TO
THE CLIENT and just maintain client-side state. They don't all
require server-side opcode handling.
```

## Confidence

```text
Confirmed:
  - 39 PlayerBase Lua binding names recovered from registrar string
    literals at addresses 0x007309xx through 0x00733750.
  - Thunk address space is contiguous LAB_006de650..LAB_006de890+
    with occasional jumps to LAB_0071e3f0+ range.
  - Each registrar follows uniform 6-step pattern:
    inputOps, outputOps, allocFunctor, nameString, registerInMap, cleanup.
  - PlayerBase has 5 command streams (Command/Talk/Notice/Emote/Push)
    based on the cancel family.
  - The fade subsystem has 8 dedicated bindings + 3 separate
    control-lock subsystems (Player/Lockon/Camera).

Likely (High):
  - The remaining ~55 unnamed registrars continue at
    0x007338a0..0x00735d60 with the same shape -- each yields a binding
    name when decompiled.
  - _executeCommand, _callServerOnCommand, _doServerOnCommand all use
    opcode 0x12e (the 6-arg RPC; payload size 104B is enough for
    11-arg dispatch).
  - _setMusic / _setWeather are LOCAL-ONLY bindings (server pushes
    music/weather state via inbound packets; local setter applies it).
  - _waitForMapLoaded yields control until the zone change completes,
    blocking subsequent Lua-script execution.

Likely (Medium):
  - The 8 fade bindings handle BOTH "in-engine" fades (cutscene start)
    AND the special "in-area loading screen" case
    (_fadeInNowLoadingForNoticeEventJustInArea).
  - The 5 distinct command streams map to:
    - Command: ability use (target action)
    - Talk:    NPC interaction
    - Notice:  event popup / confirmation
    - Emote:   emote/gesture
    - Push:    physical push interaction

Speculative:
  - The 94-binding count matches PlayerBase's Lua subclass complexity
    exactly -- a 1:1 mapping with playerbaseclass_u.lua entries.
  - The bindings beyond #40 (currently unnamed) likely cover:
    - Inventory ops (~10-15 bindings: _getItem, _setItem, _useItem, etc.)
    - Equipment ops (~5-10: _equip, _unequip, _swap, etc.)
    - Status query ops (~10-15: _getHp, _getMp, _getStats, etc.)
    - Misc (~15-25: _setRotation, _getPos, _setAnim, etc.)
```

## Annotations made in Ghidra

```text
RENAMES (34 functions this finding):
  PlayerBase_registerLua_executeTalk
  PlayerBase_registerLua_executeEmote
  PlayerBase_registerLua_canExecuteTalk
  PlayerBase_registerLua_canExecuteEmote
  PlayerBase_registerLua_cancelCommand
  PlayerBase_registerLua_cancelTalk
  PlayerBase_registerLua_cancelNotice
  PlayerBase_registerLua_cancelEmote
  PlayerBase_registerLua_cancelPush
  PlayerBase_registerLua_breakCommand
  PlayerBase_registerLua_isEventPlaying
  PlayerBase_registerLua_isCommandPlaying
  PlayerBase_registerLua_countCommandPlaying
  PlayerBase_registerLua_fadeIn / _fadeOut / _waitForFading / _isFading /
                            _cancelFading / _fadeInAfterWarp / _resetFade /
                            _fadeInNowLoadingForNoticeEventJustInArea
  PlayerBase_registerLua_lockPlayerControl / _unlockPlayerControl /
                             _isPlayerControlEnabled
  PlayerBase_registerLua_lockLockonControl / _unlockLockonControl /
                             _isLockonControlEnabled
  PlayerBase_registerLua_setLockonTarget / _getLockonTarget
  PlayerBase_registerLua_lockCameraControl / _unlockCameraControl /
                             _isCameraControlEnabled
  PlayerBase_registerLua_waitForMapLoaded
  PlayerBase_registerLua_setMusic
  PlayerBase_registerLua_setWeather
```

Plus the previously-named:
- PlayerBase_registerLua_executeCommand (existing)
- PlayerBase_registerLua_callServerOnCommand (existing)
- PlayerBase_registerLua_doServerOnCommand (existing)
- registerLua_canExecuteCommand (existing -- on CharaBase/ActorBase,
  not PlayerBase)

So 38 PlayerBase + 1 base-class = 39 total bindings documented.

## Cross-references to other findings

- **`finding_lua_to_exe_command_bridge.md`**: confirmed +
  PlayerBase_registerAllLuaBindings master block at 0x00753f90 walks
  ~94 registrars.
- **`finding_lua_api_to_zone_opcode_systematic_xref.md`**: this
  finding adds 35 new bindings to the systematic xref (was 4 PlayerBase
  bindings, now 39).
- **`finding_judge_family_19_classes_and_craft_id_space.md`**:
  PrefaceJudge handles music/weather changes; _setMusic + _setWeather
  here are the Lua bridges.
- **`finding_director_baseclass_and_226_subclasses.md`**: WeatherDirector
  + opening/cutscene directors interact with the fade subsystem.

## Annotations made in Ghidra (renames)

34 PlayerBase registrar functions renamed from `FUN_xxxxxxxx` to
descriptive `PlayerBase_registerLua_<luaApiName>` names. Original
4 named entries preserved.

## Next test

- Continue from registrar #40 (FUN_007338a0) to extract the remaining
  ~55 binding names. Estimated to reveal:
  - ~10-15 inventory/equipment bindings
  - ~10-15 stat-query bindings
  - ~5-10 emote/animation bindings
  - ~15-25 misc state/world bindings
- Force-disassemble (out-of-MCP) thunks LAB_006de650+ to recover the
  actual wire opcodes for _callServerOnCommand / _doServerOnCommand /
  _executeCommand.
- Walk NpcBaseClass master block (similar structure) to enumerate the
  3 named (callServerOnTalk/Emote/Push) plus likely many more NPC
  bindings.

## Commit suggestion

```
docs(re/exe): PlayerBase 39 of ~94 Lua bindings named -- 5-stream command system + fade/control/lockon families
```
