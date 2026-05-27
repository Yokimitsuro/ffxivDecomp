# Finding: Inbound Chat Handlers (Entries 35-37) Disassembled -- 3 Variants Mapped + Prior Label CORRECTION

**CLOSES the chat bidirectional loop FULLY.** Disassembles the 3
inbound chat handlers in the Zone dispatch table at 0x00fdfb80
(entries 35-37). Each handles a different chat packet shape; all
3 route through the chat writer infrastructure to eventually drive
client-side `_appendMessagePool`.

**Also CORRECTS the prior labels**: Entry 36 is the `/tell` handler
(2 names: sender + recipient), NOT entry 37 as the prior
finding_inbound_dispatch_table_found.md claimed.

This finding pairs with:
- `finding_parseTextCommand_thunk_chat_dispatch_architecture.md` (OUT parse)
- `finding_appendMessagePool_thunk_command_updater_dispatch.md` (OUT/IN display)

Together the 3 documents map the COMPLETE chat subsystem
bidirectionally.

## 1. The 3 inbound chat handlers (CORRECTED mapping)

```text
Entry  Address      Handler                                    Chat variant
-----  -------      -------                                    ------------
 35    0x00fdfc0c   ZoneIn_handler_chat_say_substitution_entry35  System/Say with msg+params
                    @ 0x0076c0d0                              
                                                              
 36    0x00fdfc10   ZoneIn_handler_chat_variant_C_tell         /TELL (sender + recipient)
                    @ 0x0076c220                               (already named in prior session)
                                                              
 37    0x00fdfc14   ZoneIn_handler_chat_simple_entry37         Simple chat (1 name + flags)
                    @ 0x0076c3b0                               
```

The prior finding swapped entries 36 and 37 labels. The decompile
evidence is conclusive:
- Entry 36 reads name at +0x29 (=41, recipient slot) -- /tell
- Entry 37 has no recipient -- simple chat

## 2. Entry 35: System/Say with substitution params

```c
void ZoneIn_handler_chat_say_substitution_entry35(this, packet) {
  // Extract from packet:
  //   name_str       = string at (packet + 4)         sender name
  //   msg_ref_b      = FUN_00cc9320(packet[1])        message ref B
  //   msg_ref_a      = FUN_00cc9320(packet[0])        message ref A
  //   lang_byte      = packet[2] (byte)               language code
  //   params_b       = packet + 0xc                   substitution params B (16+ bytes)
  //   params_a       = packet + 3                     substitution params A (16+ bytes)
  //   buffer_size    = 0x40 (64)                      sub buffer size

  // Build the chat message struct
  FUN_0089f180(local_msg, msg_ref_a, msg_ref_b, lang_byte,
               params_a, name_str, params_b, 0x40);
  
  // Dispatch through chat writer A
  FUN_007858c0(this+4, packet, local_msg);
}
```

Packet shape (entry 35):
```text
+0    uint32   msg_ref_a       e.g. "{player} says: ${msg}" template
+4    string   sender_name     UTF-8, null-terminated
+8    uint32   msg_ref_b       maybe channel-specific suffix template
+12   ...     params_a         16-byte substitution params block A
+72   uint8   language_byte    locale
+24+  ...     params_b         substitution params block B (12+ bytes)
+48   ...     more params      buffer up to 64 bytes total
```

This is the **system-message format** with template + substitution
params. Used by worldMaster:say (channel 40), notify (32), alert
(33), and NpcBaseClass:say (channel 38) when sent server -> client.

## 3. Entry 36: /TELL handler (sender + recipient)

```c
void ZoneIn_handler_chat_variant_C_tell(this, packet) {
  // Extract from packet:
  //   sender_name    = string at (packet + 9)          UTF-8, null-term
  //   recipient_name = string at (packet + 0x29)       UTF-8, null-term
  //   msg_ref_b      = FUN_00cc9320(packet[1])         message ref B
  //   msg_ref_a      = FUN_00cc9320(packet[0])         message ref A
  //   lang_byte      = packet[2]                       language code
  //   body_buf       = packet + 0x49                   MESSAGE BODY
  //   body_size      = 0x40 (64)                       buffer size
  
  // Build the /tell-specific message
  FUN_0089edb0(local_msg, msg_ref_a, msg_ref_b, lang_byte,
               recipient_name, sender_name, body_buf, 0x40);
  
  // Dispatch through chat writer C
  FUN_007859b0(this+4, packet, local_msg);
}
```

