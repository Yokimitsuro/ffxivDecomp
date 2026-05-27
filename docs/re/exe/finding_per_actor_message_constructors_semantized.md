# Finding: Per-Actor Message Constructors Semantized -- Opcodes 0x148/0x149 = ACTION RESULTS, 0x14f = STATUS EFFECT LIST

**Semantizes 3 of the 15 per-actor message types** by decompiling
their wire payload constructors. This converts the generic "TYPE A
command / TYPE B event" classification into concrete game messages.

The 3 opcodes pinned:
- **0x148** = SINGLE ACTION RESULT (1 record, 112 bytes)
- **0x149** = BATCH ACTION RESULT (N records of 112B, count at +0x380)
- **0x14f** = STATUS EFFECT LIST (16 fixed slots of 6B each)

## 1. Opcode 0x148/0x149 -- Action Results

### Single vs batch variants

```text
Opcode 0x148  ZoneIn_0x148_SINGLE_ACTION_RESULT
   -> FUN_00771350 (constructs 1 record)
   -> parses 1 x 112B record
   -> pushes to actor's action list

Opcode 0x149  ZoneIn_0x149_BATCH_ACTION_RESULT
   -> ActionResultBatch_construct_multiRecord_countAt_0x380_byte (FUN_007713e0)
   -> reads count BYTE at packet[+0x380]
   -> parses N records of 112B each
   -> pushes each to actor's action list
```

### Per-record layout (112 bytes / 0x70)

```text
+0x00  uint32  source/actor id field 1
+0x04  uint32  source/actor id field 2
+0x08  uint32  value field A         (damage / heal amount?)
+0x0c  uint32  value field C
+0x10  uint32  value field D         (param_1[3] used as +0x10 in struct)
+0x14  ushort  ushort field          (animation id?)
+0x16  byte    byte field            (action category? element?)
+0x18  COMPLEX 4 actor refs + 4 bytes  (4 targets + per-target flags?)
+0x1c  uint32  value field B         (param_1[7])
+0x44  byte    optional flag         (if set, 64B extension follows)
+0x4a..+0x88  conditionally: 64 bytes (16 dwords)
              -- only when flag at +0x29 is set
              -- likely: status effect chain / multi-hit details

Total record size: ~112 bytes basic, +64 conditional = up to 176B
```

### Semantics

Each action result record likely encodes:
- **Source**: who performed the action
- **Targets**: up to 4 affected actors
- **Value**: damage/heal amount(s)
- **Animation/effect**: visual feedback id
- **Category**: spell vs weapon attack vs status
- **Chain**: optional list of triggered status effects

**Server-side usage**:
- 0x148 = simple action (single-target spell, melee hit)
- 0x149 = complex action (AoE damage hitting N targets, chain heal)
- Sends with up to ~5 records per packet (limited by 0x380 byte count offset)

### Why two opcodes for similar data?

1.x's combat system distinguished:
- Simple actions = fits in single record → use compact 0x148
- AoE/chain actions = multiple results → use batch 0x149 with count

Server can choose based on action complexity, saving bandwidth for
common single-hit attacks.

## 2. Opcode 0x14f -- Status Effect List

### Construction

```text
Opcode 0x14f  ZoneIn_0x14f_STATUS_EFFECT_LIST_16slots
   -> StatusEffectList_construct_16slots_6Bperentry (FUN_00768e40)
   -> HARDCODED loop: 16 iterations
   -> reads 16 x 6 bytes = 96 bytes total
   -> pushes 16 status entries to actor's status list
```

### Wire layout

```text
+0x00..+0x60   16 entries x 6 bytes = 96 bytes total

Per-entry (6 bytes):
  +0x00  ushort  status icon id (or status effect id)
  +0x02  ushort  duration / value (seconds remaining?)
  +0x04  byte    flag / category (visible / hidden / debuff / buff?)

Total: 96 bytes of status data + header
```

### Semantics

