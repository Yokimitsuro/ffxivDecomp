# Finding: Complete 3-Channel Opcode Inventory

Consolidates the FFXIV 1.x wire opcode inventory across all three
network channels (Lobby, Zone, Chat) in both directions. Closes
the protocol-mapping work to a server-implementable state.

## Channel structure

```text
Per prior session findings (finding_ipc_channel_framing.md +
finding_packet_dispatch_by_id.md):

  3 channels x 2 directions = 6 PacketBufferTmpl classes
  - PacketBufferTmpl<LobbyProtoDown>    server -> client lobby
  - PacketBufferTmpl<LobbyProtoUp>      client -> server lobby
  - PacketBufferTmpl<ZoneProtoDown>     server -> client zone
  - PacketBufferTmpl<ZoneProtoUp>       client -> server zone
  - PacketBufferTmpl<ChatProtoDown>     server -> client chat
  - PacketBufferTmpl<ChatProtoUp>       client -> server chat

Each channel uses the SAME core dispatcher:
  ProtoChannel_dispatchPacketById @ 0x00db5300
This routes via std::map<uint, Handler*> keyed by
packet+0x18 (the segment header's target/dispatch id).

So per-channel inbound dispatch is HASH-MAP-based, not array-based.
The hash key is the dispatch id (typically an actor id, operation
step id, or similar runtime identifier), NOT the opcode itself.

The "opcode" field at packet+0 is consumed by the handler INSIDE
the dispatch (after the map lookup). For Zone, the handler is
ZoneIn_handler_dataPacket_calls_onReceiveDataPacket which then
indexes into a SECOND-LEVEL dispatch table at 0x00fdfb80 using
the opcode as an array index.
```

## LOBBY OUTBOUND opcodes (8 confirmed)

```text
OPCODE  SIZE     NAME                           PURPOSE
------  -------- ---------------------------   ---------------------------------
 0x03    32 B   LOBBY_ACK_32                   small ACK; sends step subtoken
 0x04    40 B   LOBBY_ACK_40                   another ACK with extra fields
 0x05   160 B   SERVICE_LOGIN_REQUEST          login to service (account auth)
 0x06   480 B   GAME_LOGIN_REQUEST             login to game (chara select)
 0x0B   480 B   PUT_CHARA_MAKE_DATA            character create data (chunked when full appearance)
 0x0F   160 B   SERVICE_SUB_OP                 service login sub-operation
 0x1F5   56 B   LOBBY_LOGIN_REQUEST            initial lobby login (=501 dec)
 0x1F6  120 B   CHARA_MAKE_REQUEST             chara make confirm (=502 dec)
```

All 8 opcodes built by `LobbyLoginOperation_buildAndSendPacket` and
its 4 helpers (sendAck32 / sendAck40 / sendCharaMakeOrSubOp /
sendCharaMakeOrSubOp).

Shared CONSTANTS:
```text
0x6E (110)      clientVer1?  used in SERVICE_LOGIN/GAME_LOGIN headers
0x1347 (4935)   clientVer2?  used in same headers
```

Server must accept these version values during the handshake.

## ZONE OUTBOUND opcodes (9 confirmed, all named in Ghidra)

```text
OPCODE  SIZE     NAME                                          BUILDER
------  -------- --------------------------------------------- -----------------------------
 0x12D   200 B   PACKET_TAGGED_CONTAINER                       PacketBuilder_opcode_0x12d_200B_tagged @ 0x00776760
                 (discriminator byte at +0x28; carrier for
                  Command / Talk / Emote / Push / etc.)
 0x12E   104 B   STATE_104                                     ZoneOut_send_opcode_0x12e_104B @ 0x0075e670
 0x12F   var     WORK_SYNC_UPDATE                              WorkSync_buildAndSendPacket_opcode_0x12f @ 0x0075e770
                 (binding-storage write request; payload size
                  depends on the binding being written)
 0x130    32 B   STATE_CHANGE_A / STATE_CHANGE_B               ZoneOut_send_opcode_0x130_32B_variantA/B
                 (2 variants share opcode)                     @ 0x0075e860 / 0x0075e8d0
 0x131    24 B   TOGGLE_BYTE                                   ZoneOut_send_opcode_0x131_24B_byte @ 0x0075ea50
 0x132    24 B   TOGGLE_BYTE_USHORT                            ZoneOut_send_opcode_0x132_24B_byteUshort @ 0x0075eac0
 0x133    56 B   WORKSYNC_FIELD_PUSH                           ZoneOut_send_opcode_0x133_56B @ 0x0075e950
 0x134    40 B   ANTI_TAMPER_CHALLENGE                         ZoneOut_send_opcode_0x134_40B_withNonce @ 0x0075eba0
 0x135    24 B   SUBSCRIBE_BY_BINDING_ID                       ZoneOut_send_opcode_0x135_24B_dword @ 0x0075ecd0
```

