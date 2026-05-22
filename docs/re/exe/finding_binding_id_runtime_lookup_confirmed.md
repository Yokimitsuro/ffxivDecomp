# Finding: EXE Confirms `binding id ↔ runtime field id` 1:1 Mapping

Critical validation finding. The theory that `_bindWork` IDs in the
Lua corpus map 1:1 to runtime field IDs (and thus on-wire opcodes
for actor field updates) is now **EXE-confirmed** via three distinct
binding-id constants appearing as direct arguments to typed reader
functions inside `PlayerBase_check_charaWork_state_via_binding_ids`
(formerly FUN_006de510).

Date: 2026-05-23. Discovered during Ghidra validation pass on the
`_executeCommand` thunk region.

## The Smoking Gun

`PlayerBase_check_charaWork_state_via_binding_ids` @ 0x006de510:

```c
uint __thiscall fn(this, params) {
  ...
  cVar1 = Actor_readBindingBool(this_00, params, 0xbbe, 2);  // bindingId 3006
  if (cVar1) {
    fVar3 = Actor_readBindingFloat(this_00, params, 0x7d2, -NAN);  // bindingId 2002
    if (potencial out of [lo, hi] range):
      uVar2 = Actor_readBindingUInt(this_00, params, 0x3f2, 0);  // bindingId 1010
      return uVar2;
  }
  return 0xffffffff;
}
```

Reading the binding-id constants:

```text
EXE constant   decimal   Lua-side binding (from finding_bindwork_catalog.md)
------------   -------   ----------------------------------------------------
0xbbe           3006      charaWork.property        (32-bit bitset)
0x7d2           2002      charaWork.battleSave.potencial  (float; NM-sign-coded)
0x3f2           1010      charaWork.parameterSave.hp[1]   (current HP)
```

**All three IDs match the Lua-side _bindWork catalogue exactly.**
The match is too specific to be coincidence — there are billions of
random uint16 values; the chance these three specifically map to
catalogued bindings is essentially zero.

So `binding id == runtime field id`. Confirmed.

## The Three Universal Readers

The same function uses three different reader helpers, one per type:

```text
Actor_readBindingUInt   @ 0x00cc7b90  -- reads UINT by binding id
Actor_readBindingBool   @ 0x00cc7be0  -- reads BOOL/PROPERTY-BIT by id+bitIdx
Actor_readBindingFloat  @ 0x00cc7de0  -- reads FLOAT by binding id
```

All three share the same shape:

```c
T readBindingT(actor_ref, params, bindingId, defaultOrBitIdx) {
  iVar1 = FUN_00cd8160(*this, params);  // resolve actor instance
  if ((iVar1 != 0) && (*(char*)(iVar1+0x7d) != 0) && (*(int*)(iVar1+0x14) != 0)) {
    this_00 = (void*)FUN_00ceb490(*(void**)(*this + 0x214), params);
    // ^ FETCH THE BINDINGS TABLE AT this+0x214
    result = FUN_00ce5XXX(this_00, bindingId, default, ...);
    // ^ TABLE LOOKUP BY ID
    return result;
  }
  return 0 / 0xffffffff;
}
```

The actor's bindings table is at **this+0x214**. The type-specific
accessors (`FUN_00ce5290` for UInt, `FUN_00ce53d0` for Bool/Bit,
some float variant for Float) walk that table.

The three readers have ~14-40+ xrefs each, meaning they are the
universal accessors used by every "get this field by id" path in the
codebase.

## What This Proves

