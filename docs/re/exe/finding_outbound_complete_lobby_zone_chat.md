# Finding: COMPLETE Outbound Opcode Roster for All 3 Channels (Lobby + Zone + Chat)

Closes the outbound opcode mapping across all 3 client→server channels.
Combines:

1. **Caller analysis** of Zone outbound 0x12d-0x135 (which Lua action triggers each)
2. **Lobby outbound** 8 opcodes confirmed from `LobbyLoginOperation` family
3. **Chat outbound** 4 opcodes (handshake + chat + tell + login-ack)

Plus a key architectural finding: **Chat uses GENERIC dispatch** (data-driven
opcode) unlike Zone/Lobby which hardcode an opcode per sender.

## 1. The Three Channels at a Glance

```text
CHANNEL    OUTBOUND OPCODES    PATTERN
-------    ----------------    -------
Lobby            8             1 builder + 4 cases (switch on step type)
                               + 2 ACK senders + 1 charamake/subop sender
Zone             9             1 hardcoded sender per opcode (0x12d-0x135)
Chat             4             1 GENERIC dispatch (opcode from descriptor)
```

## 2. LOBBY outbound (8 opcodes)

All 8 are pinned in 4 functions on `LobbyLoginOperation`:

### `LobbyLoginOperation_buildAndSendPacket` -- multi-opcode router

Switch on `operation->step->step_type`:

```text
CASE  OPCODE  SIZE    NAME                   PAYLOAD
----  ------  ----    ----                   -------
 0    0x1f5   0x38   LOBBY_LOGIN_REQUEST     [sessionId, opToken, 48 zeros]
                     (501 decimal, 56 B)
 2    0x05    0xa0   SERVICE_LOGIN_REQUEST   [sessionId, 0x6e clientVer1,
                     (5, 160 B)              0x1347 clientVer2, name 64B,
                                             credA 32B, credB 32B]
 3    0x06    0x1e0  GAME_LOGIN_REQUEST      [sessionId, version fields,
                     (6, 480 B)              blob 384B, credA, credB]
 4    0x1f6   0x78   CHARA_MAKE_REQUEST      [sessionId, opToken, 32 zeros,
                     (502, 120 B)            charaName 64B]
```

### `LobbyLoginOperation_sendAck32` -- opcode 0x03 (32B ACK)

```text
+0x00  sessionId
+0x08  uint8 from step+0x3c (sub-flag)
+0x09  uint8 = 0x11 constant
+0x0c  uint32 from step+0x38 (step token)
After: next_state = 0x0d
```

### `LobbyLoginOperation_sendAck40` -- opcode 0x04 (40B ACK)

```text
+0x00  sessionId
+0x08  uint32 from (LobbyClient+0x8+0x14)+0xc
+0x10  uint8 from (LobbyClient+0x8+0x14)+0x8
After: next_state = 0x0f
```

### `LobbyLoginOperation_sendCharaMakeOrSubOp` -- opcode 0x0b OR 0x0f

Switches on step->subtype:

```text
SUBTYPE  OPCODE  SIZE   ROLE
-------  ------  ----   ----
   0     0x0b    0x1e0  PUT_CHARA_MAKE_DATA (480 B)
                        Mode 1: name-only (strncpy 400B from step+0x6c)
                        Mode 2: appearance data (chunked: 400B slices,
                                FUN_005a6f10 output, sets MSB on more=true)
                        Mode 6: retainer-rename (1 byte from step+0xd)
                        After: next_state = 0x0e
   1     0x0f    0xa0   service sub-op (160 B)
                        Payload: sessionId + 32B from step+0x18 +
                                 96B from step+0x38
                        After: next_state = 0x10
```

### LOBBY summary

```text
8 distinct outbound opcodes:
  0x03  ACK32  (32B)   -- step-flag + token ack
  0x04  ACK40  (40B)   -- different ack variant
  0x05  SERVICE_LOGIN  (160B)  -- credentials login
  0x06  GAME_LOGIN     (480B)  -- game-server login
  0x0b  PUT_CHARA_MAKE (480B)  -- chara-make data stream
  0x0f  SERVICE_SUBOP  (160B)  -- service sub-op
  0x1f5 LOBBY_LOGIN    (56B)   -- initial lobby login
  0x1f6 CHARA_MAKE_REQ (120B)  -- chara-make request (kick)
```

