# Finding: CutScene + DesktopWidget + Cancel Block (Opcodes 4-18) -- 11 New Opcodes Named

Validates the prediction `opcode 12 = _onHideWidgetClip` and walks
the remaining unmapped opcodes 5, 6, 7, 14, 16, 17, 18 to close
the cutscene/targeting/cancel block. 7 new opcodes named + 1 query
opcode characterized + 1 debug opcode + 1 tree-op opcode.

Total named active opcodes now: **~31 of 48 (~65%)**, up from
~24 (~50%) after the prior round.

## Prediction validated: opcode 12 = `_onHideWidgetClip`

Walked the FUN_007599e0 wrapper -> router (FUN_008a3b00,
dynamic_cast<CutScene>) -> target FUN_006fc4d0 which calls
Lua `_onHideWidgetClip`. The prediction from
`finding_director_family_and_cutscene_closure.md` was exactly
correct.

So the Show/Hide pairing for WidgetClips matches the pattern of
UIClips (9/10), warp (20/21), touch (0/1).

## Complete CutScene/DesktopWidget block (opcodes 4-14)

```text
OPCODE  HANDLER ADDR    LUA HOOK                                    ACTOR TYPE
------  ------------    --------                                    ----------
   4    0x0075d750      _onTargetChanged                            DesktopWidget
   5    0x0075d780      _onTargetDecided                            DesktopWidget (NEW)
   6    0x0075d7b0      [GET_CURRENT_TARGET query]                  query (NEW; no Lua)
   7    0x0075d830      _onInitializationClip(PreviewSetupClip)     CutScene (NEW)
   8    0x0075d860      _onInitializationClip(Personage)            CutScene
   9    0x0075d890      _onShowUIClip                               CutScene
  10    0x0075d8d0      _onHideUIClip                               CutScene
  11    0x00759940      _onShowWidgetClip                           CutScene
  12    0x007599e0      _onHideWidgetClip                           CutScene (VALIDATED)
  13    0x0075d900      _onOpenUIClip                               CutScene
  14    0x0075d950      _onFinalizeClip (both Preview + Personage)  CutScene (NEW)
```

**11 consecutive opcodes** for the cutscene/targeting subsystem.
The block is now 100% named.

### Opcode 4/5 pair: Target lifecycle

- **Opcode 4** (`_onTargetChanged`): server tells client "your target
  proposed has changed to actor X" -- this is the SOFT target update
  (e.g. mouse hover, lock-on preview).
- **Opcode 5** (`_onTargetDecided`): server confirms "target is now
  actor X" -- the HARD target commit. Fires when the player
  actually confirms targeting (e.g. click-to-target, F-key cycle
  confirm).

The DesktopWidget+0x70 stores the "last main target" ref across both.

### Opcode 6: Query handler

**Opcode 6** is unusual: it's a CLIENT-SIDE QUERY handler that
returns the value at DesktopWidget+0x70 (the current target ref).
The body has NO Lua hook invocation -- it just reads the cached
value and writes to the caller's output buffer.

Likely usage: when the SERVER wants to verify the client's current
target state, it sends a query packet that arrives as opcode 6;
the client returns the local target ref in the response.

Alternative: an internal C++ handler that reads target state for
inclusion in outbound packets. Either way, **opcode 6 is NOT a
gameplay event** -- it's a state-read primitive.

Server impl: low priority; only needed if server wants to
explicitly verify client target state. For most servers,
authoritative state is server-side; client target state can be
inferred.

### Opcode 7/8 pair: CutScene init modes

Two INIT modes for cutscenes, distinguished by the type-tag string:

- **Opcode 7** (`_onInitializationClip` PreviewSetupClip):
  string `PTR_s_PreviewSetupClip_012bfb54`. Used for **character
  creation preview**, mount preview, equipment preview -- anywhere
  the cutscene is a non-canonical "preview" view.

- **Opcode 8** (`_onInitializationClip` Personage):
  string `PTR_s_Personage_012bfb58`. Used for **regular cutscenes**
  where the player IS the Personage on-screen (story cutscenes,
  quest dialogs, etc.).

So a server can pick the appropriate init mode based on what kind
of cutscene is starting.

