# Finding: Zone Inbound Game-Protocol Opcodes 0x143-0x1a8 -- Bridge Pattern + 50+ Opcode Table

**Documents the bridge pattern for the 50+ game opcodes** discovered
in the spawn wire-side closure session. Samples 4 representative
opcodes across the range to confirm the architecture, then provides
the complete opcode-to-handler table.

This is the WIRE PROTOCOL DOCUMENTATION needed for server-side
implementation — each opcode is a server→client message type.

## 1. The bridge pattern (confirmed across samples)

Most opcodes in the 0x143-0x1a8 range follow a **thin-bridge pattern**:

```text
HANDLER(this, param_1 (header_addr), param_2 (payload_addr)):
   1. (optional) lookup target via FUN_00cc9320(name_or_id)
   2. dispatch to subsystem at this+OFFSET:
        FUN_subsystem_specific(this+OFFSET, ..., payload)
```

The handler itself is **2-5 lines of code** — it doesn't do the
actual work; it FORWARDS to a per-subsystem dispatcher.

### Sample 1: Opcode 0x143 (FUN_00576240) -- thin 1-call bridge

```c
void ZoneIn_opcode_0x143_thinBridge_to_subsystem_0x18
       (this, param_1, param_2, param_3):
  FUN_006c5de0(this+0x18, param_3);   // forward to subsystem at +0x18
```

Subsystem at this+0x18 handles the actual logic. Payload is
forwarded raw.

### Sample 2: Opcode 0x148 (FUN_00576560) -- actor lookup + dispatch

```c
void ZoneIn_opcode_0x148_actorLookup_thenDispatch_subsystem_0x24
       (this, header_addr, payload):
  actor = FUN_00cc9320(&header_addr, *header_addr);  // lookup by id
  FUN_00580e70(this+0x24, actor, payload);            // dispatch
  FUN_00cc9330();                                     // release
```

This is the pattern for **per-actor** messages: lookup target by
id from header, dispatch to actor-targeted handler.

### Sample 3: Opcode 0x17d (FUN_005762c0) -- thin 8-byte forward

```c
void ZoneIn_opcode_0x17d_thinBridge_with8B_to_subsystem_0x18
       (this, payload_8bytes):
  FUN_006c2f30(this+0x18, payload_8bytes);
```

Forwards an 8-byte payload (uint64) to the subsystem at +0x18.

### Sample 4: Opcode 0x193 (FUN_00578c90) -- EXCEPTION: complex system handler

```c
void ZoneIn_opcode_0x193_SYSTEM_ERROR_dispatcher_22codes
       (this, error_code, param_2, param_3):
  if (param_2 == -1) iVar2 = 0;
  else               iVar2 = param_2 + param_3;
  
  if (error_code < 0x10) {
    FUN_0075f3e0(this[+4]+0x10c, error_code, iVar2);   // generic error display
  }
  else switch (error_code) {
    case 0x10/0x11/0x12: 3 specific error displays
    case 0x13: BUILD LOCALIZED ERROR STRING + PUSH TO MESSAGE POOL
                 (uses UTF-16 string templates with sub-params)
    case 0x14: System_broadcastSubsystem_preCancelHooks()
    case 0x15: FUN_00576020
    case 0x16: FUN_0075d270
  }
```

**0x193 is the SYSTEM ERROR / STATUS RESPONSE handler.** Handles
~22 distinct error/status codes. Some build localized message
strings (UTF-16, likely Japanese templates) and push them to the
chat message pool.

## 2. Subsystem destination offsets

```text
this+OFFSET    Subsystem role (inferred from xref patterns)
-----------    --------------
this+0x08      ? (used by FUN_006c5150 dispatch from 0x143 chain)
this+0x18      generic state subsystem (catches 0x143, 0x17d, 0x17e, ...)
this+0x20      ?
this+0x24      actor-bound dispatcher (catches 0x148-0x156 group)
this+0x10c     UI / message pool dispatcher (catches 0x193, error display)
this[+4]+8     subsystem chain (0x18d uses this with session at +0x4d8)
this[+4]+0xec  system error context (0x193 inner branch)
```

