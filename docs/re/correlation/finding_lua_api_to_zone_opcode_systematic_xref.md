# Finding: Lua API ↔ Zone Opcode Systematic Cross-Reference

Consolidates the complete map of **Lua-side API name** ↔ **EXE binding function**
↔ **outbound Zone opcode**, derived from enumerating `registerLua_*` /
`Lua_*` / `_invokeLua_*` functions in Ghidra and decompiling each to
identify the Lua API name + the dispatch destination.

## 1. Three flow categories

```text
INBOUND  (server -> client -> Lua hook):
  EXE _invokeLua_* function receives an inbound packet, marshals into
  ExecuteParameters, dispatches into Lua via a named "_on*" hook.

OUTBOUND (Lua -> C++ -> server):
  Lua calls a registered native binding -> EXE function reads
  ExecuteParameters, optionally builds a Zone outbound packet.

LOCAL    (Lua -> C++ only):
  EXE function executes locally; never touches the wire.
```

## 2. INBOUND mapping (server opcode → Lua hook)

```text
OPCODE  EXE INVOKER                                             LUA HOOK              CLASS
------  -----------                                              --------              -----
0       Player_invokeLua_onTouch_proximityBegin                  _onTouch_proxyBegin   Player
1       Player_invokeLua_onTouch_proximityEnd                    _onTouch_proxyEnd     Player
4       DesktopWidget_invokeLua_onTargetChanged                  _onTargetChanged      DesktopWidget
5       DesktopWidget_invokeLua_onTargetDecided                  _onTargetDecided      DesktopWidget
7       CutScene_invokeLua_onInitializationClip_PreviewSetupClip _onInitializationClip CutScene
8       CutScene_invokeLua_onInitializationClip                  _onInitializationClip CutScene
9       CutScene_invokeLua_onShowUIClip                          _onShowUIClip         CutScene
10      CutScene_invokeLua_onHideUIClip                          _onHideUIClip         CutScene
11      CutScene_invokeLua_onShowWidgetClip                      _onShowWidgetClip     CutScene
12      CutScene_invokeLua_onHideWidgetClip                      _onHideWidgetClip     CutScene
13      CutScene_invokeLua_onOpenUIClip                          _onOpenUIClip         CutScene
14      CutScene_invokeLua_onFinalizeClip                        _onFinalizeClip       CutScene
20      DesktopWidget_invokeLua_onPreWarp                        _onPreWarp            DesktopWidget
21      DesktopWidget_invokeLua_onPostWarp                       _onPostWarp           DesktopWidget
43      CharaBase_invokeLua_onChangeSystemFlag                   _onChangeSystemFlag   CharaBase
```

So **14 inbound opcodes** route into named Lua `_on*` hooks via dedicated
invoker functions. The CutScene family alone owns 8 of them.

The other ~46 inbound opcodes either:
- Write directly to object fields (no Lua hook -- pure state push)
- Construct Network::*Receiver objects (no Lua hook -- C++-only state)
- Are no-ops (the 10 reserved slots)
- Use the polymorphic UserDataReceiver vtable (22-26, 42)

## 3. OUTBOUND mapping (Lua action → Zone opcode)

### Direct binding → opcode

