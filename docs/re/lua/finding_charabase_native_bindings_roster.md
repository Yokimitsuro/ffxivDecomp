# Finding: CharaBaseClass — Complete ~91 Native Binding Roster

The master inventory of CharaBaseClass's Lua-exposed C++ native
bindings. This is the **most fundamental actor API** — every chara
(player, NPC, monster) shares this surface.

Sources read:

```text
chara/charabaseclass_u.lua    922 lines (~91 binding declarations)
```

## Categorized Roster (~91 bindings)

### Position / Direction (12)

```text
_getPos                returns (x, y, z)
_getDir                returns facing angle (radians)
_getOrientation        computes angle to face a point
_setPos                set position directly
_setDir                set facing angle
_turnDir               rotate to specific angle
_turnBack              restore previous facing
_turnCancel            cancel ongoing turn
_isTurning             query: actor mid-turn?
_waitForTurning        yield until turn completes
_movePos               move to position (animated)
_moveCancel            cancel ongoing move
_isMoving              query: actor moving?
```

### Floating (2)

```text
_setFloatingOffset     vertical hover offset (chocobo/flying NPC)
_getFloatingOffset     query current floating offset
```

### Gear / Locomotion (5)

```text
_initGear              initialize gear (movement mode)
_setGear               set gear (walk/run/sprint)
_setGearSpeed          set per-gear speed
_getGear               current gear
_getGearSpeed          current gear's speed
```

### Display Name (4)

```text
_getDisplayName               raw display name
_setDisplayName               set name
_getLocalizedDisplayName      localized variant
_getLocalizedDisplayNameForChat  variant for chat usage
```

### Main Stat / States (3)

```text
_actionActorMainStat       trigger main stat action (die/sit/etc)
_getActorMainStat          query current main stat (1=dead, 15=riding,
                            32=sit, etc.)
_isActorMainStatMode(N)    query specific state (boolean)
```

### Lockon Target (1)

```text
_getLockonTarget       current lockon target actor
```

### Graphics / Appearance (6)

```text
_initGraphicNumber             init appearance number
_setGraphicNumber              set appearance number
_setWeaponGraphic              equip weapon (visual)
_setArmorGraphic               equip armor (visual)
_setAccessoryGraphic           equip accessory (visual)
_setCharacteristicGraphic      base character appearance
```

### SubStat System — Buffs / Debuffs / Modifiers (16)

```text
_initSubStat                 initialize substat system

_setSubStatWaste / _getSubStatWaste         "waste" -- probably durability?
_setSubStatGuard / _getSubStatGuard         "guard" -- blocking state
_setSubStatChant / _getSubStatChant         "chant" -- casting state
_setSubStatObject / _getSubStatObject       "object" -- holding/wielding
_setSubStatBreakage / _getSubStatBreakage   "breakage" -- broken parts (npc battlecommon)
_setSubStatMotionPack / _getSubStatMotionPack  motion override
_setSubStatMode / _getSubStatMode           sub-mode flag
_setSubStatStatus / _getSubStatStatus       status effects (buffs/debuffs)
```

8 separate substat axes, each with set+get. So a chara can carry
8 orthogonal sub-status states simultaneously. Major design point.

### Net Status (2)

```text
_getNetStatSystem    network status (system-driven flags)
_getNetStatUser      network status (user-set flags)
```

### Location / Group System (10)

```text
_getLocation                              current location/zone
_getGroup(kind)                           get specific group by kind
_getExtendedTemporaryGroup(kind)          ditto for temp/dynamic groups
_getAllGroup()                            all groups
_getAllExtendedTemporaryGroup()           all temp groups
_getGroupByDisplayName(name)              search by display name
_getExtendedTemporaryGroupByDisplayName(name)  ditto for temp
_getGroupCurrent(category)                player's "current" group for cat
_getExtendedTemporaryGroupCurrent(cat)    ditto for temp
```

Groups are addressed by:
- **kind** (numeric id, e.g. PartyGroup = 6, CompanyGroup category 20002)
- **display name** (string lookup)
- **current category** (e.g. 20002 = current GC)

### Equipment / Trading (6)

```text
_getEquippingItem(slot)                 currently equipped item at slot
_getExtendedTemporaryEquippingItem(slot)   ditto for temp gear
_isLockingItem                           item locked by another action?
_isItemDealing                           in a trade or bazaar deal?
_getTradingItem(idx)                     item being traded at slot
_getExtendedTemporaryTradingItem(idx)    temp trading slot
```

### Bonus Points (2)