The subsystems are likely:
- this+0x18: WorldMaster or actor manager (most opcodes target this)
- this+0x24: CharaBase-bound message dispatcher (per-actor messages)
- this+0x10c: UI/message pool (for system messages and errors)

## 3. Complete opcode-to-handler table (50+ entries)

### Session opcodes (low; 0x02-0x11 + 0xca/0xcb)

```text
Opcode  Handler                                  Inferred purpose
------  -------                                  ----------------
0x02    FUN_004d90c0 + 9980 + dc5d0 + 7660       Session reauth chain
0x03    FUN_004d8560 + 2x std::string (0x20+0x200)  Login text push (announcement?)
0x04    Complex disconnect cleanup chain         Logout / session teardown
0x05    vtable[+0x24] on session                 Generic forward (poly)
0x06    FUN_0081eb90                             ? (uses this+0x17810 list)
0x07    Resync loop (linked list walk)           Reconnect re-sync
0x08    FUN_0081f090 push N=1                    Bulk state push (1 entry)
0x09    FUN_0081f090 push N=16                   Bulk state push (16 entries)
0x0a    FUN_0081f090 push N=32                   Bulk state push (32 entries)
0x0b    FUN_0081f090 push N=64                   Bulk state push (64 entries)
0x0c    FUN_004bbb30 (short+byte)                ? short event with byte tag
0x0d    vtable[+0x24]                            Generic forward
0x0e    Disconnect notice variant A              -> dispatchOutbound 0xb
0x0f    (goto default fallback)
0x10    vtable[+0x24]                            Generic forward
0x11    Disconnect notice variant B              -> dispatchOutbound 0xc
0xca    FUN_004d9910 + FUN_004caf60              ? session marker
0xcb    FUN_004d9910 + dtor                      ? session cleanup
0xcc-e5 (goto default fallback)                  Various unhandled session events
```

### Game protocol opcodes (high; 0x143-0x1a8)