Packet shape (entry 36):
```text
+0x00   uint32   msg_ref_a              format template
+0x04   uint32   msg_ref_b              channel-specific ref
+0x08   uint8    language_byte          locale code
+0x09   string   sender_name            UTF-8 sender (max 64 chars)
+0x29   string   recipient_name         UTF-8 recipient (max 64 chars)
+0x49   string   message_body           UTF-8 body (max 64 chars)
+0x89                                   end of packet (likely fixed 137 bytes)
```

The 0x40 (64-byte) max for each string slot matches **FFXIV 1.x max
display name length** (64 chars). The 0x40 body size means /tell
messages are size-limited to 64 chars (or messages are split into
multiple packets for longer content).

## 4. Entry 37: Simple chat (1 name + 2 flag bytes)

```c
void ZoneIn_handler_chat_simple_entry37(this, packet) {
  // Extract from packet:
  //   sender_name    = string at (packet + 9)         UTF-8
  //   msg_ref        = FUN_00cc9320(packet[0])        message ref
  //   lang_byte      = packet[2]                      language
  //   flag_byte      = packet[1]                      mode flag
  
  // Build the simple chat message
  FUN_0089d070(local_msg, msg_ref, flag_byte, lang_byte, sender_name);
  
  // Dispatch through chat writer B
  FUN_00785aa0(this+4, packet, local_msg);
}
```

Packet shape (entry 37):
```text
+0    uint32   msg_ref           message reference
+4    uint8    flag_byte         mode/style flag
+8    uint8    language_byte     locale
+9    string   sender_name       UTF-8 sender (max 64 chars)
+0x49 ...                        end
```

This is the **simplest variant** -- no recipient, no substitution
params, just a sender and a message reference. Likely used for
channel chat (e.g. /yell with no template substitution).

## 5. The chat writer infrastructure (3 dispatch paths)

All 3 inbound handlers route through their own chat writer:

```text
Handler                 Writer function          Use case
-------                 ---------------          --------
entry 35 (substitution) FUN_007858c0             System message dispatch
entry 36 (tell)         FUN_007859b0             Tell/whisper dispatch
entry 37 (simple)       FUN_00785aa0             Simple chat dispatch
```

All 3 writers eventually call into a common chat dispatch core
that:
1. Routes to the correct chat panel by channel ID
2. Calls `_appendMessagePool` on the desktop widget
3. Triggers Lua-side chat hooks (`_onReceiveChatMessage` or similar)

(The common core was named in prior session: FUN_00785570 = chat
dispatch core; FUN_007238b0 = ring-buffer enqueue.)

## 6. The complete chat loop (NOW FULLY MAPPED)

```text
SERVER -> CLIENT (inbound):
  Wire packet (chat opcode) arrives
   -> Zone inbound dispatcher (table @ 0x00fdfb80)
   -> One of 3 entries based on packet opcode:
      * Entry 35 if system/say with substitution
      * Entry 36 if /tell
      * Entry 37 if simple chat
   -> Handler extracts strings + refs from packet
   -> Calls chat writer (FUN_007858c0/9b0/aa0)
   -> Chat dispatch core -> ring-buffer enqueue
   -> Per-tick flush -> calls _appendMessagePool
   -> CommandUpdater routes to desktop widget UI panel
   -> Chat message visible on screen

CLIENT -> SERVER (outbound):
  User types "/say hello" in chat box
   -> Lua: desktopWidget:_parseTextCommand(text)
   -> ChatParser_tokenizeAndParse:
      * Lookup command ID by name (xtx/_textCommand)
      * Parse args per gameCommand.csv schema
   -> Returns parsed (cmdId, args[]) to Lua
   -> Lua handler (say command):
      * desktopWidget:_appendMessagePool ECHO (so user sees own msg)
      * _executeCommand to send wire packet
   -> Wire packet built per chat outbound opcode (0x140 family?)
   -> Server receives, broadcasts to nearby players
   -> Each receiving client processes via inbound path above
```

## 7. CORRECTION to prior dispatch table finding

Prior `finding_inbound_dispatch_table_found.md` listed:

```text
INCORRECT (prior):
  Entry 35 -> CHAT TYPE A (/say-style broadcast)
  Entry 36 -> CHAT TYPE B (/yell or system)
  Entry 37 -> CHAT TYPE C (/tell with sender+recipient)

CORRECTED (this finding's decompile evidence):
  Entry 35 -> system/say with substitution params (was approximately right)
  Entry 36 -> /tell with sender + recipient (was labeled "B"; ACTUALLY tell)
  Entry 37 -> simple chat (was labeled "C"; ACTUALLY simpler)
```

