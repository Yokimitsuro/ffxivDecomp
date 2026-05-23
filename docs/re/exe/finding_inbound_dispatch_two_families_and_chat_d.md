# Finding: Inbound Dispatch Table - Two Handler Families + Chat Variant D

Extends `finding_inbound_opcode_table_partial_mapping.md` by walking
the previously-unmapped entries 4-27 and 53-59 of the dispatch
table at 0x00fdfb80, identifying a 4th chat message handler, and
classifying every entry by handler family.

## What changed

```text
Newly mapped:
  Entries 4-27   (24 entries; all are thin-wrapper handlers)
  Entries 53-59  (6 entries: 5 thin wrappers + 1 chat variant)
  Entry 57       -> ZoneIn_handler_chat_variant_D   (4th chat handler)

Reclassified:
  Entry 3 ("custom dispatcher, 5 args, complex") -- ACTUALLY just a
    thin-wrapper Pattern 1 with 4 payload args. Same shape as the
    0x0075dxxx family, no special semantics. Updated.

Ghidra annotations made:
  - Renamed 0x0076c690 -> ZoneIn_handler_chat_variant_D
  - Comment at 0x0076c690 documenting the 4-variant chat family
  - Comment at 0x0075d710 correcting the entry-3 "complex" label
```

## The two handler families

Every entry I have walked in the dispatch table at 0x00fdfb80 follows
the same shape:

```c
void entry(this, args...) {
    setup_frame();
    FUN_<reader>(reader_args);             // Layer 1: parse wire bytes
    FUN_<router>(this+4, *(this+8), args); // Layer 2: dispatch to actor method
    teardown_frame();
}
```

But there are TWO distinct flavors based on whether the reader is
allowed to throw:

### Family A: `0x0075dxxx` -- fixed-payload thin wrappers

```c
void __thiscall FUN_0075d750(this, param_1, param_2) {
    undefined4 uStack_4 = this;
    FUN_008a3e90((int)&uStack_4 + 3);                                   // reader
    FUN_008a3ea0((this+4), *(this+8), param_1, param_2);                // router
    return;
}
```

No exception frame. Reader cannot throw. Payload size is known at
compile time.

Entries in this family (in the 4-27 range):

```text
4   0x0075d750
5   0x0075d780
6   0x0075d7b0
7   0x0075d830
8   0x0075d860
9   0x0075d890
10  0x0075d8d0
13  0x0075d900
14  0x0075d950
19  0x0075d980
24  ZoneIn_handler_vtable_dispatch_slot23 (0x00759cd0; polymorphic)
```

Entry 24 is a special case (already named in Ghidra): instead of
calling reader+router, it invokes vtable+0x5c on the packet object
-- the "polymorphic packet" pattern documented in
`finding_inbound_packet_polymorphism.md`. So entry 24 is Pattern 2
even though it lives at a Family-A address slot.

### Family B: `0x00759xxx` -- variable-payload thin wrappers (with SEH)

```c
void __thiscall FUN_00759940(this, param_1, param_2) {
    undefined4 uStack_10;
    void *local_c = ExceptionList;
    ExceptionList = &local_c;                                           // SEH push
    uStack_10 = this;
    FUN_008a3a80((int)&uStack_10 + 3);                                  // reader
    char cVar1 = FUN_004553a0(param_2);                                 // probe
    if (cVar1 != '\0') {
        FUN_004555a0(param_2, 10);                                      // extra read
    }
    FUN_008a3aa0((this+4), *(this+8), param_1);                         // router
    ExceptionList = local_c;                                            // SEH pop
    return;
}
```

Wrapped in an SEH (Structured Exception Handling) frame. The reader
can throw (e.g. on malformed wire data) and the frame unwinds the
stack. Some entries do additional probe-and-read patterns
(read 1 byte; if non-zero, read 10 more) -- consistent with
variable-length payload encoding.

Entries in this family (in the 4-27 range + 53-59):

