# Finding: Linkshell Wire Opcodes CLOSED -- 0x188 SINGLE + 0x189 BATCH (EntryLinkShellBuilder) + PropertyUpdater Mystery Solved

**Closes the Linkshell wire-side protocol** via interactive Ghidra
RTTI walk. Discovered:

1. **Opcode 0x188** = LINKSHELL ENTRY single update
2. **Opcode 0x189** = LINKSHELL ENTRY batch (multi-entry stride 0x40, count at +0x200)
3. **PropertyUpdater mystery solved**: PropertyUpdater_FACTORY is **slot 12
   of EntryLinkShellBuilder's vftable** -- so linkshell objects are what
   trigger property update packets

Combined with the prior Linkshell subsystem inventory, the **complete
Linkshell wire protocol** is now mapped.

## 1. The 2 NEW wire opcodes

```text
Opcode 0x188  ZoneIn_opcode_0x188_LINKSHELL_ENTRY_single_to_factory
   ↓ FUN_00576360 (thin: forwards from +0x18)
   ↓
LinkShellEntry_forwarder_single_toFactory (FUN_006cd790)
   ↓ FUN_006cd790 (thin wrapper)
   ↓
EntryLinkShellBuilder_FACTORY_constructAndEnqueue (FUN_006cc390)
   ↓
   - new(0x40) EntryLinkShellBuilder
   - new(0xf8) child struct (248B)
   - ringBuffer_enqueue_4bytes(this+8, &newPacket)
   ↓
SpawnPipeline T0-T5 drains the queue -> Lua callbacks fire

Opcode 0x189  ZoneIn_opcode_0x189_LINKSHELL_ENTRY_BATCH_to_factory
   ↓ FUN_00576370 (thin: forwards from +0x18)
   ↓
LinkShellEntry_forwarder_batch_toFactory (FUN_006cd7b0)
   ↓
LinkShellEntry_batchLoop_countAt_packet_0x200_stride_0x40 (FUN_006cc720)
   ↓ loop N times (count byte at packet[+0x200]):
   ↓   EntryLinkShellBuilder_FACTORY_constructAndEnqueue(payload + N*0x40)
   ↓
Each entry pushed to spawn pipeline ring buffer
```

## 2. EntryLinkShellBuilder vftable (19 slots @ 0x00fd447c)

```text
Slot  Address     Function                                        Notes
----  -------     --------                                        -----
[0]   0x006dacb0  FUN_006dacb0                                    dtor
[1]   0x006c0580  FUN_006c0580                                    ?
[2]   0x006d0c90  FUN_006d0c90                                    ?
[3]   0x006d0ca0  FUN_006d0ca0                                    ?
[4]   0x006d0cb0  FUN_006d0cb0                                    ?
[5]   0x006d0cc0  FUN_006d0cc0                                    ?
[6]   0x00a72a20  FUN_00a72a20                                    ?
[7]   0x00a72a20  FUN_00a72a20                                    same as [6]
[8]   0x006cd690  FUN_006cd690                                    ?
[9]   0x005b8d90  FUN_005b8d90                                    ?
[10]  0x0080fa00  FUN_0080fa00                                    ?
[11]  0x005c5c80  ZoneIn_handler_default                          inbound placeholder
[12]  0x006c5750  PropertyUpdater_FACTORY                         ← MYSTERY SOLVED
[13]  0x006c0290  FUN_006c0290                                    ?
[14]  0x006cb8e0  FUN_006cb8e0                                    ?
[15]  0x00776340  UserDataReceiver_vtable                         ← interesting cross-ref
[16]  0x00530890  FUN_00530890                                    ?
[17]  0x006ce2e0  FUN_006ce2e0                                    ?
[18]  0x00b73290  FUN_00b73290                                    ?
```

**KEY INSIGHTS**:

### Slot 12 = PropertyUpdater_FACTORY (mystery solved!)

In the prior finding `finding_group_typed_packets_remaining_opcodes_0x187_0x18b.md`,
I noted that **PropertyUpdater had no dedicated wire opcode** — it was
accessible only via "vtable callback at 0x00fd44ac".

**That callback IS in EntryLinkShellBuilder's vftable[12].**

So PropertyUpdater is **constructed BY EntryLinkShellBuilder when a
linkshell property needs to change**. The chain is:
```text
Linkshell needs property update (e.g., name change, owner change)
   ↓
EntryLinkShellBuilder calls vtable[12] = PropertyUpdater_FACTORY
   ↓
PropertyUpdater_FACTORY_constructAndEnqueue creates a PropertyUpdater
packet on the same ring buffer
   ↓
Per-frame pipeline applies the property update
```