```text
LUA API (inferred)         EXE BINDING                                    OPCODE   SIZE   ROLE
------------------         -----------                                    ------   ----   ----
_updateWork(s,sl,f0,f1)    lua_updateWork_impl @ 0x006e85e0               0x12f    56B   Work-sync write
                                                                                          (string-path)
_queryBinding (likely)     Lua_queryBinding_dispatchType_sends_0x135      0x135    24B   Binding
                            @ 0x00705eb0                                                   subscribe/query
_sendChallenge (likely)    Lua_sendChallenge_via_opcode_0x134             0x134    40B   Anti-tamper
                            @ 0x006e6360                                                   challenge
_sendByteToggle (likely)   Lua_sendByteToggle_via_opcode_0x131            0x131    24B   Toggle action
                            @ 0x006e5ad0                                                   (sit/stand/etc.)
_sendListObjectDelete      Lua_listObjectDelete_sends_0x130_variantA      0x130A   32B   List delete
                            @ 0x006dacd0                                                   (tag=0x2711)
_sendListObjectQueueAdd    Lua_listObjectQueueAdd_sends_0x130_variantA    0x130A   32B   List queue add
                            @ 0x006dae90                                                   (tag=0x2711)
_sendListIndex             Lua_listIndexSend_via_0x130_variantA           0x130A   32B   List index send
                            @ 0x006e42e0                                                   
_sendMovementState         Lua_send8byteStateAt0x68_via_0x130_variantB    0x130B   32B   Movement/
(likely)                    @ 0x006e2130                                                   transform state
_sendCompoundState         Lua_sendByteUshortAt0x68_via_0x132             0x132    24B   Byte+ushort
(likely)                    @ 0x006e2af0                                                   compound state
_send6argRpc (placeholder) Lua_send6argRpc_via_opcode_0x12e                0x12e    104B  Generic Lua RPC
                            @ 0x00894090                                                   (highest arity)
_updateWorkAlt (likely)    WorkSyncAlt_serializePayloadAndSend_opcode_0x133 0x133  56B   Work-sync TWIN
                            @ 0x006c72e0                                                   PAIR of 0x12f
```

### Server-callback bindings (opcode lives in unanalyzed thunk code)

These bindings have a NAMED registration but the actual outbound logic
is in the unanalyzed region 0x006de5xx..0x006de6xx (PlayerBase) and
0x006e9520..0x006e9660 (NpcBase). The thunk addresses are known but the
real implementations need force-disassembly.

```text
LUA API                EXE REGISTRAR                                  THUNK            CLASS
-------                -------------                                  -----            -----
_callServerOnTalk      NpcBaseClass_registerLua_callServerOnTalk      LAB_006e9520     NpcBase
                        @ 0x00736fc0
_callServerOnEmote     NpcBaseClass_registerLua_callServerOnEmote     LAB_006e95c0     NpcBase
                        @ 0x00737110
_callServerOnPush      NpcBaseClass_registerLua_callServerOnPush      LAB_006e9660     NpcBase
                        @ 0x00737260
_callServerOnCommand   PlayerBase_registerLua_callServerOnCommand     LAB_006de680     PlayerBase
                        @ 0x0073f1d0
_doServerOnCommand     PlayerBase_registerLua_doServerOnCommand       LAB_006de690     PlayerBase
                        @ 0x0073f320
_executeCommand        PlayerBase_registerLua_executeCommand          LAB_006de650     PlayerBase
                        @ 0x0073f080
```

These 6 bindings are the **PRIMARY action surface** of the Lua API:
- Player command execution (3 bindings)
- NPC interaction (3 bindings)

The MSVC COMDAT thunk pattern places member-function pointers at 0xa0
spaced addresses. The 3 NpcBase thunks (LAB_006e9520/95c0/9660) are
exactly 0xa0 apart; the 3 PlayerBase thunks (LAB_006de650/680/690) are
clustered but irregular (probably some are inlined).

### LOCAL bindings (no opcode)

```text
LUA API                       EXE BINDING                            ROLE
-------                       -----------                            ----
_canExecuteCommand            registerLua_canExecuteCommand          predicate; gates
                               @ 0x00730c00                           command dispatch
                                                                      (returns boolean)
_lookAtPlayerTutorial         Lua_worldMaster__lookAtPlayerTutorial  camera/animation
(under worldMaster)            @ 0x006e6d90                           trigger (local
                                                                      cutscene effect)
_loadWord (item localization) (not yet found in Ghidra naming)       text table lookup
_loadTextDataPermanently      (named via existing comments)          permanent text
                                                                      preload
```

## 4. Complete Lua binding registration mechanism

Every Lua binding follows this 4-step C++ registration pattern:

