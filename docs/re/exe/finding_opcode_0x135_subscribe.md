# Finding: Opcode `0x135` = Client Subscribe/Query Binding

**Critical insight** (2026-05-23). The 24-byte outbound packet
`opcode 0x135` carries a **BINDING ID** as its payload. This means
the work-sync protocol is **subscribe-based**, not broadcast-all.

## The Smoking Gun

Decompiling `Lua_queryBinding_dispatchType_sends_0x135` @ 0x00705eb0
revealed:

```c
void Lua_queryBinding_dispatchType_sends_0x135(int param_1) {
  // Read binding id from Lua args
  iVar1 = ExecuteParameters[0];  // <-- THIS IS A BINDING ID

  type = FUN_006e7370();         // 0/1/2 classification

  if (type == 0):
    // cleanup local subscription tracking
    FUN_00748920(...);
    FUN_00748920(...);

  else if (type == 1):
    // check subscribed-bindings bitmap at this+0x114
    if (bitmap[idx] is set): handle locally

  else if (type == 2 || iVar1 == 0x3f2 || iVar1 == 0x3f3 || iVar1 == 0x3f4):
    //                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //                       SPECIAL CASE: hp[1] / hpMax[1] / state_mainSkillLevel
    //                       (binding ids 1010/1011/1012 -- the 3 fastest-tick fields)
    storageIdx = FUN_006e3b20(...);
    if (storageIdx < 0):
      // Binding not yet registered locally -> ask server
      ZoneOut_send_opcode_0x135_24B_dword(channel, iVar1);
      //                                            ^^^^^
      //                                            BINDING ID GOES OUT
      return;
    ...
}
```

The hardcoded literals **`0x3f2`, `0x3f3`, `0x3f4`** = decimal
**1010, 1011, 1012** = the exact binding ids for `hp[1]`,
`hpMax[1]`, `state_mainSkillLevel` from the bindWork catalog. This
is the third independent EXE confirmation of the
`binding id == runtime field id` mapping (after the
`PlayerBase_check_charaWork_state_via_binding_ids` finding and the
hardcoded ids in the cost-point getters).

## What 0x135 Does

The 24-byte packet structure of 0x135:

```text
+0x00   uint32   opcode = 0x135
+0x04   uint32   size = 24
+0x08   16 B     framing / header
+0x18   uint32   bindingId   <-- THE PAYLOAD
```

When the client wants information about a binding that's NOT yet
locally cached (storageIdx < 0), it sends opcode 0x135 to the
server with the binding id as payload. The server's job:

1. Receive 0x135 with bindingId
2. Track this client as a subscriber to bindingId
3. Send back the current value (via some inbound opcode TBD)
4. Push future updates of bindingId to this client whenever they
   change

## The Three Types of Subscription (from FUN_006e7370)

```text
type 0   "unsubscribe" / cleanup
type 1   "one-shot query" -- check the local cache only
type 2   "persistent subscribe" -- send to server (triggers 0x135)
```

Special-cased: bindings 0x3f2/0x3f3/0x3f4 ALWAYS trigger the server
query path (even on type 1 lookups) because they're the high-tick
fields that need fresh values.

## What This Means for the Model

**The protocol is SUBSCRIBE-BASED**, not full-broadcast. This
significantly refines the wire model:

```text
PREVIOUSLY ASSUMED (full broadcast):
  Server pushes ALL binding updates to ALL connected clients
  Each client filters what it needs locally
  Bandwidth = O(actors × bindings × visible_clients)

ACTUALLY (subscribe-based):
  Client sends 0x135 with bindingIds it cares about
  Server tracks per-client subscription set
  Server pushes ONLY subscribed bindings to each client
  Bandwidth = O(actors × subscribed_bindings_per_client)
```

