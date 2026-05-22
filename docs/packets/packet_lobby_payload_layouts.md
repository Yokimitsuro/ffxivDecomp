# Packet Spec: Lobby Inbound Payload Layouts (byte-level)

Byte-level layouts of the 5 inbound payload decoders previously
pinned in `packet_lobby_inbound.md`. Closes the wire spec for the
lobby at the byte level.

Sources (all renamed in this pass):

```text
FUN_00da4b80  LobbyClient_decode_LobbyLoginPayload    (opcode 0x0C)
FUN_00da6320  LobbyClient_decode_WorldList            (opcode 0x15)
FUN_00da4c20  LobbyClient_decode_CharacterList        (opcode 0x16)
FUN_00da4d80  LobbyClient_decode_RetainerList         (opcode 0x17)
FUN_00da64b0  LobbyClient_decode_GameLoginPayload     (opcode 0x0F)
```

Two decoders are still TBD and don't change the conclusions:

```text
FUN_00da76b0  LobbyClient_decode_ServiceLoginPayload  (opcode 0x0D)
FUN_00da79d0  LobbyClient_decode_CharaMakePayload     (opcode 0x0E)
```

## Common payload prologue for list-style packets

The four list decoders (0x0C, 0x15, 0x16, 0x17) all share an
**8-byte payload prologue** before the per-entry records:

```text
+0x00  uint32  ?                       always zero in observed paths
+0x04  uint32  ?                       always zero
+0x08  uint8   flags                   bit-test against 0xFE; if low bit
                                       only (& 0xFE == 0), CLEAR the
                                       target list first ("first batch")
+0x09  uint8   count                   number of entry records that follow
+0x0A  uint8   metadata_a              opcode-specific
+0x0B  uint8   metadata_b              opcode-specific
+0x0C  uint32  ?                       (probably padding to 0x10)
+0x10  ...     count entries           per-opcode fixed stride
```

So **the records always start at payload+0x10**. The "first batch"
bit at +0x08 controls whether the client clears its target std::vector
before merging — multi-batch lists arrive without that bit set in
subsequent packets.

## Opcode 0x0C — phase-1 session/count payload

```text
target buffer: LobbyClient+0x1C0 std::vector<LobbyLoginEntry>
entry stride : 0x48 (72 bytes)

side effects on LobbyClient:
  +0x1c  uint8  = payload+0x0A
  +0x1d  uint8  = payload+0x0B
```

Each entry is appended via `FUN_00891490((this+0x1c0), entry_ptr)`.
The exact 72-byte entry layout is TBD — this is a low-priority decoder
since the phase-1 alternative path (0x1F5) is the more common one.

## Opcode 0x15 — WORLD LIST (high priority)

```text
target buffer: LobbyClient+0x1E0 std::vector<WorldEntry>
entry stride : 0x50 (80 bytes)
```

Entry layout (deduplication keys readable directly):

```text
+0x02  uint8   world_id           (the unique world identifier;
                                   the dedup key the decoder matches on)
+0x10..+0x60   80 bytes copied as-is via 20-dword memcpy into the
               vector entry
```

So a world entry is 80 bytes; the **first byte of the payload-relative
entry** at offset +0x02 is the world id (this is the byte the decoder
walks the existing vector looking for before deciding whether to add a
new entry vs skip a duplicate).

The decoder logs `"ClearWorldList"` when the "first batch" bit fires
and the existing list is wiped.

## Opcode 0x16 — CHARACTER LIST

```text
target buffer: LobbyClient+0x1F0 std::vector<CharacterEntry>
entry stride : 0x28 (40 bytes)
```

Entry layout (only the dedup field observed):

```text
+0x04  uint8   character_id      (the dedup key; matched against
                                  existing list entries)
+0x10..+0x38   40 bytes copied as-is via 10-dword memcpy
```

A character entry is **40 bytes**. The "character_id" at +0x04 is the
key the decoder matches against existing entries (deduplication during
multi-batch arrivals).

## Opcode 0x17 — RETAINER LIST

```text
target buffer: LobbyClient+0x200 std::vector<RetainerEntry>
entry stride : 0x30 (48 bytes)

side effect:
  LobbyClient+0x200 (the "world_id index" maybe?) = payload+0x10 as
  uint16 (only when "first batch" bit is set)
```

