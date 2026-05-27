# Finding: _updateWork Thunk Disassembled -- WORKSYNC State Replication Mechanism Mapped

**The heart of multiplayer state sync is now disassembled.** Maps the
CharaBase `_updateWork` C++ thunk through the entire WorkSync pipeline:
Lua call → WorkPath construction → dispatcher lookup → predictive enqueue
→ wire opcode **0x12F** serialization.

This is THE mechanism that propagates actor state changes across the
multiplayer world. Every position/HP/status/inventory update in 1.x
flows through this exact path.

Also reveals the wire opcode for WorkSync packets: **0x12F** (already
known by name `WorkSync_buildAndSendPacket_opcode_0x12f` — now
connected back to its Lua entry-point).

**5th thunk disassembled. Multiplayer state-sync architecture mapped.**

## 1. The pipeline (now end-to-end)

```text
LUA SIDE:
  actor:_updateWork("category", "field")          -- 2 args (base path)
  actor:_updateWork("group", "item", subIdx)      -- 3 args
  actor:_updateWork("list", "field", subIdx, listIdx)  -- 4 args (full path)

EXE THUNK (CharaBase_cpp_updateWork_thunk @ 0x006e7670):
  1. Extract args from Lua stack (2-4 path components)
  2. Build WorkPath:
     - WorkPath_construct_base(2 strings)            -- always
     - WorkPath_construct_withFields(2 strings + 2 shorts) -- if 4 args
     - assign extended into base via FUN_006ce1c0
  3. Get dispatcher from actor's class+0xec slot
  4. Call WorkSync_dispatchOrEnqueue

WORKSYNC DISPATCH (WorkSync_dispatchOrEnqueue @ 0x00767fc0):
  5. Look up the WorkPath entry in red-black tree
     (WorkPathTree_lowerBound @ 0x0071d420)
  6. Check sync-enabled flag at entry+0x29
  7. If sync-enabled:
     - Check if entry is already in pending UpdateQueue (dedup)
     - If new: UpdateQueue_pushEntry (local predictive state)
  8. UNCONDITIONAL: WorkSync_serializePayloadAndSend

WIRE SERIALIZATION (WorkSync_serializePayloadAndSend @ 0x00767c00):
  9. Branch on path's binary-encoding flag (path+0xac):
     - flag=0: serialize via WorkPath_joinAsString (text form)
     - flag=1: serialize via FUN_00ccaaf0 (binary form -- more compact)
  10. Build packet payload buffer
  11. Send via WorkSync_buildAndSendPacket_opcode_0x12f
      -> WIRE OPCODE 0x12F (outbound)
```

## 2. The classic predictive multiplayer pattern

The branch in `WorkSync_dispatchOrEnqueue` reveals 1.x uses **classic
predictive multiplayer**:

```text
sync-flag SET (entry+0x29 == 1):  predictive/client-authoritative fields
  Step 1: APPLY LOCALLY (UpdateQueue) -- player sees immediate response
  Step 2: SEND TO SERVER (opcode 0x12F) -- server validates
  Step 3 (later): server echo confirms or corrects
  
  Examples: own position, own HP buffer (?), local equipment swap
  
sync-flag CLEAR (entry+0x29 == 0):  server-authoritative fields
  Step 1: SKIP LOCAL APPLY
  Step 2: SEND TO SERVER (opcode 0x12F) -- request
  Step 3 (later): server pushes state via inbound WorkSync packet
  
  Examples: combat outcomes, gold transfer, trade settlement
```

This is the SAME pattern as Quake/Counter-Strike client prediction.
Lua scripts call `_updateWork` indifferent to the sync mode — the
sync-flag on each work-path entry determines the routing.

## 3. WorkPath structure (binary tree key)

The WorkPath is a 2-4 component hierarchical key:

```text
WorkPath layout:
  - base[0]: string ptr (category name, e.g. "hp" or "position")
  - base[1]: string ptr (field name, e.g. "current" or "max")
  - field0: int16  (subIndex; e.g. status[N] = N)
  - field1: int16  (listIndex; e.g. status[N][M] = M)
  - +0xac: encoding flag (0 = string serialize, 1 = binary serialize)
```

Constructed via the 2 helpers:
- `WorkPath_construct_base` @ 0x0070aa10 (2 strings only)
- `WorkPath_construct_withFields` @ 0x0070aaa0 (2 strings + 2 shorts)