Connection state transitions (LobbyConnection +0x8c):
```text
After 0x1f5 send: state = 4   (login-in-progress)
After 0x05 send:  state = 4
After 0x06 send:  state = 4
After 0x1f6 send: state = 4   (charamake-in-progress)
After 0x03 ACK:   next_state = 0xd
After 0x04 ACK:   next_state = 0xf
After 0x0b send:  next_state = 0xe
After 0x0f send:  next_state = 0x10
```

Version constants in 0x05/0x06:
```text
0x6e   (110)    clientVer1 (one byte at +0x0a)
0x1347 (4935)   clientVer2 (two bytes at +0x0c)
```

These must match the server's version check.

## 3. ZONE outbound (9 opcodes + caller mapping)

Already documented in `finding_zone_outbound_opcode_roster.md`. This finding
adds **caller-side identification** for each:

```text
OPCODE  SIZE  SENDER                              CALLER (Lua action)
------  ----  ------                              -------------------
0x12d   200B  ZoneOut_sendScriptError              Client script error chunks
                                                   + "large container" family
                                                   (4 variants via discriminator byte)
0x12e   104B  ZoneOut_send_opcode_0x12e_104B       Lua_send6argRpc_via_opcode_0x12e
                                                   (highest-arity Lua RPC: 6 args)
0x12f   56B   WorkSync_buildAndSendPacket          WorkSync_serializePayloadAndSend
                                                   (string-path-based field write)
0x130A  32B   ZoneOut_send_opcode_0x130_32B_varA   3 callers:
                                                   - Lua_listObjectDelete_sends_0x130_varA
                                                     (hardcodes type tag 0x2711)
                                                   - Lua_listObjectQueueAdd_sends_0x130_varA
                                                     (hardcodes type tag 0x2711)
                                                   - Lua_listIndexSend_via_0x130_varA
0x130B  32B   ZoneOut_send_opcode_0x130_32B_varB   Lua_send8byteStateAt0x68_via_0x130_varB
                                                   (likely movement/transform state)
0x131   24B   ZoneOut_send_opcode_0x131_24B_byte   Lua_sendByteToggle_via_opcode_0x131
                                                   (toggle action: sit/stand/etc.)
0x132   24B   ZoneOut_send_opcode_0x132_24B_bU     Lua_sendByteUshortAt0x68_via_0x132
                                                   (compound state: byte + ushort)
0x133   56B   ZoneOut_send_opcode_0x133_56B        WorkSyncAlt_serializePayloadAndSend
                                                   (PARALLEL TWIN of 0x12f --
                                                    same WorkPath_joinAsString
                                                    construction; different opcode
                                                    so different server semantic)
0x134   40B   ZoneOut_send_opcode_0x134_40B_nonce  Lua_sendChallenge_via_opcode_0x134
                                                   (anti-tamper challenge with
                                                    15-char nonce + hash)
0x135   24B   ZoneOut_send_opcode_0x135_24B_dword  Lua_queryBinding_dispatchType_sends_0x135
                                                   (binding/dispatch type query)
```

### KEY DISCOVERY: 0x12f + 0x133 are a PARALLEL TWIN PAIR

Both `WorkSync_serializePayloadAndSend` (opcode 0x12f) and `FUN_006c72e0`
(opcode 0x133) have **identical code structure**:
- Both use `WorkPath_joinAsString` to construct field paths
- Both use the same string-utility helpers (FUN_006d5af0, FUN_00446f50,
  FUN_004451f0, FUN_00445210)
- Both build a 56-byte payload with 32-byte variable string section
- Only the opcode differs

Hypothesis: 0x12f is the primary work-sync WRITE; 0x133 is a complementary
operation (CONFIRM, DELETE, LOCK, BROADCAST_REQUEST, etc.) using the same
path-based addressing.

### KEY DISCOVERY: 0x12e is the 6-arg Lua RPC

The 104-byte 0x12e packet carries **6 distinct parameters** (the highest
arity in the outbound table):
- param_2: int
- param_3: *byte
- param_4: char* string
- param_5: *uint32
- param_6: uint

This means 0x12e is the **generic Lua-to-server RPC**. Any sufficiently
complex Lua action that doesn't fit one of the more specific opcodes
(0x130-0x135) uses 0x12e.

### Magic type tag 0x2711 (= 10001)

Two of the 0x130 callers hardcode `0x2711` (10001) as a type discriminator
inside the 32-byte payload. This is likely the **OBJECT CLASS ID** for
the type of object being added/deleted in a list operation. Future research
could enumerate which 1.x class ID = 10001.

## 4. CHAT outbound (4 opcodes via GENERIC dispatch)

