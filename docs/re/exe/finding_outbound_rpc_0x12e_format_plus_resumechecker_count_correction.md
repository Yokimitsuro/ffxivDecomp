# Finding: Outbound RPC Opcode 0x12e Format (104B) + ResumeChecker Count Correction (~24, not 11)

**Maps the primary OUTBOUND RPC wire format** (client→server) and
**corrects the ResumeChecker subclass count** from 11 to ~24 based
on RTTI string enumeration.

The outbound RPC system is the complement to the inbound wire
protocol — it's how the client REQUESTS server-validated actions.

## 1. Opcode 0x12e RPC packet format (104 bytes, PRECISE)

```text
ZoneOut_send_opcode_0x12e_104B builds this packet:

  +0x00  uint32  opcode = 0x12e (HARDCODED)
  +0x04  uint32  size = 0x68 = 104 (HARDCODED)
  +0x08  uint32  sequence/request id    (*param_2)
  +0x0c  uint32  sender id              (this+8)
  +0x10  uint32  METHOD SELECTOR        ((int)*param_3, sign-extended
                                          FIRST BYTE of selector string)
  +0x14  uint32  computed param hash    (FUN_00d3aae0 from param_5)
  +0x18  byte    sub-selector           (*param_4, first byte)
  +0x19  64 B    parameter buffer       (param_5: 16 dwords copied)
  +0x59  ...     padding to 104 total

KEY INSIGHT: The "method name string" pointers passed by callers are
only used for their FIRST BYTE (at +0x10 as sign-extended int, and
+0x18 as raw byte). They are SELECTOR BYTES, not full strings.

Callers index into RTTI type-descriptor strings at specific offsets
to pick the selector byte:
  e.g. s___AVCreateStaticActorResumeCheck_012c3f40 + 0x32
       → the byte at offset 0x32 of that RTTI string = the selector
```

## 2. The outbound RPC architecture

```text
SINGLE WIRE PATH for all 0x12e RPCs:
  Lua_send6argRpc_via_opcode_0x12e (0x00894090)
    -> ZoneOut_send_opcode_0x12e_104B (0x0075e670)
    -> Application_dispatchToZoneClient
    -> wire opcode 0x12e on Zone channel

ALL outbound RPCs funnel through Lua_send6argRpc_via_opcode_0x12e.
6 args: (this, seq, selectorByte*, methodSelector*, paramBuffer*, paramCount)

CALLERS (3 confirmed RPC families):
  FUN_00894ab0  -- uses selector &DAT_0134c3fc
  FUN_00894bc0  -- uses CreateStaticActorResumeCheck-derived selector
  FUN_00896f70  -- CreateStaticActor RPC (with local-vs-remote branch)
```

## 3. The RPC ↔ ResumeChecker connection (KEY ARCHITECTURE)

```text
The outbound RPC system is TIED to the ResumeChecker async pattern:

  1. Lua script calls an action that needs server validation
     (e.g. player:createStaticActor(...))
  2. Client creates an XResumeChecker (suspends Lua coroutine)
  3. Client sends 0x12e RPC with selector derived from XResumeChecker
     RTTI type name + the param buffer
  4. Server processes the request and responds
  5. Client's XResumeChecker readiness flips, waking the coroutine
  6. Lua continues with the server's result

So the OUTBOUND RPC and the RESUMECHECKER async pattern are TWO
HALVES of the same request/response mechanism:
  - ResumeChecker = client-side "waiting for server" state
  - 0x12e RPC = the actual request sent to server
  - Inbound response = wakes the ResumeChecker

This explains why RPC selectors are derived from ResumeChecker
RTTI names: each server-validated action has a paired
(ResumeChecker, RPC selector).

FUN_00896f70 shows this clearly:
  - If condition met (local-resolvable): use FUN_00cd0940 (local path)
  - Else: send 0x12e RPC (CreateStaticActorResumeCheck selector)
  -> i.e., try locally first, fall back to server RPC
```

## 4. CORRECTION: ResumeChecker count is ~24, not 11

Prior findings documented **11 ResumeChecker subclasses**. RTTI
string enumeration reveals MANY MORE. Confirmed via `.?AV*ResumeChecker*`
strings:

```text
PRIOR 11 (script-callable + LpbLoader):
  OnInitResumeChecker, WaitResumeChecker, LoadDataResumeChecker,
  AppendMessageResumeChecker, WaitForTurningResumeChecker,
  WaitForCharaSchedulerFinishedResumeChecker,
  s_WaitForCharaSchedulerTutorialFinishedResumeChecker,
  TargetTutorialResumeChecker, s_CameraTutorialResumeChecker,
  s_ItemSearchWidgetResumeChecker, LpbLoader::ResumeChecker

NEWLY VISIBLE IN RTTI STRINGS (+13):
  TextDataReadResumeChecker (TextData async read)
  PlayingResumeChecker (CutScene playback)
  s_FadeResumeChecker (screen fade)
  s_MapLoadResumeChecker (map loading)
  BgSchedulerResumeChecker (NpcBase background scheduler)
  WaitLoadFormResumeChecker (widget .form loading)
  s_WaitForTransformIntoChocoboResumeChecker (chocobo mount transform)
  CreateClientItemResumeChecker (client item creation)
  s_PreloadResumeChecker (asset preload)
  GetStringResumeChecker (TextModuleAdapter string fetch)
  CreateStaticActorResumeChecker (static actor creation -- RPC-backed)
  ClientOrderEventWaitingResumeChecker (event block wait)
  CancelResumeChecker (cancel operation)

TOTAL: ~24 ResumeChecker subclasses (was 11 documented)
```

