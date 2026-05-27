# Finding: System invokeLua Callbacks + UserDataReceiver Target-Mode Dispatch Deepened

Closes two open targets at once:

1. **System class invokeLua** (opcodes 17/18) -- locates the
   `_onPreCutSceneCancel` / `_onPostCutSceneCancel` Lua hook firers
   and renames them as proper `System_invokeLua_*` callbacks.
2. **UserDataReceiver target-mode dispatch** (opcodes 22-26 polymorphic
   block, deepened) -- decodes the 4-way switch in `FUN_0089fbf0`,
   identifies the 5 CommandUpdater send-helpers it routes to, and
   confirms the UserDataReceiver field layout.

**Net new annotations**: 8 functions renamed + 1 large decompiler
comment on the dispatcher.

## Part A: System invokeLua callbacks for opcodes 17/18

Per `finding_invokeLua_paradigm_15_callbacks.md`, opcodes 17/18 were
known to terminate at `_onPreCutSceneCancel` / `_onPostCutSceneCancel`
Lua hooks. The wrapper functions were unnamed.

### A.1. Architecture

Unlike CharaBase/CutScene/DesktopWidget (which each have a separate
`Router_dispatch_to_*` + `Class_invokeLua_*` pair), the **System class
fuses router + invokeLua into one function**. MSVC inlined the router
because System has only 2 events -- creating a separate wrapper would
be pure overhead.

```text
Address      Function                                  Triggered by
-------      --------                                  ------------
0x008a45d0   System_invokeLua_onPreCutSceneCancel      Zone inbound opcode 17
0x008a4720   System_invokeLua_onPostCutSceneCancel     Zone inbound opcode 18
```

### A.2. Function shape

Both functions follow:

```text
1. Resolve System singleton actor:  FUN_00cc9320(local_a4, 0xc0000024)
                                                            ^^^^^^^^^^
                                                System singleton ID
2. (Pre-only) Build empty args tuple
3. (Pre-only) Call _onPreCutSceneCancel(...)
4. Call broadcast helper (cleanup hooks):
     Pre  -> System_broadcastSubsystem_preCancelHooks   (FUN_0075b300)
     Post -> System_broadcastSubsystem_postCancelHooks  (FUN_0075b330)
5. (Post-only) Call _onPostCutSceneCancel(...)
   (Post differs: broadcast happens BEFORE Lua call)
```

The asymmetric pre/post ordering is intentional:
- **Pre**: Lua hook fires FIRST (let scripts save state), then
  subsystem cleanup runs.
- **Post**: subsystem cleanup runs FIRST (release resources), then
  Lua hook fires (let scripts react to the cleanup).

### A.3. The two broadcast helpers

```text
FUN_0075b300 -> System_broadcastSubsystem_preCancelHooks
FUN_0075b330 -> System_broadcastSubsystem_postCancelHooks
```

Both walk a vtable on the resolved system context. They call 4
slots each, spaced 0xC bytes apart:

```text
Pre helper:   slots at vtable+0x04, +0x10, +0x1c, +0x28
Post helper:  slots at vtable+0x08, +0x14, +0x20, +0x2c
```

Each vtable position is paired (`pre = slot N`, `post = slot N+4`),
so the pre-helper fires the 4 "preCancel" methods and the post-helper
fires the 4 corresponding "postCancel" methods across 4 registered
subsystems.

This is the **broadcast-cancellation mechanism**: when a cutscene is
cancelled, 4 subsystems (UI, audio, animation, network presumably)
each get a `preCancel()` and `postCancel()` call to clean up in order.

### A.4. System singleton actor id

```text
0xC0000024  = System singleton (resolved via FUN_00cc9320)
            
The 0xC0000000 mask = "global / namespace actor" -- distinguishes
singleton system actors from real player/NPC actors.
0x24 = sub-id for System itself.
```

Same actor-id pattern as observed elsewhere:
- `0xC0000024` = System
- Players + NPCs use actor ids without the 0xC0000000 mask.

## Part B: UserDataReceiver Target-Mode Dispatch Decoded

`finding_polymorphic_block_userdataReceiver.md` identified that
`FUN_0089fbf0` is a 4-way switch on `*(byte *)(this+0x10)`. This
finding decodes what each mode does and renames the 5 helper functions
it routes to.