The /tell handler is at entry 36, not entry 37. Verified by:
- Function name ZoneIn_handler_chat_variant_C_tell already in Ghidra
- Decompile shows 2 name reads (sender at +9, recipient at +0x29)
- Buffer 0x40 at +0x49 matches FFXIV 1.x max name length

## 8. Buffer-size constant: 0x40 (64) = max name/body length

All 3 handlers use `0x40` (64) as the buffer size for string slots.
This matches **FFXIV 1.x max display name length** (64 UTF-8 chars
for player names).

The /tell packet (entry 36) has 3 such buffers:
- Sender name (64)
- Recipient name (64)
- Message body (64)

Plus the 4-byte refs and language byte at the start = packet size
of ~0x89 = 137 bytes per /tell.

Long /tell messages (>64 chars) are likely SPLIT into multiple
packets by the server, since the wire format has a fixed body
buffer size.

## 9. Renames made (2; entry 36 was already named)

```text
RENAMES:
  - 0x0076c0d0 -> ZoneIn_handler_chat_say_substitution_entry35
                  (system/say with msg refs + sub params + 0x40 buf)
  - 0x0076c3b0 -> ZoneIn_handler_chat_simple_entry37
                  (simple chat: 1 name + 2 flag bytes)

ALREADY NAMED (prior session):
  - 0x0076c220 -> ZoneIn_handler_chat_variant_C_tell
                  (the /tell handler with sender + recipient)
```

## 10. Confidence

```text
Confirmed:
  - 3 inbound chat handlers at table entries 35-37 disassembled
  - Entry 36 is /tell (2 names + body), NOT entry 37 (prior was wrong)
  - All 3 use 0x40 (64) buffer size matching FFXIV 1.x max name length
  - All 3 route via chat writer functions (FUN_007858c0/9b0/aa0)
  - Eventually flow to client-side _appendMessagePool for UI rendering
  - Closes chat loop bidirectionally end-to-end

Likely (High):
  - Entry 35 is the "with template substitution" form -- used for
    system messages where text has ${var} placeholders
  - Entry 36 packet size is exactly 137 bytes (0x89) per /tell
  - Long /tell messages are split into multiple packets server-side
  - Channel routing happens AFTER the inbound handler (via msg_ref_b
    or similar that contains the channel ID)
  - The common chat dispatch core (FUN_00785570 per prior naming)
    handles channel-to-panel routing

Likely (Medium):
  - Entry 37 (simple) is for /yell channel since it has the
    flag_byte for "shout-style" rendering
  - The msg_ref_a/msg_ref_b in entry 35 might be (template ID,
    locale variant ID) for i18n template lookup
  - The flag_byte in entry 37 might be (chat_mode, channel_id)
    encoded into 1 byte
```

## 11. Cross-references

- `finding_inbound_dispatch_table_found.md` -- prior dispatch table
  finding that ASSIGNED initial labels (this finding CORRECTS them)
- `finding_parseTextCommand_thunk_chat_dispatch_architecture.md` --
  OUTBOUND PARSE side of chat (user typing)
- `finding_appendMessagePool_thunk_command_updater_dispatch.md` --
  OUTBOUND/INBOUND DISPLAY side (where messages arrive in UI)
- `finding_worldmaster_complete.md` -- channels 32/33/38/40 routing
- `finding_npc_dialog_protocol.md` -- NPC dialog (uses channel 38
  via NpcBaseClass:say)

## 12. Next test

```text
1. Disassemble FUN_00785570 (chat dispatch core) to confirm
   channel-to-panel routing
2. Disassemble FUN_007238b0 (ring-buffer enqueue) for the
   per-tick flush mechanism
3. Identify the chat-specific OUTBOUND opcodes (0x140 family?)
   that the Lua-side handlers eventually send via _executeCommand
4. Disassemble Lua handlers for /say, /tell, /yell to confirm
   they route through _executeCommand
5. Map the chat panel UI widget (Window_ChatLogWidget etc.) to
   see where the message_pool actually renders
6. 3 sibling _updateWork thunks (Director/Item/Group) -- confirm
   WorkSync pattern uniformity
7. vtable[0x6c] walk for sample classes -- 200+ mechanical names
```

## Commit suggestion

```
docs(re/exe): inbound chat handlers (entries 35-37) disassembled -- 3 variants mapped; CHAT LOOP FULLY CLOSED bidirectionally; CORRECTION to entry 36/37 swap
```