This roughly DOUBLES the known ResumeChecker hierarchy. The pattern
is even more pervasive than documented — nearly every async operation
(loading, fading, RPC, scheduling, text fetch) has its own checker.

### Categorization of the ~24 checkers

```text
ASYNC I/O / LOADING (6):
  LoadDataResumeChecker, TextDataReadResumeChecker,
  s_MapLoadResumeChecker, WaitLoadFormResumeChecker,
  s_PreloadResumeChecker, LpbLoader::ResumeChecker

SERVER RPC-BACKED (3):
  CreateStaticActorResumeChecker, CreateClientItemResumeChecker,
  GetStringResumeChecker

ANIMATION / VISUAL (3):
  PlayingResumeChecker (cutscene), s_FadeResumeChecker,
  s_WaitForTransformIntoChocoboResumeChecker

SCHEDULER (3):
  WaitForCharaSchedulerFinishedResumeChecker,
  s_WaitForCharaSchedulerTutorialFinishedResumeChecker,
  BgSchedulerResumeChecker

TUTORIAL (3):
  TargetTutorialResumeChecker, s_CameraTutorialResumeChecker,
  s_ItemSearchWidgetResumeChecker

CORE / MISC (6):
  OnInitResumeChecker, WaitResumeChecker, AppendMessageResumeChecker,
  WaitForTurningResumeChecker, ClientOrderEventWaitingResumeChecker,
  CancelResumeChecker
```

## 5. Server-side RPC requirements

```text
For a COMPLETE server, the 0x12e RPC handler must:

1. Read packet:
   +0x08 sequence id (echo back in response)
   +0x0c sender id (player id)
   +0x10 method selector (1 byte, sign-extended)
   +0x18 sub-selector (1 byte)
   +0x19 64-byte param buffer

2. Dispatch by selector to the appropriate handler:
   - CreateStaticActor: validate + assign actor id + respond
   - CreateClientItem: validate item + respond
   - GetString: fetch localized string + respond
   - (and other RPC-backed checkers)

3. Send response that wakes the client's ResumeChecker:
   - Likely via an inbound opcode carrying the sequence id
   - Client matches sequence -> finds pending ResumeChecker -> wakes coroutine

4. The 64-byte param buffer encodes the RPC arguments
   (per-method format; needs per-RPC decode)

OUTBOUND RPC OPCODES (the full set, from prior + this finding):
  0x12e  6-arg named RPC (104B) -- PRIMARY action request channel
  0x12f  WorkSync update (56B)
  0x130  list lifecycle ACK (32B)
  0x131  byte toggle (24B)
  0x132  item state (24B)
  0x133  WorkSync alt / init ACK (56B)
  0x134  challenge/nonce (40B)
  0x135  subscribe binding (24B)
  0x12d  tagged container (200B)
```

## 6. Confidence

```text
Confirmed:
  - 0x12e packet is 104 bytes with the documented field layout
  - Method selector is a single byte at +0x10 (sign-extended)
  - 64-byte param buffer copied from param_5 (16 dwords)
  - ALL 0x12e RPCs funnel through Lua_send6argRpc_via_opcode_0x12e
  - 3 RPC caller families identified
  - ~24 ResumeChecker subclasses exist (RTTI string confirmed)
  - RPC selectors derived from ResumeChecker RTTI names

Likely (High):
  - Each RPC-backed action pairs a ResumeChecker with a 0x12e selector
  - "Try local, fall back to RPC" pattern (per FUN_00896f70)
  - Server response wakes the ResumeChecker via sequence-id matching
  - The 64-byte param buffer is per-method structured

Speculative:
  - The selector byte values map to a server-side RPC dispatch table
  - Some RPCs (GetString) might be cached client-side after first fetch
  - The _executeCommand path (in unanalyzed gap 0x006de507+) likely
    uses a similar or the same 0x12e mechanism
```

## 7. Open thread: _executeCommand body

```text
The _executeCommand thunk (LAB_006de650) is in an UNANALYZED Ghidra
region (0x006de507..0x006df000+). Auto-analysis didn't detect it as
a function.

This is the front-end for ALL player commands (UI/hotkey/macro).
Its body likely builds a 0x12e RPC (or similar) for server-bound
commands. To fully close the outbound command path, this function
needs manual Ghidra disassembly/creation at 0x006de650.

WORKAROUND: the RPC mechanism IS documented here (0x12e format);
_executeCommand almost certainly uses it. The exact selector +
param packing for commands needs the gap function analyzed.
```

## 8. Cross-references

- `finding_zone_outbound_opcode_roster.md` -- the 9 outbound opcodes
- `finding_resumechecker_11th_subclass_LpbLoader_plus_vtable_methodology.md`
  -- prior 11-subclass count (CORRECTED here to ~24)
- `finding_resumechecker_full_inventory_10_subclasses_confirmed.md`
  -- the original inventory (now superseded)
- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the INBOUND side (responses wake ResumeCheckers)
- `finding_command_execute_wire.md` -- the _executeCommand Lua-side
  reconstruction (body still in gap)

## 9. Next test

```text
1. Manually create function at 0x006de650 in Ghidra to analyze
   _executeCommand body (the command RPC builder)
2. Decode the 64-byte param buffer format for CreateStaticActor RPC
3. Find the INBOUND response opcode that wakes ResumeCheckers
   (sequence-id matching)
4. Enumerate the selector byte values (RPC dispatch table)
5. Update the ResumeChecker findings + QUICK_REFERENCE with the
   ~24 count correction
```

## Commit suggestion

```
docs(re/exe): outbound RPC opcode 0x12e format (104B, byte-selector + 64B param buffer) + ResumeChecker count CORRECTION (~24 not 11); RPC tied to ResumeChecker async pattern
```
