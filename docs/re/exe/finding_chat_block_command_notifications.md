# Finding: "Chat" Block Are Command Notifications, Variant C = /tell-style

Walks the chat builders + the multi-mode dispatcher FUN_0089fbf0 +
correlates with Lua outbound calls. Closes the chat-block
investigation with a refined model: **the 4 "chat" handlers are not
raw chat -- they are Command update notifications** routed through
the chat display ring buffer. Variant C is the only one with a
recipient name buffer, confirming /tell-style addressing.

## Key result

```text
ALL 4 "chat" handlers (entries 35, 36, 37, 57) carry
COMMAND-system notifications, not raw chat messages.

Evidence:
  - The "magic byte" tag they write is at offset 0x3f of the RTTI
    type descriptor for class
      "Application::Lua::Script::Client::Command::CommandUpdaterBase"
  - The string at 0x012c4170 is
      ".?AVCommandUpdaterBase@Command@Client@Script@Lua@Application@@"
  - All 4 chat builders use this tag, so all 4 handlers route via
    the Command-update class hierarchy.

So the entry names "chat A/B/C/D" should be read as "command update
variant A/B/C/D". They use the chat-display ring buffer because
that's how 1.x surfaces command-result text to the player.
```

## Refined variant table

```text
ENTRY  PRIOR LABEL  WIRE PAYLOAD SHAPE                ROLE
-----  -----------  -----------------                  ----
 35    chat A       single name + msg + ushort id     COMMAND-update
                                                       single-target broadcast
 36    chat B       40-char name + payload + type +  COMMAND-update
                    subtype                            typed/categorized
 37    chat C       sender name + 64-byte RECIPIENT  COMMAND-update with
                    name at +0x49 + payload + type    targeted recipient
                                                       (=> /tell-style)
 57    chat D       id + 32-byte body + type byte    COMMAND-update
                                                       (no clear distinguishing
                                                        feature vs A/B)
```

## Confirmed: entry 37 is /tell-style (recipient-targeted)

The chat-C builder (FUN_0089e320, the only 4-arg builder) reads a
64-byte recipient name at packet offset 0x49:

```c
char *FUN_0089e320(void *this, char *param_1, undefined4 *param_2, int param_3) {
    FUN_008a0870(local_18, param_2, this);            // build sender info
    FUN_0078f810(local_20, param_3 + 0x49, 0x40);     // READ 64-BYTE
                                                       // RECIPIENT NAME at +0x49
    FUN_007906c0(local_20, local_18);                 // combine sender+recipient

    if (sender_list_empty(this)) {
        *param_1 = AVCommandUpdaterBase[0x3f];         // standard Command tag
    } else {
        *param_1 = DAT_0134c560;                       // "Tell" type tag
                                                        // (DIFFERENT from Command tag)
    }
    return param_1;
}
```

So entry 37 is the unique variant that:
- Reads a SECOND name (recipient) at offset 0x49 (64 bytes, matches FFXIV's
  64-char max name length)
- Uses a SPECIAL TYPE TAG (`DAT_0134c560`) when sender info is present
  (vs the standard Command tag for the other variants)

This is the **`/tell` whisper subsystem**.

## A/B/D builders are byte-identical

The other three builders (FUN_0089d220 / FUN_0089d170 / FUN_0089d340) are
literally byte-identical 1-statement functions:

```c
void FUN_0089d220(char *param_1) {
    *param_1 = s___AVCommandUpdaterBase_Command_C_012c4170[0x3f];
    return;
}
```

So the only thing distinguishing entries 35 vs 36 vs 57 at the
BUILDER level is which one gets called. The actual differentiation
between A/B/D happens in the wrapper (which reads different payload
layouts) and downstream consumers (which use the channel id to
choose UI presentation).

Conclusion: **A/B/D cannot be named individually from EXE evidence
alone**. The 3 channels need correlation with:
- Lua chat command implementations (e.g. `commandbaseclass.lua`
  descendants for /say /yell /shout /party /linkshell)
- Outbound packet builders (one of opcodes 0x12d-0x135) that emit
  to specific channels
- Network capture or game-state observation

## The multi-mode dispatcher FUN_0089fbf0

This function is BOTH:
- Secondary vtable slot 23 of UserDataReceiver (see
  `finding_polymorphic_block_userdataReceiver.md`)
- Router for non-polymorphic dispatch entry 42

It has a 4-way switch on `*(byte *)(this+0x10)`:

```text
mode 0 (actor target):
   dynamic_cast<CharaBase>(local_actor)
   -> dynamic_cast<WorldMaster>(packet_target) ?
      FUN_00772050(WorldMaster path) : FUN_00771f50(CharaBase path)

mode 1 (id target):
   resolved_actor = FUN_008a1510(this+8)
   FUN_007721b0(by-id, *resolved, this+0x1a as channel, ...)

mode 2 (name target):
   name = FUN_008a15b0(this+8)
   FUN_00772560(by-name, name_buf, this+0x1a as channel, ...)

mode 0xff (broadcast / all):
   dynamic_cast<WorldMaster>(local_actor) ?
      FUN_00772650(broadcast-all) :
      FUN_00771f50(CharaBase fallback)
```

So the dispatcher selects a target-resolution strategy based on
`*(this+0x10)`:

```text
mode 0    -> direct actor reference
mode 1    -> resolve by numeric id
mode 2    -> resolve by name string
mode 0xff -> broadcast (no specific target)
```

This is a **single packet-class supporting 4 target types**. Each
COMMAND notification can be addressed via any of the 4 modes.

## Target-delivery functions (the 5 callees)

