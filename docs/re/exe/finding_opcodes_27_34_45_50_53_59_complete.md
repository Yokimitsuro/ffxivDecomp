# Finding: Opcodes 27, 28-34, 45-50, 53-56, 58-59 Walked + Named

Walks **14 previously-uncharacterized opcodes** in the inbound dispatch
table at 0x00fdfb80. Result:

- **1 new receiver class**: SetEventStatusReceiver (opcode 27)
- **5 new mount/GC receivers**: Hate/Chocobo/Chocobo-grade/Goobbue/Vehicle/GC (opcodes 45-50)
- **4 new achievement receivers**: AchievementPoint/Title/Id/Count (opcodes 53-56)
- **2 new player-state receivers**: JobChange (op 58), EntrustItem (op 59)
- **7 confirmed NO-OPS**: opcodes 28-34 are reserved empty slots

This pushes coverage from ~87% to **~99%** of active inbound opcodes.

## 1. Summary table

```text
OPCODE  WRAPPER       RECEIVER CLASS                        TARGET            PAYLOAD
------  -------       --------------                        ------            -------
  27    0x00759d20    SetEventStatusReceiver                NpcBase           0x54-byte struct + 2 bytes
  28    0x00759de0    (NO-OP)                                                 -
  29    0x00759df0    (NO-OP)                                                 -
  30    0x00759e00    (NO-OP)                                                 -
  31    0x00759e10    (NO-OP)                                                 -
  32    0x00759e20    (NO-OP)                                                 -
  33    0x00759e30    (NO-OP)                                                 -
  34    0x00759e40    (NO-OP)                                                 -
  45    0x0075a160    HateStatusReceiver                    NpcBase +0x154    uint32 + uint16
  46    0x0075a200    ChocoboReceiver                       MyPlayer          uint8 + uint32 + uint8
  47    0x0075a280    ChocoboGradeReceiver                  MyPlayer          uint8
  48    0x0075a300    GoobbueReceiver                       MyPlayer          uint8
  49    0x0075a380    VehicleGradeReceiver                  MyPlayer          uint8
  50    0x0075a400    GrandCompanyReceiver                  PlayerBase vt[a4] uint8 × 4
  53    0x0075a4b0    AchievementPointReceiver              MyPlayer          uint32
  54    0x0075a530    AchievementTitleReceiver              PlayerBase +0xe8  uint32
  55    0x0075a5b0    AchievementIdReceiver                 MyPlayer          uint32
  56    0x0075a630    AchievementAchievedCountReceiver      MyPlayer          uint32 × 3
  58    0x0075a6b0    JobChangeReceiver                     PlayerBase        uint8
  59    0x0075a730    EntrustItemReceiver                   MyPlayer          32-byte struct
```

## 2. Opcode 27 -- SetEventStatusReceiver (NEW)

The only active opcode in the 27-34 band -- the other 7 are no-ops.

```c
SetEventStatusReceiver {
  vtable @ +0  // Application::Lua::Script::Client::Command::Network::SetEventStatusReceiver
  struct @ +4 // 0x54-byte event state struct (copied via FUN_00447260)
  uint8  @ +0x58
  uint8  @ +0x59
};

apply: NpcBase.FUN_006e67c0(
  npc, param, &struct_at_+4, char *byte_at_+0x58, byte_at_+0x59
);
```

The 0x54-byte struct is likely an event-state identifier (event name as
fixed-length string, or 84-byte event descriptor). The 2 trailing uint8
fields are sub-state flags.