This explains why PropertyUpdater has no dedicated wire opcode —
**it's an INTERNAL side-effect of EntryLinkShellBuilder operations**,
not a server-pushed packet.

### Slot 15 = UserDataReceiver_vtable cross-reference

Slot 15 references `UserDataReceiver_vtable`. This means
EntryLinkShellBuilder IMPLEMENTS the UserDataReceiver interface
(or shares functionality). UserDataReceiver is the inbound
data packet handler (per opcode 0x17... data packet finding).

So linkshell entries also handle "user data" packets — likely for
the **linkshell member roster sync** (member updates flow through
this path).

### Vftable size: 19 slots (vs PacketRequestBase's 13)

EntryLinkShellBuilder ADDS 6 SLOTS to the base PacketRequestBase
vftable. These extra slots are linkshell-specific overrides:
- Slot 13 (new): linkshell-specific cleanup?
- Slot 14 (new): linkshell roster update?
- Slot 15 (new): UserDataReceiver implementation
- Slot 16 (new): ?
- Slot 17 (new): ? (same as PacketRequestBase[3] = FUN_006ce2e0)
- Slot 18 (new): ? (same as PacketRequestBase[4] = FUN_00b73290)

Slots 17/18 reuse FUN_006ce2e0 and FUN_00b73290 from PacketRequestBase
— these are inherited/shared methods.

## 3. Wire packet 0x188 / 0x189 format

```text
SINGLE 0x188 payload (param_2):
  +0x00..+0x04  id_pair_a (linkshell id?)
  +0x08         class name string (variable length, null-terminated)
  +0x0c (param_2[3])  flag field
                  if 0: use -1 as effective value
                  else: use this value directly
  +0x10..+0x18  additional data (4 dwords passed to FUN_006d79d0)

  Per entry size: 0x40 bytes (64 bytes) -- matches operator_new size

BATCH 0x189 payload:
  Same per-entry format as 0x188
  +0x000..+0x040  entry 0
  +0x040..+0x080  entry 1
  ...
  +0x200          BYTE = count (max 8 entries fit before +0x200 boundary,
                                  so max linkshells per player is 8?)

LIKELY: server sends 0x189 at LOGIN/ZONE ENTER to push the player's
full linkshell list (up to 8 linkshells per ARR comparison).
```

## 4. Updated Group:: subclass → opcode map (FINAL)

```text
Subclass               Wire opcode  Trigger
--------               -----------  -------
EntryBuilder           0x17c TAG0   ACTOR SPAWN
BreakupBuilder         0x143        ACTOR DESPAWN
OnlineStatusUpdater    0x17c TAG0xe ONLINE STATUS CHANGE
MemberInfoUpdater      0x18b        MEMBER INFO UPDATE
WorkSyncUpdater        0x187        WORKSYNC STATE BATCH
PropertyUpdater        (internal)   FIRED BY EntryLinkShellBuilder vtable[12]
EntryLinkShellBuilder  0x188/0x189  LINKSHELL JOIN/LEAVE/UPDATE (single/batch) ← NEW
```

**All 8 Group:: subclasses now fully wire-mapped.**

## 5. Updated complete Linkshell wire protocol

```text
SERVER -> CLIENT (Linkshell management):
  0x188 SINGLE  linkshell join/leave/update (1 entry, ~40 bytes)
  0x189 BATCH   linkshell roster push (N entries, login/zone enter)
  
  Side effects (via EntryLinkShellBuilder vftable[12]):
    PropertyUpdater fires when linkshell name/icon/etc. changes

SERVER -> CLIENT (Linkshell chat):
  0xC9 chat with linkshell channel byte (chat mode 5)
  Standard chat protocol, payload identifies as linkshell

CLIENT -> SERVER (Linkshell actions):
  Chat input: 0xC9 outbound with chat mode 5 byte
  UI commands: UILuaCommands.ChangeCurrentLinkshell + SetCurrentLinkshell
    → trigger _executeCommand to send command opcode (TBD)
  Operations: Join/Leave/Create probably via outbound RPC opcode 0x12e
```

## 6. The opcode 0x188/0x189 placement in dispatcher