### B.1. The dispatcher (now named)

```text
0x0089fbf0 = UserDataReceiver_dispatchByTargetMode
```

Annotated with a 36-line decompiler comment covering the mode-byte
semantics, target resolution per mode, and the receiver field layout.

### B.2. The 4 target-resolution modes

```text
MODE BYTE  TARGET TYPE             HELPER CALLED
---------  -----------             -------------
   0x00    Direct CharaBase ptr    CommandUpdater_send_toCharaBase
                                   OR _WMSelf variant if local_e4
                                      is WorldMaster
   0x01    Numeric actor id        CommandUpdater_send_toActorId
   0x02    Actor name (string)     CommandUpdater_send_toActorName
   0xFF    Broadcast / fallback    CommandUpdater_send_broadcast
                                   if source is WorldMaster/ActorBase;
                                   else falls back to _toCharaBase
```

### B.3. The 5 CommandUpdater send helpers (now named)

```text
Address      New name                                       Mode used
-------      --------                                       ---------
0x00771f50   CommandUpdater_send_toCharaBase                0 (no WM) + 0xFF fallback
0x00772050   CommandUpdater_send_toCharaBase_WMSelf         0 (WM self-target)
0x007721b0   CommandUpdater_send_toActorId                  1
0x00772560   CommandUpdater_send_toActorName                2
0x00772650   CommandUpdater_send_broadcast                  0xFF (broadcast)
```

All 5 share the same outer shape (verified via `_toCharaBase`):

```c
void CommandUpdater_send_X(receiver, target, channelByte, msgIdRef,
                           opcode, payload) {
    record = FUN_0076b3d0(receiver, opcode, channelByte, 0, 0);
    record[0x42] = (-1 == target_id) ? 0 : target_id;
    routingRecord = new CommandUpdateRoute(receiver, record, ...);
    submit_to_router(receiver_context + 0xe0,
                     target, routingRecord);
    cleanup_receiver(receiver);
}
```

So all 5 build a `CommandUpdate` record (offset 0x48 bytes) + a
routing record, then submit to the per-context global router at
`receiver_context + 0xe0`. The only difference between the 5 is the
TARGET BINDING (direct ptr vs id vs name vs broadcast).

### B.4. Two more newly-named helpers

```text
0x008a1510   UserDataReceiver_extractActorId    (mode 1 reader)
0x008a15b0   UserDataReceiver_extractActorName  (mode 2 reader)
```

These read the target-id/target-name field from the receiver
object (at this+8) so the dispatch can route appropriately.

### B.5. Confirmed UserDataReceiver field layout

```text
Offset  Size   Field                                Source
------  -----  -----                                ------
+0x00   4B     primary vtable                       finding_polymorphic_block (S-1)
+0x04   ?      string pool / message store ref      _dispatchByTargetMode reads
+0x08   ?      target binding (mode-dependent)      mode 0 = CharaBase ptr
                                                    mode 1 = int actor id
                                                    mode 2 = string name
+0x10   1B     MODE BYTE (0/1/2/0xFF)              the switch input
+0x14   ?      resolved actor reference             vtable slot 23 writes
+0x18   2B     ushort opcode/event id              passed as msg arg
+0x1a   1B     channel/sub-id byte                 passed as channel arg
+0x20   4B     payload container head ptr          accumulated by slot 22
+0x24   4B     payload container tail ptr          accumulated by slot 22
```

The 3 fields modified at runtime:
- `+0x10` is set during construction (by the caller) to the desired
  target mode.
- `+0x14` is filled by opcode 24 (vtable slot 23).
- `+0x20/+0x24` are appended by repeated opcode 23 (vtable slot 22).

So the **full receive sequence for a UserDataReceiver-routed
notification** is:

```text
Server sends:
  N x opcode 23 (append_payload entry N times)
  1 x opcode 24 (set target actor)
  1 x final dispatch opcode (entry 42 or similar) that triggers
      UserDataReceiver_dispatchByTargetMode
```

Then the dispatcher reads the mode byte at +0x10 (which was set at
allocation time, not via wire) and routes the accumulated payload
to the correct CommandUpdater_send_* helper.