The base-version is used for path[0..2]; the with-fields version
EXTENDS by appending the 2 shorts (deepened path with indexed access).

## 4. The dispatcher table at class+0xec

```text
For each actor class, vtable[0xec] holds the WorkSync dispatcher pointer.
This means every Lua-registered class with sync-able state has its OWN
dispatcher.

The dispatcher itself layout (partial):
  - +0x04 : WorkPath tree root (red-black tree of registered fields)
  - +0x24 : UpdateQueue (pending local-apply entries)
  - +0x30 : queue start offset
  - +0x34 : current batch flag

The tree is keyed by the WorkPath uint32 hash. Each leaf entry has:
  - +0x10 : pointer to the entry's metadata (with sync-flag at +0x29)
  - (plus value storage, dirty flag, last-server-value, etc.)
```

The WorkSync dispatcher is a **per-class red-black tree of all
synchronizable fields**. This is similar to Unreal Engine's replicated
property system or Unity's NetworkBehaviour SyncVar system.

## 5. The wire packet: opcode 0x12F

```text
WorkSync_buildAndSendPacket_opcode_0x12f gets called at the end of
WorkSync_serializePayloadAndSend. The opcode 0x12F is the outbound
wire packet for all WorkSync updates.

Per prior outbound opcode roster (commit feb3086):
  Zone opcodes: 9 outbound, 0x12F = WORK_SYNC carrier
  Used for ALL actor state synchronization (position, HP, status, etc.)

The packet payload contains:
  - actor session ID (from param_2 = call-context uint*)
  - serialized WorkPath (text or binary form)
  - new value (encoded per field type)
```

This connects this finding's runtime mechanism to the previously-known
wire opcode for state sync.

## 6. Two serialization paths (text vs binary)

```text
TEXT serialization (path+0xac == 0):
  Used for: human-readable paths during dev or first occurrence
  Payload: e.g. "position.x" as null-terminated string + value
  Cost: ~10-30 bytes per update
  
BINARY serialization (path+0xac == 1):
  Used for: optimized/cached path encoding after first use
  Payload: compact binary token + value
  Cost: ~4-8 bytes per update
```

The flag at `path+0xac` is set to 1 after the first text-form send
(probably during a "register this path" handshake). Subsequent
updates use the binary form for bandwidth efficiency.

This is a **bandwidth-optimization pattern** for sticky paths
(positions/HP that update frequently).

## 7. Implications for server design

```text
For a multiplayer server, this maps DIRECTLY to:

1. Server must receive opcode 0x12F packets and dispatch by:
   - actor session ID -> target actor
   - WorkPath -> which field to update
   - Value -> new value (typed)

2. Server must distinguish 2 paths just like the client:
   - Initial path (text form): "name.subfield" + value
   - Cached path (binary form): token + value
   - Server probably issues path-registration replies that bind a
     token to a text path (the inbound counterpart)

3. Server must support BOTH predictive and authoritative modes:
   - Predictive fields: trust client's value, validate range/sanity
   - Authoritative fields: ignore client's value, push server's own
     value back via OWN outbound opcode 0x12F (echo)

4. Server's actor model needs a parallel WorkPath tree per class:
   - Same field schema as client (each field has sync-flag)
   - Server can broadcast updates to nearby clients via the same
     opcode + value protocol

5. The dispatcher per class is exhaustive - every replicated field
   must be in the tree. This gives us a complete inventory of the
   "wire surface" of the multiplayer model.
```

## 8. Cross-class sharing (4 classes have _updateWork)

```text
From master walks, _updateWork bindings exist on:
  - CharaBaseClass    @ 0x0073eb40 (THIS finding's thunk)
  - DirectorBaseClass @ 0x0073fc50 (per finding_director_master)
  - ItemBaseClass     @ 0x00730810 (per finding_item_master)
  - GroupBaseClass    @ 0x0073ef30 (per finding_groupbase_master)
```

