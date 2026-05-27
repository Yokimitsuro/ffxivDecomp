# Finding: CommandUpdate Record Layout (0x118 = 280B) + BehaviorLogger Listener (0x48 = 72B)

Decodes the two records allocated by every `CommandUpdater_send_*`
helper. The previous finding
(`finding_system_invokeLua_and_userdatareceiver_dispatch.md`) referred
to "the 0x48-byte CommandUpdate record" -- that was wrong. The TRUE
CommandUpdate record is **0x118 bytes (280B)**; the 0x48-byte
record is a SEPARATE structure: the BehaviorLogger listener that
attaches to it.

## 1. The two-record architecture

Every `CommandUpdater_send_*` helper allocates BOTH records:

```c
void CommandUpdater_send_toCharaBase(receiver, target, channelByte, ...) {
    // RECORD A: CommandUpdate (0x118 bytes, allocated + enqueued in ring buffer)
    record = CommandUpdater_allocAndEnqueueRecord(
              receiver, opcode, channelByte, 0, NULL);
    record[0x42] = (target_id == -1) ? 0 : target_id;
    
    // RECORD B: BehaviorLogger listener (0x48 bytes, attaches to A)
    routingRecord = operator_new(0x48);
    BehaviorLogger_SourceDisplayNameResolverListener_ctor(
              routingRecord, receiver, record, target, opcode, payload);
    // ctor sets: record->+0xa8 = routingRecord (back-pointer)
    
    submit_to_router(receiver_context + 0xe0, target, routingRecord);
    cleanup_receiver(receiver);
}
```

So each `send_*` call produces:
- **Record A** : 280B CommandUpdate record, enqueued in CommandUpdater's
  ring buffer at +8
- **Record B** : 72B BehaviorLogger listener, registered with the
  global display-name resolver at +0xe0

## 2. Record A -- CommandUpdate (0x118 bytes / 280B)

Allocated + constructed by:
- `CommandUpdater_allocAndEnqueueRecord` (0x0076b3d0) -- allocates 0x118B,
  calls constructor, enqueues pointer into ring buffer
- `CommandUpdate_constructor_init` (0x00776690) -- initialises fields

### Field layout

```text
Offset  Size  Field                  Notes
------  ----  -----                  -----
+0x000  0x54  string buffer A         3-buffer pool; sender display name
+0x054  0x54  string buffer B         recipient display name
+0x0a8  4B    listener back-ptr       set by routing record ctor
                                      (NULL until BehaviorLogger
                                       listener is created)
+0x0ac  4B    reserved (= 0)
+0x0b0  0x54  string buffer C         log/format text (msg body)
+0x104  4B    command id / opcode     param_1 from caller
+0x108  4B    reserved (= 0)
+0x10c  2B    reserved short (= 0)
+0x10e  2B    event id / sub-opcode   param_2 from caller
                                      (e.g. 0xcf1c for achievements)
+0x110  1B    channel / sub-id byte   param_3 from caller (e.g. 0x20)
+0x111  1B    flag / mode byte        param_4 from caller
+0x112  1B    reserved (= 0)
+0x113  1B    reserved (= 0)
+0x114  1B    reserved (= 0)
+0x115..0x117  padding to 0x118 alignment
```

The 3 string buffers are pre-initialised empty (each is its own ~84-byte
string container -- the canonical `FUN_00445cf0` init pattern). They
get filled later by the BehaviorLogger listener as display names
resolve.

### Ring-buffer enqueue

`CommandUpdater_allocAndEnqueueRecord` calls
`ringBuffer_enqueue_4bytes(CommandUpdater + 8, &recordPtr)`. The ring
buffer layout (at CommandUpdater+8):

```text
+0x00  vtable / type byte
+0x04  bucket array (each bucket holds 4 entries, 16B each)
+0x08  capacity (uint, in entries / 4)
+0x0c  read head index
+0x10  write tail index
```

The enqueue function (FUN_007238b0) auto-allocates new buckets when
needed, wraps modulo capacity. So the CommandUpdater can buffer many
outgoing CommandUpdate records.

## 3. Record B -- BehaviorLogger Listener (0x48 bytes / 72B)

Allocated via `operator_new(0x48)`, constructed by
`BehaviorLogger_SourceDisplayNameResolverListener_ctor` (0x00789cd0).

### Class hierarchy (per RTTI evidence)