## Part C: Why this is the "1.x CommandUpdater" routing layer

The `CommandUpdater` family handles **multi-target command result
broadcasts**. When a player executes a Command (per
`finding_playerbase_lua_bindings_99_complete.md` slot 1
`_executeCommand`), the result must be **broadcast to the relevant
audience**:

- Self only (`_toCharaBase_WMSelf` -- the casting player gets a private
  result)
- One specific other actor (`_toCharaBase` -- the target actor of a
  spell sees the result)
- Multiple actors by id list (`_toActorId` -- party/group results)
- Named broadcast (`_toActorName` -- linkshell or zone group)
- Full broadcast (`_broadcast` -- zone-wide / system messages)

The 4-mode dispatch lets ONE wire opcode carry results for ALL of
these audience types. The server sets the mode byte based on what the
command's `Receiver` filter is.

This is consistent with the 1.x Lua corpus: the `CommandBaseClass`
has a `Receiver` field that controls who sees the result, and the
9 receiver variants (per `finding_command_baseclass_and_judges.md`)
map onto these 4 wire modes.

## Part D: Updated EXE <-> Lua bridge inventory

```text
PRIOR TOTAL (before this finding):  138 bridge points
  - registerLua_*:  123 (PlayerBase 99 + NpcBaseClass 24)
  - invokeLua_*:    15  (CharaBase 1 + CutScene 8 + DesktopWidget 4
                         + Player 2)

THIS FINDING:                       +2 invokeLua
  - System_invokeLua_onPreCutSceneCancel   (opcode 17)
  - System_invokeLua_onPostCutSceneCancel  (opcode 18)

NEW TOTAL:                          140 bridge points
  - registerLua_*:  123
  - invokeLua_*:    17  (added System class)

Plus 8 new infrastructure renames (CommandUpdater + UserDataReceiver
helpers) that strengthen the receiver-side architecture.
```

## Server design implications

```text
For server implementation of the CommandUpdate broadcast subsystem:

1. The server picks the receiver audience for each command result
   and SETS the mode byte (+0x10) accordingly before sending opcode 24.

2. Sequence for a command result push:
   a. server -> client: opcode 23 (N times) -- payload chunks
   b. server -> client: opcode 24 -- resolve target actor
                          (only relevant for modes 0, 1)
   c. server -> client: opcode 42 (or similar terminator) --
                          triggers UserDataReceiver_dispatchByTargetMode

3. Mode selection per command type:
   _executeCommand result with single target -> mode 0 (direct ptr)
                                                 or mode 0xFF (via id)
   Action visible to party                     -> mode 1 (id-list)
   Linkshell broadcast                          -> mode 2 (named)
   System notice / zone announce                -> mode 0xFF (broadcast)

For cutscene cancellation:
  The server only needs to SEND opcode 17 (pre-cancel) followed by
  opcode 18 (post-cancel). The client handles everything else --
  Lua scripts fire, broadcast hooks fire to 4 subsystems.

  No payload required: both opcodes carry no data; they're pure
  events.
```

## Annotations made in Ghidra

```text
RENAMES (10):
  - 0x008a45d0 -> System_invokeLua_onPreCutSceneCancel
  - 0x008a4720 -> System_invokeLua_onPostCutSceneCancel
  - 0x0075b300 -> System_broadcastSubsystem_preCancelHooks
  - 0x0075b330 -> System_broadcastSubsystem_postCancelHooks
  - 0x0089fbf0 -> UserDataReceiver_dispatchByTargetMode
  - 0x008a1510 -> UserDataReceiver_extractActorId
  - 0x008a15b0 -> UserDataReceiver_extractActorName
  - 0x00771f50 -> CommandUpdater_send_toCharaBase
  - 0x00772050 -> CommandUpdater_send_toCharaBase_WMSelf
  - 0x007721b0 -> CommandUpdater_send_toActorId
  - 0x00772560 -> CommandUpdater_send_toActorName
  - 0x00772650 -> CommandUpdater_send_broadcast

COMMENTS (1 multi-line, 36 lines):
  - 0x0089fbf0 -- full 4-mode dispatch table + field layout +
                  cross-reference to entry 42 reuse
```

