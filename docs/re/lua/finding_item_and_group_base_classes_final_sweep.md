# Finding: ItemBaseClass + GroupBaseClass Base Classes (final base-mechanics sweep)

**Completes the engine base-mechanics sweep.** Documents the two
remaining base classes — ItemBaseClass and GroupBaseClass — both thin
shells whose substantial logic lives in `_common` files / subclass
families already covered by prior findings. Key new facts: item CSV
binding set, group 256-member capacity, and the group member-update
callbacks that are the INBOUND side of the MemberInfoUpdater (0x18b)
wire packet.

## 1. ItemBaseClass (68 lines, base shell)

```text
_onInit(self):
   -> _callSuperClassFunc("_onInit")  (ActorBase)
   -> _bindSpreadSheetData(itemDataSheet)    item stats
   -> _bindSpreadSheetData(equipmentSheet)   equipment data
   -> _bindSpreadSheetData(weaponSheet)      weapon stats
   -> _bindSpreadSheetData(armorSheet)       armor stats
   -> _bindSpreadSheetData(accessorySheet)   accessory stats
   -> if owned: worldMaster:_loadWord("itemName", catalogId)
      (load localized item name)

_onFinalize(self):
   -> if owned: worldMaster:_unloadWord("itemName", catalogId)

An item instance BINDS the 5 item-stat CSVs (so it can query its
stats by catalog id) and loads its localized name on init. The
190+ stat-query functions are in ItemBaseClass_common (4686 lines,
prior finding finding_item_common_inventory.md).

ITEM CSV SET (the 5 stat tables):
  itemData, equipment, weapon, armor, accessory
  (these are also the tables CommonJudge loads -- shared calc data)
```

## 2. GroupBaseClass (71 lines, base shell)

```text
_onInit(self):
   -> _callSuperClassFunc("_onInit")
   -> groupWork._temp = { _assignForChild = 256 }
   -> groupWork._sync = { _assignForChild = 256 }
   -> init()

MEMBER-UPDATE CALLBACKS (empty in base; subclasses override):
  _onUpdateMember(self, ?, ?)
  _onUpdateMemberInformation(self, ?)
  _onUpdateGroupInformation(self, ?)
  _onUpdateWork(self, ?)

init / _onFinalize

KEY FACTS:
1. 256-MEMBER CAPACITY: _assignForChild = 256 (vs area's 64). Groups
   (especially linkshells) can hold up to 256 members.
2. groupWork has _temp (local) + _sync (replicated) tiers, like Director.
3. The member-update callbacks are the INBOUND WIRE HANDLERS for
   group state -- they fire when the server pushes group updates.
```

## 3. Group callbacks = inbound side of Group:: wire packets

```text
The GroupBaseClass _on* callbacks are the LUA-SIDE RECEIVERS for the
Group:: typed packets mapped in the wire findings:

  Wire packet (EXE)              Lua callback (this finding)
  -----------------              ---------------------------
  MemberInfoUpdater (0x18b)  ->  _onUpdateMemberInformation
  EntryLinkShellBuilder      ->  _onUpdateMember (member added/removed)
    (0x188/0x189)
  (group info update)        ->  _onUpdateGroupInformation
  WorkSyncUpdater (0x187)    ->  _onUpdateWork

So the EXE Group:: subclass packets (from the spawn-pipeline /
typed-packet findings) deliver INTO these GroupBaseClass Lua
callbacks. This closes the loop:
  Server -> 0x18b MemberInfoUpdater -> spawn pipeline -> GroupBase
  -> _onUpdateMemberInformation -> Lua updates the group roster UI

The Group_invokeLua_onUpdateMember* EXE functions (from the
invokeLua roster finding) are the bridge that calls these.
```

## 4. Group subclass families (prior findings)

```text
GroupBaseClass subclasses (4 families, per prior findings):
  PartyGroup (u9sql3svpu)       PlayerPartyGroup / MonsterPartyGroup
  CommunityGroup (7vxxpw1ql)    GrandCompanyGroup / RetainerGroup / Linkshell
  ContentGroup (7vwq5wq)        instance-scoped roster (kinds 30001/30006)
  RelationGroup (s5y9q1vw)      Trade/Invite/Bazaar 2-actor confirmations

(documented in finding_relation_group_family.md,
 finding_party_subclasses_and_weather.md,
 finding_company_group_freecompany.md)
```

## 5. Server-side implications