The ctor writes TWO vtable pointers; the SECOND overwrites the first:

```text
Slot 1 (overwritten):
  Application::Lua::Script::Client::DisplayNameResolver
    ::GetNameListenerInterface

Slot 2 (final):
  Application::Lua::Script::Client::BehaviorLogger
    ::SourceDisplayNameResolverListener
```

So the runtime type is **BehaviorLogger::SourceDisplayNameResolverListener**,
which implements the **GetNameListenerInterface** interface (it has
both vtables for multiple inheritance).

### Field layout

```text
Offset  Size  Field                            Notes
------  ----  -----                            -----
+0x00  4B    primary vtable                    BehaviorLogger::
                                               SourceDisplayNameResolverListener
                                               ::vftable
+0x04  4B    receiver context                  param_1 (the CommandUpdater
                                               instance that owns this)
+0x08  4B    CommandUpdate back-pointer        param_2 (points back to
                                               Record A); used to update
                                               Record A's string buffers
                                               when names resolve.
                                               Also: Record A.+0xa8 =
                                               this listener (set in this
                                               ctor's final line).
+0x0c  4B    target actor identifier          *param_3 (dereferenced)
                                               -- the actor whose display
                                               name needs resolving for
                                               the log output
+0x10  4B    routing context                   param_4 (opcode or flag)
+0x14  4B    reserved / padding
+0x18  varies payload copy                     FUN_007446e0 copies
                                               +0x14..+0x28 from param_5
                                               (an inbound payload record)
                                               into +0x18..+0x40 of this
+0x40  1B    flag (from payload+0x28)         copied from payload[0x28]
+0x41..0x47  padding to 0x48 alignment
```

The listener is the **back-reference channel** for asynchronous name
resolution: when the CommandUpdate's target actor finally has its
display name available, the BehaviorLogger listener's vtable methods
fire to populate the string buffers in Record A.

## 4. Full data flow (server -> client outbound)

```text
1. Player command triggers a CommandUpdater_send_* call.

2. CommandUpdater_allocAndEnqueueRecord:
   - operator_new(0x118)              -- allocate Record A
   - CommandUpdate_constructor_init   -- init fields with command id +
                                         event id + channel byte +
                                         flag byte
   - ringBuffer_enqueue                -- queue Record A in
                                         CommandUpdater's ring buffer
                                         at +8

3. Caller writes target id to Record A.+0x42 (the "caster actor wire id").

4. operator_new(0x48) + BehaviorLogger_SourceDisplayNameResolverListener_ctor:
   - allocate Record B
   - construct with refs to receiver + Record A + target id + opcode +
     copied payload
   - SET Record A.+0xa8 = Record B  (back-link)

5. submit_to_router(receiver_context + 0xe0, target, Record B):
   - registers Record B as a display-name listener for the target
   - the global router fires Record B's vtable methods when the
     target's display name is resolved (server-pushed actor data
     arrives)

6. Record A is THEN serialised + sent to the server via the
   CommandUpdater's outbound channel (the ring buffer is drained on
   the next outbound tick).

7. Server processes the command, sends responses back. The
   UserDataReceiver chain (per
   finding_polymorphic_block_userdataReceiver / finding_system_invokeLua)
   collects responses keyed back to Record A via opcode 0xcf1c etc.

8. When the response arrives, the BehaviorLogger listener (Record B)
   fires to update Record A's string buffers with the resolved
   display names.

9. The completed Record A is then rendered to the chat/log UI.
```

## 5. Server design implications

```text
For a server emitting CommandUpdater notifications, the CRITICAL
fields the server must populate (after the client side allocates):

  Wire-relevant fields in Record A:
    +0x104  command id (4B)        determined by the calling helper
    +0x10e  event id / sub-opcode  (commonly 0xcf1c for achievements)
    +0x110  channel byte           (commonly 0x20)
    +0x111  flag/mode byte         determined by caller
    +0x42*4 = +0x108 caster wire id  (-1 sentinel -> 0)

  Note: +0x108 is overwritten by the line:
      record[0x42] = caster_id
  (record[0x42] in 32-bit indexing == record + 0x108)

So the server's CommandUpdate response must include:
  - The 4-byte command id (matches a request id)
  - 2-byte event id (e.g. 0xcf1c)
  - 1-byte channel
  - 1-byte mode flag
  - 4-byte caster id (or sentinel)
  - Payload (separately sent via opcode 23 in the polymorphic block,
    then assembled by UserDataReceiver dispatch)

The 3 string buffers (+0x000, +0x054, +0x0b0) are CLIENT-FILLED from
the resolved display names; the server never sends string data
directly into these buffers -- it provides actor IDs, and the client
resolves the names via BehaviorLogger Listener (Record B).
```