```c
void XxxBase_registerLua_<luaApiName>(Class *self, RegisterCtx *ctx) {
  // Step 1: build input parameter type vector
  // (one descriptor per arg: H/M/_N/Utf8String/LuaControl*/etc.
  //  -- see finding_execute_parameters_marshalling.md)
  inputOps = Functor_buildInputStackOperatorVector(...)
  
  // Step 2: build output parameter type vector  
  outputOps = Functor_buildOutputStackOperatorVector(...)
  
  // Step 3: allocate a Functor pointing at the THUNK address
  //   (the thunk forwards to the actual member function)
  functor = Functor_pool_alloc(this, self, &THUNK_ADDR, 0, inputOps, outputOps)
  
  // Step 4: register the binding under its Lua-visible string name
  //   FUN_00cccad0 inserts (luaApiName, functor) into a hash map
  FUN_00447260(&nameBuf, "<_luaApiName>", DAT_00f67298)
  FUN_00cccad0(&nameBuf, functor, ctx)
}
```

The functor is then invoked when Lua calls the bound function. The thunk
in turn dispatches to the real C++ implementation (which may be in an
unanalyzed region).

### Functor pool

Per `finding_polymorphic_block_userdataReceiver.md` and verified here:
- Each Functor entry is **0x58 bytes**
- Pool is owned by the class registry
- Functor_pool_alloc returns an `undefined8 *` (the functor descriptor)

## 5. Naming convention pattern

```text
EXE NAMING                       LUA-SIDE EQUIVALENT
----------                       -------------------
XxxBase_invokeLua_onYyy          (Inbound) -> calls Lua hook XxxClass:_onYyy
XxxBase_registerLua_zzz          (Outbound) -> Lua calls XxxClass:_zzz
                                 The "_zzz" name is the literal string
                                 passed to FUN_00447260 + FUN_00cccad0
Lua_aaaa_via_opcode_NNN          (Outbound impl) -> sends opcode NNN
Lua_bbbb (no _via)               (Local) -> no outbound packet
```

So the EXE side has THREE NAMING PREFIXES that map to behavior:
- `_invokeLua_` = server pushed packet -> invoke Lua hook
- `_registerLua_` = register binding for Lua-callable function
- `Lua_*_via_opcode_` = the actual implementation that sends a packet
- `Lua_*` (no via) = local-only Lua binding

## 6. Cross-reference summary table

```text
DIRECTION    OPCODE   LUA API                EXE FUNCTION                            ROLE
---------    ------   -------                ------------                            ----
INBOUND      0        _onTouch_proxyBegin    Player_invokeLua_onTouch_proximityBegin proximity start
INBOUND      1        _onTouch_proxyEnd      Player_invokeLua_onTouch_proximityEnd   proximity end
INBOUND      4        _onTargetChanged       DesktopWidget_invokeLua_onTargetChanged target swap
INBOUND      5        _onTargetDecided       DesktopWidget_invokeLua_onTargetDecided target lock-on
INBOUND      7-14     _onInitClip/etc.       CutScene_invokeLua_* (8 hooks)          cutscene flow
INBOUND      20       _onPreWarp             DesktopWidget_invokeLua_onPreWarp       pre-warp setup
INBOUND      21       _onPostWarp            DesktopWidget_invokeLua_onPostWarp      post-warp finish
INBOUND      43       _onChangeSystemFlag    CharaBase_invokeLua_onChangeSystemFlag  flag toggle

OUTBOUND     0x12e    _send6argRpc           Lua_send6argRpc_via_opcode_0x12e        generic 6-arg RPC
OUTBOUND     0x12f    _updateWork            lua_updateWork_impl                     work-sync write
OUTBOUND     0x130A   _sendList* (3 vars)    Lua_list*_sends_0x130_variantA          list mutate
OUTBOUND     0x130B   _sendMovementState     Lua_send8byteStateAt0x68_via_0x130_varB transform state
OUTBOUND     0x131    _sendByteToggle        Lua_sendByteToggle_via_opcode_0x131     1-byte toggle
OUTBOUND     0x132    _sendCompoundState     Lua_sendByteUshortAt0x68_via_0x132      byte+ushort
OUTBOUND     0x133    _updateWorkAlt         WorkSyncAlt_serializePayloadAndSend     work-sync TWIN
OUTBOUND     0x134    _sendChallenge         Lua_sendChallenge_via_opcode_0x134      anti-tamper
OUTBOUND     0x135    _queryBinding          Lua_queryBinding_dispatchType_sends_0x135 subscribe/query

OUTBOUND     ?        _callServerOnTalk      NpcBaseClass_registerLua_callServerOnTalk  NPC talk send
OUTBOUND     ?        _callServerOnEmote     NpcBaseClass_registerLua_callServerOnEmote NPC emote send
OUTBOUND     ?        _callServerOnPush      NpcBaseClass_registerLua_callServerOnPush  NPC push send
OUTBOUND     ?        _callServerOnCommand   PlayerBase_registerLua_callServerOnCommand command request
OUTBOUND     ?        _doServerOnCommand     PlayerBase_registerLua_doServerOnCommand   command fallback
OUTBOUND     ?        _executeCommand        PlayerBase_registerLua_executeCommand      THE main entry

LOCAL        -        _canExecuteCommand     registerLua_canExecuteCommand              boolean gate
LOCAL        -        _lookAtPlayerTutorial  Lua_worldMaster__lookAtPlayerTutorial      camera local
```