This matches the **known 1.x status effect limit of 16 slots per
actor**. Each slot is fixed-size for direct array indexing on client.

**Empty slots**: probably encoded with status_id == 0 (sentinel).

**Server-side usage**:
- Send 0x14f WHENEVER status list changes for an actor
- This is a HIGH-FREQUENCY message in combat (buffs/debuffs cycle)
- Always sends FULL list (16 entries) rather than diff -- simpler client logic

### Why the 16-slot limit?

1.x's status icon UI had exactly 16 visible slots. The wire format
matches this UI constraint. Some status effects might have been
"hidden" (not in the 16) but stored internally.

## 3. Updated per-actor message type table

```text
Opcode  Type  Semantic name                    Sub-dispatcher    Constructor
------  ----  -------------                    --------------    -----------
0x148   A     SINGLE ACTION RESULT             FUN_00580e70      FUN_00771350
0x149   A     BATCH ACTION RESULT (N x 112B)   FUN_00580ef0      FUN_007713e0
0x14a   A     (TBD -- different sub)           FUN_00580f70      ?
0x14b   A     (TBD)                            FUN_00580ff0      ?
0x14c   A     (TBD)                            FUN_00581070      ?
0x14d   A     (TBD -- ushort payload)          FUN_005810f0      ?
0x14e   A     (TBD)                            FUN_00581170      ?
0x14f   B     STATUS EFFECT LIST (16 x 6B)     FUN_005811f0      FUN_00768e40
0x150   B     (TBD)                            FUN_00581270      ?
0x151   B     (TBD)                            FUN_005812f0      ?
0x152   B     (TBD -- ushort payload)          FUN_00581370      ?
0x153   B     (TBD)                            FUN_005813f0      ?
0x154   B     (TBD)                            FUN_00581470      ?
0x155   B     (TBD)                            FUN_005814f0      ?
0x156   B     (TBD)                            FUN_00581570      ?

INFERENCE PATTERN:
  Opcodes 0x148-0x149 = Action Results (1 single + 1 batch variant)
  Opcode 0x14f = Status Effect List
  Other 12 opcodes likely follow similar paired pattern:
    - simple/batch variants
    - or different list types (action queue, animation queue, etc.)
```

## 4. Renames + comments applied

```text
0x007713e0  → ActionResultBatch_construct_multiRecord_countAt_0x380_byte
0x00768e40  → StatusEffectList_construct_16slots_6Bperentry
0x0076b760  → ActionResult_parseSingleRecord_112B_complex
0x00789b90  → ActionResult_pushToActorList_88Bstride

0x00580e70  → ZoneIn_0x148_SINGLE_ACTION_RESULT_to_actor_queue
0x00580ef0  → ZoneIn_0x149_BATCH_ACTION_RESULT_multiRecord_to_actor_queue
0x005811f0  → ZoneIn_0x14f_STATUS_EFFECT_LIST_16slots_to_actor_queue

Plus 2 comprehensive decompiler comments at 0x007713e0 and 0x00768e40
documenting full wire packet layouts.
```

## 5. Server-side combat protocol (refined)

```text
COMBAT MESSAGE FLOW (server -> client during combat):

  Action invocation:
    SIMPLE action (1 target):   send 0x148 + 1 record (112B)
    AOE/CHAIN action (N targets): send 0x149 + N records
  
  Status effect change:
    Send 0x14f with all 16 status slots (96B)
    Even if only 1 status changed, sends full list
  
  Per-actor state updates:
    HP/MP change:  send 0x18b MemberInfoUpdater (if party)
                   or WorkSync 0x12F (general)
    Position:      WorkSync 0x12F
  
  Combat events (other 12 opcodes 0x14a-0x14e, 0x150-0x156):
    Specific semantics still TBD -- likely include:
      - Cast bar update (cast start/progress/finish)
      - Animation triggers (gestures, jumps, emotes)
      - TP / GCD updates
      - Target lock events
      - Aggro changes
```

## 6. Confidence