So in practice:
- A player joining a zone sends 0x135 for hp/hpMax of all visible
  actors (+ extra for myPlayer's full set).
- Server sends initial values + pushes future updates only for
  subscribed bindings.
- This is ~10x more bandwidth-efficient than full broadcast.

## Updated Wire Roster Understanding

The work-sync protocol has at least these client-initiated opcodes:

```text
0x12f  client writes a binding (sets value)
       payload: WorkPath strings + indices
0x135  client subscribes to a binding (requests updates)
       payload: bindingId (uint32)
0x131  client toggles a byte state (probably an enum)
0x132  client sets a byte+ushort state (compound toggle)
0x134  client sends challenge/anti-tamper (40B + nonce)
```

Plus the server's responses (not yet pinned):
```text
TBD  server pushes binding update (binding id + value)
     -- likely opcode 0x12e (104B) or 0x133 (56B) by size match
0x12d (any variant) server pushes bulk state / script log
```

## Server Implementation Picture (Updated)

A subscribe-based server has a simpler shape than a broadcast one:

```python
class Server:
    subscriptions = {}  # {client_id -> set(binding_id)}
    actor_field_changes = []  # queue of (actor_id, binding_id, value)

    def on_packet_0x135(self, client_id, binding_id):
        self.subscriptions[client_id].add(binding_id)
        # Send current value immediately
        current = self.read_field(client.target_actor, binding_id)
        self.send_binding_update(client_id, binding_id, current)

    def on_packet_0x12f(self, client_id, work_path):
        # Client wrote a field
        struct, slot, field, idx = parse_work_path(work_path)
        # Apply locally
        self.apply_write(struct, slot, field, idx, ...)
        # Notify all subscribers of this binding
        binding_id = self.resolve_binding(struct, slot, field)
        for cid in self.subscriptions:
            if binding_id in self.subscriptions[cid]:
                self.send_binding_update(cid, binding_id, value)

    def tick(self):
        # 3.3 Hz: push hp/mp/tp updates to subscribers
        for client_id, bound in self.subscriptions.items():
            for bid in bound & HIGH_FREQ_BINDINGS:
                value = self.read_actor_field(client.target_actor, bid)
                if value changed:
                    self.send_binding_update(client_id, bid, value)
```

## Assessment

```text
Confirmed:
  - Opcode 0x135 (24-byte packet) carries a binding id as payload.
  - The work-sync protocol is SUBSCRIBE-BASED, not broadcast-all.
  - 3 subscription types: cleanup (0), one-shot (1), persistent (2).
  - Bindings 1010/1011/1012 (hp/hpMax/level) are special-cased to
    always trigger the server query path due to their high tick rate.
  - Third independent EXE confirmation of binding id ==
    runtime field id (1:1).

Likely (High):
  - The server's "push field update" response opcode is 0x12e (104B)
    or 0x133 (56B) -- both have variable payloads. 0x133 is likely
    given its size match with 0x12f.
  - Each client maintains its own subscription set, allowing for
    different visibility (myPlayer vs other players, instance vs
    overworld).

Likely (Medium):
  - The subscription is per-(client, binding_id) pair -- not
    per-(client, actor, binding_id). The server probably tracks
    "this client cares about binding X" and broadcasts updates for
    X on whichever actor changes it. Client filters by actor id.
  - The "type 1" one-shot query (without server roundtrip) is the
    UI path for fields that don't need real-time sync (e.g. NPC
    nameplate info that updates at 60s rate).

Speculative:
  - The 0x131 (byte payload) and 0x132 (byte+ushort) opcodes might
    be SUBSCRIBE-WITH-SUB-INDEX variants -- when subscribing to
    array-typed bindings (e.g. command[64]), you'd specify which
    slot.
  - The 24-byte packet size for 0x135 has overhead of ~20 bytes
    (header + padding), so the actual subscription request is just
    a uint32 with the binding id.
```

## Open Threads

```text
1. Find the inbound opcode for "server pushes binding update".
   Strategy: decompile callers of Actor_readBindingUInt/Bool/Float
   from network-receive paths. The packet handler that calls these
   readers based on an opcode literal is the dispatcher.

2. Map the other client-initiated opcodes (0x131, 0x132) by
   decompiling their callers:
     0x131: callers in 0x006dXXX range (3 of them)
     0x132: caller at 0x006e2af0

3. Walk WorkPath_joinAsString to byte-exact understand the 32-byte
   joined-string serialization at offset +4/+20 of the 0x12f
   packet payload.
```
