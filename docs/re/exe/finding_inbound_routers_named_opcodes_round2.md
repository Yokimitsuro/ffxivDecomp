# Finding: Inbound Routers + Named Opcodes (Round 2)

Closes the per-opcode router walk for representative entries in
Family A, Family B, and the chat family. Adds 8 newly-named Lua
hook opcodes (4, 9, 10, 11, 13, 20, 21, plus characterization of
chat A/B/C/D dispatch core). Cumulative coverage now ~46% of
active opcodes named.

## Method

For each target entry, I:
1. Decompiled the dispatch table wrapper (e.g. `FUN_0075d750`).
2. Identified the router (`FUN_008a3XXX+0x10`).
3. Decompiled the router to find the dynamic_cast target type
   and the callee method.
4. Decompiled the callee to find the Lua hook name (string passed
   to `FUN_00447260` which builds the Lua function-name buffer).
5. Renamed the wrapper, the router, and the Lua-invoking method
   in Ghidra. Added decompiler comments at each.

## Newly named opcodes

```text
ENTRY  WRAPPER (RENAMED)                                          LUA HOOK         ACTOR
-----  -----------------                                          --------         -----
   4   ZoneIn_handler_opcode_4_DesktopWidget_onTargetChanged      _onTargetChanged DesktopWidget
   8   ZoneIn_handler_opcode_8_CutScene_onInitializationClip      _onInitializationClip  CutScene
   9   ZoneIn_handler_opcode_9_CutScene_onShowUIClip              _onShowUIClip    CutScene
  10   ZoneIn_handler_opcode_10_CutScene_onHideUIClip             _onHideUIClip    CutScene
  11   ZoneIn_handler_opcode_11_CutScene_onShowWidgetClip         _onShowWidgetClip CutScene
  13   ZoneIn_handler_opcode_13_CutScene_onOpenUIClip             _onOpenUIClip    CutScene
  20   ZoneIn_handler_opcode_20_DesktopWidget_onPreWarp           _onPreWarp       DesktopWidget
  21   ZoneIn_handler_opcode_21_DesktopWidget_onPostWarp          _onPostWarp      DesktopWidget
```

Plus polymorphic-vtable opcodes (round 2 additions):

```text
ENTRY  WRAPPER (RENAMED)                          VTABLE SLOT
-----  -----------------                          -----------
  22   ZoneIn_handler_vtable_dispatch_slot21      slot 21 (+0x54)
  23   ZoneIn_handler_vtable_dispatch_slot22      slot 22 (+0x58)
  24   ZoneIn_handler_vtable_dispatch_slot23      slot 23 (+0x5c)  [already named in earlier session]
  25   ZoneIn_handler_vtable_dispatch_slot24      slot 24 (+0x60)
  26   ZoneIn_handler_vtable_dispatch_slot25      slot 25 (+0x64)
```

Plus chat (renamed in round 1, characterized in round 2):

```text
ENTRY  WRAPPER                                    WRITER                BUILDER
-----  -------                                    ------                -------
  35   ZoneIn_handler_chat_variant_A (FUN_0076c0d0)  FUN_007858c0      FUN_0089d220 (1-arg)
  36   ZoneIn_handler_chat_variant_B (FUN_0076c3b0)  FUN_00785aa0      FUN_0089d170 (1-arg)
  37   ZoneIn_handler_chat_variant_C (FUN_0076c220)  FUN_007859b0      FUN_0089e3f0 (4-arg) <-- outlier
  57   ZoneIn_handler_chat_variant_D                 FUN_00785bf0      FUN_0089d340 (1-arg)
```