Plus a sub-variant for chunked script errors:
```text
 0x12D   var     SCRIPT_ERROR                                  ZoneOut_sendScriptError_opcode_0x12d @ 0x0076e270
                 (uses opcode 0x12d but DIFFERENT builder
                  path -- bypasses the 200B tagged builder)
```

## CHAT OUTBOUND opcodes (1 fixed + dynamic forwarder)

```text
OPCODE   SIZE   NAME                                  BUILDER
------- ------- ------------------------------------- ----------------------------------
 0x02    56 B  CHAT_INITIAL_HANDSHAKE                ChatClient_sendInitialHandshake @ 0x00db4070
               (version constant 0x3C6B same as Zone)

  any   var    CHAT_GENERIC_FORWARD                  FUN_00db3e30 @ 0x00db3e30
               (opcode + size read from message
                body; payload memcpy'd from +0x18)
```

The chat channel has only ONE FIXED opcode (the handshake). All
other outbound chat traffic flows through the GENERIC FORWARDER
(FUN_00db3e30) which takes a message struct containing the opcode
+ size + payload. So chat outbound is data-driven rather than
opcode-multiplexed.

Shared CONSTANT with Zone:
```text
0x3C6B (15467)   version constant in INITIAL_HANDSHAKE
                 -- both Zone and Chat use the same value, so a
                 server can do one version check for both
```

## ZONE INBOUND opcodes (~60 active in the second-level dispatch)

Per `finding_inbound_dispatch_two_families_and_chat_d.md` and
`finding_inbound_routers_named_opcodes_round2.md`:

Second-level dispatch table at `0x00fdfb80` (~224 entries, 4-byte
stride). Of these:
- ~60 are active (entries 0-60 cover the active range; 60+ are
  predominantly no-op tail).
- ~25 are NAMED with specific Lua hooks identified.
- Rest are classified by family but not by purpose.

Key named entries (full list in the cited findings):
```text
 0  proximity touch BEGIN  -> _onTouch (gathering / sit / raid)
 1  proximity touch END    -> _onTouch (inverse)
 2  _onMoveAtSit
 4  _onTargetChanged                       (DesktopWidget)
 8  _onInitializationClip                  (CutScene)
 9  _onShowUIClip                          (CutScene)
10  _onHideUIClip                          (CutScene)
11  _onShowWidgetClip                      (CutScene)
13  _onOpenUIClip                          (CutScene)
20  _onPreWarp                             (DesktopWidget)
21  _onPostWarp                            (DesktopWidget)
22  vtable slot 21 -- NO-OP for UserDataReceiver
23  vtable slot 22 -- APPEND_PAYLOAD       (UserDataReceiver)
24  vtable slot 23 -- RESOLVE_ACTOR        (UserDataReceiver)
25  vtable slot 24 -- NO-OP for UserDataReceiver
26  vtable slot 25 -- NO-OP for UserDataReceiver
35  chat A         -> Command-update notification (single name)
36  chat B         -> Command-update notification (40-char name)
37  chat C         -> Command-update notification (recipient targeted = /tell-style)
38  _onReceiveDataPacket (generic 192-byte data)
57  chat D         -> Command-update notification (variant D)
60  _onFinalize    (actor destroyed)
```

## LOBBY/CHAT INBOUND opcodes (not enumerated; per-handler)

Lobby and Chat channels do NOT use a second-level dispatch table.
Instead they use the channel-level `ProtoChannel_dispatchPacketById`
hash-map dispatcher with one Handler per inbound opcode/operation.

Per-handler enumeration requires walking each `Handler` registered
in the channel's std::map, which is set up at channel-init time
elsewhere in the binary (not yet enumerated).

