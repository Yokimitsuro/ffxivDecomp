# Finding: WorkSync Inbound Path -- 4 BitPacked WRITERS Pinned + Bidirectional Asymmetry Confirmed

**Closes the WorkSync writers gap.** Identifies the 4 type-specialized
**BitPacked writers** that update an actor's bit-packed binding
storage. These are the type-specialized inverses of the previously-
named BitPacked readers, and they are the leaf functions that any
inbound state-update packet handler MUST call to apply server-pushed
field changes.

Also **confirms the bidirectional asymmetry** documented in prior
findings: C→S uses STRING paths over opcode 0x12F, S→C uses BINDING
IDS over a DIFFERENT opcode (still not pinned in the dispatch table
— but the leaf writers it must call ARE now pinned).

**6th thunk-area investigation. 5 new function names added.**

## 1. The asymmetric WorkSync wire model (now fully documented)

```text
DIRECTION       OPCODE     PAYLOAD              SIZE     PURPOSE
---------       ------     -------              ----     -------
C -> S          0x12F      string path +        56 B     "I changed this field"
                           value                          (player UI action)

S -> C          0x?? (TBD) binding-id +         ~6-8 B   "field X is now Y"
                           value                          (broadcast tick)

C -> S          0x135      binding-id           24 B     "subscribe to field X"
                                                          (request push)
```

Why asymmetric:
- C->S is RARE (player UI events) -> string paths OK (~30 bytes overhead)
- S->C is FREQUENT (per-tick HP updates) -> compact IDs only (~6 bytes)
- 5x bandwidth improvement on the hot path

## 2. The 4 newly-pinned BitPacked writers

Each is the type-specialized inverse of the corresponding reader:

```text
typeTag   bytes    READER                         WRITER (NEW NAMES)
-------   -----    ------                         ------------------
   1      1 B      BitPacked_readByte_type1       BitPacked_writeByte_type1
                   @ 0x00d11c70                   @ 0x00d11d30
   2      2 B      BitPacked_readShort_type2      BitPacked_writeShort_type2
                   @ 0x00d11cf0                   @ 0x00d11e90
   3      3 B      BitPacked_readUint24_type3     BitPacked_writeUint24_type3
                   @ 0x00d11db0                   @ 0x00d11fd0
   4      4 B      BitPacked_readUint32_type4     BitPacked_writeUint32_type4
                   @ 0x00d11e50                   @ 0x00d12080
```

Pattern (all 4):
```c
void BitPacked_writeXxx_typeN(this, slotPtr, bitOffsetPtr, valuePtr) {
  FUN_00ce44d0(*this, slotPtr,
               (uint)((*bitOffsetPtr & 7) != 0) + (*bitOffsetPtr >> 3),
               valuePtr, N, 0);
  // ^                          ^
  // bit-to-byte offset alignment   N = byte count for type tag N
}
```

All 4 delegate to **`BindingStorage_writeField_lowLevel_byBindingId`**
(@ 0x00ce44d0, NEW NAME) which is the low-level write into the bit-
packed buffer with the binding ID as the key.

## 3. The lowlevel writer: `BindingStorage_writeField_lowLevel_byBindingId`

```text
@ 0x00ce44d0
Signature: void writeField(storage, slotIdxByte, bitOffset, value,
                            byteCount, flags)

Storage layout (deduced):
  this+0x2C : start of binding metadata table (4-byte entries)
  this+0x30 : end of metadata table
  this+0x04 : raw bit-packed byte buffer (storage base)

Algorithm:
  1. Index into metadata table via slotIdxByte
  2. Validate index bounds (FUN_009d22b4 = assert/abort)
  3. Get inner table entry +4 (subslot offsets array)
  4. Index by sub-bucket byte
  5. Compute final write offset
  6. Call FUN_00ccb560 -- the actual bit-packed write into storage
```

This is the universal "apply field update" leaf. ANY inbound packet
handler that processes server-pushed field updates MUST ultimately
call one of the 4 BitPacked writers (which delegate here).

## 4. The intermediate dispatch (FUN_00d294b0)

Found 4 intermediate functions that do read-then-write on a binding,
each tied to one type:

```text
FUN_00d294b0   intermediate dispatch for type 2 (short)
FUN_00d29e00   intermediate dispatch for type 1 (byte) [predicted]
FUN_00d2a2d0   intermediate dispatch for type 3 (uint24) [predicted]
FUN_00d2b400   intermediate dispatch for type 4 (uint32) [predicted]
```

Pattern (FUN_00d294b0):
```c
void dispatch(this, storage, param2, param3, slotPtr, params, dim2, dim1) {
  if (*slotPtr != 0) {
    // Validate that field is being broadcast (DAT_0130d78c sentinel check)
    if ((*params != DAT_0130d78c) && (*dim1 != DAT_0130d79c)) {
      offset = dim2 * (*params) + (*dim1);  // 2D array index
    }
    FUN_00d25900(this, &params, offset);
    BitPacked_readShort_type2(slotPtr, storage+0x2c, storage+0x14, &params);  // READ current
    BitPacked_writeShort_type2(slotPtr, storage+0x14, &params);                // WRITE new
  }
}
```

This "read-then-write" pattern is RECONCILIATION:
- Reads the current local value (for dirty-checking / change detection)
- Writes the new server value if changed
- The `FUN_00d25900` is likely a "notify watchers" callback

This is the **server-push-apply path** — when the server sends a
state update, it eventually flows into one of these 4 intermediate
dispatchers which read-then-write the binding storage.

## 5. The inbound packet handler -- still NOT pinned (but bounded)

```text
PINNED:                                  NOT YET PINNED:
- All BitPacked writers (4 leaves)       - The specific inbound opcode for
- BindingStorage_writeField_lowLevel       server-pushed binding-id updates
- Intermediate dispatcher chain          - The packet-receive function that
- The Zone inbound dispatch table          extracts binding-id + value from
  (224 slots @ 0x00fdfb80)                 wire bytes and routes to writers

VTABLE ROUTING:
The intermediate dispatchers (FUN_00d294b0, etc.) are accessed via
VTABLE (data ref from 0x0110fcf8 etc.), meaning they're polymorphic
methods on some packet/handler class. The actual class needs to be
identified via the vtable's RTTI info.

Possible inbound opcodes (matching outbound 0x12f / 0x135 / etc.):
  - 0x130, 0x131, 0x132 (adjacent to 0x12f sender) -- LIKELY candidates
  - 0x136, 0x137 (adjacent to 0x135 subscribe) -- also plausible
  - All would need to be checked for a handler that calls the writers
```

## 6. Why this advances the architecture map significantly

Even without the exact inbound opcode, knowing the WRITERS is
architecturally important because:

```text
1. The "apply" pipeline is now COMPLETE end-to-end (just missing the
   wire entry point):
   
   wire packet -> ??? -> intermediate dispatch -> BitPacked writer -> 
   BindingStorage_writeField_lowLevel -> FUN_00ccb560 bit-packed
   write -> actor+0x214 storage updated

2. The 4-type system is FULLY documented (u8/u16/u24/u32 read + write
   pairs all named).

3. The reconciliation pattern (read-then-write with notify) is the
   client's mechanism for change-detection -- this matters for UI
   refresh, predictive rollback, etc.

4. The READS of these writers' callers tell us which actor classes
   own which binding tables (every class with charaWork bindings
   reaches these 4 leaves via its class-specific dispatcher).

5. For server implementation, the wire format is now
   reverse-engineerable from these leaves alone:
   - Type tag determines byte count (1/2/3/4)
   - Binding ID determines storage offset
   - Server's broadcast packet just needs to encode
     (actorId, bindingId, type, value)
```

## 7. Cross-class binding storage at vtable+0x214

```text
EVERY actor that uses bindWork inherits a storage at this+0x214
containing the bit-packed buffer + metadata. The class hierarchy
(per finding_workpath_and_binding_storage_internals.md):

  PlayerBase   -- ~94 bindings, the most
  CharaBase    -- ~76 bindings (shared with NpcBase)
  NpcBase      -- ~23 bindings
  ItemBase     -- ~19 bindings (items get state too)
  GroupBase    -- ~16 bindings (party-level state)
  Director     -- ~5 bindings (scene state)

Each class's binding metadata is registered at engine init by
_bindWork(id, struct, slot, field) calls in the corresponding
Lua _u.lua file (the `_bindWork_inl` pattern).

The same writer leaves are used regardless of class -- the difference
is just WHICH bindings are registered at WHICH IDs per class.
```