```text
ITEMS:
  - Item instances bind 5 stat CSVs (itemData/equipment/weapon/armor/
    accessory) -- client-local stat data
  - Server tracks item OWNERSHIP + catalog id + quantity + condition;
    client computes stats from the CSVs (per level-adjust formulas)
  - Localized item names loaded client-side (worldMaster:_loadWord)

GROUPS:
  - Server maintains group rosters (up to 256 members)
  - Server pushes group updates via Group:: typed packets:
    * 0x188/0x189 EntryLinkShellBuilder (member join/leave)
    * 0x18b MemberInfoUpdater (member info change)
    * 0x187 WorkSyncUpdater (group state)
  - Client receives via GroupBase _onUpdateMember* callbacks
  - groupWork._sync = the replicated group state (server-authoritative)

This completes the group wire<->Lua loop: the EXE Group:: subclasses
(producer) deliver to the GroupBase Lua callbacks (consumer).
```

## 6. ENGINE BASE-MECHANICS SWEEP COMPLETE

```text
All 13 base mechanics now documented:
  1. ActorBase (lifecycle) -- via createActor/spawn findings
  2. CharaBase (battle/event schemas)
  3. PlayerBase (command flow)
  4. NpcBase (talk/events)
  5. AreaBase (zone bootstrap)
  6. DirectorBase (content orchestration)
  7. QuestBase (quest engine)
  8. StatusBase (status effects)
  9. CommandBase (action model)
  10. Judge (data provider + depiction)
  11. ItemBase (this finding -- stat CSV binding)
  12. GroupBase (this finding -- 256-member, update callbacks)
  13. WidgetBase / DesktopWidget (UI orchestrator)

Plus the cross-cutting systems: server-notify/notice authorization,
spawn pipeline, WorkSync, the 4-confirmed client-side-content principle.

The remaining ~2600 Lua files are CONTENT INSTANCES (concrete quests,
NPCs, directors, statuses, commands, items, widgets) that INSTANTIATE
these documented base patterns. Reading them = content cataloging,
not engine understanding.
```

## 7. Confidence

```text
Confirmed:
  - ItemBaseClass binds 5 stat CSVs + loads localized name
  - GroupBaseClass: 256-member capacity, _temp+_sync work tiers
  - Group _on* callbacks = inbound receivers for Group:: wire packets
  - 4 group subclass families (party/community/content/relation)
  - Both _common/family logics covered by prior findings

Likely (High):
  - _onUpdateMemberInformation <- 0x18b MemberInfoUpdater (direct mapping)
  - _onUpdateMember <- EntryLinkShellBuilder member changes (0x188/0x189)
  - 256-member capacity = linkshell max (vs party ~8, content rosters)
  - Item stat computation is client-side (server tracks ownership)

Confirmed sweep:
  - 13 base mechanics documented; remaining corpus = content instances
```

## 8. Cross-references

- `finding_item_common_inventory.md` -- the 190+ item stat functions
- `finding_relation_group_family.md` -- RelationGroup (2-actor confirmations)
- `finding_party_subclasses_and_weather.md` -- PartyGroup subclasses
- `finding_company_group_freecompany.md` -- GrandCompany/CommunityGroup
- `finding_group_typed_packets_remaining_opcodes_0x187_0x18b.md` --
  the Group:: wire packets these callbacks receive
- `finding_linkshell_wire_opcodes_0x188_0x189_CLOSED.md` -- EntryLinkShellBuilder
- `finding_directorbaseclass_content_orchestration_model.md` -- the
  _temp/_sync work-tier pattern (shared with groups)

## 9. Next test

```text
Engine architecture sweep is COMPLETE. Remaining work options:
1. CONTENT CATALOGING: read concrete instances (specific quests/NPCs/
   directors) for a content database
2. CSV DATA: the ~125 remaining FFXIVTool CSVs (server content tables)
3. FINE DETAIL: command payload byte layout, per-director _sync schemas,
   specific status/item formulas
4. CONSOLIDATION: a unified "server implementation guide" synthesizing
   all findings into an implementation roadmap
```

## Commit suggestion

```
docs(re/lua): ItemBase + GroupBase base classes -- item binds 5 stat CSVs; group 256-member + _onUpdateMember* callbacks (inbound side of 0x18b/0x187/Linkshell wire); ENGINE BASE-MECHANICS SWEEP COMPLETE (13 mechanics)
```