Entry layout:

```text
+0x04  uint32  retainer_id        (or one of its world-id pair; the
                                   decoder dedups against +0x04 of
                                   existing entries)
+0x1C..+0x4C   48 bytes copied as-is via 12-dword memcpy
```

A retainer entry is **48 bytes**. The decoder also tracks an
additional list at `LobbyClient+0x1d4` (stride 0x2E0 = 736 bytes) that
it updates with the per-retainer detail block — that secondary list
seems to be a per-retainer "owning-character meta-record". Detailed
layout TBD but the **per-retainer record stride is 0x2E0 (736 bytes)**
in this companion list.

## Opcode 0x0F — game-login payload (the world handoff)

This is the **highest-impact** inbound packet for a server. It carries
all the information the client needs to switch to the world server.

```text
LobbyClient_decode_GameLoginPayload(this, payload):
  log "onGameLongReply(pRepl->ticketId="              (typo "Long" not "Login" - preserved)

  this+0x224 = Utf8String  hostname     (strncpy max 32 bytes from payload+0x58)
  this+0x278 = uint16      port         (from payload+0x56)
  this+0x27a = uint16      (zeroed)
  this+0x27c = uint32      ticket_id    (from payload+0x08)
  this+0x280 = Utf8String  identifier   (strncpy max 64 bytes from payload+0x14)
  this+0x2d4 = Utf8String  session_blob (strncpy max 32 bytes from payload+0x78)
```

So the wire payload of opcode 0x0F has this **exact layout**:

```text
+0x00  uint32   ?
+0x04  uint32   ?
+0x08  uint32   ticket_id          (-> LobbyClient+0x27c)
+0x0C  uint8[8] ?
+0x14  char[64] identifier         (max 64 B; -> LobbyClient+0x280; Utf8String dest)
+0x54  uint16   ?
+0x56  uint16   port               (-> LobbyClient+0x278)
+0x58  char[32] hostname           (max 32 B; -> LobbyClient+0x224; Utf8String dest)
+0x78  char[32] session_blob       (max 32 B; -> LobbyClient+0x2d4)
+0x98  ?
```

Payload size is at least 0x98 (152 bytes) by the offsets used.

After this decode runs, the client has everything it needs to:
1. Open a TCP socket to `hostname:port`
2. Send `identifier` + `ticket_id` as the initial auth on the new
   socket
3. Use `session_blob` as the per-world handshake token

So the **world-server bring-up requires** (from the lobby side):
- The lobby server emits a 0x0F response with hostname, port, ticket,
  identifier and session_blob.
- The world server accepts a connection on (host, port) and verifies
  the (ticket, identifier, session_blob) tuple.

## LobbyClient struct memory map (updated)

Cross-referencing all five decoders plus the previously-pinned
`finding_lobby_flow.md` offsets:

```text
LobbyClient {
  +0x008  LobbyConnection*       (the active connection)
  +0x018  login attempt counter
  +0x01c  uint8  metadata_a      (from 0x0C payload +0x0A)
  +0x01d  uint8  metadata_b      (from 0x0C payload +0x0B)
  +0x020  session key/token       uint32
  +0x028  last activity timestamp
  +0x044  setup op queue
  +0x0b0  credential A            Utf8String
  +0x104  credential B            Utf8String
  +0x1a8  login op queue
  +0x1c0  std::vector<LobbyLoginEntry>   entries 0x48 (72) B each
  +0x1d0  ? (Utf8String? slot identity?)
  +0x1d4  std::vector<RetainerDetail>    entries 0x2E0 (736) B each
  +0x1e0  std::vector<WorldEntry>         entries 0x50 (80) B each
  +0x1f0  std::vector<CharacterEntry>     entries 0x28 (40) B each
  +0x200  std::vector<RetainerEntry>      entries 0x30 (48) B each
  +0x224  Utf8String  world_server_host
  +0x278  uint16      world_server_port
  +0x27a  uint16      (zero)
  +0x27c  uint32      ticket_id
  +0x280  Utf8String  identifier         (64 B max)
  +0x2d4  Utf8String  world_session_blob  (32 B max)
  +0x330  ? (passed to LobbyLoginOperationStep ctor)
}
```