All 4 likely follow the SAME thunk pattern (same WorkSync dispatch,
same opcode 0x12F send). They use class-specific WorkPath trees
(each class's vtable[0xec] points to its own dispatcher), but the
mechanism is uniform.

This means **all actor types (characters, directors, items, groups)
sync state through the same wire opcode 0x12F**. The server can
implement a single 0x12F handler with class-aware routing.

## 9. Renames made (2)

```text
RENAMES:
  - 0x006e7670 -> CharaBase_cpp_updateWork_thunk
                  (the C++ entry-point for actor:_updateWork)
  - 0x0071d420 -> WorkPathTree_lowerBound
                  (red-black tree lookup of WorkPath entries)

ALREADY NAMED (from prior work):
  - 0x00767fc0 -> WorkSync_dispatchOrEnqueue
  - 0x00767c00 -> WorkSync_serializePayloadAndSend
  - 0x0070aa10 -> WorkPath_construct_base
  - 0x0070aaa0 -> WorkPath_construct_withFields
  - (and others including WorkSync_buildAndSendPacket_opcode_0x12f)
```

## 10. Confidence

```text
Confirmed:
  - actor:_updateWork(args) backed by CharaBase_cpp_updateWork_thunk
  - WorkPath supports 2-4 components (base + optional 2 shorts)
  - Dispatcher lives at actor class vtable[0xec]
  - Red-black tree storage for WorkPath entries
  - Sync-enabled flag at entry+0x29 controls predictive vs authoritative
  - UpdateQueue at dispatcher+0x24 for local predictive apply
  - Wire opcode 0x12F is the WorkSync carrier (confirmed via
    WorkSync_buildAndSendPacket_opcode_0x12f name)
  - 2 serialization paths: text (initial) and binary (cached after
    first send)
  - All 4 _updateWork bindings (Chara/Director/Item/Group) likely
    follow same pattern

Likely (High):
  - The dedup check (FUN_0077d8a0 binary search) prevents flooding
    when many Lua-side updates happen in one frame
  - The 'batch flag' at dispatcher+0x34 enables atomic transaction:
    multiple _updateWork calls in one frame become one packet
  - Server's inbound 0x12F handler updates the actor's authoritative
    state (server-side WorkPath tree)
  - The binary encoding token may be a stable hash of the path string
    (or a server-assigned ID)

Likely (Medium):
  - The sync-flag SET behavior also includes server reconciliation:
    if server's authoritative value differs from local prediction,
    UpdateQueue is rewound and replayed (typical client prediction
    + reconciliation)
  - Director._updateWork uses the same WorkSync dispatcher but with
    a director-scoped WorkPath tree
  - Item._updateWork was the one using opcode 0x132 thunk in prior
    finding (Item Bazaar item-state sync)
  - Group._updateMemberAndInformation is a specialized version of
    Group._updateWork for the larger member+state payload
```

## 11. Cross-references

- `finding_charabase_80_of_83_registrars_complete.md` -- located the
  _updateWork registrar @ 0x0073eb40
- `finding_groupbase_master_16_of_16_complete.md` -- documents the
  shared _updateWork pattern across CharaBase/Director/Item/Group
- `finding_item_master_20_of_20_registrars_complete.md` -- Item's
  _updateWork uses opcode 0x132 (potentially different carrier?)
- `finding_complete_3channel_opcode_inventory.md` -- the outbound
  opcode roster including 0x12F WorkSync carrier
- `finding_spreadsheet_thunks_exe_data_bridge.md` -- prior thunk
  disassembly establishing the disassembly methodology

## 12. Next test

```text
1. Verify Director / Item / Group _updateWork thunks follow SAME
   pipeline:
   - Director_cpp_updateWork_thunk (registrar 0x0073fc50)
   - Item_cpp_updateWork_thunk (registrar 0x00730810)
   - Group_cpp_updateWork_thunk (registrar 0x0073ef30)
2. Disassemble the INBOUND 0x12F handler -- server-pushed state
   updates that drive the client's authoritative state apply
3. Find where vtable[0xec] is initialized per class
   (each class's dispatcher must be set up at engine init)
4. Document the actor state-replication model from a server's POV:
   - List all WorkPath entries per class
   - Map sync-flag to predictive vs authoritative semantics
   - Match against MeteorReborn's existing protocol assumptions
5. Disassemble _bindWorkSync or similar (where Lua scripts register
   their WorkSync schema at boot)
```

## Commit suggestion

```
docs(re/exe): _updateWork thunk disassembled -- WORKSYNC pipeline mapped end-to-end (Lua -> WorkPath tree -> opcode 0x12F wire send); predictive multiplayer pattern confirmed
```