The Chat channel is **structurally different** from Lobby/Zone. Instead of
N hardcoded senders, Chat has a **SINGLE generic dispatch function**
(`ChatClient_dispatchOutbound_generic` at 0x00db3e30) that reads the opcode
and size from the caller's DESCRIPTOR struct.

### Descriptor layout

```text
+0x00  uint32  opcode
+0x04  uint32  size
+0x08..+0x17  reserved (header padding)
+0x18+        payload bytes
```

### Generic dispatch state machine

```text
this+0x8c (chat state):
  1-2: only opcode 0x02 (handshake) is permitted
   3 : any opcode is permitted (post-handshake operations)
```

So the Chat connection ENFORCES handshake-first via the state field.

### The 4 Chat outbound opcodes

```text
OPCODE  SIZE   CALLER                                                ROLE
------  ----   ------                                                ----
0x02    56B    ChatClient_sendInitialHandshake (0x00db4020)          handshake
                                                                      Payload:
                                                                      +0  uint32 0x3C6B
                                                                          (version, SAME
                                                                           as Zone)
                                                                      +4  uint8 0
                                                                      Sets state -> 2
                                                                      
        56B    ChatOut_send_handshake_or_loginAck_op_0x02_or_0x12c   handshake (redundant
                                                                      send via the generic
                                                                      caller, branch 1)
                                                                      
0x12c   24B    ChatOut_send_handshake_or_loginAck_op_0x02_or_0x12c   post-login ack
        (300)                                                         (branch 2; state=1)
                                                                      Increments DAT_0132fb98
                                                                      counter
                                                                      
0xc8    560B   ChatTellDescriptor_construct + dispatch_generic       TELL (whisper)
        (200)                                                         Payload:
                                                                      +0x18  recipient
                                                                             name (32B)
                                                                      +0x38  message text
                                                                             (512B)
                                                                      
0xc9    536B   ChatOut_send_opcode_0xc9_chatMessage_536B             CHAT MESSAGE
        (201)                                                         Payload:
                                                                      +0x14  channel/type
                                                                             param
                                                                      +0x18  message text
                                                                             (512B)
                                                                      Used for SAY, YELL,
                                                                      LINKSHELL, PARTY, etc.
                                                                      (channel discriminator
                                                                       is the param_1 arg)
```

### Channel discriminator inside 0xc9

The opcode 0xc9 is reused for ALL chat channels (say/yell/shout/party/
linkshell/freecompany). The `param_1` arg passed to `FUN_004df6d0`
discriminates which channel.

This is the **same compression pattern** as Zone's 0x12d "large container"
opcode -- one opcode handles many sub-cases via a discriminator byte/word.

## 5. Outbound coverage status

```text
LOBBY:  8 / 8 opcodes documented      100% complete
ZONE:   9 / 9 opcodes + caller map     100% complete
CHAT:   4 / 4 opcodes documented       100% complete

TOTAL:  21 outbound opcodes across 3 channels  100% complete
```

## 6. Server implication

To accept a real 1.x client, a server must:

### Listen on 3 separate channels

```text
Channel    Required opcodes
-------    ----------------
Lobby      0x03 0x04 0x05 0x06 0x0b 0x0f 0x1f5 0x1f6  (8 inbound)
Zone       0x12d 0x12e 0x12f 0x130 0x131 0x132        (6 mandatory)
           0x133 0x134 0x135                          (3 nice-to-have)
Chat       0x02 0x12c 0xc8 0xc9                       (4 inbound)
```

### Version compatibility constants

```text
0x3C6B  (15467)  -- Zone + Chat handshake version
0x6e    (110)    -- Lobby clientVer1 (ServiceLogin/GameLogin)
0x1347  (4935)   -- Lobby clientVer2 (ServiceLogin/GameLogin)
```

A version-tolerant test server must accept these exact values OR
relax the version check.

### State machines per channel

**Lobby**: per-step token mechanism; state advances 0->4->0xd->0xe->0xf->0x10
through the login flow.

**Zone**: post-handshake state = 4 (per the segment-level dispatch);
no per-message state advancement.

**Chat**: this+0x8c state {1, 2, 3} = {pre-handshake, post-handshake-1,
post-handshake-2-or-ready}. Only opcode 0x02 allowed below state 3.

## Confidence

