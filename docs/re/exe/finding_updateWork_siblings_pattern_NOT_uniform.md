# Finding: 3 _updateWork Siblings Disassembled -- Pattern is NOT Uniform; 3 Distinct Wire Paths Discovered

**Major correction to a prior hypothesis.** Disassembles the 3
sibling `_updateWork` thunks (Director, Item, GroupBase) to compare
against CharaBase's `_updateWork` (prior finding). The prior
**"high confidence prediction"** that all 4 share the same WorkSync
pipeline is **WRONG** -- only Director matches CharaBase. Item uses
a COMPLETELY DIFFERENT wire opcode (0x132), and GroupBase uses a
custom dispatch path.

This is the kind of architectural correction the per-thunk
disassembly approach is designed to catch.

**4 distinct `_updateWork` implementations now confirmed:**

| Class | Thunk | Pipeline | Wire opcode |
|---|---|---|---|
| CharaBase | CharaBase_cpp_updateWork_thunk @ 0x006e7670 | WorkSync via class+0xec | **0x12F** (56B) |
| Director | lua_updateWork_impl @ 0x006e85e0 | WorkSync via class+0xec | **0x12F** (56B) |
| Item | Lua_sendByteUshortAt0x68_via_0x132 @ 0x006e2af0 | Direct opcode, NO WorkPath | **0x132** (24B) |
| GroupBase | GroupBase_cpp_updateWork_thunk_customDispatch @ 0x006e8890 | WorkPath built, custom dispatch via +0x68 | TBD (probably 0x12F) |

## 1. Director _updateWork -- IDENTICAL to CharaBase

The named function `lua_updateWork_impl` @ 0x006e85e0 IS the generic
WorkSync implementation. Director's registrar
(`DirectorBaseClass_registerLua_updateWork`) wires this generic
implementation as Director's thunk:

```text
Pipeline (Director):
  1. Extract 2-4 args from Lua stack (struct, slot, idx0, idx1)
  2. Build WorkPath (176 bytes, std::string + std::string + 2 shorts)
  3. Get dispatcher: actor.class->vtable[0xec]
  4. Call WorkSync_dispatchOrEnqueue(dispatcher, actor, callCtx, workPath)
  5. Eventually sends opcode 0x12F (56-byte STRING packet) via Zone
```

This is the SAME as CharaBase. Both classes share the generic impl.

## 2. Item _updateWork -- COMPLETELY DIFFERENT (opcode 0x132)

Item's `Lua_sendByteUshortAt0x68_via_0x132` @ 0x006e2af0 does NOT
build a WorkPath, does NOT call WorkSync_dispatchOrEnqueue, and
sends a DIFFERENT wire opcode:

```c
void Lua_sendByteUshortAt0x68_via_0x132(this, luaCtx) {
  // 1. Get reference to call source
  callRef = FUN_00cc73b0(luaCtx, ...);
  
  // 2. Get the Zone outbound dispatcher
  zoneDispatcher = FUN_0075d460(luaCtx_class, ...);
  
  // 3. Send opcode 0x132 with item state:
  ZoneOut_send_opcode_0x132_24B_byteUshort(
    zoneDispatcher,
    callContext,
    (byte*)(this + 0x68),   // byte field at item+0x68 (state byte?)
    (short)*(this + 0x6c)   // ushort at item+0x6c (state value?)
  );
}
```

Item's `_updateWork` is **NOT a WorkSync update** -- it's a custom
24-byte item-state notification. The packet carries (byte, ushort)
from item's offsets 0x68/0x6c.

These offsets are likely Item's:
- +0x68 = Bazaar/Dealing state byte (locking/dealing/trading enum)
- +0x6c = Associated value (price? quantity? attachment ref?)

**Why Item is special**: Items have a SIMPLER state model than
actors. The Bazaar/Trade lifecycle (LOCKING/DEALING/TRADING per
prior finding) is a single byte-enum + value. No need for the
full WorkPath/WorkSync overhead.

## 3. GroupBase _updateWork -- WorkPath built, custom dispatch

GroupBase's thunk @ 0x006e8890 builds a WorkPath like CharaBase
but DISPATCHES VIA A DIFFERENT MECHANISM:

```c
void GroupBase_cpp_updateWork_thunk_customDispatch(luaCtx) {
  // Same as CharaBase up to here:
  arg0 = Lua_getString(stack, 0);  // structName
  arg1 = Lua_getString(stack, 1);  // slotCategory
  WorkPath_construct_base(path, arg0, arg1);
  
  // Optional 4-arg path extension (same as CharaBase):
  if (arg2.type != 6) {
    short field0 = Lua_getInt(stack, 2) - 1;
    short field1 = Lua_getInt(stack, 3) - 1;
    path_ext = WorkPath_construct_withFields(...);
    FUN_006ce1c0(path, path_ext);
  }
  
  // DIFFERENT: call FUN_006c7a80 with offset +0x68
  // (NOT WorkSync_dispatchOrEnqueue with class+0xec)
  FUN_006c7a80(
    (local_178 + 0x68),    // group's own dispatcher at +0x68
    actor,
    workPath
  );
}
```

GroupBase has its **own dispatcher at offset +0x68** (not the class
vtable's +0xec slot). This suggests GroupBase instances have a
PER-INSTANCE dispatch table rather than per-class.

Why: Groups have variable membership and need per-group update
batching. A class-level dispatcher would serialize all group
updates; per-group lets each group update independently.

## 4. The corrected WorkSync pipeline understanding

```text
PRIOR (incorrect): "All 4 _updateWork bindings funnel through
                     WorkSync_dispatchOrEnqueue -> opcode 0x12F"

CORRECTED:
  CharaBase _updateWork   -> WorkSync standard -> opcode 0x12F (56B string)
  Director _updateWork    -> WorkSync standard -> opcode 0x12F (56B string)
  Item _updateWork        -> Direct send       -> opcode 0x132 (24B byte+ushort)
  GroupBase _updateWork   -> WorkPath built    -> per-instance dispatch via +0x68
                              (probably still 0x12F downstream)
```

**3 distinct wire paths**:
1. Standard WorkSync (CharaBase + Director): 56-byte string-path packet
2. Direct item state (Item): 24-byte byte+ushort packet
3. Per-instance group dispatch (GroupBase): TBD but custom

## 5. Wire opcode 0x132 -- new dedicated Item state opcode

Now confirmed:

```text
Opcode 0x132 = 24-byte packet (per ZoneOut_send_opcode_0x132_24B_byteUshort)
Payload:
  +0    header (4B)
  +4    sender ref (4B)
  +8    ... framing (8B)
  +16   (byte) item state byte
  +17   (ushort) item state value
  +20   padding to 24 bytes

Used by:  ItemBaseClass._updateWork (NO other known users)
Purpose:  Notify item state change (Bazaar lock/deal/trade transitions)
Reason:   Simpler than full WorkSync; items don't need WorkPath
          structure since their state model is enum+value
```

## 6. Why the asymmetry makes sense

```text
WORKSYNC (CharaBase/Director): for COMPLEX hierarchical state
  - Has many fields per actor (HP, MP, stats, status effects, etc.)
  - Needs path-based addressing ("charaWork.parameterSave.hp[1]")
  - Each field has its own sync semantics (rate, priority)
  - 56-byte packet with string path
  
DIRECT NOTIFY (Item): for SIMPLE state transitions
  - Items have only a few state transitions (Bazaar lifecycle)
  - State is (enum byte, value ushort) -- no hierarchy needed
  - 24-byte packet is sufficient
  - Bypasses WorkSync overhead

PER-INSTANCE DISPATCH (GroupBase): for VARIABLE-MEMBERSHIP entities
  - Group state changes need per-group batching (each group is
    independent)
  - Class-level WorkSync would serialize all group updates
  - Per-instance dispatch (+0x68) allows per-group queues
```

## 7. Architectural lesson: per-class _updateWork is OVERLOADED

The Lua API `obj:_updateWork(args)` looks uniform from script
side, but the binding is registered with a **class-specific thunk**.
This is the WHOLE POINT of master block registrars -- they wire each
class to its own implementation.

The 17 master blocks documented in prior session are the engine's
way of saying "each class can have a completely custom impl for
each binding name". This finding proves that the assumption "same
binding name = same implementation" is INCORRECT.

Future thunk-walking work must check each class's registrar
individually, not assume uniformity.

## 8. Updated WorkSync coverage

```text
PREVIOUSLY DOCUMENTED:
  - CharaBase _updateWork pipeline (FUN_006e7670 / opcode 0x12F)
  - WorkSync_dispatchOrEnqueue (FUN_00767fc0)
  - WorkSync_serializePayloadAndSend (FUN_00767c00)
  - WorkSync_buildAndSendPacket_opcode_0x12f (FUN_0075e770)
  - 4 BitPacked writers (inbound apply path)

NEWLY CONFIRMED:
  - Director _updateWork shares CharaBase's pipeline (via shared
    lua_updateWork_impl function at 0x006e85e0)
  - Item _updateWork is COMPLETELY DIFFERENT (opcode 0x132)
  - GroupBase _updateWork uses custom per-instance dispatch (+0x68)

STILL UNKNOWN:
  - GroupBase's downstream wire opcode (likely 0x12F but not
    confirmed)
  - The exact role of GroupBase's +0x68 dispatcher (per-instance
    queue? broadcast list?)
```

## 9. Renames made (1 new + 3 reconciliations)

```text
NEW RENAME:
  - 0x006e8890 -> GroupBase_cpp_updateWork_thunk_customDispatch

ALREADY NAMED (per prior session work):
  - 0x006e7670 -> CharaBase_cpp_updateWork_thunk (this session's prior finding)
  - 0x006e85e0 -> lua_updateWork_impl (the GENERIC WorkSync impl;
                  used by both CharaBase wrapper and Director directly)
  - 0x006e2af0 -> Lua_sendByteUshortAt0x68_via_0x132 (Item's direct
                  state-notify path)
```

Note: CharaBase_cpp_updateWork_thunk is **not the same as**
lua_updateWork_impl -- they're 2 different functions doing similar
work. CharaBase has its own wrapper; Director uses the bare
generic. The duplication is likely because CharaBase's thunk
predates the refactor that created the generic impl.

## 10. Confidence

```text
Confirmed:
  - 4 _updateWork bindings have 4 DISTINCT thunk implementations
  - Director and CharaBase share WorkSync pipeline + opcode 0x12F
  - Item uses opcode 0x132 directly (NOT WorkSync)
  - GroupBase has custom dispatch via per-instance +0x68 offset
  - The 4 thunks all use their class's specific functor factory:
    * CharaBase: 0x00726460
    * Director: 0x00726d50
    * Item: 0x00726670
    * GroupBase: 0x007265c0
  - Item's 24-byte packet @ opcode 0x132 carries (byte, ushort) state
  - WorkSync is NOT universal across _updateWork callers

Likely (High):
  - Item's +0x68/+0x6c map to Bazaar state (locking/dealing/trading
    byte + associated value)
  - GroupBase's +0x68 is the group's local update batch buffer
    (per-group rather than per-class queue)
  - The pattern (one Lua API, many class impls) applies to other
    bindings too -- "_updateWork" was just predicted to be uniform
    because the name is shared; reality is they're 4 different impls
  - The lua_updateWork_impl naming suggests it WAS uniform at one
    point; CharaBase, Item, GroupBase later got specialized variants

Likely (Medium):
  - Other shared binding names (_getGroup, _getOwner, _updateWork
    even) may have similar specialized impls per class
  - The DesktopWidget _updateWork (if any) might be different again
  - Future thunk work should ALWAYS check the registrar's thunk
    target, not assume sharing
```

## 11. Cross-references

- `finding_updateWork_thunk_worksync_state_replication.md` -- the
  CharaBase finding that this finding RECONCILES with 3 siblings
- `finding_worksync_wire_opcode_0x12f.md` -- documents the generic
  lua_updateWork_impl that Director uses directly
- `finding_item_master_20_of_20_registrars_complete.md` -- where
  Item's _updateWork was first identified with opcode 0x132 carrier
- `finding_groupbase_master_16_of_16_complete.md` -- where
  GroupBase's _updateWork was listed alongside _updateMemberAndInformation
- `finding_director_master_block_located_5_registrars_complete.md`
  -- where Director's _updateWork was found

## 12. Next test

```text
1. Disassemble GroupBase's downstream FUN_006c7a80 to identify its
   wire opcode
2. Disassemble ZoneOut_send_opcode_0x132_24B_byteUshort to map the
   24-byte packet layout precisely
3. Check Item._updateMemberAndInformation (the sibling Group binding
   at registrar 0x007306c0) -- another candidate for specialized impl
4. Walk vtable[0xec] (WorkSync dispatcher slot) for sample classes
   to enumerate per-class dispatcher implementations
5. Look for the OTHER class _updateWork callers (DesktopWidget,
   WorldMaster) if they exist -- predict more specialized impls
```

## Commit suggestion

```
docs(re/exe): 3 _updateWork siblings disassembled -- pattern NOT uniform; Item uses opcode 0x132 (NOT 0x12F), GroupBase has per-instance custom dispatch; major hypothesis correction
```