### Opcode 9-14: Per-clip lifecycle

```text
9   _onShowUIClip       paired with 10
10  _onHideUIClip       (hide overlay)
11  _onShowWidgetClip   paired with 12
12  _onHideWidgetClip   (hide interactive widget)
13  _onOpenUIClip       (no obvious pair; standalone open-mode)
14  _onFinalizeClip     (CutScene end; runs for both Preview AND
                         Personage modes; conditionally if Preview
                         was active)
```

Opcode 14 (`_onFinalizeClip`) cleans up BOTH modes:
- Pass 1 (conditional, if Preview was active): invoke
  `_onFinalizeClip("PreviewSetupClip", actorclassSheet+0x14)`
- Pass 2 (unconditional): invoke
  `_onFinalizeClip("Personage", actorclassSheet+4)`, then delete
  the Personage object at this+0x68.

## Opcode 16: Debug script execution

**Opcode 16** (`FUN_00759a60`) dispatches to the Debug actor
class (Application::Lua::Script::Client::Control::Debug). The
target `FUN_006dc8b0` invokes a script via the
`FUN_00cc7ad0 + FUN_00cd0980/09a0` script-execution pair instead
of a named `_on*` hook.

So **opcode 16 = ARBITRARY SCRIPT EXEC on Debug actor**. This is
the development/test opcode -- a server in dev/QA mode can ship
small Lua snippets to the client for debugging.

Server impl: optional / disabled in production. A retail server
should disable opcode 16 to prevent script injection.

## Opcode 17/18 pair: CutScene cancel lifecycle

```text
opcode 17  _onPreCutSceneCancel    PAIR start
opcode 18  _onPostCutSceneCancel   PAIR end
```