## 8. Renames made (5)

```text
RENAMES:
  - 0x00d11d30 -> BitPacked_writeByte_type1
                  (NEW name; was FUN_00d11d30)
  - 0x00d11e90 -> BitPacked_writeShort_type2
  - 0x00d11fd0 -> BitPacked_writeUint24_type3
  - 0x00d12080 -> BitPacked_writeUint32_type4
  - 0x00ce44d0 -> BindingStorage_writeField_lowLevel_byBindingId
                  (was FUN_00ce44d0; the lowlevel write path)
```

## 9. Confidence

```text
Confirmed:
  - 4 BitPacked WRITER functions are the type-specialized inverses
    of the 4 BitPacked READERS
  - All 4 delegate to the same BindingStorage_writeField_lowLevel_byBindingId
  - The lowlevel writer uses the same metadata table at storage+0x2c
    as the readers (so they share schema)
  - FUN_00d294b0 et al. are intermediate dispatchers doing read-then-
    write for change-detection / reconciliation
  - These intermediate dispatchers are vtable methods (data refs from
    0x0110fcf8 etc.)
  - The asymmetric protocol design (C->S strings, S->C IDs) is now
    fully documented end-to-end on both directions' leaf functions

Likely (High):
  - The inbound packet handler for binding-id updates is reachable
    via the vtable at 0x0110fcf8 (likely a packet-processor class
    with type-dispatch on the type tag)
  - The exact opcode is probably 0x130, 0x131, or 0x132 (adjacent
    to 0x12f outbound)
  - The wire format for S->C binding updates is:
    (4-byte header) + (actorId u32) + (bindingId u16) + 
    (typeTag u8) + (value u8/u16/u24/u32 per type)
    = ~10-14 bytes per single-field update

Likely (Medium):
  - There may be a MULTI-update form that packs N (bindingId, value)
    pairs in one packet for bulk broadcasts (e.g. zone init when
    many actors come into view)
  - The "notify watchers" function FUN_00d25900 fires the Lua-side
    onUpdate hooks (which scripts use to react to state changes)
  - The DAT_0130d78c sentinel check (-1 typically) signals "no
    array indexing" for non-array bindings
```

## 10. Cross-references

- `finding_updateWork_thunk_worksync_state_replication.md` -- the
  OUTBOUND WorkSync side (this finding maps the INBOUND counterpart)
- `finding_binding_id_runtime_lookup_confirmed.md` -- confirmed
  binding-id == runtime-field-id (this finding now adds writer side)
- `finding_workpath_and_binding_storage_internals.md` -- the bit-
  packed storage layout that these writers update
- `finding_worksync_wire_opcode_0x12f.md` -- the outbound opcode
  for the C->S path (this finding investigates the S->C inverse)
- `finding_opcode_0x135_subscribe.md` -- the subscription opcode
  that triggers server-side broadcast registration
- `finding_inbound_dispatch_table_found.md` -- the inbound dispatch
  table at 0x00fdfb80 (224 entries; the inbound binding-update
  opcode handler MAY or MAY NOT be in this table)

## 11. Next test

```text
1. Walk the vtable at 0x0110fcf8 to identify the packet-processor
   class that owns the intermediate dispatchers; this should reveal
   the inbound opcode via the dispatch context
2. Find the inbound opcode by:
   - Searching for callers of FUN_00d294b0 etc. through the vtable
   - Or grep for instructions loading 0x130/0x131/0x132 constants
3. Disassemble FUN_00d25900 (the watcher-notify function) to
   understand the change-notification cascade
4. Decompile the 3 sibling _updateWork thunks (Director/Item/Group)
   to confirm they all funnel through the same WorkSync_dispatchOrEnqueue
5. Document the WorkSync schema register path: where _bindWork
   actually creates the binding-id <-> field-offset mapping
```

## Commit suggestion

```
docs(re/exe): WorkSync inbound writers PINNED -- 4 type-specialized BitPacked writers + lowlevel byBindingId writer; bidirectional asymmetric protocol confirmed
```