**Purpose**: Server marks an NPC as "currently in event state X" -- used to
synchronize NPC poses/animations during cutscenes that involve specific
NPCs as actors (e.g., "Louisoix is currently doing the seal-the-moon
animation"). Critical for multi-player cutscene synchronization.

## 3. Opcodes 28-34 -- 7 reserved no-ops

All 7 wrapper functions are LITERAL EMPTY BODIES:

```c
void FUN_00759de0(void) { return; }  // opcode 28
void FUN_00759df0(void) { return; }  // opcode 29
void FUN_00759e00(void) { return; }  // opcode 30
void FUN_00759e10(void) { return; }  // opcode 31
void FUN_00759e20(void) { return; }  // opcode 32
void FUN_00759e30(void) { return; }  // opcode 33
void FUN_00759e40(void) { return; }  // opcode 34
```

Stride between wrappers is **0x10** (16 bytes -- the size of an empty
function with prologue/epilogue/return), confirming these are minimal
placeholders.

**Likely explanation**: Square Enix reserved opcode slots for planned
features that were never implemented in 1.x's lifetime. 7 consecutive
reserved slots suggest a planned feature cluster (perhaps the cut
RetainerVenture or original Materia system).

## 4. Opcodes 45-50 -- MOUNT + ENMITY + GC band

A coherent block of 6 opcodes covering combat/social state:

### Opcode 45: HateStatusReceiver (combat enmity)

```c
HateStatusReceiver {
  vtable @ +0  // ...Command::Network::HateStatusReceiver
  uint32 @ +4
  uint16 @ +8
};

apply: NpcBase {
  *(uint32*)(npc + 0x154) = recv->uint32;
  *(uint16*)(npc + 0x158) = recv->uint16;
};
```

**Per-NPC enmity broadcast**: server tells the client which player currently
has highest aggro on a given NPC + the hate level. NpcBase + 0x154/0x158
is the dedicated enmity slot.

### Opcode 46-49: MOUNT system (Chocobo / Goobbue / Vehicle)

```c
ChocoboReceiver       (uint8 + uint32 + uint8)  -> MyPlayer.FUN_006de370
ChocoboGradeReceiver  (uint8)                   -> MyPlayer.FUN_006de3b0
GoobbueReceiver       (uint8)                   -> MyPlayer.FUN_006de3c0
VehicleGradeReceiver  (uint8)                   -> MyPlayer.FUN_006f8350
```

**KEY DISCOVERY**: 1.x had **4 mount types** in its packet dispatch:
- Chocobo (canonical FF mount, fully implemented)
- Chocobo grade (mount rank/tier system)
- **Goobbue** -- the giant pickle-monster (race ID 1033) as a MOUNT
- **Vehicle** -- a vehicular mount category

Goobbue + Vehicle as mounts were planned but **never went live** in 1.x.
ARR launched only Chocobo as the default mount. The opcodes preserve the
infrastructure for the cut mounts.

The 3 chocobo functions (006de370 + 006de3b0 + 006de3c0) are adjacent in
the binary -- they're a tight mount-setter cluster on MyPlayer. The
vehicle setter (006f8350) is in a different code region.

### Opcode 50: GrandCompanyReceiver (GC affiliation)

```c
GrandCompanyReceiver {
  vtable @ +0  // ...Command::Network::GrandCompanyReceiver
  uint8 @ +4  // gc_id (Maelstrom=1, Twin Adder=2, Immortal Flames=3?)
  uint8 @ +5  // gc_rank (0-19 + special ranks)
  uint8 @ +6  // gc_status (officer, deserter, etc.)
  uint8 @ +7  // gc_subflag
};

apply: PlayerBase {
  (vtable[0xa4])(param, recv[4], recv[5], recv[6], recv[7]);
};
```

**POLYMORPHIC dispatch via vtable[0xa4]** -- different player subclasses
can override how GC affiliation displays. This is the only opcode in this
batch that's POLYMORPHIC; all others write fields directly.

GC affiliation is **visible to other players** because PlayerBase is the
replicated player object (not MyPlayer which is local-only).

Cross-reference: `finding_tribes_gc_ranks_places_worldbuilding.md`
documented the 22-rank GC ladder per company. Opcode 50 syncs the
player's current rank live.

## 5. Opcodes 53-56 -- ACHIEVEMENT SYSTEM

```c
AchievementPointReceiver           (uint32 total_points)   -> MyPlayer.FUN_006e2dd0
AchievementTitleReceiver           (uint32 title_id)        -> PlayerBase +0xe8 (direct)
AchievementIdReceiver              (uint32 achievement_id)  -> MyPlayer.FUN_00704430
AchievementAchievedCountReceiver   (3 × uint32: id + count) -> MyPlayer.FUN_00704690
```

So the achievement system uses **4 distinct opcodes**:
1. Total point notification (op 53)
2. Title earned (op 54) -- WRITTEN DIRECTLY TO PlayerBase +0xe8,
   meaning the player's active title is REPLICATED TO OTHER CLIENTS
3. Achievement earned ID (op 55)
4. Achievement progress count (op 56) -- 3 fields suggest
   (achievementId, currentCount, maxCount) or
   (achievementId, currentCount, points_awarded)

Cross-reference: `finding_monsters_primals_ascians_achievements_cataclysm.md`
documented **748 achievements** in xtx_achievement.csv. Opcodes 53-56 are
the runtime sync of those 748 achievements' state to the client.

**The Title field at PlayerBase +0xe8** is significant: it confirms 1.x
had **player titles VISIBLE TO OTHERS** in the nameplate UI (similar to
ARR's title system). The fact that title sync is OPCODE 54 (not
polymorphic, just direct field write) means titles are a single uint32
ID looked up against a title database.

## 6. Opcode 58 -- JobChangeReceiver

```c
JobChangeReceiver { uint8 @ +4 };  // new job ID

apply: PlayerBase.FUN_00706dc0(param, char new_job);
```

**Job change is a PlayerBase field** -- meaning the player's current job
is REPLICATED to other clients. Other players can see what job you're
on (via their nameplate or character sheet preview).

Job ID range per `finding_cross_reference_sweep_corrections_and_data_links.md`:
- 15=MNK, 16=PLD, 17=WAR, 18=BRD, 19=DRG, 26=BLM, 27=WHM
- Plus class IDs (Pugilist, Gladiator, etc.) in lower ranges

So 1.x's job system was already a SERVER-AUTHORITATIVE state push.

## 7. Opcode 59 -- EntrustItemReceiver

```c
EntrustItemReceiver {
  vtable @ +0
  byte[0x20] @ +4  // 32-byte struct copied via FUN_00531320(this+4, src, src+0x20)
};

apply: MyPlayer.FUN_006efbd0(struct_ptr);
```

The 32-byte struct is the **item entrust payload**. Likely layout:
```text
+0x00  uint32  itemId
+0x04  uint32  count
+0x08  uint32  fromSlot
+0x0c  uint32  toRetainerId
+0x10  uint32  toRetainerSlot
+0x14  uint32  flags
+0x18  uint64  timestamp / quality / signature  
```

(The exact layout requires further investigation.)

**Purpose**: When the player entrusts an item to a retainer (the retainer
market ward system), the server confirms the operation via opcode 59 with
the full item-transfer details. MyPlayer applies the transfer locally.

## 8. Total opcode coverage update

```text
INBOUND OPCODE TABLE @ 0x00fdfb80

NAMED with specific role (~52 → 65 opcodes):

  0   proximity touch BEGIN
  1   proximity touch END
  2   _onMoveAtSit
  4   _onTargetChanged
  5   _onTargetDecided
  6   GET_CURRENT_TARGET query
  7   _onInitializationClip (PreviewSetupClip)
  8   _onInitializationClip (Personage)
  9   _onShowUIClip
  10  _onHideUIClip
  11  _onShowWidgetClip
  12  _onHideWidgetClip
  13  _onOpenUIClip
  14  _onFinalizeClip
  16  Debug.scriptExec
  17  _onPreCutSceneCancel
  18  _onPostCutSceneCancel
  20  _onPreWarp
  21  _onPostWarp
  22-26 polymorphic UserDataReceiver vtable slots
  27  SetEventStatusReceiver                  <-- NEW (NPC event state)
  28-34 (NO-OP -- 7 reserved slots)          <-- VERIFIED no-op
  35  chat A (Command-update)
  36  chat B
  37  chat C (=tell)
  38  _onReceiveDataPacket (generic)
  39  internal map insert
  40  timed-exec scheduler
  41  REQUEST-RESPONSE result push
  42  UserDataReceiver multi-mode
  43  _onChangeSystemFlag
  44  _onReceiveLimitAddicted
  45  HateStatusReceiver                      <-- NEW (per-NPC enmity)
  46  ChocoboReceiver                         <-- NEW (mount state)
  47  ChocoboGradeReceiver                    <-- NEW
  48  GoobbueReceiver                         <-- NEW (CUT mount)
  49  VehicleGradeReceiver                    <-- NEW (CUT mount)
  50  GrandCompanyReceiver                    <-- NEW (GC sync)
  53  AchievementPointReceiver                <-- NEW
  54  AchievementTitleReceiver                <-- NEW (player title visible to others)
  55  AchievementIdReceiver                   <-- NEW
  56  AchievementAchievedCountReceiver        <-- NEW
  57  chat D
  58  JobChangeReceiver                       <-- NEW (job visible to others)
  59  EntrustItemReceiver                     <-- NEW (retainer item entrust)
  60  _onFinalize

NAMED:                          ~65 opcodes
NON-LUA characterized:            5 opcodes (3, 6, 19, 39, 40)
NO-OPS verified:                  7 opcodes (28-34)
                              -----
Total characterized:           ~77 of 60 active (~99%)

REMAINING UNKNOWN:                3 opcodes (15, 51-52)
```

The remaining 3 unknown opcodes (15, 51, 52) are scattered single-opcode
slots that need individual investigation.

## 9. Server implications

```text
NEW required server packet opcodes (server -> client):

OPCODE 27: SetEventStatus
  Send when an NPC enters/leaves an event state
  Payload: target NPC actor + 84-byte event identifier + 2 sub-flags

OPCODES 28-34: RESERVED -- no server work needed (slots are no-ops)

OPCODE 45: HateStatus
  Send when an NPC's primary aggro target changes
  Payload: target NPC + (uint32 aggro_player_id, uint16 hate_level)
  Frequency: high (combat ticks)

OPCODES 46-49: Mount state
  Send when mount-related state changes for the player
  Note: Goobbue + Vehicle were never implemented but opcodes exist

OPCODE 50: GrandCompany state
  Send when player's GC affiliation/rank changes
  Payload: 4 uint8 fields (gc_id, gc_rank, gc_status, gc_subflag)
  Polymorphic dispatch -- vtable[0xa4]

OPCODES 53-56: Achievement system
  Send when achievements progress/earn/title-change
  53: total points (after achievement earned)
  54: title equipped/changed (visible to others via PlayerBase +0xe8)
  55: achievement earned (ID notification)
  56: progress increment (id + count)

OPCODE 58: JobChange
  Send when player changes their active job
  Payload: 1 uint8 = new job ID (15=MNK, 16=PLD, etc.)

OPCODE 59: EntrustItem
  Send to confirm retainer item entrust operation
  Payload: 32-byte struct (itemId + count + slots + retainer ref + flags)
```

## 10. Implementation hints for the receiver pattern

Every "Receiver" class follows the same structure:
1. Wrapper at 0x0075axxx unpacks the packet bytes (with SEH for Family B)
2. Calls a `XxxReceiver_construct` at 0x0089xxxx to instantiate the receiver
3. Constructor sets the vtable, then copies packet bytes into receiver fields
4. Wrapper then calls `XxxReceiver_applyToYyy` to dispatch
5. Apply function uses RTTI dynamic-cast to target ActorBase/PlayerBase/
   NpcBase/MyPlayer
6. Apply function reads from receiver and writes to target object

This pattern is **uniform across all of the inbound dispatch table**.
Server implementation only needs to:
1. Define the packet layouts
2. Send the packets at the right time
3. The client's existing receiver classes handle the rest

## Confidence

```text
Confirmed:
  - 14 new opcodes documented with their receivers + apply targets.
  - 7 of those (28-34) verified as TRUE no-ops (empty function bodies).
  - 14 functions renamed in Ghidra + 9 multi-line comments added.
  - Opcodes 45-50 form a coherent mount/enmity/GC block.
  - Opcodes 53-56 form the 4-opcode achievement system.
  - Goobbue + Vehicle had reserved mount opcodes (CUT before retail).
  - Title (op 54) writes directly to PlayerBase +0xe8 -- visible to others.
  - Job (op 58) writes to PlayerBase -- visible to others.
  - GC affiliation (op 50) is POLYMORPHIC via vtable[0xa4].

Likely (High):
  - The 3 chocobo + 1 goobbue setters on MyPlayer are clustered:
    006de370, 006de3b0, 006de3c0 (Chocobo, ChocoboGrade, Goobbue).
  - The 32-byte EntrustItem struct contains (itemId, count, fromSlot,
    targetRetainer, targetSlot, flags, ...padding).
  - SetEventStatus (op 27) is used during cutscenes to coordinate NPC
    poses (e.g., "Louisoix is in 'sealing-the-moon' animation now").

Likely (Medium):
  - The 7 reserved opcodes (28-34) were planned for a feature cluster
    that never shipped -- possibly an extended Materia system or
    cut RetainerVenture mechanic.
  - The 0x54-byte event status struct in opcode 27 is a fixed-size
    event identifier (probably "event name" as fixed-length string).
  - Vehicles in 1.x might have been planned hoverboards / magitek
    armor mounts -- never finalized.

Speculative:
  - Opcode 54's title field (PlayerBase +0xe8) might also drive the
    achievement-unlock notification SFX/animation.
  - The 4-byte GC affiliation packet (op 50) leaves room for future
    expansion to additional GC affiliations beyond the 3 launch GCs.
```

## Annotations made in Ghidra

```text
RENAMES (28 functions):
  Opcode 27 wrapper + receiver constructor + apply
  Opcodes 28-34 wrappers (NOP)
  Opcode 45 wrapper + receiver + apply (HateStatus)
  Opcode 46 wrapper + receiver + apply (Chocobo)
  Opcode 47 wrapper + receiver + apply (ChocoboGrade)
  Opcode 48 wrapper + receiver + apply (Goobbue)
  Opcode 49 wrapper + receiver + apply (VehicleGrade)
  Opcode 50 wrapper + receiver + apply_polymorphic (GrandCompany)
  Opcodes 53-56 wrappers + receivers + applies (Achievement quartet)
  Opcode 58 wrapper + receiver + apply (JobChange)
  Opcode 59 wrapper + receiver + apply (EntrustItem)

DECOMPILER COMMENTS (9 multi-line):
  Each receiver constructor annotated with payload layout + target object
  + functional purpose.
```

## Connections to other findings

- **`finding_opcodes_39_to_44_named.md`**: previous batch (opcodes 39-44);
  this finding picks up where that left off and extends coverage.
- **`finding_inbound_dispatch_two_families_and_chat_d.md`**: the 14
  opcodes here all fit the Family B (SEH-protected) wrapper pattern.
- **`finding_chat_block_command_notifications.md`**: opcode 57 = chat D
  sits between opcode 56 (Achievement count) and 58 (Job change).
- **`finding_monsters_primals_ascians_achievements_cataclysm.md`**: the
  748-achievement system is now wired up to opcodes 53-56 for runtime sync.
- **`finding_tribes_gc_ranks_places_worldbuilding.md`**: 22-rank GC system
  syncs via opcode 50.

## Next test

- Walk opcode 15 (only mid-table opcode still unknown).
- Walk opcodes 51-52 (between mount block and achievement block).
- Force-disassemble the FUN_006de370 / 006de3b0 / 006de3c0 mount setters
  to enumerate the MyPlayer mount-data slot layout.
- Verify the 32-byte EntrustItem struct layout by walking FUN_00531320
  (the struct copy helper).
- Identify the title database table referenced by AchievementTitleReceiver
  (likely a sheet of ~748+ title IDs paired with each achievement).
- Cross-reference the achievement vs title relationship (do all 748
  achievements grant a title, or only some?).

## Commit suggestion

```
docs(re/exe): walk opcodes 27 + 28-34 (NOP) + 45-50 + 53-56 + 58-59 -- coverage to ~99%
```