## 7. The Big Unknown: which opcode do command/NPC bindings use?

The 6 server-callback bindings (3 NPC + 3 PlayerBase) ALL forward to thunks
in unanalyzed code. Per the comments already in Ghidra:
- The bodies are in regions 0x006de5xx..0x006df000+ and 0x006e9520..0x006e9660+
- These regions need a **force-disassemble pass** to recover the wire opcodes

The most likely candidates (from process of elimination):
- **0x12e (6-arg RPC, 104B)** -- big enough for command args (commandName,
  command, A2..A10 = 11 params). Already documented as the
  `Lua_send6argRpc_via_opcode_0x12e` callsite. The `_executeCommand`
  binding has 11 args and probably uses opcode 0x12e.
- **0x130A (list, 32B)** -- could carry NPC interaction (Talk/Emote/Push)
  with object id + index. Plausible for `_callServerOnTalk` etc.

This is the **highest-value remaining EXE work** for the project.

## 8. ExecuteParameters marshalling chain

Per `finding_execute_parameters_marshalling.md`, the 14 StackOperator types
that marshal Lua args to C++:

```text
StackOperator      Meaning
-------------      -------
H, M               numeric scalars
_N                 named scalar
Utf8String         text
LuaControl*        actor reference
AutoReleaseTenta   short-lived ref
Nil                null
Table              Lua table
IndividualIndex    enumerator
Variable           bound variable
LuaControlArray    array of refs
... (14 total)
```

The `Functor_buildInputStackOperatorVector` calls at registration time set
up which marshallers run for each binding. For `_executeCommand` (11 args),
the input vector has 11 marshalling descriptors.

## Confidence

```text
Confirmed:
  - 14 INBOUND opcodes mapped to specific Lua _on* hooks via dedicated
    EXE invoker functions.
  - 11 OUTBOUND opcodes mapped to specific EXE sender functions, of
    which 8 have been traced back to their Lua-callable wrappers.
  - 6 server-callback bindings registered (NPC: Talk/Emote/Push;
    PlayerBase: callServerOnCommand/doServerOnCommand/executeCommand).
  - 2 local-only bindings (_canExecuteCommand predicate +
    _lookAtPlayerTutorial camera trigger).
  - Lua binding registration follows uniform 4-step pattern:
    inputOps -> outputOps -> Functor alloc -> name+register.
  - Functor pool entry size = 0x58 bytes.
  - The 3 NpcBase thunks are at 0xa0 offsets (MSVC COMDAT pattern).
  - _updateWork takes (structName, slotName, field0, field1) -- 4 args
    confirmed via lua_updateWork_impl decomp.
  - _queryBinding takes (bindingId) and reads ExecuteParameters[0] as a
    binding ID -- 0x3f2/0x3f3/0x3f4 hardcoded for hp/hpMax/skillLevel.
  - 0x12f and 0x133 are a TWIN PAIR with identical code structure.

Likely (High):
  - _executeCommand uses opcode 0x12e (6-arg RPC) because:
    - Argument count matches (executeCommand has 11 Lua args; 0x12e is
      the highest-arity outbound)
    - 104-byte payload size is enough for commandName + command + 9
      parameter slots
  - _callServerOnCommand, _doServerOnCommand also use 0x12e (siblings
    sharing the PlayerBase command bridge).
  - _callServerOnTalk/Emote/Push (NPC interactions) use a smaller opcode
    -- possibly 0x130A or 0x132 since they need only (npcId, action_byte,
    optional_param).

Likely (Medium):
  - 0x133 (WorkSyncAlt twin) is the SERVER ACK or BROADCAST counterpart
    to 0x12f. Server might send 0x133 to confirm a 0x12f write.
  - The 0x2711 (10001) magic tag in 0x130 list ops is an OBJECT CLASS ID
    -- likely Status (which has getObjectClassId = 5 per
    finding_statusbaseclass_complete_math_pipeline.md, so 5 != 10001
    means it's a DIFFERENT class). 10001 might be a "list-tracked
    actor reference" class id.

Speculative:
  - The "_callServerOn*" prefix vs "_doServerOn*" prefix likely means:
    - call: client-initiated request -> server response expected
    - do: client-initiated action -> server applies (no response needed)
  - The 11-arg shape of _executeCommand hints at a 11-slot generic action
    table: (commandName, commandSheetRef, target, choice, item, paramA-F).
```