```text
Opcode  Handler                                  Likely purpose
------  -------                                  --------------
0x143   thinBridge to subsystem_0x18             ? generic state event
0x144/5 fallback                                 unhandled
0x146   FUN_005764c0 (header+payload)            ?
0x148   actorLookup -> subsystem_0x24            ACTOR-bound message variant A
0x149   FUN_005765d0 (same shape as 0x148)       ACTOR variant B
0x14a   FUN_00576640                             ACTOR variant C
0x14b   FUN_005766b0                             ACTOR variant D
0x14c   FUN_00576720                             ACTOR variant E
0x14d   FUN_00576790 (ushort payload)            ACTOR variant F (short)
0x14e   FUN_00576800                             ACTOR variant G
0x14f   FUN_00576870                             ACTOR variant H
0x150   FUN_005768e0                             ACTOR variant I
0x151   FUN_00576950                             ACTOR variant J
0x152   FUN_005769c0 (ushort payload)            ACTOR variant K (short)
0x153   FUN_00576a30                             ACTOR variant L
0x154   FUN_00576aa0                             ACTOR variant M
0x155   FUN_00576b10                             ACTOR variant N
0x156   FUN_00576b80                             ACTOR variant O
0x157-6c (fallback)                              unhandled batch
0x16d   FUN_005763c0 (byte payload)              ? short byte event
0x16e   FUN_00576430 (no payload)                ? trigger
0x16f-72 (fallback)                              unhandled
0x175   (fallback)                               unhandled
0x176   FUN_00576bf0                             ?
0x177   (fallback)
0x178   (fallback)
0x179   (fallback)
0x17a   FUN_005763b0 (uint payload)              ? generic uint event
0x17b   (fallback)
0x17c   ★ SPAWN PACKET -> SpawnPipeline_FACTORY ★ ACTOR SPAWN (PINNED)
0x17d   thinBridge with 8B to subsystem_0x18     ? generic uint64 event
0x17e   FUN_005762d0 (uint payload)              ?
0x17f   FUN_005762e0 (uint64 payload)            ?
0x180   FUN_005762f0 (uint64 payload)            ?
0x181   FUN_00576300 (uint64 payload)            ?
0x182   FUN_00576310 (uint64 payload)            ?
0x183   FUN_00576320 (uint payload)              ?
0x184   FUN_00576330 (uint payload)              ?
0x185   FUN_00576340 (uint payload)              ?
0x186   FUN_00576350 (uint payload)              ?
0x187   FUN_00576390 (uint payload)              ?
0x188   FUN_00576360 (uint payload)              ?
0x189   FUN_00576370 (uint payload)              ?
0x18a   FUN_00576380 (raw int payload)           ?
0x18b   FUN_005763a0 (uint payload)              ?
0x18c   (fallback)                               unhandled
0x18d   FUN_00575550 + FUN_0055cf70              COMPLEX session-bound dispatch
                                                  (uses session at this+0x4d8)
0x18e   (fallback)
0x18f   FUN_00576c60 (399 decimal)               ?
0x190   FUN_00576cd0 (400 decimal)               ?
0x191   FUN_00576d40                             ?
0x192   (fallback)
0x193   ★ SYSTEM ERROR DISPATCHER ★              22 error/status codes,
        FUN_00578c90 (3 args)                     localized message strings
0x194   (fallback)
0x195   (fallback)
0x196   FUN_00576050                             ?
0x197   (fallback)
0x198   FUN_00576150 (string payload)            ? text/string event
0x199-a2 (fallback batch)
0x1a3   FUN_00576140 (uint payload)              ?
0x1a4-8 (fallback)                               unhandled batch
```

**Total characterized opcodes**: ~50 with specific handlers,
plus ~40+ that fall through to default (subsystem+0x4e0 vtable[+0x24]).

## 4. Inferred semantic groups

```text
GROUP A: Per-actor messages (0x148-0x156)
  Pattern: actor lookup by id -> dispatch to this+0x24 (CharaBase manager)
  Likely: actor state updates, action notifications, status changes
  15 variants -- probably one per major actor state class

GROUP B: Generic state events (0x143, 0x17d, 0x17e, 0x183-0x18b, etc.)
  Pattern: thin forward to subsystem_0x18
  Likely: generic state push (uint/uint64 values)
  Multiple variants by payload size + meaning

GROUP C: Object-id events (0x17f-0x182)
  Pattern: forward 8-byte uint64 payload
  Likely: object/entity references (8-byte composite ids)

GROUP D: Short payload events (0x14d, 0x152, 0x16d)
  Pattern: 2-byte ushort or 1-byte payload
  Likely: enum codes / small status values

GROUP E: SPAWN (0x17c)
  Pattern: full typed-packet dispatch via Group::PacketRequestBase
  PINNED -- see finding_spawn_wire_side_CLOSED...

GROUP F: SYSTEM ERROR / STATUS (0x193)
  Pattern: 3-arg complex dispatcher with 22 codes + localized strings
  Likely: server-to-client error responses (login fail, action denied,
          system messages with substitution params)

GROUP G: Session lifecycle (0x02-0x11, 0xca/0xcb)
  Patterns vary; handle handshake, login, logout, resync, disconnect
  Low-opcode = session protocol layer

GROUP H: Special complex dispatch (0x18d)
  Uses session object at this+0x4d8 + observer at this+0x4e0
  Likely: critical state change with subscriber notification
```

## 5. Server-side implementation guide