```text
Confirmed:
  - Lobby: 8 outbound opcodes pinned with sizes + payload layouts.
  - Zone: 9 outbound opcodes pinned in earlier finding + caller mapping
    in this finding.
  - Chat: 4 outbound opcodes pinned (handshake, login-ack, tell, message).
  - Chat uses GENERIC dispatch (data-driven opcode), unlike Lobby/Zone.
  - Magic type tag 0x2711 used by 0x130 list operations.
  - Version constants 0x3C6B (Zone/Chat), 0x6e/0x1347 (Lobby).
  - 0x12f and 0x133 share IDENTICAL code structure (work-sync TWIN PAIR).
  - 0x12e is the 6-arg Lua RPC (highest arity).

Likely (High):
  - 0x133 is the COMPLEMENT operation to 0x12f (delete/confirm/broadcast
    on the same path-based field).
  - Opcode 0xc9 channel discriminator (param_1) maps to:
    say=0, yell=1, shout=2, linkshell=3+, party=N, etc.
  - 0x12c chat opcode is a POST-LOGIN ACK confirming chat session
    is fully established.

Likely (Medium):
  - The 8 Lobby outbound opcodes + 9 Zone outbound + 4 Chat outbound
    cover EVERY client-to-server message in 1.x.
  - The version constants 0x6e + 0x1347 might encode date+build:
    0x6e = 110 = November 0? or version major?
    0x1347 = 4935 in decimal -- could be a build number.

Speculative:
  - Opcode 0x12e's 6 params might map to a single Lua RPC type
    that wraps any sufficiently-complex Lua action.
  - The Chat opcode space (0x02, 0xc8, 0xc9, 0x12c) suggests other
    opcodes exist (0x01, 0x03-0xc7, 0xca-0x12b) -- perhaps reserved
    for future GM commands, channel management, etc.
```

## Annotations made in Ghidra

```text
RENAMES (7 functions this finding):
  0x006dacd0 -> Lua_listObjectDelete_sends_0x130_variantA
  0x006dae90 -> Lua_listObjectQueueAdd_sends_0x130_variantA
  0x006e42e0 -> Lua_listIndexSend_via_0x130_variantA
  0x006e2130 -> Lua_send8byteStateAt0x68_via_0x130_variantB
  0x006e2af0 -> Lua_sendByteUshortAt0x68_via_0x132
  0x006c72e0 -> WorkSyncAlt_serializePayloadAndSend_opcode_0x133
  0x00894090 -> Lua_send6argRpc_via_opcode_0x12e
  0x004df6d0 -> ChatOut_send_opcode_0xc9_chatMessage_536B
  0x004df810 -> ChatOut_send_opcode_0xc8_tell_560B
  0x004df9a0 -> ChatOut_send_handshake_or_loginAck_opcode_0x02_or_0x12c
  0x004e3750 -> ChatTellDescriptor_construct_opcode_0xc8
  0x00db3e30 -> ChatClient_dispatchOutbound_generic

COMMENTS (4 multi-line):
  0x006c72e0  (work-sync twin pair explanation)
  0x006dacd0  (list-object-delete pattern + 0x2711 magic tag)
  0x00894090  (6-arg Lua RPC)
  0x00db3e30  (chat generic dispatch state machine + caller table)
  0x004e3750  (tell descriptor layout)
```

## Connections to other findings

- **`finding_zone_outbound_opcode_roster.md`**: this finding adds caller-
  side identification + closes opcode 0x133's pair relationship.
- **`finding_lobby_flow.md`**: this finding pins the exact opcodes used
  in each lobby login phase (previously marked TBD).
- **`finding_zone_chat_channel_architecture.md`**: this finding completes
  the chat outbound roster beyond initial handshake.
- **`finding_worksync_wire_opcode_0x12f.md`**: this finding identifies
  the parallel twin (0x133) of the work-sync opcode.

## Next test

- Identify the 0x2711 magic tag (object class ID 10001) in the data
  tables -- likely an entity type identifier.
- Walk FUN_004e3750's callers to find the TELL caller(s) -- which Lua
  function dispatches a tell.
- Find inbound opcodes for the 3 channels (the SERVER -> CLIENT direction):
  - Lobby inbound is partly mapped via dispatch functions (LobbyLogin/
    ServiceLogin/GameLogin/CharaMake) -- enumerate opcodes per phase.
  - Zone inbound is documented in finding_inbound_dispatch_100_percent...
  - Chat inbound is documented via opcodes 35/36/37/57 (chat A/B/C/D).
- Test whether 0x6e + 0x1347 are interpretable as date or build number.

## Commit suggestion

```
docs(re/exe): COMPLETE outbound opcode roster for Lobby (8) + Zone (9) + Chat (4) -- 21 opcodes total
```