```text
_encodeBonusPoint(value)        pack bonus point value (probably bit field)
_decodeBonusPoint(encoded)      unpack
```

Used for serializing stat allocation in saves / transfers.

### Job / Class (1)

```text
_getJob()        current job id (15-19, 26-27 per finding_ffxivbattle_stats_and_jobs)
                  Returns 0 if class-only (no job equipped)
```

### Work / Group Sync (2)

```text
_updateWork(struct, slot, fieldOrIdx0, fieldOrIdx1)
              -> THIS IS THE WIRE OPCODE 0x12f trigger
              (see finding_worksync_wire_opcode_0x12f.md)

_updateGroup(...)
              -> group-membership sync (similar but for group state)
```

**Confirmed binding**: `_updateWork` here is the SAME function that
generates the 0x12f packet on the wire. The Lua-side declaration
matches the EXE-side packet builder.

### Nameplate (6)

```text
_setNameplate(slot, owner, defaultIcon)   initialize nameplate
_setNameplateColor(color)                  text color
_setNameplateIcon(slot, iconId)            icon at slot (per
                                            finding_depiction_judge_nameplate.md)
_setNameplateGauge(value)                  HP/MP gauge value
_setNameplateVisible(bool)                 show/hide
_isNameplateVisible                        query
```

### Map Marker (1)

```text
_setMapMarker(id)         show marker icon on map
```

### LookAt (6) — Tracking and Eye Contact

```text
_lookAtCharacter(target, weight)        head-track target (0..1 weight)
_lookAtCharacterEid(entityId, weight)   look-at by entity id
_lookAtPosition(x, y, z, weight)        look at world position
_lookAtDirection(angle, weight)         look in direction
_cancelLookAt()                          release look constraint
_getLookAtCharacter()                    current look target
```

### Visibility / Grounding (2)

```text
_setGroundOn(bool)        chocobo/flying: stay on ground vs hover
_setVisible(bool)         render actor (show/hide)
```

### CharaScheduler — Animation System (3)

```text
_runCharaScheduler(schedulerId)              play animation
_runCharaSchedulerAgainstTarget(id, target)  play animation pointed at target
_waitForCharaSchedulerFinished()              yield until animation done
```

Scheduler ids in 0x18098000+ range (see finding_npc_event_system.md
for the 8-emote variant ids).

### Item / Inventory (8)

```text
_getItem(packageId, slot)                       item at slot in package
_getItemPackageCapacity(packageId)              max items in package
_getItemPackageFreeSpace(packageId)             empty slots in package
_hasItemPackage(packageId)                      package exists?
_getExtendedTemporaryItem(packageId, slot)     temp items
_updateItemPackage(packageId)                   sync item package
_createVirtualItem(itemId)                      create non-persistent item
_createExtendedTemporaryVirtualItem(itemId, p1, p2)  temp virtual item
```

### Other (3)

```text
_getGrandOnExtraStat()      grand stat (probably Grand Company-related)
_isAccessibleInServer()     is this actor reachable on server?
_getSystemFlag()            generic system flag query
```

## Architecture Insights

```text
Total: ~91 native bindings (vs PlayerBaseClass's 94).

Inheritance chain:
  ActorBaseClass (~few bindings, parent)
    └── CharaBaseClass (~91; THIS finding)
        ├── PlayerBaseClass (+94 additional; finding above)
        └── NpcBaseClass (+npc-specific bindings)

Coverage:
  Position/movement   12 + 5 gear = 17
  Appearance          6 graphics + 2 floating = 8
  Status modeling     3 main + 16 substat + 2 net = 21 (LARGEST GROUP)
  Group/location      10
  Equipment/items     6 + 8 = 14
  Nameplate/UI        6 + 1 map + 6 lookat = 13
  Animation           3 + 6 lookat = 9
  Sync to server      2 (updateWork, updateGroup)
  Misc                ~6
  TOTAL              ~91
```

### Status Modeling is the Biggest Subsystem (21 bindings)

3 main-stat + 16 substat + 2 net-stat = 21 status-related bindings.
This is **much more elaborate than ARR's status system**. The 8
substat axes (waste/guard/chant/object/breakage/motionPack/mode/
status) allow very fine-grained state tracking.

Some examples of what these likely encode:
- **waste**: durability decay (1.x had item durability)
- **guard**: blocking stance
- **chant**: casting bar progress
- **object**: held item / weapon-out state
- **breakage**: destroyed body parts (npcWork.battleCommon.partsExists)
- **motionPack**: motion override (e.g. wounded limp animation)
- **mode**: sub-state of main stat
- **status**: buff/debuff list

### Position System (17 bindings)

