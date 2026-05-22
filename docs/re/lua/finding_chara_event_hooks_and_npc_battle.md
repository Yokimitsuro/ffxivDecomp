# Finding: `CharaBaseClass` Event Hooks + NPC Battle Schema

Combined pass on two related pieces of the actor system:

1. **CharaBaseClass event hooks** — the `_onChange*` reactive callbacks
   that fire when server-pushed state changes land on an actor.
2. **NpcBaseClass battle schema** — the `npcWork.battleCommon` struct
   (parts + aggro), the data the DepictionJudge nameplate reads for
   monster rendering.

Sources read:

```text
chara/charabaseclass.lua                12.7 KB  (top-level method list)
chara/npc/npcbaseclass_battle.lua        2.0 KB  (full read; small file)
```

## CharaBaseClass top-level method inventory (partial; first 60)

Method roles, grouped:

```text
identity / relations
  isPlayer / isRestrictedByContents
  getPlayerParty / getParty / isPartyLeader
  getContentGroup / getCurrentContentGroup / hasCurrentContent
  getRelationGroup / hasRelationGroup / getRelationGroupFellow
  countRelationGroupMember
  countCommunityGroup / getCommunityGroup

status / state queries
  getMainSkill                       current job/class id
  getDepictionJudge                  back-pointer for nameplate
  isDeadMode / isSitMode
  getReadyCommand / getReadyCommandSlotLength / searchReadyCommand
  getCommandName
  getStatus / getStatusSlotLength / getStatusTime  -- buff/debuff slots

inventory / items
  hasItem / checkSameItemInPackage / getItemPackageItemCount

lifecycle
  _onInit
  _onUpdateDisplayName
  processUpdateInitWork

update receivers
  _onUpdateWork
  _onUpdateGroupCurrent
  _onUpdateItemPackage           updateItemPackage helper
  _onUpdateTradingItem
  updateGameParameters
  updateCommandAcquired / processUpdateCommandAcquired
  updateItemPackage

inbound packet dispatch
  _onReceiveDataPacket            (the "data" packetType handler;
                                   see finding_desktopwidget_packet_dispatch.md)
  processReceiveData              (subclass override slot)

reactive state-change hooks
  _onChangeActorMainStat
  _onChangeSubStatMode
  _onChangeSubStatStatus
  _onChangeNetStatSystem
  _onChangeNetStatUser
  _onChangeSystemFlag
  _onChangeJob
  _onChangeAccessibleInServer
```

(There are more methods after line 1734 not enumerated here.)

## The `_onChange*` reactive hooks — sync update fan-out

These are the **read-side counterpart** of `_bindWork`. When a server
update lands via the C++ PacketProcessor's sync path and writes into
`actor.work[field]`, the runtime additionally raises a typed event
to the actor's `_onChange*` hook. Each hook corresponds to a class of
state change:

```text
_onChangeActorMainStat(self, oldValue, newValue)
  fires when the actor's "main stat" changes. From earlier reading
  (finding_worldmaster_and_actor_packet_flow.md), main-stat value 15
  is the "riding" state -- the hook checks for this and triggers
  desktopWidget:processUpdateChocoboStatus().

_onChangeSubStatMode(self, ...)
  empty in CharaBaseClass; subclasses override.

_onChangeSubStatStatus(self, A1, A2, A3)
  invokes desktopWidget:processChangeSubStatStatus(self, A1, A2, A3).
  Drives the buff/debuff slot UI.

_onChangeNetStatSystem(self, ...)
  net status (system flag) change. Used by DepictionJudge for the
  net-status icons 312/313 in nameplate slot 1.

_onChangeNetStatUser(self, ...)
  net status (user-set) change. Icon 314 in nameplate slot 1.

_onChangeSystemFlag(self, ...)
  generic system flag change.

_onChangeJob(self, ...)
  job/class change. Triggers re-render of skill icons, command list.

_onChangeAccessibleInServer(self, ...)
  whether this actor is currently reachable on the server (online,
  not in instance, etc.).
```

### Combined picture: bindWork ↔ onChange

The work-sync system has TWO sides for each field:

```text
write side (sync update arrives)             read side (Lua reactive)
-------------------------------------------- ---------------------
binding 1010 -> actor.charaWork              _onChangeActorMainStat
.parameterSave.hp                            (when HP-state-change
                                              flag triggers)

binding 3006 -> actor.charaWork.property     _onChangeSystemFlag
                                             (when property bits flip)

binding 1001 -> actor.charaWork              _onChangeJob /
.parameterSave.state_mainSkill                _onChangeActorMainStat
```

So a single binding id update can raise multiple `_onChange*` hooks
depending on which fields actually changed. The runtime maintains the
correspondence; Lua scripts subscribe declaratively by **defining a
method with the right name**.

### Server implication for state changes

A server doesn't need to send "raise hook X" packets. It only sends
field updates (via the binding-id sync path). The client's runtime
fans out to the appropriate `_onChange*` hooks automatically by
observing which fields changed.

So **the wire surface for state change is the same as the wire
surface for sync** — just the binding ids and their payload formats.

## NPC Battle Schema (full)

`NpcBaseClass:initForBattleCommon(npc, aggro, partsName, partsExists_1..8)`
populates the per-NPC battle state at `npcWork.battleCommon`:

```text
npcWork.battleCommon = {
  aggro         int8           -- aggro level (0 = no aggro on player,
                                  >0 = aggro present)
  partsName     int32          -- name id for body-parts label
  partsExists   array[8] bool  -- per-body-part existence flags
  _nesting      schema         -- declares this is a nested-struct
                                  field for the work-sync engine
}
```

The `_nesting` schema (also pinned this pass):

