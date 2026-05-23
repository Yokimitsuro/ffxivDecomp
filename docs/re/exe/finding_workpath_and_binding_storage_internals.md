# Finding: WorkPath Struct Layout + Binding Storage is Bit-Packed

Two adjacent EXE findings from the same Ghidra session (2026-05-23):

1. The `WorkPath` struct that travels inside the work-sync packet
   payload has a fixed C++ layout — 176 bytes per instance, two
   `std::string` fields + 2 field indices + flags.

2. The actor-side binding storage uses a **bit-packed layout** with
   4 type tags (u8/u16/u24/u32), a metadata table per binding, and a
   vtable-dispatched read/write API.

## Part 1: `WorkPath` Struct Layout

Pinned by decompiling both constructors:

```text
WorkPath_construct_base       @ 0x0070aa10
WorkPath_construct_withFields @ 0x0070aaa0
```

Both call `FUN_00447200` (std::string copy assignment) twice — once
for structName at +0x00, once for slotCategory at +0x54. The
`_withFields` variant additionally writes the field indices at
+0xa8/+0xaa and sets the `hasFields` flag at +0xac.

```text
WorkPath struct (176 bytes / 0xb0):

offset  type            field             notes
------  --------------  -------------     -----------------------------
+0x00   std::string     structName        ~84 bytes (SBO + heap);
                                          e.g. "charaWork", "playerWork"
+0x54   std::string     slotCategory      ~84 bytes (same shape);
                                          e.g. "parameterSave",
                                          "battleSave", "eventTemp"
+0xa8   uint16          fieldIdx0         0 for base form
+0xaa   uint16          fieldIdx1         0 for base form (sub-idx)
+0xac   uint8           hasFields         0 = base ctor, 1 = with-fields
+0xad   uint8           reserved
+0xae   uint8           reserved
```

The two `std::string` fields use the standard MSVC STL string layout:
SBO (small buffer optimization) up to ~15 chars inline, otherwise
heap-allocated. The 84-byte size suggests `std::string` with an
extended SBO buffer (typical 0x18 for plain STL, but 0x54 here implies
a custom string class or padding for alignment).

## Part 2: Binding Storage is Bit-Packed

Tracing the reader chain from `Actor_readBindingUInt` down to the
type-specific helpers reveals that **the actor's binding storage is
a bit-packed byte buffer** addressed via per-binding metadata
entries.

### Binding Metadata Entry (~12 bytes)

Each binding registered via `_bindWork(id, struct, slot, field)`
creates a metadata entry. The entry's layout (deduced from
`BindingStorage_readField_dispatchByType` @ 0x00ce5290):

```text
binding_entry struct (~12 bytes; addressed as pbVar1):

offset  type      field             notes
------  --------  ----------------  --------------------------------
+0x00   ???       bucket key        Used by the read/write low-level
                                    functions to index into the
                                    storage-class table.
+0x01   char      sub-bucket key    pbVar1[1] = pbVar1+1
+0x04   uint      baseBitOffset     Start position in the bit-packed
                                    storage area (IN BITS).
+0x08   int16     arrayFlag         >= 0 means array binding;
                                    enables the dim1 offset path.
+0x0a   byte      sizeDim2          Size for dim2 array stride.
+0x0b   byte      typeTag           1=u8, 2=u16, 3=u24, 4=u32;
                                    ALSO used as dim1 stride
                                    multiplier (× 8 to convert
                                    bytes→bits).
```

### Type Tag Space (4 types)

Each binding's type tag selects one of 4 read functions:

```text
typeTag   size      reader            notes
-------   -----     ---------------   -----------------------
   1      1 byte    BitPacked_readByte_type1   (0x00d11c70)
   2      2 bytes   BitPacked_readShort_type2  (0x00d11cf0)
   3      3 bytes   BitPacked_readUint24_type3 (0x00d11db0) — uint24!
   4      4 bytes   BitPacked_readUint32_type4 (0x00d11e50)
```

The type 3 (u24) is interesting — 3-byte fields save a byte over u32
while still supporting up to 16M values. HP/HPMax (binding 1010/1011)
likely use u24 since max HP in 1.x rarely exceeded 6-digit ranges.

### Bit-Offset Arithmetic

The `BindingStorage_readBytes_lowLevel` (0x00ce4550) handles bit-to-
byte address conversion:

```c
byteOffset = bitOffset >> 3        // /8 to get byte position
bitInByte  = bitOffset & 7         // mod 8 for sub-byte alignment
```

The vtable+8 read method walks both. So fields can start MID-BYTE in
the storage. This makes the packing extremely dense — no padding
between fields of different types.

### Two-Dimensional Array Support

The dispatcher computes the bit offset for a (dim1, dim2) access:

```c
bitOffset = baseBitOffset
if (arrayFlag >= 0):
    bitOffset += typeTag * dim1Idx * 8     // dim1 stride
if (dim2Idx > 0):
    bitOffset += sizeDim2 * dim2Idx * 8    // dim2 stride
```

So a binding like `commandSlot_recastTime[40]` is array[40] of int32
(type 4), with stride 4 * 8 = 32 bits per element. Two-dimensional
arrays (like `comboNextCommandId[2]` × something) are supported via
the dim2 path.

### Storage Class Polymorphism