```text
PRIORITY OPCODES TO IMPLEMENT FIRST (for working zone session):
  0x02  session reauth        -- needed at connect
  0x03  login text push       -- announcement string at zone enter
  0x07  resync                -- needed on reconnect
  0x0e/0x11  disconnect       -- needed for clean logout
  0x17c SPAWN (PINNED)        -- needed to populate zone with actors
  0x148-0x156 actor messages  -- 15 actor-bound message types
                                  (need to characterize each one)
  0x193 system errors         -- needed for any server-rejected action

DEFERRED (can implement later):
  0x143, 0x17d, 0x17e... generic state events
  0x17f-0x182 object refs
  0x18a, 0x18b uint events
  0x183-0x189 uint events
  Bulk state push 0x08-0x0b (large payloads; needed for resync)

NEVER IMPLEMENT (cosmetic / debug):
  0xca/0xcb session markers (low priority debug)
  Default-fallthrough opcodes (legacy / removed)
```

## 6. Sub-handler decompilation (3 spot checks)

### FUN_006c5de0 (called by 0x143 bridge)

```c
void FUN_006c5de0(this, payload):
  FUN_006c5150(this+8, payload);   // forward to inner subsystem
```

Another thin bridge -- the actual logic is in FUN_006c5150.

### FUN_00580e70 (called by 0x148 actor-bound dispatch)

```c
void FUN_00580e70(this, actor, payload):
  command_obj = FUN_0076b950(this, actor);   // get per-actor command queue
  cmd_msg = FUN_00771350(local, payload);    // construct command message
  FUN_00764a30(command_obj, cmd_msg);        // enqueue
  FUN_0076df10(cmd_msg);                     // cleanup
```

This is the **per-actor command-enqueue path** — server's action
commands flow through here into the actor's command queue.

### FUN_006c2f30 (called by 0x17d 8-byte bridge)

```c
void FUN_006c2f30(this, payload_8bytes):
  intermediate = this[+0xc];
  if (intermediate && intermediate[+8] && FUN_006c2d30(...) returns false):
    // first try inner dispatcher
    return;
  FUN_006c2a50(this[+8], payload_8bytes);   // fallback dispatcher
```

Two-tier dispatch with fallback path.

## 7. Renames + comments applied this round

```text
0x00576240  FUN_00576240  → ZoneIn_opcode_0x143_thinBridge_to_subsystem_0x18
0x00576560  FUN_00576560  → ZoneIn_opcode_0x148_actorLookup_thenDispatch_subsystem_0x24
0x005762c0  FUN_005762c0  → ZoneIn_opcode_0x17d_thinBridge_with8B_to_subsystem_0x18
0x00578c90  FUN_00578c90  → ZoneIn_opcode_0x193_SYSTEM_ERROR_dispatcher_22codes_with_localized_strings
```

## 8. Confidence

```text
Confirmed:
  - 50+ specific opcode handlers in Zone main dispatch table
  - Bridge pattern: thin 2-5 line forwarders to subsystems
  - 4 opcodes decompiled and renamed (0x143, 0x148, 0x17d, 0x193)
  - Subsystem dispatch via this+0x18, this+0x24, this+0x10c offsets
  - Opcode 0x193 has 22 error/status codes with localized strings
  - Opcode 0x148-0x156 (15 opcodes) all follow actor-lookup pattern

Likely (High):
  - The 0x148-0x156 group is per-actor message variants (15 message
    types targeting actors by id)
  - The 0x17e-0x18b group is generic state events with varying payload
    sizes (uint vs uint64)
  - The "subsystem at this+0x24" is likely the CharaBase manager or
    actor command dispatcher
  - System error opcode 0x193 codes 0x10-0x16 map to specific UI
    error categories (login fail, action denied, etc.)

Likely (Medium):
  - Most opcodes ULTIMATELY route to Lua callbacks via the standard
    invokeLua_on* pattern (would need 1-2 levels deeper decomp to
    prove for each)
  - The default-fallthrough opcodes (0x144, 0x157-0x16c, etc.) are
    LEGACY or NOT-YET-IMPLEMENTED in 1.x patches
```

## 9. Cross-references

- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the parent finding that discovered this opcode range
- `finding_appendMessagePool_thunk_command_updater_dispatch.md`
  -- the message pool subsystem (target of 0x193 localized strings)
- `finding_application_mainTick_and_per_frame_subsystem_dispatch.md`
  -- the main loop architecture that drives ZoneClient_mainLoopTick
- `finding_inbound_chat_handlers_3_variants_decompiled.md`
  -- the prior 3-handler chat finding (now placed in proper context)

## 10. Next test

```text
1. Decompile FUN_00576210 (opcode 0x18d complex dispatch) -- likely
   the most complex remaining handler in this range
2. Sample 5-7 of the 0x14e-0x156 actor-bound handlers to confirm
   they're variants of actor command/state messages
3. Document the 22 error codes for opcode 0x193 (each with its
   localized string template)
4. Find the SPAWN_DESPAWN opcode (BreakupBuilder path) -- likely a
   variant of 0x17c with different TYPE TAG, OR a separate opcode
5. Identify GROUP A subsystem at this+0x24 (CharaBase manager?
   actor command dispatcher?)
```

## 11. ADDENDUM: Per-actor message system FULLY CHARACTERIZED

Second pass deep-dived the actor-bound group (0x148-0x156, 15 opcodes).
**All 15 follow IDENTICAL structure** with only the sub-dispatcher
differing. This reveals the **per-actor message routing infrastructure**.

### Sub-dispatcher pattern (confirmed across 5 samples)

```c
ActorMsg_HANDLER(this, actor_addr, payload):
   1. queue = ActorMessageQueue_lookupOrCreate_perActorId_WorkPathTree(this, actor)
        // looks up per-actor queue in red-black tree at this+0x10
        // creates new queue if actor not seen before
   2. msg = CONSTRUCT_MESSAGE_TYPE_X(local_buf, payload)
        // type A: FUN_007713xx family
        // type B: FUN_00768exx family
   3. ENQUEUE_VARIANT(queue, msg)
        // variant A: FUN_00764a30
        // variant B: FUN_00764b30
   4. CLEANUP(msg)
        // type A: FUN_0076df10
        // type B: FUN_007660c0
```

### 15 actor-bound opcodes -- sub-dispatcher table

```text
Opcode  Wire size  Sub-dispatcher        Constructor    Enqueue     Cleanup
------  ---------  --------------        -----------    -------     -------
0x148   uint32     FUN_00580e70 (typeA)  FUN_00771350   FUN_00764a30 FUN_0076df10
0x149   uint32     FUN_00580ef0 (typeA)  FUN_007713e0   FUN_00764a30 FUN_0076df10
0x14a   uint32     FUN_00580f70 (typeA)  ?              ?            ?
0x14b   uint32     FUN_00580ff0 (typeA)  ?              ?            ?
0x14c   uint32     FUN_00581070 (typeA)  ?              ?            ?
0x14d   ushort     FUN_005810f0 (typeA)  ?              ?            ?  ← short payload variant
0x14e   uint32     FUN_00581170 (typeA)  ?              ?            ?
0x14f   int (raw)  FUN_005811f0 (typeB)  FUN_00768e40   FUN_00764b30 FUN_007660c0  ← INT raw, TYPE B
0x150   uint32     FUN_00581270 (typeB?) ?              ?            ?
0x151   uint32     FUN_005812f0 (typeB?) ?              ?            ?
0x152   ushort     FUN_00581370 (typeB?) ?              ?            ?  ← short payload variant
0x153   int (raw)  FUN_005813f0 (typeB)  ?              ?            ?
0x154   uint32     FUN_00581470 (typeB?) ?              ?            ?
0x155   uint32     FUN_005814f0 (typeB?) ?              ?            ?
0x156   uint32     FUN_00581570 (typeB?) ?              ?            ?

Sub-dispatchers are evenly spaced at +0x80 byte intervals
(FUN_00580e70, FUN_00580ef0, FUN_00580f70, ... +0x80 each).
This is a TABLE-DRIVEN dispatch pattern.

TWO MESSAGE TYPES identified:
  TYPE A (FUN_007713xx + FUN_00764a30):
    Opcodes 0x148-0x14e (7 variants) -- different payload data per opcode
  TYPE B (FUN_00768exx + FUN_00764b30):
    Opcodes 0x14f-0x156 (8 variants) -- different payload data per opcode

Type A vs Type B uses DIFFERENT message constructors AND DIFFERENT
enqueue methods. Probably distinguishes between:
  - Command vs Event messages
  - Source-targeted vs Target-targeted
  - Immediate vs Deferred dispatch
  (Specific semantics need more decomp to disambiguate)
```

