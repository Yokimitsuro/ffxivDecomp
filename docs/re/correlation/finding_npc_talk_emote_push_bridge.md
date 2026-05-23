# Finding: Lua `_callServerOnTalk/Emote/Push` -> EXE NpcBaseClass Bridge

Extends the existing `_callServerOnCommand` correlation finding
(`finding_lua_to_exe_command_bridge.md`) to the three NPC-specific
outbound calls. Same Functor-based bridge pattern; same Zone channel
machinery; real packet builders still in the unanalysed window.

Sources read:

```text
EXE @ 0x00736fc0  NpcBaseClass_registerLua_callServerOnTalk
EXE @ 0x00737110  NpcBaseClass_registerLua_callServerOnEmote
EXE @ 0x00737260  NpcBaseClass_registerLua_callServerOnPush
EXE @ 0x0073f2b9  PlayerBase_registerLua_callServerOnCommand (reference)

EXE strings:
  0x00fd6e68  "_callServerOnTalk"
  0x00fd6e7c  "_callServerOnEmote"
  0x00fd6e90  "_callServerOnPush"
  0x00fd745c  "_callServerOnCommand"  (already known)

EXE label targets (NOT auto-analysed -- same unanalysed window
                    as the PlayerBase command thunks at 0x006de650-690):
  0x006e9520  -> NpcBaseClass::callServerOnTalk    (MFP thunk)
  0x006e95c0  -> NpcBaseClass::callServerOnEmote   (MFP thunk)
  0x006e9660  -> NpcBaseClass::callServerOnPush    (MFP thunk)

Lua source:
  lua/decompiled/src/729s9/wu7/wu789r57y9rr.lua    (NpcBaseClass body,
                                                    lines 410, 432, 465, 487, 519)
  lua/decompiled/src/729s9/wu7/wu789r57y9rr_p.lua  (binding specs,
                                                    lines 107-111, 123-127, 143-147)
```

## Bridge

```text
Lua:
  NpcBaseClass:_onTalkEvent(actor, args)  -> self:_callServerOnTalk(actor, args)
  NpcBaseClass:_onEmoteEvent(actor, args) -> self:_callServerOnEmote(actor, args)
  NpcBaseClass:_onPushEvent(actor, args)  -> self:_callServerOnPush(actor, args)

EXE binding spec (per _p.lua):
  _callServerOnTalk_inl returns ("self", "_callServerOnTalk_cpp")
  _callServerOnEmote_inl returns ("self", "_callServerOnEmote_cpp")
  _callServerOnPush_inl returns ("self", "_callServerOnPush_cpp")

EXE registration (same shape as PlayerBase command bindings):
  FUN_0072d400(this, lua_state, MFP_THUNK, 0, accessor1, accessor2)
                                ^^^^^^^^^
                                LAB_006e9520 / 95c0 / 9660

EXE thunks (UNANALYSED, all in 0x006e9520..0x006e9700+):
  LAB_006e9520  NpcBaseClass::callServerOnTalk
  LAB_006e95c0  NpcBaseClass::callServerOnEmote   (+0xa0 from prev)
  LAB_006e9660  NpcBaseClass::callServerOnPush    (+0xa0 from prev)

C++ method signature (inferred from analogous PlayerBase RTTI):
  void NpcBaseClass::callServerOnTalk(ExecuteParameters const&)
  void NpcBaseClass::callServerOnEmote(ExecuteParameters const&)
  void NpcBaseClass::callServerOnPush(ExecuteParameters const&)
```

The thunks are spaced exactly 0xa0 (160) bytes apart, which matches
the MSVC pattern: each thunk is a small fixed-size COMDAT block that
does `jmp rel32` to the real body. The real bodies share the same
unanalysed code window as the PlayerBase command thunks.

## Probable wire carrier: outbound opcode 0x12d

All 9 outbound opcodes (0x12d-0x135) are now named in Ghidra:

```text
0x12d  PacketBuilder_opcode_0x12d_200B_tagged          large structured container
       ZoneOut_sendScriptError_opcode_0x12d             script error variant
0x12e  ZoneOut_send_opcode_0x12e_104B                   104 bytes
0x12f  WorkSync_buildAndSendPacket_opcode_0x12f         WorkSync update
0x130  ZoneOut_send_opcode_0x130_32B_variantA           32B state change A
0x130  ZoneOut_send_opcode_0x130_32B_variantB           32B state change B
0x131  ZoneOut_send_opcode_0x131_24B_byte               1-byte payload
0x132  ZoneOut_send_opcode_0x132_24B_byteUshort         byte + ushort
0x133  ZoneOut_send_opcode_0x133_56B                    56 bytes
0x134  ZoneOut_send_opcode_0x134_40B_withNonce          anti-tamper challenge
0x135  ZoneOut_send_opcode_0x135_24B_dword              subscribe by binding id
```

The 200-byte tagged container at `PacketBuilder_opcode_0x12d_200B_tagged`
is the most likely carrier for Talk/Emote/Push/Command. Its layout:

```text
+0x00  uint32   opcode = 0x12d
+0x04  uint32   size = 200
+0x08  16 B     framing header
+0x18  uint32   param_1
+0x1c  uint32   param_2
+0x20  uint32   param_3
+0x24  uint32   param_4
+0x28  byte     DISCRIMINATOR   <-- tag selects variant
+0x29  32 B     hash / id / nonce
+0x49  128 B    main payload    (32 dwords)
```

The DISCRIMINATOR at +0x28 is the most likely "command-id selector".
The 4 outbound NPC/player calls would emit 0x12d with 4 different
discriminator values:

```text
DISC?    BINDING                  PROBABLE OPCODE 0x12d VARIANT
-----    -------                  ----------------------------
 ?       _callServerOnCommand     general PlayerBase command
 ?       _callServerOnTalk        NPC talk request
 ?       _callServerOnEmote       NPC emote request
 ?       _callServerOnPush        NPC push request
```

Pinning the specific discriminator values requires force-disassembling
the thunks at 0x006e9520/95c0/9660 (and the PlayerBase thunks at
0x006de650/680/690) -- still gated on the manual Ghidra session
listed in `finding_lua_to_exe_command_bridge.md`.

## Full request/response loop (with what is known)

```text
CLIENT -> SERVER  (outbound, unanalysed body):
  player_action       =>  Lua _onXxxEvent
                      =>  Lua _callServerOnXxx
                      =>  EXE Functor::Execute
                      =>  EXE NpcBaseClass::callServerOnXxx(ExecuteParameters)
                      =>  Build PacketRequestBase(opcode=0x12d, disc=?)
                      =>  ZoneProtoChannel.ClientPacketBuilder send

SERVER -> CLIENT  (inbound, known via earlier findings):
  command result push  =>  Wire opcode 35/36/37/57 ("chat A/B/C/D" =
                           Command-update notifications, per
                           finding_chat_block_command_notifications.md)
                       =>  Inbound dispatch table entry routes via
                           UserDataReceiver vtable
                       =>  Lua hook fires (entry 37 = /tell-style with
                           recipient name)
                       =>  Chat ring-buffer queues the UI line
```

## What the server needs for a minimal Talk loop

```text
1. Receive inbound opcode 0x12d on the Zone channel.
2. Read the discriminator byte at +0x28; if it matches the "talk"
   variant id, dispatch to the Talk handler.
3. Validate target NPC actor id (from one of param_1..param_4).
4. Construct a Command-update notification and push back to the client
   on the inbound chat-block channel (likely opcode 35 = chat A for
   open-display, or use targeted variant if directed at a specific
   recipient).
5. Client displays the Talk result via the chat ring buffer and may
   trigger UI/animation hooks (_onTalkEvent has a lockon-camera branch;
   server-side state may need to track that).
```

Same flow for /Emote and /Push; only the discriminator and the
result-string template differ.

## Annotations made in Ghidra

```text
RENAMES:
  - 0x00736fc0 -> NpcBaseClass_registerLua_callServerOnTalk
  - 0x00737110 -> NpcBaseClass_registerLua_callServerOnEmote
  - 0x00737260 -> NpcBaseClass_registerLua_callServerOnPush

COMMENTS:
  - 0x00736fc0 (multi-line, with thunk addresses, sibling pattern,
                Lua-source cross-references, and link to the prior
                bridge finding)
```

## Confidence

```text
Confirmed:
  - The 3 NPC outbound calls (Talk/Emote/Push) are registered the
    same way as _callServerOnCommand: Functor over a member function
    pointer thunk.
  - Thunks at 0x006e9520 / 95c0 / 9660 are spaced 0xa0 apart, the
    MSVC COMDAT thunk pattern.
  - All 9 outbound opcodes (0x12d-0x135) are now named in Ghidra.

Likely (High):
  - The real method bodies use ExecuteParameters and serialize via
    PacketRequestBase -> ZoneProtoChannel (same as the PlayerBase
    command bindings, by class-pattern analogy).
  - The outbound wire opcode for all 4 calls (Talk/Emote/Push/Command)
    is 0x12d, distinguished by the discriminator byte at +0x28.

Likely (Medium):
  - Each binding emits a SHARED packet shape; the discriminator selects
    the variant; the server can implement one handler that dispatches
    on the discriminator.
  - The inbound counterparts (server-pushed result notifications) flow
    through the chat-block A/B/C/D opcodes 35/36/37/57. The specific
    mapping (which inbound opcode corresponds to which outbound binding)
    requires correlation work.

Speculative:
  - The 4 chat variants (A/B/C/D inbound) correspond 1:1 to the 4
    outbound bindings (Command/Talk/Emote/Push). That would explain
    why there are exactly 4 of each. But this is only speculation.
```

## Next test

- Force-disassemble at 0x006e9520 / 95c0 / 9660 (manual Ghidra
  session). Read the thunk's `jmp rel32` to find the real body
  location, then read the body to:
  * Confirm opcode = 0x12d
  * Read the discriminator byte value written at +0x28
  * Confirm the payload-marshalling path uses
    Parameter::StackOperatorInterface
- Same for the PlayerBase command thunks at 0x006de650/680/690.
- Once discriminator values are pinned, cross-reference with inbound
  chat-block opcodes to find the response variant per outbound call.

## Commit suggestion

```
docs(re/correlation): name NpcBaseClass Talk/Emote/Push outbound bridge
```