(The four chat writers share a near-identical body and all funnel
into `FUN_00785570(chatMgr, packet_id)`. Only the builder choice
varies. See decompiler comment at `0x00785570` for the dispatch
core's analysis.)

## Cluster pattern: opcodes group by target actor class

Walking the routers reveals that **opcodes cluster by which actor
class they target**:

```text
CutScene cluster:        8, 9, 10, 11, 13   (UI / cinematic events)
DesktopWidget cluster:   4, 20, 21          (player UI / warp lifecycle)
Polymorphic cluster:     22-26              (5 consecutive vtable slots
                                              21-25 of the packet's vtable)
Chat cluster:            35, 36, 37, 57     (4 distinct chat channels)
Generic data:            38                 (192-byte _onReceiveDataPacket)
Lifecycle:               0, 1, 2, 60        (touch begin/end, move-at-sit,
                                              finalize)
```

So opcode IDs are NOT arbitrary -- they were allocated in BLOCKS by
subsystem. CutScene got 5 slots (and the 4-7 + 9-10 range looks
contiguous), DesktopWidget got a small set, polymorphic packets got
5 consecutive slots, chat got 4 slots (with one outlier at 57).

## CutScene UI clip model (opcodes 9 / 10 / 13)

The 3 CutScene UI clip opcodes share a common pattern:

```text
1. param_2 is a UI clip INDEX into a static array DAT_0134b564
   (stride 0x54 = 84 bytes per entry).
2. The handler reads the static clip data from this array.
3. The packet provides additional dynamic data:
     - scalar args (position, timing, fade)
     - variable-length vectors of override values
4. The handler invokes the matching Lua hook with all data.
```

Opcode 9 (`_onShowUIClip`)   -- transient overlay show, with override
                                lists for per-element customization
Opcode 10 (`_onHideUIClip`)  -- inverse: hide the overlay
Opcode 13 (`_onOpenUIClip`)  -- open the clip as an INTERACTIVE
                                widget; has two modes (param_2 == 1
                                = single-value list; param_2 == 3
                                = bit-flag + value list)

So the cutscene UI is built on a **static client-side clip table**
indexed by integer ID. Server only sends the ID + dynamic
parameters; client owns the layout.

## DesktopWidget warp lifecycle (opcodes 20 / 21)

Paired event flow analogous to opcodes 0/1 (touch begin/end):

```text
SERVER PUSHES                       CLIENT-SIDE EFFECT
-------------                       ------------------
opcode 20 (_onPreWarp)              flag_0x7b = 1; UI saves state, fades out
... (actual zone change)            
opcode 21 (_onPostWarp)             validated by flag_0x7b == 1;
                                     UI restores state; flag_0x7b = 0
```

The +0x7b byte on DesktopWidget is the **warp-in-progress flag**.
`_onPostWarp` is guarded by this flag, so post-warp without prior
pre-warp is a no-op (defensive against out-of-order packets).

## Router pattern (canonical)

Every Family-A and Family-B router I have walked follows the same
shape:

```c
void router(packet, actor_ptr, args...) {
    void *typed = ___RTDynamicCast(actor_ptr, 0,
                    ActorBase::RTTI_Type_Descriptor,
                    <TargetClass>::RTTI_Type_Descriptor, 0);
    if (typed != NULL) {
        <TargetClass>::method(typed, packet, args...);
    }
    // else: silently drop (wrong-typed actor)
}
```

So the runtime model is:
- packets carry an actor reference (resolved to a generic ActorBase*)
- routers do dynamic_cast<TargetClass> to enforce the type
- wrong-typed actors are SILENTLY ignored, no error log

This is consistent with packets being addressed to actor IDs and
the type filter being a defensive runtime check. If a server bug
addresses a CutScene event to a non-CutScene actor, the packet is
just dropped.

## Lua-invocation pattern (canonical)

Every "target method" I walked builds Lua args and calls a hook
via this pattern:

```c
void <TargetClass>::invokeLua_onXxx(this, lua_state, args...) {
    // build args tuple
    FUN_00584e10(args_buf, ...);
    FUN_00585020(args_buf, &arg1);
    FUN_00585020(args_buf, &arg2);
    // ... (any number of args)
    // build function name buffer
    FUN_00447260(name_buf, "_onXxx", DAT_00f67298);
    // call Lua
    FUN_00cc7a90(lua_state, this, name_buf, args_buf);
    // cleanup
    FUN_00446f50(name_buf);
    FUN_00584540(args_buf);
}
```

So the Lua call helpers are:
- `FUN_00584e10`     -- args buffer init
- `FUN_00585020`     -- push uint32 arg
- `FUN_00748c80/da0/e00` -- push other types (sheet entry, vector, etc.)
- `FUN_00447260`     -- build Lua function name buffer
- `FUN_00cc7a90`     -- invoke Lua function on this object
- `FUN_00446f50`     -- function name buffer destructor
- `FUN_00584540`     -- args buffer destructor

These are the **canonical Lua bridge helpers** for inbound packet ->
Lua hook conversion. Any inbound opcode that calls a Lua hook will
go through them.

## Chat dispatch characterization (no per-channel naming yet)

The 4 chat writers share an almost byte-identical body. They differ
ONLY in which builder they invoke before the common dispatch:

```text
all 4 writers do:
  - read chatMgr at *(piVar3->[0])+0xf4
  - check chatMgr+0x10 == 0  (chat available flag)
  - guard via FUN_0089d220 / 0x0089d170 / 0x0089d340 / 0x0089e3f0
  - if guard returns the magic byte at s___AVCommandUpdaterBase[0x3f]
    -> proceed
  - else: drop
  - FUN_00794250/240 (packet finalize)
  - FUN_00785570(chatMgr, packet_id)  (actual dispatch)
```

The builder addresses are CONTIGUOUS in the binary which suggests
they share a base class but have distinct virtual methods (or just
different overloads of the same chat-format serializer).

Channels are NOT yet named because:
- The chat writers don't reference any string identifiers
  (channel names) directly.
- Distinguishing /say vs /yell vs /tell vs /shout requires
  Lua-side correlation (where the player-facing chat command
  strings live).

This is the next correlation task -- see `Next test` below.

## Active opcode coverage (cumulative)

```text
ROUND 1 (prior session):
  named:               16 opcodes (touch, sit, chat A/B/C, dataPacket, finalize,
                                    + 9 "active but unidentified" family entries)
  family-classified:   ~48 active entries

ROUND 2 (this finding):
  newly named:         8 opcodes (target-changed, init/show/hide/widget/open
                                   clip, pre/post warp)
  polymorphic named:   5 entries (slots 21-25)
  chat D characterized

  cumulative named:    22 of ~48 active opcodes (~46%)
  remaining unnamed:   ~26 active opcodes (~54%)
```

## Confidence

```text
Confirmed:
  - 8 new Lua hook bindings (opcode -> _onXxx):
      4 -> DesktopWidget._onTargetChanged
      8 -> CutScene._onInitializationClip
      9 -> CutScene._onShowUIClip
     10 -> CutScene._onHideUIClip
     11 -> CutScene._onShowWidgetClip
     13 -> CutScene._onOpenUIClip
     20 -> DesktopWidget._onPreWarp
     21 -> DesktopWidget._onPostWarp
  - 5 polymorphic vtable opcodes at slots 21-25 (entries 22-26).
  - The router pattern is dynamic_cast<TargetClass> + method dispatch.
  - The 4 chat writers funnel into FUN_00785570 with builder-only
    variance.
  - DesktopWidget's +0x7b byte is the warp-in-progress flag.

Likely (High):
  - The +0x68/+0x6c/+0x70 fields on DesktopWidget store target-tracking
    state (max_targets, target_tracker, last_main_target_ref).
  - Opcode 7 (FUN_0075d830 -- a sibling of opcodes 4 and 8) is likely
    also a DesktopWidget event (target-related, given proximity to 4).
  - Opcode 12 (FUN_007599e0) and 14 (FUN_0075d950) are likely also
    CutScene UI events given proximity to the 8-13 CutScene block.

Likely (Medium):
  - The chat outlier 36 (4-arg builder) carries the most metadata,
    suggesting it is the SYSTEM message channel (sender + category
    + recipient + body) rather than /say.
  - Chat D (entry 57) being in a separate block from A/B/C (35-37)
    suggests it was added LATER in development.

Speculative:
  - The CutScene UI clip array at DAT_0134b564 (stride 0x54) is a
    static table of ~50-100 clip definitions; the index space is
    likely <0x100 (1 byte).
  - Opcode 11 (_onShowWidgetClip) is distinct from opcode 9
    (_onShowUIClip) in that "WidgetClip" = a higher-level interactive
    widget (e.g. dialog choice), while "UIClip" = a graphical overlay.
```

## Ghidra annotations added

```text
RENAMES:
  - 0x006fe960 -> DesktopWidget_invokeLua_onTargetChanged
  - 0x006fbe80 -> CutScene_invokeLua_onInitializationClip
  - 0x006fc080 -> CutScene_invokeLua_onShowUIClip
  - 0x006fc260 -> CutScene_invokeLua_onHideUIClip
  - 0x006fc3a0 -> CutScene_invokeLua_onShowWidgetClip
  - 0x006fc5f0 -> CutScene_invokeLua_onOpenUIClip
  - 0x006fede0 -> DesktopWidget_invokeLua_onPreWarp
  - 0x006fef10 -> DesktopWidget_invokeLua_onPostWarp
  - 0x008a3aa0 -> Router_dispatch_to_CutScene_method_FUN_006fc3a0  (entry 11)
  - 0x008a3ea0 -> Router_dispatch_to_DesktopWidget_onTargetChanged (entry 4)
  - 0x008a3990 -> Router_dispatch_to_CutScene_onInitializationClip (entry 8)
  - 0x008a39e0 -> Router_dispatch_to_CutScene_onShowUIClip         (entry 9)
  - 0x008a3a40 -> Router_dispatch_to_CutScene_onHideUIClip         (entry 10)
  - 0x008a3b50 -> Router_dispatch_to_CutScene_onOpenUIClip         (entry 13)
  - 0x008a4410 -> Router_dispatch_to_DesktopWidget_onPreWarp       (entry 20)
  - 0x008a44d0 -> Router_dispatch_to_DesktopWidget_onPostWarp      (entry 21)
  - 0x00759940 -> ZoneIn_handler_opcode_11_CutScene_onShowWidgetClip
  - 0x0075d750 -> ZoneIn_handler_opcode_4_DesktopWidget_onTargetChanged
  - 0x0075d860 -> ZoneIn_handler_opcode_8_CutScene_onInitializationClip
  - 0x0075d890 -> ZoneIn_handler_opcode_9_CutScene_onShowUIClip
  - 0x0075d8d0 -> ZoneIn_handler_opcode_10_CutScene_onHideUIClip
  - 0x0075d900 -> ZoneIn_handler_opcode_13_CutScene_onOpenUIClip
  - 0x00759bb0 -> ZoneIn_handler_opcode_20_DesktopWidget_onPreWarp
  - 0x00759c20 -> ZoneIn_handler_opcode_21_DesktopWidget_onPostWarp
  - 0x00759c90 -> ZoneIn_handler_vtable_dispatch_slot21
  - 0x00759cb0 -> ZoneIn_handler_vtable_dispatch_slot22
  - 0x00759cf0 -> ZoneIn_handler_vtable_dispatch_slot24
  - 0x00759d10 -> ZoneIn_handler_vtable_dispatch_slot25

DECOMPILER COMMENTS (substantial multi-line) added at:
  - 0x006fe960 (target-changed flow, 0x68/0x6c/0x70/0x7c offsets)
  - 0x006fbe80 (initialization-clip + Personage object)
  - 0x006fc080 (show-ui-clip + variable args)
  - 0x006fc260 (hide-ui-clip + clip array)
  - 0x006fc3a0 (show-widget-clip)
  - 0x006fc5f0 (open-ui-clip + 2 modes)
  - 0x006fede0 (pre-warp + 0x7b flag)
  - 0x006fef10 (post-warp + 0x7b guard)
  - 0x00785570 (chat dispatch core + 4 builders mapping)
  - 0x00759c90 (polymorphic block 22-26)
```

## Next test

- Walk the chat-builders FUN_0089d170/d220/d340/e3f0 to find the
  chat-format string layout each one constructs. The wire payload
  shape per channel may hint at the channel kind (e.g. 2-name
  format = /tell).
- Cross-reference the chat builders against Lua chat command
  scripts (`commandbaseclass.lua` + descendants) to find the
  /say /yell /tell /shout chat command implementations and which
  outbound opcode they trigger -- that maps to the receiving
  inbound writer.
- Walk the remaining unnamed routers in the CutScene block
  (opcodes 5, 6, 7, 12, 14, 15-19) to close the CutScene UI
  surface. These likely include: clip step, clip end, scene done,
  fade in/out, scene loop, motion play, etc.
- Walk the polymorphic packet vtable: 5 distinct virtual methods
  at slots 21-25. Identifying ONE packet class's vtable layout
  unlocks the semantics for all 5 opcodes (22-26).

## Commit suggestion

```
docs(re/exe): name 8 inbound opcodes (CutScene + warp lifecycle) + characterize chat dispatch core
```