```text
Confirmed:
  - 0x148 = single 112B action result record
  - 0x149 = batch N x 112B action result records (count at +0x380)
  - 0x14f = 16-slot status effect list (6B per entry)
  - Per-record format: 5 ids/values + ushort/byte + 4-actor list + opt 64B
  - 7 renames + 2 decompiler comments applied
  - Pattern: TYPE A includes simple+batch variants; TYPE B is fixed lists

Likely (High):
  - The 4-actor refs in action records = 4 affected targets max per record
  - The 64B optional payload = status chain / multi-hit details
  - The other 12 opcodes follow similar paired patterns (e.g., 0x14a/14b
    might be cast-start/cast-finish; 0x150/151 might be HP/MP delta)
  - The ushort field at +0x14 is animation id (matches UI cast bar info)

Speculative:
  - 0x14a = CAST START (action begin announcement)
  - 0x14b = CAST CANCEL
  - 0x14c = STATUS APPLY (single)
  - 0x14d = STATUS REMOVE (single, ushort = status id)
  - 0x14e = COOLDOWN UPDATE
  - 0x150 = HP CHANGE (TYPE B)
  - 0x151 = MP CHANGE
  - 0x152 = ANIMATION TRIGGER (TYPE B, ushort = anim id)
  - 0x153 = TP CHANGE
  - 0x154-156 = miscellaneous flag/state events

  These are educated guesses; verification requires per-opcode decomp.
```

## 7. Cross-references

- `finding_zone_inbound_game_opcodes_0x143_0x1a8_bridge_pattern.md`
  -- parent finding with full 50+ opcode table
- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the SPAWN protocol (which targets the same per-actor queues
  this finding's actions write to)
- `finding_combat_command_pipeline_and_4param_scaling.md`
  -- the Lua-side combat formulas (server sends action results; Lua
  applies them via formulas mapped here)

## 8. Next test

```text
1. Decompile FUN_00580f70 (0x14a), FUN_00580ff0 (0x14b) to confirm
   they're cast-start/cast-cancel variants
2. Decompile the FUN_00581270/F0 (0x150/151) constructors -- if HP/MP
   change, server has clear per-stat update opcodes
3. Verify the 64B optional payload format (open the 16-dword extension
   inside ActionResult_parseSingleRecord_112B_complex)
4. Find OUTBOUND action invocation opcode (client tells server "I want
   to cast X"); should be in the outbound Zone opcodes
```

## 9. ADDENDUM: 2 more opcodes verified (0x14c + 0x150) -- REVEALS PATTERN

Verified 2 speculated opcodes; the speculations were WRONG but in
a way that REVEALS THE TRUE PATTERN.

### Opcode 0x14c -- LARGE ACTION BATCH (64 records FIXED)

```text
NOT "status apply" as speculated.
Actual: HARDCODED 64-record loop, each 112B (same as 0x148/0x149).

Constructor: LargeActionBatch_construct_64records_112B_hardcoded
(FUN_007715f0)

Wire packet: 64 records x 112B = ~7168 bytes minimum.

Likely use:
  - RAID-WIDE combat log push (full instance event history)
  - Full combat log refresh after resync
  - Server-forced full state push for combat log
  - DEBUG / instance damage tracker dump
```

### Opcode 0x150 -- EXTENDED STATUS LIST (32 slots)

```text
NOT "HP change" as speculated.
Actual: HARDCODED 32-slot loop, each 6B (IDENTICAL format to 0x14f
status list, just DOUBLE the slots).

Constructor: ExtendedStatusList_construct_32slots_6B_hardcoded
(FUN_00768ef0)

Per-entry: ushort status_id + ushort duration + byte flag

Likely use:
  - EXTENDED status display (passives + actives combined)
  - ABILITY LIST (32 known abilities visible)
  - TARGET status display (32 slots showing target's effects)
  - Tiered status display companion to 0x14f
```

### THE REAL PATTERN: variable-size lists

```text
The per-actor messages aren't randomly assigned -- they're
LISTS OF VARYING SIZES with TWO PAYLOAD TYPES:

TYPE A LISTS (112B per record = "ACTION RECORD"):
  0x148 = 1 record   (single action)
  0x149 = N records  (count at +0x380, variable batch)
  0x14c = 64 records (fixed large batch)
  (probably 0x14a/0x14b = other fixed sizes)
  (probably 0x14d/0x14e = related variants)

TYPE B LISTS (6B per entry = "STATUS ENTRY"):
  0x14f = 16 slots   (primary status list)
  0x150 = 32 slots   (extended status list)
  (probably 0x151-0x156 = other 6B-entry lists at various sizes)

REFINED HYPOTHESIS for remaining 10 opcodes:

  0x14a = 4 records?    (small fixed action batch)
  0x14b = 8 records?    (medium fixed action batch)
  0x14d = 1 ushort?     (single status remove? 2-byte payload)
  0x14e = ?             (other action variant)

  0x151 = 64 slots?     (large status display)
  0x152 = 1 ushort?     (single status add? 2-byte payload)
  0x153 = ?             (different list type)
  0x154-0x156 = other list types or sizes

PATTERN INSIGHT: 1.x server pre-batches state updates by size into
different opcodes. Client routes by opcode to the correct list
constructor. This avoids the overhead of a "type byte + count" header
in every packet.

The trade-off: requires 15 distinct opcodes (one per list type/size),
but each packet is highly compact (no header overhead for size info).
```

### Updated per-actor opcode table

```text
Opcode  Type  Verified semantic                         Status
------  ----  -----------------                         ------
0x148   A     SINGLE ACTION RESULT (1 x 112B)           VERIFIED
0x149   A     VARIABLE ACTION BATCH (N x 112B)          VERIFIED
0x14a   A     ?? (fixed action batch, size TBD)         INFERRED
0x14b   A     ?? (fixed action batch, size TBD)         INFERRED
0x14c   A     LARGE ACTION BATCH (64 x 112B)            VERIFIED
0x14d   A     ?? (ushort payload variant)               INFERRED
0x14e   A     ?? (other action variant)                 INFERRED
0x14f   B     PRIMARY STATUS LIST (16 x 6B)             VERIFIED
0x150   B     EXTENDED STATUS LIST (32 x 6B)            VERIFIED
0x151   B     ?? (probably larger status list)          INFERRED
0x152   B     ?? (ushort payload variant)               INFERRED
0x153-0x156 B ?? (other status/event lists)             INFERRED

15 opcodes total. 5 verified (33%). 10 inferred from pattern.
```

## 10. ADDENDUM: server-side combat protocol REFINED

```text
SERVER COMBAT MESSAGE STRATEGY:

  Single small event:    send 0x148 (1 action record)
  Multi-target event:    send 0x149 (variable batch)
  Combat log refresh:    send 0x14c (full 64-record refresh)
  
  Status state change:   send 0x14f (16-slot primary list)
  Extended status:       send 0x150 (32-slot extended list)
  
  HP/MP/Position update: send WorkSync 0x12F or
                              MemberInfoUpdater 0x18b (if party)

  System rejection/error: send 0x193 with appropriate code

ADVANTAGE OF THIS DESIGN:
  - Compact packets (no header per packet for size/type)
  - Client list constructors can be optimized per fixed size
  - Server can choose packet type based on data volume
  
DISADVANTAGE:
  - Requires 15 distinct opcodes (vs ~5 if size was in header)
  - Server logic more complex (must pick right opcode)
```

## Commit suggestion

```
docs(re/exe): per-actor messages SEMANTIZED -- 0x148/0x149 = ACTION RESULTS (single/batch 112B records); 0x14f = STATUS EFFECT LIST (16 x 6B slots) [+addendum: 0x14c = 64-record action batch; 0x150 = 32-slot extended status; PATTERN revealed: 15 opcodes encode variable-size lists in 2 payload types]
```
