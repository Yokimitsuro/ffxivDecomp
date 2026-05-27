# Finding: GroupBase _updateWork Wire Opcode CONFIRMED -- 0x133 (Secondary WorkSync; 56B Twin of 0x12F)

**Closes the gap from the prior siblings finding.** GroupBase's
`_updateWork` ultimately sends wire opcode **0x133** (NOT 0x12F as
predicted, NOT 0x132 like Item).

This brings the full breakdown to:
- **0x12F**: primary WorkSync (CharaBase + Director) -- 56-byte string path
- **0x132**: Item state notify (Item only) -- 24-byte byte+ushort
- **0x133**: secondary WorkSync (GroupBase only) -- 56-byte string path

0x133 is the **"ALT" variant of 0x12F** -- identical structure
(WorkPath_joinAsString + serialization), only the opcode byte
differs.

## 1. The dispatch chain (now complete)

```text
Lua: group:_updateWork("groupWork", "memberRoster")
   ↓
GroupBase_cpp_updateWork_thunk_customDispatch @ 0x006e8890:
   - Build WorkPath (same as CharaBase: 2-4 components, 176 bytes)
   - Call FUN_006c7a80(local_178+0x68, actor, workPath)
     ^^^^^^^^^^^^^^^^^ -- per-instance dispatch via +0x68
   ↓
FUN_006c7a80 @ 0x006c7a80:
   - Single-line wrapper:
     WorkSyncAlt_serializePayloadAndSend_opcode_0x133(
       actor, this+0x8, workPath)
   ↓
WorkSyncAlt_serializePayloadAndSend_opcode_0x133 @ 0x006c72e0:
   - IDENTICAL structure to WorkSync_serializePayloadAndSend
   - Uses same WorkPath_joinAsString + serialization
   - Final call: ZoneOut_send_opcode_0x133_56B (...)
   ↓
Wire: 56-byte packet on Zone channel with OPCODE 0x133
```

## 2. The 3-opcode breakdown (FULL picture)

```text
Opcode  Size   Class user      Path                  Predictive enqueue?
------  ----   ----------      ----                  -------------------
0x12F   56B    CharaBase       WorkSync_dispatchOrEnqueue
                                -> predictive UpdateQueue
                                -> WorkSync_serializePayloadAndSend
                                -> opcode 0x12F                 YES
0x12F   56B    Director        same as CharaBase
                                (shared lua_updateWork_impl)    YES
0x132   24B    Item            DIRECT send via
                                ZoneOut_send_opcode_0x132_24B   NO
0x133   56B    GroupBase       FUN_006c7a80 (1-line wrapper)
                                -> WorkSyncAlt_serializePayload
                                -> opcode 0x133                 NO (no enqueue)
```

**Key insight: 0x12F vs 0x133 difference is the ENQUEUE behavior**.

- 0x12F: goes through full WorkSync pipeline including
  UpdateQueue_pushEntry (predictive apply + dedup)
- 0x133: SKIPS the predictive enqueue, goes straight to serializer +
  wire send

This matches the per-class semantic needs:
- CharaBase/Director state changes are PER-ACTOR and benefit from
  predictive apply (the player sees changes immediately)
- GroupBase state changes are PER-GROUP and don't need prediction
  (group state is naturally server-authoritative; client just relays)

## 3. Why GroupBase needs a separate opcode (0x133 not 0x12F)

Server-side dispatch reasoning:
- Server receives opcode 0x12F: "actor X changed field Y" -- routes
  to actor's WorkPath tree
- Server receives opcode 0x133: "group X changed field Y" -- routes
  to group's WorkPath tree (different storage from per-actor)

The dual opcodes let the server keep actor state and group state in
separate hash maps without ambiguity. Otherwise server would need
to check the WorkPath's first string ("charaWork" vs "groupWork")
to decide routing -- the opcode is a faster pre-routing hint.

## 4. The "secondary work-sync" hypothesis (refined)

The Ghidra symbol comment on WorkSyncAlt_serializePayloadAndSend_opcode_0x133
suggested:

> 0x133 = secondary work-sync (likely confirm/delete/lock?)

But the evidence from this finding shows:

> 0x133 = secondary work-sync USED EXCLUSIVELY BY GroupBase
> The "secondary" naming is correct (different routing target),
> but it's not "confirm/delete/lock" semantics -- it's the same
> SET-FIELD semantic as 0x12F, just for group-level state.

The prior speculation was wrong; this finding pins the actual use.

## 5. Updated wire opcode roster (for _updateWork callers)

```text
Class           Opcode  Packet  Predictive
-----           ------  ------  ----------
CharaBase       0x12F   56B     YES (UpdateQueue)
Director        0x12F   56B     YES (UpdateQueue)
Item            0x132   24B     NO (state notify only)
GroupBase       0x133   56B     NO (group is server-authoritative)
```

## 6. Server implementation implications (REFINED)

```text
SERVER INBOUND OPCODE HANDLERS (for _updateWork inbound):
  0x12F handler: actor work-sync (HP/MP/position/status/...)
  0x132 handler: item state (Bazaar lock/deal/trade)
  0x133 handler: group work-sync (roster/leader/...)

ALL 3 use the same Zone channel.
0x12F and 0x133 share the same WorkPath payload format.
0x132 has a unique compact byte+ushort format.

Server can implement 0x12F and 0x133 with shared parser code
since the payload format is identical -- they only differ in
routing target (actor table vs group table).
```

## 7. Cross-references

- `finding_updateWork_siblings_pattern_NOT_uniform.md` -- the prior
  finding that left this gap open
- `finding_updateWork_thunk_worksync_state_replication.md` -- the
  CharaBase opcode 0x12F path
- `finding_worksync_wire_opcode_0x12f.md` -- 0x12F packet layout
- `finding_item_master_20_of_20_registrars_complete.md` -- Item's
  opcode 0x132 first identified

## 8. Confidence

```text
Confirmed:
  - GroupBase _updateWork sends wire opcode 0x133 (NOT 0x12F)
  - 0x133 is "secondary work-sync" -- structurally identical to 0x12F
  - Both 0x12F and 0x133 use WorkPath_joinAsString serialization
  - GroupBase SKIPS predictive UpdateQueue enqueue (group state is
    server-authoritative)
  - Server should implement 0x12F and 0x133 with shared parser
  - Item's 0x132 is structurally DIFFERENT (24-byte byte+ushort)

Likely (High):
  - The 0x12F vs 0x133 opcode split is a server-side ROUTING HINT
    (actor table vs group table)
  - The "WorkSyncAlt" naming reflects this routing distinction
  - DesktopWidget and WorldMaster may have their own _updateWork
    variants if they exist (not yet checked)
```

## Commit suggestion

```
docs(re/exe): GroupBase _updateWork uses opcode 0x133 -- secondary WorkSync (56B twin of 0x12F, structurally identical, different routing target)
```
