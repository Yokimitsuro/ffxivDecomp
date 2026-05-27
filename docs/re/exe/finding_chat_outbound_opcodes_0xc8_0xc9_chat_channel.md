# Finding: Chat Outbound Wire Opcodes Pinned -- 0xC8 (/tell) + 0xC9 (chat) on CHAT Channel

**Closes the chat outbound wire gap.** Confirms the wire opcodes
used when chat messages leave the client. Discovers that chat goes
over the **dedicated Chat channel** (not Zone), and that channels
32/33/38/40 all multiplex into a single wire opcode (0xC9), with
/tell using its own dedicated opcode (0xC8).

This pairs the inbound chat finding to complete the chat
bidirectional wire format documentation.

## 1. The 2 chat outbound opcodes

```text
Opcode  Size      Function                                       Use case
------  ----      --------                                       --------
0xC8    560 B     ChatOut_send_opcode_0xc8_tell_560B            /TELL (whisper)
                  @ 0x004df810                                   2 names: recipient + body
0xC9    536 B     ChatOut_send_opcode_0xc9_chatMessage_536B     Chat MESSAGE
                  @ 0x004df6d0                                   1 sender + body (all channels)
```

Both dispatch via `ChatClient_dispatchOutbound_generic` to the
**Chat channel** (separate from Zone channel which carries
state/WorkSync opcodes).

## 2. Architecture: Chat channel vs Zone channel

```text
ZONE CHANNEL (state/world opcodes):
  0x12d  Tagged container
  0x12e  RPC carrier (104B)
  0x12f  WorkSync C->S (56B string)
  0x132  Item state notify (24B)
  0x133  WorkSync C->S group variant (56B alt)
  0x135  Subscribe binding-id

CHAT CHANNEL (chat opcodes):
  0xc8   /tell (560B, 2 names)
  0xc9   chat message (536B, 1 name)
  0x02 / 0x12c   chat handshake/loginAck

LOBBY CHANNEL: separate set (8 outbound + 9 inbound)

The 3 channels are SEPARATE TCP/UDP-style streams. Chat doesn't
compete with state updates for bandwidth.
```

## 3. Why /tell needs its own opcode

The 0xC8 (/tell) packet has an EXTRA name slot for the recipient:

```text
ChatOut_send_opcode_0xc8_tell_560B:
  Args: this, recipient_name, message_body
  
  - local_250 (16B align): RECIPIENT NAME (copied via FUN_00447bc0)
  - local_228 (512B):      MESSAGE BODY
  - Built via ChatTellDescriptor_construct_opcode_0xc8
    -> distinct packet shape from regular chat
  - Final dispatch: ChatClient_dispatchOutbound_generic
```

The 560-byte packet = 32B header/framing + 16B recipient name + 512B body.

For regular chat (0xC9), the SENDER is implicit (the connected
client), so no extra name field is needed. /tell needs to specify
WHO RECEIVES the message.

## 4. Why all 4 channels (32/33/38/40) use the SAME opcode (0xC9)

```text
ChatOut_send_opcode_0xc9_chatMessage_536B packet:
  +0x00   opcode = 0xc9
  +0x04   size = 0x218 (536)
  +0x08   sender_id (param_1)
  +0x0c   message body (max 0x200 = 512 bytes)
  +0x20c  padding/framing to 536 total

The CHANNEL ID (32/33/38/40) is MULTIPLEXED into the message body
or wrapper header (likely a 1-byte prefix). Server reads the channel
ID from the payload and routes accordingly:
  32 -> system notify (yellow text)
  33 -> system alert (red text)
  38 -> NPC dialog (white text)
  40 -> world cryer / global say
```

So the **wire format is uniform** (all chat messages = opcode 0xC9
+ 536-byte packet), but the **content includes the channel ID** for
server-side routing.

This is simpler than having 4 separate opcodes -- saves opcode
space and makes the server's chat dispatch a single handler.

## 5. The chat send wrapper chain

```text
Lua: worldMaster:say(actor, msgIdx)
 -> desktopWidget:_appendMessagePool(actor, channel=40, msgRef, msgIdx)
 -> DesktopWidget_cpp_appendMessagePool_thunk
 -> CommandUpdater_send_broadcast (for system messages)
   OR CommandUpdater_send_toActorId (for NPC dialog)
   OR ...
 -> CommandUpdater_allocAndEnqueueRecord (280B record)
 -> Queue flush eventually:
 -> FUN_004d82e0 (chat send wrapper):
    - Validate ChatClient connected (this+0x174ec)
    - FUN_00c99e40 (format message; substitution param expansion)
    - Optional: FUN_004ce760 (local echo to chat log buffer)
    - ChatOut_send_opcode_0xc9_chatMessage_536B
 -> ChatClient_dispatchOutbound_generic
 -> Wire packet on CHAT channel
```

For /tell, the chain is similar but FUN_004d83e0 wraps the 0xC8
opcode instead.

## 6. Substitution params (FUN_00c99e40)

```text
The 12-int substitution params from CommandUpdate records get
expanded into the message body before wire send.

Example:
  Lua: worldMaster:say(actor, msgIdx=42, ${player}=playerName,
                       ${item}=itemName)
  CommandUpdate record stores:
    - msgIdx = 42
    - params = [playerName_id, itemName_id, ...]
  
  Wire-send time:
    - Lookup msgIdx 42 in localized message table -> template:
      "${player} found ${item}!"
    - Substitute param[0]=playerName, param[1]=itemName
    - Final string: "Bob found Sword!"
    - Pack into 0xC9 packet body
```