```text
_nesting = [
  {"partsName",   "integer32"},
  {"partsExists", "array", 8, "boolean"},
  {"aggro",       "integer8"}
]
```

This schema declaration is what the work-sync engine uses to walk and
update individual fields within `battleCommon`.

### Accessors

```text
NpcBaseClass:getPartsName()       -> npcWork.battleCommon.partsName
NpcBaseClass:isPartsExists(idx)   -> npcWork.battleCommon.partsExists[idx]
NpcBaseClass:getAggro()           -> npcWork.battleCommon.aggro
```

`getAggro` is **the function DepictionJudge calls** to decide
between nameplate slot-2 icons 517 (NM with aggro) and 518 (NM idle).
So:

```text
server pushes aggro field update for NPC actor
   -> npcWork.battleCommon.aggro = newValue
   -> next DepictionJudge:judgeNameplate(npc) call
        -> getAggro() returns new value
        -> if aggro > 0 -> icon 517
           else        -> icon 518
```

The nameplate "this monster has aggro on me" indicator is therefore
driven by a single int8 field that updates via the work-sync system.

### Server implication for NPC battle state

To put an enemy NPC into a fight-ready state:

```text
1. Push npcWork.battleCommon.partsName  (int32; the body-parts label)
2. Push npcWork.battleCommon.partsExists[1..8]  (bools; which parts
   are alive)
3. Push npcWork.battleCommon.aggro  (int8; 0 if not engaged, >0 if
   engaged with at least one player)
```

When a player damages a specific body part:

```text
1. Server marks partsExists[partIdx] = false
2. Push update for that array element
3. Client's runtime updates npcWork.battleCommon.partsExists[partIdx]
4. Next nameplate render reflects the part being destroyed (if the
   nameplate shows parts; that's a per-NPC variation).
```

Boss fights with multi-target bodies (1.x had several) used this
8-part model. The hostile vs idle visual distinction is solely from
the aggro field, regardless of which parts are alive.

## Cross-references with previous findings

```text
binding 5001  npcWork.actorClassId          (from bindWork catalog)
NPC.npcWork = {
  actorClassId               (1010-ish per NPC; from sheet)
  battleCommon = {           (this finding; pinned)
    partsName / partsExists / aggro
  }
  -- more fields probably exist; full schema TBD
}
```

So `npcWork` is a struct with at least `actorClassId` and
`battleCommon` substructures. The full enumeration would need reading
`npcbaseclass.lua` initWork.

## Assessment

```text
Confirmed:
  - CharaBaseClass declares 8 _onChange* reactive hooks (ActorMainStat,
    SubStatMode, SubStatStatus, NetStatSystem, NetStatUser,
    SystemFlag, Job, AccessibleInServer).
  - These hooks are the read-side counterpart of _bindWork: a single
    sync update from the server can raise multiple _onChange*
    callbacks depending on which fields changed.
  - NpcBaseClass:initForBattleCommon establishes the battle schema:
    npcWork.battleCommon = {aggro int8, partsName int32,
    partsExists bool[8]}.
  - NpcBaseClass:getAggro() is the function DepictionJudge calls for
    the slot-2 nameplate icon selection (517 hostile / 518 idle).

Likely (High):
  - CharaBaseClass has more _onChange* hooks beyond line 1734 that
    weren't enumerated this pass (e.g. _onChangeHp, _onChangeBuff,
    _onChangeStatus). Reading the rest of the file would surface them.
  - The runtime mapping from a binding id update to a Lua _onChange*
    invocation is data-driven (a table mapping field paths to hook
    names). Reading the C++ side of _bindWork would surface the table.

Likely (Medium):
  - The partsExists bool[8] supports up to 8 named body parts per NPC.
    Used in 1.x for boss fights like Ifrit (horns + body), Lesser
    Garuda (wings + body), Hamlet Defense waves (multi-segment
    enemies). Each part is shown in the targeting cursor / nameplate.
  - aggro values are likely small integers (0..N where N is the
    server's aggro tier count); the int8 storage suggests up to 127
    discrete aggro states.

Speculative:
  - The _onChange* hook names are auto-derived from the field name
    via a runtime convention: field "actorMainStat" -> hook
    "_onChangeActorMainStat". If true, declaring a new field on a
    work struct would automatically wire up the hook lookup.

Next test:
  - Read CharaBaseClass lines 1734..end for the remaining methods
    (the file is 12.7 KB so probably ~50 more methods).
  - Read npcbaseclass_u.lua (4.4 KB) for the full NPC native binding
    table. That should expose more bindings in the 5000 range and
    the rest of the NPC C++ method surface.
  - Find the C++ side of the field->hook mapping. The runtime data
    table is probably built at engine startup and is data-driven.

Commit suggestion:
  docs(re/lua): CharaBase _onChange hooks + NPC battle schema (parts +
                aggro)
```

## Server implication (consolidated)

The minimal-viable-server picture for ACTOR STATE is now complete:

1. **For every visible actor on screen**, push `charaWork.parameterSave`
   fields (hp, hpMax, mainSkill, mainSkillLevel) via bindings
   1001/1010/1011/1012.
2. **For NPC actors specifically**, push `npcWork.battleCommon`
   fields (aggro, partsName, partsExists). Without these, the nameplate
   defaults to "neutral neutral neutral" colors.
3. **State change "events" are free** — the client raises
   `_onChange*` hooks automatically as fields update; no separate
   "raise hook" packet needed. Subclass overrides in scripts
   (e.g. `Player._onChangeJob`) get invoked when the corresponding
   field updates.

This is **a much smaller surface** than enumerating every
"OnXxxChanged" opcode separately. The server's responsibility is
field-level, not event-level.