This **supersedes** the earlier offset guesses in
`finding_lobby_flow.md`:

- The earlier "world list at +0x1d0" was wrong by one slot. Actual is
  +0x1e0.
- The earlier "character list at +0x1e0" was wrong. Actual is +0x1f0.
- The earlier "retainer list at +0x1f0" was wrong. Actual is +0x200.
- The "slot/identity info at +0x200" doesn't exist as a single 16-byte
  field; the layout there is the std::vector<RetainerEntry>.
- The world-server host/port/ticket/identifier live FAR beyond the
  list region, at +0x224..+0x2d4.

## Assessment

```text
Confirmed:
  - All list-style inbound packets share an 8-byte prologue with a
    "first batch" bit and a count byte.
  - World entries are 80 B; character entries are 40 B; retainer
    entries are 48 B (with a 736-B companion record per retainer).
  - Opcode 0x0F (game-login payload) carries: ticket_id (uint32 at
    +0x08), port (uint16 at +0x56), 64-byte identifier (at +0x14),
    32-byte hostname (at +0x58), 32-byte session blob (at +0x78).

Likely (High):
  - The dedup keys (world_id at entry+0x02; character_id at
    entry+0x04; retainer_id at entry+0x04) are the canonical id
    fields the server-side authority uses. They are uint8 in the
    payload header but the data probably extends in the per-entry
    record bytes -- the dedup just keys on the leading byte.
  - The +0x1d0 slot on LobbyClient (between session blob and
    retainer-detail list) is a single Utf8String -- likely the
    user's account identifier echoed back from the server, since
    none of the list decoders touch it.

Likely (Medium):
  - The 736-byte retainer-detail records at +0x1d4 contain
    per-retainer inventory metadata (item counts, slot rosters)
    rather than just "name + id". 736 B is too big for a name
    record and too small for full inventory; matches a "retainer
    summary" packet that includes equipment overview.

Speculative:
  - The 32-byte session blob in opcode 0x0F is the value the world
    server uses to short-circuit re-authentication (i.e. the
    client just presents it and the world server skips a fresh
    cred check). This is the same shape SquareEnix used in later
    FFXIV builds.

Next test:
  - Decompile FUN_00da76b0 (decode_ServiceLoginPayload) and
    FUN_00da79d0 (decode_CharaMakePayload) for the remaining two
    inbound opcodes (0x0D and 0x0E sub-ops).
  - Find any inbound packet that populates LobbyClient+0x1d0 (the
    one untouched slot) -- it must come from somewhere in the
    incoming chain.
  - Decompile the FUN_00da8ed0 helper used by decode_GameLoginPayload
    -- it is the "Utf8String-from-fixed-buffer" copier and probably
    contains the strncpy-with-nul-terminator-detect logic.

Commit suggestion:
  docs(packets): pin lobby inbound payload byte layouts (5 decoders)
```

## Server implication (final consolidation)

A minimal compatible lobby server now has **byte-level field
specifications** for the most important inbound responses:

```text
phase 2 world list (opcode 0x15):
  send 8-byte prologue (flags=1 for first batch; count=N)
  send N * 80-byte WorldEntry records starting at payload+0x10
  each record: world_id at +0x02; up to ~78 B of additional fields TBD

phase 2 character list (opcode 0x16):
  same prologue
  N * 40-byte CharacterEntry records; character_id at +0x04

phase 2 retainer list (opcode 0x17):
  same prologue + uint16 at +0x10 (world_id this list belongs to?)
  N * 48-byte RetainerEntry records; retainer_id at +0x04

phase 3 world handoff (opcode 0x0F):  -- THE CRITICAL ONE
  +0x08  ticket_id (uint32)
  +0x14  identifier (64 B; null-terminate or strncpy semantics)
  +0x56  port (uint16)
  +0x58  hostname (32 B)
  +0x78  session_blob (32 B)
  total payload >= 0x98 (152 B)
```

These are enough to drive the client end-to-end through the lobby
to the world handoff. The remaining list field layouts (78 B per
WorldEntry, 36 B per CharacterEntry, 44 B per RetainerEntry) are
the next refinement needed; they probably include world name,
character name, retainer name, GC, last-login timestamp etc.