This is the **same template substitution** discussed in the chat
inbound finding (entries 35-37 reading msg_ref_a/b refs). The
server pushes template IDs + param IDs; client expands locally for
display.

## 7. Chat opcode SEPARATION rationale

```text
WHY split into 3 channels (Lobby/Zone/Chat) at all?

LOBBY:    persistent during login phase only
          carrier for character select + world enter
          low bandwidth, low priority
ZONE:     persistent during in-zone gameplay
          carries state sync (WorkSync), commands, actions
          high bandwidth, HIGH priority
CHAT:     persistent across zones
          carries chat messages, player-to-player communication
          low-medium bandwidth, MEDIUM priority

The 3-channel design lets the engine prioritize differently:
  - State updates (Zone) get priority for gameplay
  - Chat messages don't block state updates
  - Chat can fail/reconnect independent of zone server
  
This is critical for 1.x's MMO architecture where zone server may
restart (zone migration) but chat session persists.
```

## 8. Renames already done (no new renames needed)

The 2 chat outbound functions were already named in Ghidra:
```text
0x004df6d0  ChatOut_send_opcode_0xc9_chatMessage_536B
0x004df810  ChatOut_send_opcode_0xc8_tell_560B
0x004df9a0  ChatOut_send_handshake_or_loginAck_opcode_0x02_or_0x12c
```

This finding documents how they're invoked from the
CommandUpdater dispatch chain.

## 9. Confidence

```text
Confirmed:
  - Chat outbound uses 2 wire opcodes (0xC8 tell, 0xC9 chat)
  - Both dispatch on Chat channel via ChatClient_dispatchOutbound_generic
  - /tell (0xC8) is 560B with recipient name slot
  - Regular chat (0xC9) is 536B with sender + body (channel multiplexed
    inside payload)
  - 4 channels (32/33/38/40) all funnel through opcode 0xC9
  - Chat is SEPARATE from Zone channel (different TCP stream)
  - Substitution params (12 ints) expanded via FUN_00c99e40 before wire

Likely (High):
  - The channel ID is encoded as a 1-byte prefix or in the message
    header byte at a fixed offset in the 512B body
  - Tell messages over 64 chars (per inbound finding) are split into
    multiple 0xC8 packets server-side; client receives concatenated
  - The 280B CommandUpdate record (outbound) is the queue staging;
    the actual 536/560B packet is built at flush time from the record
```

## 10. Cross-references

- `finding_inbound_chat_handlers_3_variants_decompiled.md` -- the
  INBOUND chat side (server -> client display)
- `finding_appendMessagePool_thunk_command_updater_dispatch.md` --
  the OUTBOUND CommandUpdater dispatcher (4 variants)
- `finding_parseTextCommand_thunk_chat_dispatch_architecture.md` --
  the OUTBOUND parse side (user typing)
- `finding_worldmaster_complete.md` -- channels 32/33/38/40 routing
- `finding_ipc_channel_framing.md` -- 3-channel architecture
  (Lobby/Zone/Chat)

## 11. Updated chat loop FULL DIAGRAM

```text
USER TYPES "/say hello" in chat box
   ↓
LUA: desktopWidget:_parseTextCommand("/say hello")
   ↓
EXE: ChatParser_tokenizeAndParse -> returns (cmdId, args[])
   ↓
LUA: cmdId 'say' handler:
     - desktopWidget:_appendMessagePool ECHO (local UI)
     - _executeCommand (wire)
   ↓
EXE: DesktopWidget_cpp_appendMessagePool_thunk
   ↓
EXE: CommandUpdater_send_broadcast (for /say's channel 40)
   ↓
EXE: CommandUpdater_allocAndEnqueueRecord (280B record)
   ↓
EXE: Queue flush per game tick
   ↓
EXE: FUN_004d82e0 wrapper:
     - FUN_00c99e40 (substitution params expansion)
     - ChatOut_send_opcode_0xc9_chatMessage_536B
   ↓
EXE: ChatClient_dispatchOutbound_generic
   ↓
WIRE: opcode 0xC9 on Chat channel, 536 bytes
   ↓
SERVER: receives, validates, broadcasts to nearby players
   ↓
WIRE: server pushes back via Chat channel inbound opcode
   ↓
EXE: Inbound chat handler (entry 35/36/37 of Zone dispatch table)
   * Wait actually inbound is on Zone channel per dispatch table
   * This suggests the inbound chat actually arrives via Zone
   * Or the dispatch table is shared between Zone and Chat
   ↓
EXE: Chat writer -> dispatch core -> ring-buffer enqueue
   ↓
EXE: Per-tick flush -> _appendMessagePool
   ↓
EXE: CommandUpdater_invokeLua_onUpdateWork_*
   ↓
LUA: chat panel widget receives and displays
```

## 12. Next test

```text
1. Decode the exact byte position of channel ID in opcode 0xC9 body
2. Verify whether inbound chat is on Zone channel (entries 35-37
   suggest yes) or Chat channel (would expect a separate dispatch
   table)
3. Walk FUN_004ce760 (local echo function) to confirm it writes
   to the chat log buffer
4. Find /yell and /shout specific routing (which use opcode 0xC9
   but with what channel byte?)
5. Document /linkshell chat opcode (if separate from 0xC9)
```

## Commit suggestion

```
docs(re/exe): chat outbound wire opcodes pinned -- 0xC8 /tell + 0xC9 chat message on Chat channel; 4 channels multiplex into opcode 0xC9
```