## Server implications

```text
The COMPLETE Lua API surface that touches the wire:
  6 outbound RPC bindings (commands + NPC interactions)
  9 outbound state-sync bindings (work-sync, toggles, queries)
  14 inbound hook deliveries (cutscene, targeting, warping, etc.)

A test server must handle:
  - 9 documented outbound opcodes (0x12d-0x135 range)
  - PLUS the 6 unknown opcodes used by command/NPC bindings
    (probably some combination of 0x12e + others)
  
  - Push to client the 14 inbound opcodes documented above
  - Plus the ~46 other inbound opcodes that don't hit Lua
```

## Annotations made in Ghidra

This finding doesn't add new annotations -- it consolidates the existing
~35 Lua_*/registerLua_*/_invokeLua_* function names into a single
cross-reference document.

## Cross-references to other findings

- **`finding_outbound_complete_lobby_zone_chat.md`**: this finding maps
  each Zone outbound opcode (0x12d-0x135) to its Lua-side trigger.
- **`finding_inbound_dispatch_100_percent_coverage.md`**: this finding
  identifies which inbound opcodes have Lua _on* hooks (vs direct field
  writes).
- **`finding_execute_parameters_marshalling.md`**: explains the
  ExecuteParameters/Functor system that backs every Lua binding.
- **`finding_polymorphic_block_userdataReceiver.md`**: documents the
  Functor pool allocator used by every register call.
- **`finding_chara_cliprog_and_event_extensions.md`**: the CharaBase
  cliprog extensions register additional Lua hooks beyond the
  documented 14.

## Next test

The highest-value remaining work for systematic mapping:

1. **Force-disassemble LAB_006de5xx and LAB_006e9520+** to recover the
   opcodes used by:
   - _executeCommand (probably 0x12e)
   - _callServerOnCommand / _doServerOnCommand
   - _callServerOnTalk / _callServerOnEmote / _callServerOnPush
   
2. **Identify the 0x2711 (10001) class ID** by cross-referencing FFXIVTool
   data tables for objects with class ID 10001.

3. **Find additional Lua bindings** by searching for other
   `XxxBase_registerLua_*` patterns -- this finding covers only the
   already-named ones; more may exist with FUN_ prefix.

4. **Walk inbound opcodes 22-26 (UserDataReceiver vtable slots)** to
   identify which Lua hooks fire for each slot.

5. **Cross-reference _queryBinding ID space** (0x3f2 = 1010, 0x3f3 = 1011,
   0x3f4 = 1012) against the `finding_bindwork_catalog.md` to confirm the
   binding ID -> field path mapping.

## Commit suggestion

```
docs(re/correlation): Lua API <-> Zone opcode systematic cross-reference -- 14 inbound + 11 outbound mappings
```