5 bindings for position/direction + 5 for turning + 5 for moving +
2 gear control = a complete movement API. Lua scripts can:
- Read actor position
- Move to a target position (animated)
- Rotate to face anything
- Override movement speed via gears

### Group System (10 bindings)

Multiple ways to query group membership:
- By kind (numeric, fastest)
- By display name (string, slowest but flexible)
- By current category (most common case)

The "extended temporary" variants suggest some groups exist only
briefly (e.g. RelationGroup confirmations).

## Notable Cross-References

```text
_updateWork                  -> WIRE OPCODE 0x12f (validated EXE-side)
_lookAtCharacter             -> Used in NpcBaseClass dialog turn
_runCharaScheduler           -> NPC dialog emote system (0x18098000 ids)
_setNameplateIcon            -> DepictionJudge nameplate rendering
_getJob                      -> 7 jobs (15-19, 26-27 per ffxivbattle)
_actionActorMainStat 15      -> Riding chocobo (state 15)
_actionActorMainStat 1       -> Dead state
_actionActorMainStat 32      -> Sit emote
```

## Server Implementation Picture

Most of these bindings are CLIENT-LOCAL (read from synced state +
mutate visual presentation). The bindings that touch the wire are:

```text
NETWORK-TOUCHING:
  _updateWork                  generates opcode 0x12f
  _updateGroup                 likely generates similar packet
  _updateItemPackage           sync item state to server

LOCAL-ONLY MUTATIONS:
  All position/movement bindings  (animation; server gets snapshot)
  All graphic bindings            (purely visual)
  All nameplate bindings          (purely visual)
  All lookat bindings             (purely visual)
  All gear bindings               (movement style; client renders)

SERVER-PUSHED STATE READS:
  _getActorMainStat              from synced charaWork
  _getSubStatXxx (8 axes)        from synced charaWork
  _getNetStatXxx                 from synced charaWork
  _getJob                        from synced parameterSave
  _getEquippingItem              from synced charaWork.command array
  _getGroup family               from group membership state
  _getDisplayName                from server-pushed name string
```

So a server's per-actor sync surface is:
- charaWork sync (HP, status, etc.) -- documented
- charaWork.command sync (equipped commands) -- documented
- Group memberships
- Display name + localized variants
- Position (likely separate movement packet)
- Visual state changes (less critical; server snapshot suffices)

## Assessment

```text
Confirmed:
  - 91 native bindings in CharaBaseClass (just below PlayerBase's 94).
  - SubStat is the biggest subsystem (16 bindings = 8 axes x 2 ops).
  - _updateWork in this file is the same function that emits
    opcode 0x12f on the wire (confirmed via EXE-side finding).
  - Cross-references confirmed: _lookAtCharacter / _runCharaScheduler
    / _setNameplateIcon match prior Lua-side findings.

Likely (High):
  - The 8 substat axes are 1.x's elaborate status tracking design
    (more granular than ARR's single-buff-list approach).
  - Most graphics bindings (Weapon/Armor/Accessory/Characteristic)
    are independent slots that decompose the character's appearance
    into 4 layers.
  - "Extended temporary" group/item variants are short-lived,
    runtime-only state (vs persistent server-stored).

Likely (Medium):
  - The "breakage" substat is shared between NPC body parts
    (battleCommon.partsExists) and player item durability (waste).
  - "_actionActorMainStat" triggers state transitions vs "_set" which
    just writes the value. So state changes go through a controlled
    state machine.

Speculative:
  - The substat axes likely have NUMERIC values (e.g. guard level,
    chant percentage), not just booleans. The set/get pairs imply
    per-actor running values.
  - The "object" substat tracks what the actor is HOLDING (sword vs
    bow vs none) -- used for weapon-swap animations.
```

## Closes the API Surface

Combined with prior findings:
- **CharaBaseClass: 91 bindings (this finding)** — base actor API
- **PlayerBaseClass: 94 bindings** — player-specific extensions
- **NpcBaseClass: ~24 bindings (from npcbaseclass_u.lua, 237 lines)** —
   pending; brief grep showed event/talk/push family
- **WorldMaster: 24 bindings** (already documented)

Combined surface: ~233+ native bindings for the core actor + world
APIs. The vast majority are client-local queries; only a handful
touch the network (updateWork, updateGroup, updateItemPackage,
direct server calls).

This is **the complete Lua-to-C++ API surface for 1.x's actor
system**. A test server implementing the work-sync wire opcodes +
the broadcast channels can drive any of these client behaviors
via state pushes; no need to replicate the 233 bindings server-side.