For server bring-up:
```text
Lobby inbound: server needs to respond to opcodes 0x03 / 0x04 / 0x05
               / 0x06 / 0x0B / 0x0F / 0x1F5 / 0x1F6 (Lobby outbound
               opcodes are paired with INBOUND ack/result packets).

Chat inbound:  server needs to respond to opcode 0x02 (handshake ack)
               and push chat messages via the generic forwarder shape.

Zone inbound:  server needs to push the documented Zone inbound
               opcodes (60+ active in the second-level dispatch table)
               for events the client expects.
```

## Server implementation summary

```text
TO IMPLEMENT A FFXIV 1.x COMPATIBLE SERVER, MINIMAL OPCODES:

PHASE 1 -- Lobby flow:
  Listen on Lobby channel. Handle inbound:
    0x1F5 LOBBY_LOGIN_REQUEST -> respond with login ack (TBD opcode)
    0x05  SERVICE_LOGIN_REQUEST -> respond with chara list (TBD)
    0x06  GAME_LOGIN_REQUEST -> respond with world handoff
    0x0B  PUT_CHARA_MAKE_DATA -> accept chara create chunks
    0x1F6 CHARA_MAKE_REQUEST -> respond with creation result

PHASE 2 -- Zone connection:
  Send chat handshake (opcode 0x02) and zone handshake (Zone's
  INITIAL_HANDSHAKE, opcode TBD; uses same version 0x3C6B).
  Accept client subscriptions (opcode 0x135) for binding ids.

PHASE 3 -- Player init:
  Push WorkSync updates (opcode 0x12F) populating playerWork
  fields for the spawning actor.
  Push initial _onTouch / _onSpawn events via the Zone inbound
  dispatch table.

PHASE 4 -- Gameplay:
  Process Zone outbound 0x12D (commands via discriminator byte)
  and respond with Command-update notifications via inbound
  chat-block opcodes 35/36/37/57.
  Push proximity events (opcodes 0/1) when player crosses
  interaction-point boundaries.
  Handle world state changes via opcodes 0x12E-0x135.

The 3-channel design is consistent throughout:
  - Lobby is short-lived (handshake only).
  - Zone carries gameplay traffic.
  - Chat carries text messages (with one fixed handshake and a
    generic forwarder).
```

## Confidence

```text
Confirmed:
  - 8 Lobby outbound opcodes (full payload sizes documented).
  - 9 Zone outbound opcodes (named in Ghidra).
  - 1 fixed Chat outbound opcode + dynamic forwarder.
  - Channel dispatcher uses std::map<uint, Handler*> at 0x00db5300.
  - Zone has a SECOND-LEVEL dispatch table at 0x00fdfb80 for
    its ~60 active inbound event types.
  - Shared version constant 0x3C6B between Zone and Chat handshakes.
  - Shared version constants 0x6E and 0x1347 in Lobby login headers.

Likely (High):
  - Lobby and Chat inbound dispatch is per-Handler via the std::map;
    there is no second-level array-based table for them.
  - Each Lobby outbound has a paired inbound ack/result the server
    must send; mapping these requires walking ChatClient /
    LobbyClient receivers (out of scope here).
  - The generic Chat forwarder allows arbitrary message types, so
    the server's chat traffic uses message-type bytes embedded in
    the payload rather than distinct opcodes.

Likely (Medium):
  - The 0x6E and 0x1347 constants likely represent client major
    and minor version (110 = 0x6E might be patch revision; 0x1347
    might be build number).
  - The 224-entry Zone inbound dispatch table is configured at
    actor-class-init time and is fixed per actor type. Different
    actor types (Player vs NPC vs WorldMaster) may install
    different handler sets into the same table.

Speculative:
  - The Lobby handshake constants 0x6E (110) match the patch
    "1.10" if interpreted as "1.<patch_revision>" where 0x6E = 110.
    But 1.23b is the client patch, so this might be a fixed handshake
    legacy from an earlier protocol version. Server must accept
    these values regardless.
```

## Next test

- Walk the std::map population code in each channel's init function
  to enumerate the Lobby/Chat inbound Handler registrations.
- Read ChatProtoChannel's per-opcode handler table to identify the
  message-type bytes used in the generic forwarder.
- Cross-reference Lobby outbound 0x05 / 0x06 / 0x1F5 / 0x1F6 with
  the corresponding inbound ack opcodes (the *param_4 = 0xd/0xe/0xf
  state values in the senders likely correspond to expected
  inbound opcodes).

## Commit suggestion

```
docs(re/exe): complete 3-channel opcode inventory (Lobby 8 + Zone 9 + Chat 1 outbound)
```