```text
FUN_00771f50  -- deliver to single CharaBase actor (mode 0/0xff)
FUN_00772050  -- deliver to WorldMaster (mode 0 with WorldMaster cast)
FUN_007721b0  -- deliver by numeric id (mode 1)
FUN_00772560  -- deliver by name string (mode 2)
FUN_00772650  -- broadcast/all (mode 0xff with WorldMaster cast)
```

Each builds a 0x48-byte heap-allocated "chat message" struct via
operator_new(0x48) + FUN_00789cd0, then hands it to a chat-manager
delivery function (FUN_0076ff20 / FUN_00770f10 / FUN_007722a0).

## Connection to Lua

Lua-side calls related to NPC interaction (in
`lua/decompiled/src/729s9/wu7/wu789r57y9rr.lua`):

```text
_callServerOnTalk     (line 410, 432)  -- player talked to NPC
_callServerOnEmote    (line 465, 487)  -- player emoted at NPC
_callServerOnPush     (line 519)        -- player pushed NPC

Lua-defined hooks:
_onTalkEvent / _onTalkRequest / _onTalkRejected
_onEmoteEvent / _onEmoteRequest
_onPushEvent
```

These are OUTBOUND from client (Lua wraps the call, native sends to
server). The INBOUND counterparts (server -> client command-result
notifications) likely include the 4 Command-update channels we
documented here, but the 1:1 mapping is not yet established.

`_callServerOnTalk` would emit an OUTBOUND command-talk packet;
the server may respond with an inbound notification at entry 35 or 36
or another opcode entirely. Pinpointing requires tracing
`_callServerOnTalk` from Lua to its native bridge call (the
`_callServer*` family has `_inl` / `_cpp` variants visible in the
Lua) and then walking that native function to the outbound packet
builder.

## Annotations made in Ghidra

```text
RENAMES:
  - 0x0076c220 -> ZoneIn_handler_chat_variant_C_tell
  - 0x0089e3f0 -> ChatBuilder_tell_thunk
  - 0x0089e320 -> ChatBuilder_tell_readRecipientName
  - 0x0089d220 -> ChatBuilder_singleTarget_writeCommandTag_A
  - 0x0089d170 -> ChatBuilder_singleTarget_writeCommandTag_B
  - 0x0089d340 -> ChatBuilder_singleTarget_writeCommandTag_D

COMMENTS:
  - 0x0076c220 (entry 37 /tell wrapper -- recipient buffer offset)
  - 0x0089e320 (recipient-name reader + special "Tell" tag)
  - 0x00785570 (chat dispatch core -- updated to reflect Command-update
                interpretation and the byte-63 RTTI magic tag)
```

## Confidence

```text
Confirmed:
  - Entry 37 is /tell-style (recipient-targeted) -- confirmed via
    64-byte name buffer read at packet offset 0x49.
  - The "chat" magic byte tag is byte 63 of the RTTI type descriptor
    for CommandUpdaterBase, indicating these handlers route through
    the Command system, not raw chat.
  - 4-mode dispatcher (FUN_0089fbf0) routes by target type:
    actor / id / name / broadcast.
  - 3 of the 4 chat builders (A/B/D) are byte-identical -- they only
    write the Command-class tag and do not differentiate channel
    on their own.
  - Lua side has _callServerOnTalk / OnEmote / OnPush as the
    OUTBOUND counterparts to this Command system.

Likely (High):
  - The 4 channels (35/36/37/57) correspond to 4 distinct UI/audio
    presentations of command-result text (e.g. /say-style overlay
    vs /yell-style log entry vs /tell whisper vs system message).
  - Entry 37 (recipient-targeted) is the only one that can carry a
    "to:player_name" header; the others are sender-only.

Likely (Medium):
  - The COMMAND system here is the GameCommandBaseClass family
    (documented elsewhere). Server pushes command-result events to
    the client which displays them in the chat ring buffer plus
    triggers any related effects (animations, status updates).
  - The 4 chat channels A/B/D might correspond to 3 of:
    [Say, Yell, Shout, Party, Linkshell, System] -- but the
    individual assignment requires more correlation work.

Speculative:
  - The "Tell" special tag DAT_0134c560 is probably a small string
    or single byte distinguishing the recipient-targeted variant
    from the general Command tag. Could mark the UI channel as
    "whisper" vs "open chat".
```

## Coverage update

```text
Active opcodes named/characterized:
  CONFIRMED ROLE:    24 (touch, sit, target-changed, 5 CutScene UI,
                        warp pre/post, polymorphic block 22-26,
                        data, finalize, 4 chat variants A/B/C/D
                        as Command-update notifications)
  POSITIVE NAME C:    1  (entry 37 = /tell-style)
  POSITIVE NAME A/B/D: 0  (require Lua/network correlation)

Out of ~48 active opcodes:
  ~25 NAMED with specific role
  ~23 family-classified only

Coverage: ~52% specific role + ~48% family-classified
```

## Next test

- Walk `_callServerOnTalk`'s native counterpart (likely in the
  0x008aXXXX range based on prior Lua-to-EXE bridge findings) to
  identify which OUTBOUND opcode it emits. That gives the
  request/response pairing for the command system.
- Cross-reference DAT_0134c560 to find the "Tell" tag content
  (string / enum / single byte) and what other tags exist.
- Walk FUN_00789cd0 (the 0x48-byte command-message struct
  constructor) to map the message field layout.
- Look at the Lua `commandbaseclass.lua` family for /say /yell /tell
  /shout command implementations -- those will identify which
  outbound opcode corresponds to each chat channel.

## Commit suggestion

```
docs(re/exe): chat block are Command-update notifications; entry 37 = /tell
```