```text
11  0x00759940
12  0x007599e0
15  0x00759a50
16  0x00759a60
17  0x00759ad0
18  0x00759b40
20  0x00759bb0
21  0x00759c20
22  0x00759c90
23  0x00759cb0
25  0x00759cf0
26  0x00759d10
27  0x00759d20
53  0x0075a4b0
54  0x0075a530
55  0x0075a5b0
58  0x0075a6b0
59  0x0075a730   (reads 0x20 = 32 bytes of payload)
```

### Family C: `0x0076cxxx` -- chat message handlers

A third family lives in 0x0076cXXX and corresponds to the chat
subsystem. Each one shares the FUN_00785XXX writer family:

```text
ENTRY  HANDLER          WRITER         IDENTIFIED VARIANT
-----  -------          ------         ------------------
 35    0x0076c0d0       0x007858c0     CHAT A (broadcast / /say-style)
 36    0x0076c3b0       0x00785aa0     CHAT B (system / /yell-style)
 37    0x0076c220       0x007859b0     CHAT C (whisper / /tell -- 2 names)
 41    0x0076c4d0       0x0089d530     NOT CHAT (different writer family;
                                       request/response-style)
 57    0x0076c690       0x00785bf0     CHAT D (NEW -- 4th chat variant)
```

### Chat variant D (NEW)

```c
void __thiscall ZoneIn_handler_chat_variant_D(this, param_1) {
    int local_40[9];
    FUN_0089d270(local_40, param_1);                  // decoder/builder
    FUN_00785bf0((this+4), param_1, local_40);        // chat writer (0x00785bf0)
    FUN_0089d2f0(local_40);                            // destructor
    return;
}
```

The four chat variants now have writers at addresses 0x007858c0,
0x007859b0, 0x00785aa0, 0x00785bf0 -- consecutive in a ~0x100-byte
stride. So the chat subsystem reserved 4 outgoing channels in the
build address space, all four are populated, and they map to 4
inbound dispatch table entries.

Likely chat-variant semantics (Speculative until matched against
client UI strings):

```text
Chat A  -> /say or zone broadcast            (single name + msg)
Chat B  -> /yell or system message           (single name + payload)
Chat C  -> /tell (player-to-player whisper)  (sender + recipient)
Chat D  -> /shout, /party, or linkshell?     (single name + 32-byte body
                                               + type byte at +0x24)
```

## Entry 41 reclassification (NOT chat)

Entry 41 at FUN_0076c4d0 was hypothesized to be a chat variant because
it lives in the 0x0076cXXX address range. Walking it shows it uses
the **0x0089d5XX builder/writer family** (FUN_0089d530 / FUN_0089d610
/ FUN_0089d5b0), NOT the chat writer family at 0x00785XXX.

```c
FUN_0076c4d0(param_1) {
    // Read 4-byte id (default -1 if zero)
    local_e0 = -1; if (*param_1) local_e0 = *param_1;
    // Read 32 bytes (4 * uint64) at param_1[1..7]
    *pcVar1[0..3] = ... ;
    // Read 1 byte at param_1[9] (offset 0x24)
    local_e1 = (char)param_1[9];
    // Validate via FUN_00447260
    FUN_00447260(local_c4, pcVar1, DAT_00f67298);
    if (id == -1 && type == 0 && body[0] == 0) {
        // empty/null -- discard
    } else {
        FUN_0089d530(local_70, *param_1, local_c4, type);
        FUN_0089d610(local_70, ...);
        FUN_0089d5b0(local_70);
    }
}
```

So entry 41 is a **REQUEST/RESPONSE-style handler** with:

```text
offset 0x00 (4B):   id (correlation? default -1)
offset 0x04 (32B):  body (4 x uint64 chunks)
offset 0x24 (1B):   type/flag byte
```

Total ~37 bytes read. The writer/builder family 0x0089d5XX is used by
several other server-pushed event types. Best guess (Speculative):
this is a **negotiation result** or **command result** push -- a
short typed payload pushing the outcome of a prior request.

