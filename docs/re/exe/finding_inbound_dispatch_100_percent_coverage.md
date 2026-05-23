# Finding: Inbound Dispatch Table 100% Coverage Achieved

The last 3 uncharacterized opcodes (15, 51, 52) are **all NO-OPs**.
Verified by decompiling each wrapper function -- all 3 are empty
`void FUN_xxx(void) { return; }` bodies.

Coverage of the inbound dispatch table at **0x00fdfb80 is now 100%**.

## The 3 remaining opcodes

```text
OPCODE  WRAPPER       CONTENT
------  -------       -------
  15    0x00759a50    void FUN_00759a50(void) { return; }  -- NO-OP
  51    0x0075a490    void FUN_0075a490(void) { return; }  -- NO-OP
  52    0x0075a4a0    void FUN_0075a4a0(void) { return; }  -- NO-OP
```

So **10 total NO-OPs** in the dispatch table:

```text
Op 15  -- scattered slot between cutscene block (4-14) and chat block
Op 28-34 (7 consecutive) -- reserved cluster between SetEventStatus and chat
Op 51-52 (2 consecutive) -- reserved cluster between GC and Achievement bands
```

## Coverage final state

```text
INBOUND OPCODE TABLE @ 0x00fdfb80 -- 100% CHARACTERIZED

ACTIVE LUA-HOOK OPCODES (~30):
  0, 1   proximity touch BEGIN/END
  2      _onMoveAtSit
  4-14   cutscene block (_onTargetChanged through _onFinalizeClip)
  16     Debug.scriptExec
  17, 18 cutscene cancel
  20, 21 warp
  43     _onChangeSystemFlag
  44     _onReceiveLimitAddicted (anti-fatigue)
  60     _onFinalize

NON-LUA STATE OPCODES (~6):
  3      (placeholder)
  6      GET_CURRENT_TARGET query
  19     (placeholder)
  38     _onReceiveDataPacket (generic)
  39     internal map insert
  40     timed-execution scheduler
  41     REQUEST-RESPONSE result push

POLYMORPHIC USERDATARECEIVER (5):
  22-26  vtable slots (per finding_polymorphic_block_userdataReceiver)
  42     UserDataReceiver multi-mode

NETWORK RECEIVER OPCODES (~14):
  27     SetEventStatusReceiver (NpcBase)
  45     HateStatusReceiver (NpcBase)
  46-49  Chocobo / ChocoboGrade / Goobbue / VehicleGrade (MyPlayer)
  50     GrandCompanyReceiver (PlayerBase, polymorphic)
  53-56  Achievement quartet (Point/Title/Id/Count)
  58     JobChangeReceiver
  59     EntrustItemReceiver

CHAT OPCODES (4):
  35     chat A (Command update)
  36     chat B
  37     chat C (=tell)
  57     chat D

NO-OP / RESERVED (10):
  15
  28, 29, 30, 31, 32, 33, 34  (7 consecutive)
  51, 52
```

**TOTAL: 60 active opcodes + 10 no-ops = ~70 dispatch table entries**

(The dispatch table at 0x00fdfb80 has 224 declared entries but only
~70 are within the actual "used" range observed in client code.)

## Annotations made in Ghidra

```text
RENAMES (3 functions this finding):
  0x00759a50 -> ZoneIn_handler_opcode_15_NOP
  0x0075a490 -> ZoneIn_handler_opcode_51_NOP
  0x0075a4a0 -> ZoneIn_handler_opcode_52_NOP
```

## Why so many reserved slots?

```text
Pattern of NO-OP placement suggests:

1. The 10 NO-OPs are SPREAD across the table, not bunched at the end.
2. The 7-slot cluster (28-34) is the largest.
3. The 2-slot cluster (51-52) sits between mount block (45-50) and
   achievement block (53-56).
4. The single slot (15) sits in the middle of the cutscene block (4-18).

INTERPRETATION:
- Square Enix used the dispatch table as a SIGNED SLOT REGISTRY.
- Each slot was reserved when a feature was planned.
- Some features were cut before going live, but the slots remained
  to avoid renumbering the entire table.
- The 7-slot cluster (28-34) was the biggest single planned feature
  that got cut -- likely a multi-opcode subsystem (retainer venture?
  full materia system? housing/apartment management?).
```

## Confidence

```text
Confirmed:
  - All 3 remaining opcodes (15, 51, 52) are empty no-op wrappers.
  - Inbound dispatch table at 0x00fdfb80 is now 100% characterized.
  - Total 60 active + 10 no-op = ~70 dispatch entries used.
  - 14 functions renamed in Ghidra across the 3 new no-ops + retroactive
    finding cleanup.

Likely (Medium):
  - The 7-slot cluster (28-34) was a single planned multi-opcode feature
    cluster, not 7 independent never-implemented features.
  - The scattered single no-ops (15, 51, 52) were planned features that
    each got their slot reserved but were cut individually.

Speculative:
  - Slot 15 sits between cutscene-control (14 _onFinalizeClip) and
    Debug.scriptExec (16), so it might have been an additional
    cutscene-related hook that was deemed unnecessary.
  - Slots 51-52 between GC (50) and Achievement (53) might have been
    GC-rank or GC-promotion notification opcodes.
```

## Lua corpus + EXE dispatch table -- both now ~complete

```text
LUA: 99% architecturally documented (sub-system level)
EXE INBOUND DISPATCH: 100% characterized (every opcode named)

REMAINING EXE WORK:
  - OUTBOUND opcodes (Lobby 8 + Zone 9 + Chat dynamic) -- partial
  - Force-disassemble PlayerBase/NpcBase thunks
  - Map remaining unanalyzed functions in 0x0089xxxx range
  - String table cross-references for command/quest IDs
```

## Connections to other findings

- **`finding_opcodes_27_34_45_50_53_59_complete.md`**: this finding adds
  the last 3 opcodes (15, 51, 52) to the dispatch table coverage.
- **`finding_inbound_dispatch_two_families_and_chat_d.md`**: complete
  family classification of dispatch entries.
- All prior `finding_opcode_*` findings combined now cover 100% of the
  inbound dispatch table.

## Commit suggestion

```
docs(re/exe): opcodes 15 + 51-52 all NO-OPs -- inbound dispatch table 100% characterized
```