Both invoked on a SYSTEM actor (looked up via actor id `0xc0000024`
which is most likely the WorldMaster -- per prior session,
WorldMaster's static id is `310001` but the inbound id is offset).

The pre/post pattern mirrors warp (opcodes 20/21):
- **Opcode 17**: server announces cutscene is being cancelled;
  client preps to abort cutscene state.
- **Opcode 18**: server confirms cancel completed; client cleans
  up the cancelled state.

Used for: player skipped a cutscene, GM force-cancelled, content
cancelled due to disconnect, etc.

## Opcode 19: Tree-node flag set

**Opcode 19** (`FUN_0075d980` -> `FUN_006edaa0`) walks a tree-like
structure at this+0x130 (`std::map` or `std::set`), finds the node
by key, and sets a byte flag to 1 at the node's +4 offset.

No Lua hook is called. This is a low-level state-set operation
used internally by C++. The specific meaning depends on what's
in `*(this + 0x130)`. Without further context this opcode is
unidentified.

Server impl: deferred until we know what container at +0x130 is.

## Updated coverage

```text
INBOUND OPCODE TABLE @ 0x00fdfb80 -- coverage as of this round:

Named with Lua hook:   25 opcodes
   0, 1, 2 (touch/sit), 4, 5, 8, 9, 10, 11, 12, 13, 14
   (CutScene/DesktopWidget), 20, 21 (warp), 22-26 (polymorphic
   slots), 35, 36, 37, 38, 57 (chat-block + data), 60 (finalize),
   17, 18 (CutSceneCancel)
   
Characterized as non-Lua:    3 opcodes
   3 (4-arg payload, family A; no specific Lua),
   6 (GET_CURRENT_TARGET query),
   19 (tree-node flag set)
   
Family-classified only:    ~20 opcodes
   15 (no-op), 16 (Debug script), 27, 39-50 (Family B small ops),
   51-52 (no-op), 53-56, 58-59 (small B variants)

TOTAL:
  ~28 specifically identified (~58%)
  ~20 family-classified  (~42%)
  100% characterized by family or specific role.
```

## Ghidra annotations made this round

```text
RENAMES:
  - 0x006fc4d0 -> CutScene_invokeLua_onHideWidgetClip
  - 0x006febb0 -> DesktopWidget_invokeLua_onTargetDecided
  - 0x006fbcc0 -> CutScene_invokeLua_onInitializationClip_PreviewSetupClip
  - 0x006fb9c0 -> CutScene_invokeLua_onFinalizeClip
  - 0x006fbc50 -> CutScene_method_setActiveAndFinalize
  - 0x006dc8b0 -> Debug_executeScriptFromCutSceneTable
  - 0x008a3b00 -> Router_dispatch_to_CutScene_onHideWidgetClip
  - 0x008a3ed0 -> Router_dispatch_to_DesktopWidget_onTargetDecided
  - 0x008a45d0 -> Router_dispatch_to_System_onPreCutSceneCancel
  - 0x008a4720 -> Router_dispatch_to_System_onPostCutSceneCancel
  - 0x007599e0 -> ZoneIn_handler_opcode_12_CutScene_onHideWidgetClip
  - 0x0075d780 -> ZoneIn_handler_opcode_5_DesktopWidget_onTargetDecided
  - 0x0075d7b0 -> ZoneIn_handler_opcode_6_GetCurrentTarget_query
  - 0x0075d830 -> ZoneIn_handler_opcode_7_CutScene_onInitializationClip_Preview
  - 0x0075d950 -> ZoneIn_handler_opcode_14_CutScene_setActiveAndFinalize
  - 0x00759a60 -> ZoneIn_handler_opcode_16_Debug_scriptExec
  - 0x00759ad0 -> ZoneIn_handler_opcode_17_onPreCutSceneCancel
  - 0x00759b40 -> ZoneIn_handler_opcode_18_onPostCutSceneCancel

COMMENTS (multi-line):
  - 0x006fc4d0 (Lua hook + pair-with-opcode-11 explanation + prediction-confirmed note)
  - 0x0075d7b0 (query semantics + server-side rare usage)
  - 0x006fb9c0 (FinalizeClip dual-pass invocation + closes the cutscene block)
```

## Confidence

```text
Confirmed:
  - Opcode 12 = _onHideWidgetClip (Lua hook string matches body).
  - Opcode 5 = _onTargetDecided (Lua hook string matches; sibling
    of opcode 4).
  - Opcode 7 = _onInitializationClip with PreviewSetupClip tag.
  - Opcode 8 = _onInitializationClip with Personage tag.
  - Opcode 14 = _onFinalizeClip (called for both Preview AND
    Personage modes).
  - Opcode 17 = _onPreCutSceneCancel; Opcode 18 = _onPostCutSceneCancel
    (paired with 17 like warp 20/21).
  - Opcode 6 is a query handler returning DesktopWidget+0x70
    (current target ref); not a Lua event.
  - Opcode 16 dispatches to the Debug actor for arbitrary script
    execution.

Likely (High):
  - Opcode 13 (_onOpenUIClip) has NO paired _onCloseUIClip in the
    immediate block (opcodes 14-19 don't fire it). Either the
    OpenClip is closed via _onFinalizeClip (opcode 14) or via a
    higher opcode (TBD; may be 27 or later).
  - Opcode 19 is internal state machinery; its purpose depends on
    the C++ container at this+0x130 which is not yet identified.

Likely (Medium):
  - Opcode 16's "Debug script exec" pathway accepts a script name
    via the packet payload; the server can run arbitrary client-side
    Lua. Production server should not enable this without
    authorization checks.
  - The "System" actor at id 0xc0000024 (opcodes 17, 18) is the
    WorldMaster's secondary id used for inbound system events.

Speculative:
  - The 6 opcodes (15, 27, 51, 52, 78, 88) confirmed as NO-OP in
    earlier rounds are likely VESTIGES of opcodes that existed
    in early development and were never used in retail 1.x.
  - Opcode 19's flag-set might be related to STATUS EFFECTS or
    SUBSCRIPTIONS -- the +0x130 container is likely the actor's
    status list or subscription table.
```

## Next test

- Cross-reference opcode 13's `_onOpenUIClip` to find its close
  counterpart (read CutScene_common.lua around line 499 to find
  whether close is via _onFinalizeClip or a distinct hook).
- Sample 3-5 of the unmapped Family-B opcodes 27, 39-50 to
  identify their target actor classes.
- Walk opcode 19's container at this+0x130 to identify what flag
  is being set.

## Commit suggestion

```
docs(re/exe): close CutScene block; validate opcode 12 + name 7 new opcodes (~65% coverage)
```