## Reclassification of entry 3

Entry 3 (FUN_0075d710) was labeled "custom dispatcher (5 args, complex)"
in the earlier finding. Walking the body shows it is just a
Family-A thin wrapper with 4 payload args (vs 1-2 for siblings):

```c
void __thiscall FUN_0075d710(this, param_1, param_2, param_3, param_4) {
    undefined4 uStack_4 = this;
    FUN_008a36b0(&uStack_4 + 3);
    FUN_008a36c0((this+4), *(this+8), param_1, param_2, param_3, param_4);
    return;
}
```

So entry 3 is just a 4-byte-payload event (4 args = roughly 16 bytes
of inline data). NOT special. The earlier "complex" label is removed.

## Updated active-opcode map (entries 0-60)

```text
ENTRY   HANDLER FAMILY      IDENTIFIED PURPOSE (where known)
-----   --------------      --------------------------------
   0    0x00759820 (B)      _onTouch begin (flag=1)
   1    0x007598a0 (B)      _onTouch end (flag=0)
   2    0x00759920 (B)      _onMoveAtSit
   3    0x0075d710 (A)      4-arg payload event (unidentified)
   4    0x0075d750 (A)      2-arg payload event
   5    0x0075d780 (A)      2-arg payload event
   6    0x0075d7b0 (A)      2-arg payload event
   7    0x0075d830 (A)      2-arg payload event
   8    0x0075d860 (A)      1-arg payload event
   9    0x0075d890 (A)      1-arg payload event
  10    0x0075d8d0 (A)      1-arg payload event
  11    0x00759940 (B)      variable-length event (probe + read 10)
  12    0x007599e0 (B)
  13    0x0075d900 (A)
  14    0x0075d950 (A)
  15    0x00759a50 (B)
  16    0x00759a60 (B)
  17    0x00759ad0 (B)
  18    0x00759b40 (B)
  19    0x0075d980 (A)
  20    0x00759bb0 (B)
  21    0x00759c20 (B)
  22    0x00759c90 (B)
  23    0x00759cb0 (B)
  24    ZoneIn_handler_vtable_dispatch_slot23  POLYMORPHIC PACKET
                                                (vtable+0x5c.process)
  25    0x00759cf0 (B)
  26    0x00759d10 (B)
  27    0x00759d20 (B)
  28-34 NO-OP (6 reserved slots)
  35    0x0076c0d0 (C)      CHAT A (broadcast)
  36    0x0076c3b0 (C)      CHAT B (system)
  37    0x0076c220 (C)      CHAT C (whisper, 2 names)
  38    ZoneIn_handler_dataPacket           generic 192-byte data
                                              -> _onReceiveDataPacket
  39    0x00759ed0 (B)      byte-prefixed length-prefixed
  40    0x00759f50 (B)      3-uint args
  41    0x0076c4d0          REQUEST-RESPONSE result push
                              (NOT chat -- writer 0x0089d530)
  42    0x00759fd0 (B)      2-arg
  43    0x0075a060 (B)      1-uint
  44    0x0075a0e0 (B)      1-byte
  45    0x0075a160 (B)      string + ushort
  46    0x0075a200 (B)      byte+uint+byte
  47    0x0075a280 (B)      1-byte
  48    0x0075a300 (B)      1-byte
  49    0x0075a380 (B)      1-byte
  50    0x0075a400 (B)      4-arg
  51-52 NO-OP (2 reserved slots)
  53    0x0075a4b0 (B)      1-uint
  54    0x0075a530 (B)
  55    0x0075a5b0 (B)
  56    0x0075aaa0 (B)      1-byte
  57    ZoneIn_handler_chat_variant_D (0x0076c690)  CHAT D (NEW)
  58    0x0075a6b0 (B)
  59    0x0075a730 (B)      32-byte payload
  60    Actor_eventHandler_onFinalize (0x006f6900)  _onFinalize
```