## 6. Server behavior verification

Testable claims (high confidence):
1. The CommandUpdate record is exactly 0x118 bytes
   (verified: `operator_new(0x118)` in `CommandUpdater_allocAndEnqueueRecord`)
2. The BehaviorLogger listener is exactly 0x48 bytes
   (verified: `operator_new(0x48)` in `CommandUpdater_send_toCharaBase`
    and siblings)
3. The listener back-pointer is at Record A.+0xa8
   (verified: ctor line `*(this+8)+0xa8 = this`)
4. The 3 string buffers are at +0x000, +0x054, +0x0b0
   (verified: 3 calls to `FUN_00445cf0` in `CommandUpdate_constructor_init`)

## 7. Annotations made in Ghidra

```text
RENAMES:
  - 0x0076b3d0 -> CommandUpdater_allocAndEnqueueRecord
  - 0x00776690 -> CommandUpdate_constructor_init
  - 0x00789cd0 -> BehaviorLogger_SourceDisplayNameResolverListener_ctor
  - 0x007238b0 -> ringBuffer_enqueue_4bytes

COMMENTS:
  - 0x00776690 (full Record A layout, all 9 fields)
  - 0x00789cd0 (full Record B layout, class hierarchy, all 7 fields)
```

## 8. Confidence

```text
Confirmed:
  - Record A (CommandUpdate) is 0x118 bytes
  - Record B (BehaviorLogger listener) is 0x48 bytes
  - Class is BehaviorLogger::SourceDisplayNameResolverListener
    (RTTI evidence in vftable writes)
  - The 2-record architecture: A holds the data, B routes name
    resolution back to A
  - Listener back-pointer at A.+0xa8 (verified in B's ctor)
  - 3 string buffers in A at +0x000, +0x054, +0x0b0
  - Ring buffer at CommandUpdater+8 holds enqueued A records

Likely (High):
  - The 3 string buffers are for sender / recipient / log-format text
    based on the typical chat/log pattern (also matches
    finding_chat_block_command_notifications)
  - Record A.+0x42 (uint, == +0x108 byte offset) is the casting
    actor's wire id, with -1 sentinel becoming 0

Likely (Medium):
  - The payload-copy in B (+0x18..+0x40) is the 0x14-byte "actor
    identifier" record (the unit moved through opcode 23 = append
    payload entry)
  - The ring buffer at CommandUpdater+8 is drained on each network
    tick to serialize Record A onto the wire

Speculative:
  - The reserved byte at A.+0x114 may be a "completed" flag that
    flips once name resolution finishes
  - Record A is what gets rendered into the chat/log UI ring buffer
    after the resolver listener fills it
```

## 9. Cross-references

- `finding_system_invokeLua_and_userdatareceiver_dispatch.md` -- the
  prior finding that named the 5 send-helpers; this finding corrects
  the "0x48 byte CommandUpdate record" claim (true CommandUpdate is
  0x118; the 0x48 is the separate BehaviorLogger listener)
- `finding_chat_block_command_notifications.md` -- established that
  "chat" opcodes are CommandUpdater notifications; this finding
  reveals the on-wire data shape
- `finding_polymorphic_block_userdataReceiver.md` -- explains how
  inbound opcodes 22-26 build the responses that fire the
  BehaviorLogger listener

## 10. Next test

```text
With CommandUpdate record fully laid out:

  1. Walk the BehaviorLogger SourceDisplayNameResolverListener vtable
     to find the methods that get called when names resolve:
     - GetName / OnGetName methods (interface)
     - SourceDisplayName-specific methods (concrete)
  2. Verify that opcode 0xcf1c is the per-command-result trigger by
     reading the dispatch table at receiver_context+0xe0
  3. Move on to Lua corpus (Quest/Linkshell/etc subsystems per the
     user's plan)
```

## Commit suggestion

```
docs(re/exe): CommandUpdate record 0x118B + BehaviorLogger listener 0x48B (FUN_0076b3d0 + FUN_00789cd0 decoded)
```