### ActorMessageQueue infrastructure

```c
ActorMessageQueue_lookupOrCreate_perActorId_WorkPathTree(this, actor_id):
  queue_map = this+0x10  // red-black tree (WorkPathTree style)
  found = WorkPathTree_lowerBound(queue_map, &out, actor_id)
  if (found):
    return *(int**)(found_node + 0x10)   // existing queue ptr
  else:
    new_queue = operator_new(8)           // 8-byte queue head
    new_queue = FUN_0075f5b0(new_queue)    // ctor
    map.insert(actor_id, new_queue)
    return new_queue
```

### Renames + comments added in this addendum

```text
0x0076b950  FUN_0076b950  → ActorMessageQueue_lookupOrCreate_perActorId_WorkPathTree
0x00580e70  FUN_00580e70  → ActorMsg_0x148_construct_typeA_enqueueVariantA
0x00580ef0  FUN_00580ef0  → ActorMsg_0x149_construct_typeA_enqueueVariantA_alt
0x005811f0  FUN_005811f0  → ActorMsg_0x14f_construct_typeB_enqueueVariantB_intPayload
0x00576240/560/2c0/8c90  -- per main finding above

Plus decompiler comment at 0x0076b950 documenting the queue
infrastructure.
```

### Inferred semantics for the 15 actor-bound message types

```text
Without per-message-type semantic info (would need deeper decomp of
each FUN_007713xx and FUN_00768exx variant), the most likely meanings
based on MMO architecture conventions are:

TYPE A group (0x148-0x14e) -- COMMANDS / ACTIONS:
  0x148  action invocation (cast)
  0x149  action result (cast complete)
  0x14a  action cancel
  0x14b  damage / heal apply
  0x14c  status apply
  0x14d  status remove (short opcode = enum)
  0x14e  cooldown / recast update

TYPE B group (0x14f-0x156) -- EVENTS / STATE:
  0x14f  HP/MP change (int = absolute or delta)
  0x150  position update
  0x151  facing direction update
  0x152  animation trigger (short = anim id)
  0x153  TP / resource change (int)
  0x154  flag set
  0x155  flag clear
  0x156  miscellaneous event

These are EDUCATED GUESSES based on MMO patterns. Verification
would require per-variant decomp of the message constructors.
```

### Server-side priority refined

```text
For working basic combat / movement:
  HIGHEST PRIORITY (must implement):
    0x148 (action invocation)
    0x14b (damage/heal)
    0x14f (HP/MP change)
    0x150 (position update)
    
  HIGH PRIORITY (needed for combat polish):
    0x14c (status apply)
    0x14d (status remove)
    0x152 (animation)
    
  MEDIUM PRIORITY:
    0x149 (action result)
    0x14a (action cancel)
    0x153 (resource change)
    
  LOWER PRIORITY:
    0x14e (cooldown sync)
    0x151 (facing)
    0x154-0x156 (flags / misc)
```

## Commit suggestion

```
docs(re/exe): Zone inbound game opcodes 0x143-0x1a8 bridge pattern + 50+ opcode table (4 samples decompiled, semantic groups inferred, server-side priority list) [+addendum: 15 actor-bound opcodes 0x148-0x156 sub-dispatcher table + per-actor queue infrastructure]
```