## Architecture refinement

The dispatch table is **NOT just a flat opcode->function table**. It is
a **typed event registration table** where each entry binds:

1. A wire opcode (table index)
2. A reader (parses the payload)
3. A router (calls the actor's event method)
4. A frame style (Family A = no SEH; Family B = SEH-wrapped)

Some entries hijack this convention:

- Entry 24 invokes a virtual method on the packet itself
  (polymorphic dispatch -- the packet IS the event implementation).
- Entries 35-37 and 57 are CHAT handlers (a single subsystem with
  4 typed channels).
- Entry 41 is a request-response result handler (different writer
  family).
- Entry 60 calls into the Lua _onFinalize hook.

So the dispatch table mixes **event opcodes**, **subsystem opcodes**
(chat), **lifecycle opcodes** (touch / sit / finalize), and one
**polymorphic packet** opcode. This breadth explains the 4-byte
table stride: a single pointer per opcode is all that is needed for
the wide variety of dispatch styles.

## Confidence

```text
Confirmed:
  - Entries 4-27 + 53-59 mapped (24 + 5 new entries).
  - Two handler families: 0x0075dxxx (no SEH) and 0x00759xxx (SEH).
  - Entry 57 is a 4th chat variant. Writer 0x00785bf0 is the 4th
    in the chat writer family (0x007858c0/007859b0/00785aa0/00785bf0).
  - Entry 41 is NOT chat. Writer 0x0089d530 is a different family.
  - Entry 3 is NOT a "complex custom dispatcher". It is a Family A
    thin wrapper with 4 payload args, no special semantics.
  - Active opcode range bounded to ~60 entries with predominantly
    NO-OP tail beyond that.

Likely (High):
  - The chat variants 35/36/37/57 correspond to 4 distinct chat
    channels in 1.x (/say, /yell, /tell, and one of: /shout,
    /party, /linkshell). UI evidence needed to pin which is which.
  - Family A vs B selection at handler-creation time is purely
    payload variability: fixed-size payloads use Family A;
    variable-size payloads use Family B for safety on malformed
    input.
  - Entry 41's writer family 0x0089d5XX handles command/negotiation
    result pushes -- short typed payloads with a correlation id and
    a 32-byte result body.

Likely (Medium):
  - The 0x008a3XXX router pool contains ~100 distinct routers
    (one pair (reader, router) per active opcode). The router
    decides which actor method to call based on the parsed payload.
  - Future work could enumerate the 100 routers to map opcode ->
    actor method 1:1.

Speculative:
  - The 4th chat variant (entry 57) is likely /shout (zone-wide
    broadcast) because it has a single name + 32-byte body and
    no "tell-style" sender+recipient pair.
  - Entry 41 may be the "command result" return path for outbound
    opcode 0x12d (tagged container request/response correlation).
```

## Updated opcode count

```text
Active opcodes mapped so far:    ~22 (named subsystem)
Active opcodes identified by    ~38 (family-classified, semantics TBD)
   handler family but unnamed:
Total active opcode estimate:    ~60 (entries 0-60 range)
Total table entries:            ~224
Reserved/no-op tail:            ~164 (entries 60+)
Coverage of active opcodes:     ~37% NAMED + ~63% FAMILY-CLASSIFIED
                                = 100% characterized by family,
                                  ~37% by purpose
```

## Next test

- Pick 5-10 of the Family B entries (e.g. entries 11, 15, 20, 25)
  and walk their router function (FUN_008a3XXX+0x10) to identify
  the actor method called. This converts "family-classified" to
  "purpose-identified" entries.
- Cross-reference the 4 chat writers (FUN_00785XXX family) against
  Lua chat-handling scripts to label which chat variant is which.
- Confirm entry 41 is a command/negotiation result push by
  cross-referencing FUN_0089d530 callers against outbound opcode
  0x12d senders.

## Commit suggestion

```
docs(re/exe): map inbound dispatch entries 4-27 + chat variant D
```