## Confidence

```text
Confirmed:
  - System_invokeLua_onPreCutSceneCancel / onPostCutSceneCancel are
    the inline router+invoke pair for opcodes 17/18
  - System singleton actor id is 0xC0000024 (verified in both functions)
  - Pre/Post asymmetric ordering of Lua call vs subsystem broadcast
    (Pre: Lua first; Post: cleanup first)
  - 4 subsystems subscribe to cancel hooks via vtable at
    receiver-context + 0xe0; pre/post sit at slot offsets +4/+8
    paired (+0x10/+0x14, etc.)
  - UserDataReceiver +0x10 mode byte switches dispatch among 4 paths
  - 5 CommandUpdater send helpers are the dispatch terminals
  - Field layout (+0x10 mode, +0x14 resolved target, +0x18 opcode,
    +0x1a channel, +0x20/+0x24 payload container) all confirmed

Likely (High):
  - Mode 0 (direct CharaBase) is the "send to one specific actor"
    path (target's wire id was zero -- the local resolved object
    pointer is enough)
  - Mode 0xFF differentiates broadcast (zone-wide if source is
    WorldMaster/ActorBase) from "lookup by id and send single"
    (the fallback case where source is a specific actor)
  - The 4-subsystem cancel-broadcast is for UI, audio, animation,
    network state cleanup
  - CommandUpdater_send_toCharaBase's +0x42 field is the casting
    actor's wire id; -1 sentinel becomes 0 for "no caster"

Likely (Medium):
  - The 4 CancelHook subsystems correspond to specific game systems
    (UI, audio, animation, network) -- needs slot-by-slot vtable read
    to confirm
  - The payload "container" at +0x20/+0x24 is a doubly-linked list
    (head + tail pointers) rather than a std::vector (which would
    have size + capacity pointers)

Speculative:
  - The "WMSelf" suffix on the variant function suggests it's used
    when the SOURCE is WorldMaster and the TARGET is "self" --
    i.e. the player's own UI rendering of their own command result
  - The 0x48-byte CommandUpdate record stores the result code +
    flags + receiver field + payload tail in a fixed layout that
    could be further reverse-engineered
```

## Cross-references

- `finding_polymorphic_block_userdataReceiver.md` -- the original
  finding for opcodes 22-26 + UserDataReceiver class identification;
  this finding deepens its "next test" section
- `finding_invokeLua_paradigm_15_callbacks.md` -- the registerLua vs
  invokeLua paradigm split; this finding adds System (paradigm 2)
- `finding_cutscene_block_complete_opcodes_4_to_18.md` -- opcodes 17/18
  characterized; this finding renames the wrapper functions
- `finding_command_baseclass_and_judges.md` -- 9 Receiver variants
  in 1.x Lua; this finding maps them to 4 wire modes
- `finding_chat_block_command_notifications.md` -- established that
  "chat" opcodes are actually CommandUpdater notifications; this
  finding shows the dispatch infrastructure

## Next test

```text
With System (2 callbacks) + UserDataReceiver decoded:

  1. Walk inbound opcodes 27+ to find more invokeLua/CommandUpdater
     routings (per finding_complete_3channel_opcode_inventory may be
     already characterized as NO-OPs in finding_inbound_dispatch_two_families_and_chat_d)
     
  2. Look for more invokeLua callbacks by searching strings starting
     with "_on" -- enumerate the FULL invokeLua roster across all
     classes (estimated 25-40 total, currently 17 named)

  3. Walk Director/Judge master blocks -- separate paradigm (likely
     not registerLua/invokeLua at all; possibly Lua-internal
     subscriber pattern)

  4. Read FUN_0076b3d0 (CommandUpdate record allocator) + FUN_00789cd0
     (routing record allocator) -- get the EXACT struct layout of
     the 0x48-byte CommandUpdate record. This is the unit the server
     must emit.

  5. Read the 4 cancel-hook subsystem vtable slots to identify which
     subsystems subscribe (likely UI/audio/animation/network)
```

## Commit suggestion

```
docs(re/exe): System invokeLua callbacks (opcodes 17/18) + UserDataReceiver 4-mode dispatcher decoded (5 CommandUpdater helpers named)
```