The actual storage is owned by a vtable-based class. The reader
functions look up the class via two-level bucket addressing:

```c
storage_class_table = this + 0x2c              // array of class pointers
bucket = *param_1                              // first index byte
storage_class = storage_class_table[bucket]
slot_table = storage_class + 4                 // per-class slot table
sub_bucket = *param_2                          // second index byte
field_base = slot_table[sub_bucket]
```

Two bytes of indexing → can fit up to 256×256 = 64K storage classes.
1.x uses far fewer (~10-20 actor classes), so plenty of headroom.

The vtable+8 method (read) takes (storage, key, dst, base, size).
The vtable+0x10 method (semantic TBD — possibly write or direct-
return read) takes (storage, key, base, value).

## Why This Matters for the Wire

The bit-packed in-memory storage is the **same data model** the wire
likely uses for compact updates. A "field update" packet from the
server probably encodes:

```text
+0   uint16    bindingId
+2   uint?    arrayIdx1   (if array)
+?   uint?    arrayIdx2   (if 2D)
+?   N bytes  value       (where N = typeTag)
```

So the bandwidth per field update is small: 2 bytes opcode + 4 bytes
indices + 1-4 bytes value = ~7-10 bytes per field. Multiple updates
can be batched in a single packet (e.g. all stat changes after a
level-up combined into one ~50-byte packet).

## Assessment

```text
Confirmed:
  - WorkPath struct is 176 bytes with 2 std::string + 2 uint16 +
    flags. Used as the wire payload for opcode 0x12f.
  - Binding storage is BIT-PACKED -- fields can start mid-byte for
    maximum density.
  - 4 type tags (u8/u16/u24/u32) cover the integer field space.
    Float fields use a separate reader path (Actor_readBindingFloat
    at 0x00cc7de0 — deeper analysis pending).
  - Metadata entries are ~12 bytes per binding, indexed by binding id.
  - 2D array indexing supported via dim1Idx * typeTag * 8 + dim2Idx *
    sizeDim2 * 8 offset formula.

Likely (High):
  - HP/HPMax bindings (1010/1011) use type 3 (u24, max 16M) -- this
    explains why HP wire updates are SO small.
  - The vtable+0x10 method at 0x00ce45d0 (currently "writeField_lowLevel")
    is more likely a SECOND READ VARIANT specialized for byte-sized
    direct-return, not a writer. The real writer for incoming server
    updates lives in a yet-to-be-found packet handler.
  - The float reader (Actor_readBindingFloat) probably has type tag 5
    or uses a separate vtable for IEEE 754 -- needs verification.

Likely (Medium):
  - The two-level bucket addressing (this+0x2c[bucket1][bucket2]) is
    for STORAGE CLASS POLYMORPHISM. Different actor types (Chara,
    NPC, Player) have different storage class implementations under
    the hood.

Speculative:
  - The 176-byte WorkPath is heavyweight (mostly std::string padding
    for SBO). On the wire it gets compacted to ~32 bytes (per the
    0x12f packet finding) -- only the meaningful chars survive
    serialization.
  - The vtable-based polymorphism means the binding storage class
    could be SWAPPED at runtime (e.g. "lightweight other-player"
    storage vs "full myPlayer storage") to save memory.
```

## Ghidra Annotations Made (this pass)

```text
Renamed:
  0x0070aa10  -> WorkPath_construct_base
  0x0070aaa0  -> WorkPath_construct_withFields
  0x00ce5290  -> BindingStorage_readField_dispatchByType
  0x00ce4550  -> BindingStorage_readBytes_lowLevel
  0x00ce45d0  -> BindingStorage_writeField_lowLevel
                  (with comment noting semantic uncertainty)
  0x00d11c70  -> BitPacked_readByte_type1
  0x00d11cf0  -> BitPacked_readShort_type2
  0x00d11db0  -> BitPacked_readUint24_type3
  0x00d11e50  -> BitPacked_readUint32_type4

Comments added at:
  - All 2 WorkPath constructors (full layout pinned)
  - BindingStorage_readField_dispatchByType (full algo + metadata
    entry layout)
  - BindingStorage_readBytes_lowLevel (vtable+8 read semantics)
  - BindingStorage_writeField_lowLevel (semantic uncertainty noted)
  - BitPacked_byte_type1_value (called helper; semantic TBD)
```

## Open Threads

```text
1. Find the binding storage WRITER -- the function that gets called
   when the server pushes a field update packet. Must update the
   bit-packed storage from network bytes. Not yet pinned.
   
   Candidates to search:
   - Inbound dispatch in ZoneClient receive path
   - Functions with multiple calls to BitPacked write functions
   - "case 0x130" or similar near 0x12f in switch statements

2. Decompile the float reader chain (Actor_readBindingFloat at
   0x00cc7de0 down). Likely follows the same pattern with a
   different vtable.

3. Walk WorkPath_joinAsString (0x006cea20) to recover the EXACT byte
   layout of the joined-string form sent over wire opcode 0x12f.
   The function uses "/" as separator and concatenates structName +
   "/" + slotCategory. The field indices probably get appended as
   "[N][M]" or "/N/M" suffix when hasFields flag is set.

4. Find the server-broadcast opcode (the opposite direction of
   0x12f). Probably consecutive (0x130, 0x131, 0x12e?).
```