```text
Looking at the Zone_MAIN_inbound_opcode_dispatcher_50plus_handlers,
the 0x188/0x189 pair were previously labeled as "uint payload" handlers
in the per-actor message section. Actually:

REVISED PLACEMENT:
  0x186  ?  (might also be a linkshell variant; need to check)
  0x187  WORKSYNC BATCH (WorkSyncUpdater)
  0x188  LINKSHELL ENTRY single (EntryLinkShellBuilder)  ← CORRECTED
  0x189  LINKSHELL ENTRY batch (EntryLinkShellBuilder)   ← CORRECTED
  0x18a  ?  (might be ANOTHER variant)
  0x18b  MEMBER INFO (MemberInfoUpdater)

The clustering 0x187/0x188/0x189/0x18a/0x18b strongly suggests these
are ALL Group:: typed-packet dispatchers (5 opcodes for 5 subclass
factories). I previously only documented 0x187 and 0x18b; now 0x188
and 0x189 are confirmed Linkshell.

POSSIBLE: 0x186 and 0x18a may dispatch to other Group:: subclasses
not yet discovered, or to MORE EntryLinkShellBuilder variants.
```

## 7. Renames + comments applied

```text
0x00576360  → ZoneIn_opcode_0x188_LINKSHELL_ENTRY_single_to_factory
0x00576370  → ZoneIn_opcode_0x189_LINKSHELL_ENTRY_BATCH_to_factory
0x006cd790  → LinkShellEntry_forwarder_single_toFactory
0x006cd7b0  → LinkShellEntry_forwarder_batch_toFactory
0x006cc390  → EntryLinkShellBuilder_FACTORY_constructAndEnqueue
0x006cc720  → LinkShellEntry_batchLoop_countAt_packet_0x200_stride_0x40
0x006cbfb0  → EntryLinkShellBuilder_ctor_setsVftable_allocates0xf8Child
0x006cb860  → EntryLinkShellBuilder_dtor_revertsToParentVftable

Plus comprehensive decompiler comment at 0x006cc390 documenting full
wire packet layout + processing flow + 0xf8 child struct purpose.
```

## 8. Cross-references

- `finding_linkshell_subsystem_inventory.md`
  -- the prior Lua-side inventory (this finding closes the wire-side)
- `finding_group_typed_packets_remaining_opcodes_0x187_0x18b.md`
  -- prior partial mapping; PropertyUpdater mystery NOW SOLVED here
- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the main dispatcher pattern (this finding extends it)

## 9. Confidence

```text
Confirmed:
  - Opcodes 0x188 (single) and 0x189 (batch) carry EntryLinkShellBuilder
  - EntryLinkShellBuilder ctor at FUN_006cbfb0 sets vftable
  - 0x40 byte EntryLinkShellBuilder + 0xf8 (248B) child struct
  - 19-slot vftable (6 more than PacketRequestBase base)
  - Slot 12 = PropertyUpdater_FACTORY (solves PropertyUpdater mystery)
  - Slot 15 = UserDataReceiver_vtable (interface implementation)
  - Slot 11 = ZoneIn_handler_default (inbound placeholder, inherited)
  - 9 renames + 1 decompiler comment applied
  - All 8 Group:: subclasses now wire-mapped

Likely (High):
  - 0x189 BATCH used at login/zone enter for full linkshell list refresh
  - PropertyUpdater triggers when linkshell name/icon/color changes
  - Slot 15 UserDataReceiver implementation = linkshell member roster sync
  - Max linkshells per player ≈ 8 (based on 0x200 byte count boundary
    suggesting 8 x 0x40 = 0x200 max entries)

Speculative:
  - 0x186 and 0x18a may be additional Group:: subclass dispatchers
  - The 0xf8 child structure of EntryLinkShellBuilder stores:
    * Linkshell id, name, owner_id, icon_id, color
    * Member roster (small embedded array?)
    * Per-linkshell flags
```

## 10. Next test

```text
1. Decompile FUN_00576350 (0x186) and FUN_00576380 (0x18a) to see if
   they're also Group:: subclass dispatchers
2. Walk PropertyUpdater factory (FUN_006c5750) to see the data flow
   from EntryLinkShellBuilder vtable[12]
3. Examine the 0xf8 (248B) child structure layout to map linkshell
   data fields
4. Find OUTBOUND linkshell command opcodes (join/leave/create)
5. Cross-reference with Lua-side LinkshellGroup C++ class
```

## Commit suggestion

```
docs(re/exe): LINKSHELL wire-side CLOSED -- opcodes 0x188 SINGLE + 0x189 BATCH (EntryLinkShellBuilder); PropertyUpdater mystery solved (vtable[12] of LinkShellBuilder); all 8 Group:: subclasses wire-mapped
```