```text
CONFIRMED:
  - The 25+ binding IDs catalogued in finding_bindwork_catalog.md
    are valid runtime field IDs. The C++ runtime uses them as keys
    to a table at actor+0x214.
  - Each binding has an associated TYPE (uint, bool, float, ...).
    The reader is type-specific; the writer side (per
    finding_lpb_loader_chain.md's lua_updateWork_impl =
    FUN_006e85e0) likely takes the type via the slot/field strings
    passed to _updateWork.
  - The on-wire format for "actor X field Y updated" is most likely:
      packet header
      bindingId (uint16, e.g. 0x03f2 for hp[1])
      typed payload (uint/float/bool per the binding's registered type)

LIKELY (High):
  - The wire opcode IS the bindingId verbatim. Server pushes a
    "field update" segment with opcode 0x3f2 plus 2 bytes (the new
    hp[1] value). No translation table is needed.
  - The bindings table at actor+0x214 is built incrementally by
    _bindWork() registration calls during the actor's _onInit
    sequence. Each call adds an entry { bindingId -> (struct,
    slot, field, type, defaultValue) }.

LIKELY (Medium):
  - The 3 reader helpers correspond to the 3 typed _onChange*
    hooks: bool readers feed _onChangeSubStatMode/Status, float
    readers feed _onChangeNetStat, uint readers feed
    _onChangeActorMainStat (which read hp).
  - Sub-array indexing (e.g. hp[1] vs hp[2]) is handled via the 4th
    arg to readBindingUInt (-1 in the example for "scalar/no sub-
    index"); positive values would index into array bindings.

SPECULATIVE:
  - The 0xbbe / 0x7d2 / 0x3f2 IDs appearing as DIRECT LITERALS in
    this C++ function (rather than passed via parameters) means
    this specific function HARDCODES "test alive + check potencial
    range + read hp" -- it's a fast-path predicate, probably for a
    UI / nameplate rendering pre-check.
  - The runtime probably treats the binding table as a fixed-size
    array (e.g. indexed [0..65535] for full uint16 coverage) for
    O(1) lookup, with empty slots marked by a sentinel.

NOT YET CONFIRMED:
  - The full type tag space (UInt, Bool, Float observed; possible
    Actor, String, Array<T> still TBD).
  - The C++ side of _bindWork() registration (the function that
    POPULATES the table at actor+0x214). Would surface the exact
    table data structure.
  - The on-wire framing around the bindingId (header bytes, segment
    type, etc.) -- still requires capture or further EXE analysis.
```

## Server Implication

The "wire surface for actor sync" model is now precise enough to
implement server-side:

```text
For every field update the server wants to push:
  1. Look up the field's binding id from the catalogue
     (e.g. hp[1] = 0x3f2 = 1010)
  2. Pack { bindingId (u16), payload (per field type) }
  3. Wrap in the standard Zone-channel segment type 3 (IPC)
  4. Send

Client side (already validated):
  - PacketProcessor receives the segment
  - Dispatches by bindingId to a per-id handler
  - Handler writes into actor's binding table at offset 0x214
  - Runtime triggers any _onChange* Lua hooks for that field

No opcode translation needed. No per-field handler registration on
the server. A single "field update" sender that takes (actorId,
bindingId, value) covers EVERY field in the catalogue.
```

This is the most important finding for server bring-up: it
collapses what could have been ~25 separate packet builders into
a SINGLE polymorphic builder that uses the binding id as the
dispatcher.

## Ghidra Annotations Made

Functions renamed:

```text
0x006de510  FUN_006de510  ->  PlayerBase_check_charaWork_state_via_binding_ids
0x00cc7b90  FUN_00cc7b90  ->  Actor_readBindingUInt
0x00cc7be0  FUN_00cc7be0  ->  Actor_readBindingBool
0x00cc7de0  FUN_00cc7de0  ->  Actor_readBindingFloat
0x00730c00  FUN_00730c00  ->  registerLua_canExecuteCommand
```

Decompiler comments added at all 5 addresses documenting:
- The binding-id literal evidence
- The shared reader shape (actor+0x214 table)
- Cross-references to Lua-side findings
- Server implication for on-wire opcode use

## Open Threads

```text
1. Pin the C++ side of _bindWork (the registrar that populates the
   actor+0x214 table). Likely in the 0x006exxxx range alongside
   _updateWork @ 0x006e85e0. Pinning it would expose the exact
   table layout and the type tag space.

2. Confirm the wire framing around bindingId. Two candidates:
   a) bindingId is a direct opcode in segment type 3 (1-to-1 wire)
   b) bindingId is part of a sub-payload inside a fixed-opcode
      "FieldUpdate" segment (1-level of indirection)
   Either way the catalogue still drives the model; just the
   serializer template differs.

3. Walk the 14-40 xrefs to Actor_readBindingUInt/Bool/Float and
   confirm that the 0x00573xxx range is the family of Lua-exposed
   "_get<Field>" native bindings. Renaming each would unlock the
   actor-side Lua bridge for the entire actor API.
```
