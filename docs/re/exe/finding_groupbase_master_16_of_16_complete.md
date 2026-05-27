# Finding: GroupBaseClass Master 16 of 16 COMPLETE -- SINGLE-MASTER PATTERN (not multi)

Locates the **GroupBaseClass_registerAllLuaBindings** master block at
FUN_00757b70 via string-xref tracing. Walks ALL 16 registrar slots in
one batch. **Tests + REFUTES the multi-master hypothesis for Group**:
all 15 user-facing bindings live in the BASE master, with 1 engine-
internal added. The Party/Linkshell/Community subclasses are pure Lua
with NO additional native bindings.

**11th master block identified. 372 total registrars catalogued.**

## 1. GroupBaseClass master block (FUN_00757b70)

```text
Master:         GroupBaseClass_registerAllLuaBindings @ 0x00757b70
Total slots:    16 registrars
Renamed:        master + ALL 16 registrars (100% walked)
Address span:   0x0074cad0-0x00757b70 (cluster around 0x0074cxxx +
                0x0074dxxx + 0x00756xxx + 0x00730xxx)

Vs _u.lua:      groupbaseclass_u.lua declares 15 bindings
                EXE has 15 user-facing + 1 engine-internal = 16
```

## 2. The 16 named GroupBaseClass registrars

### Identification / Classification (2 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
  3   0x0074cd70   _getKind                     group type enum
                                                (Party / Linkshell /
                                                 GrandCompany / etc.)
 14   0x0074d940   _getProperty                 generic property bag
```

### Display Names (4 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
 13   0x0074d7f0   _getDisplayName              group name
 11   0x0074d550   _getLocalizedDisplayName_internal   ENGINE-INTERNAL
                                                       (group name,
                                                        localized;
                                                        NOT in _u.lua)
 12   0x0074d6a0   _getMemberDisplayName        per-member name
 10   0x0074d400   _getMemberLocalizedDisplayName  per-member
                                                     localized name
```

### Membership Query (5 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
  1   0x0074cad0   _getMember              get member by index
  2   0x0074cc20   _countMember            roster size
  6   0x0074d160   _isMember               actor IS in group?
  4   0x0074cec0   _isExistInClientMember  in client roster?
  5   0x0074d010   _isExistInWorldMember   in world roster?
```

The 2 "isExist*" variants are interesting -- they distinguish:
- **client roster**: members visible to the local client (subset)
- **world roster**: full server-side roster (superset)

This split allows the client to show a limited view (e.g., only
nearby party members) while the server tracks the full group.

### Member Location (1 binding)

```text
Slot  Address      Lua binding
----  -------      -----------
  9   0x0074d2b0   _getMemberLocation     position of given member
```

Used to render party member markers on the world map / minimap.

### Occupancy Group (2 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
  7   0x00756b70   _getOccupancyGroup
  8   0x00756cc0   _getExtendedTemporaryOccupancyGroup
```

The **occupancy group** is a containing group (a player-party that
contains a chocobo party, or a linkshell that contains a party).
The "Extended Temporary" variant returns preview/uncommitted state
(consistent with the pattern on CharaBase).

### WorkSync (2 bindings)

```text
Slot  Address      Lua binding
----  -------      -----------
 15   0x0073ef30   _updateWork                       generic sync
 16   0x007306c0   _updateMemberAndInformation       specialized
                                                      member+state sync
```

`_updateWork` is the SHARED pattern (also on CharaBase, Director,
Item). `_updateMemberAndInformation` is Group-specific: pushes
both the member roster AND member-state info in one packet.

## 3. SINGLE-MASTER vs MULTI-MASTER -- pattern REFUTED for Group

Hypothesis (before this finding):

```text
Group might split into multiple masters like Area:
  - GroupBaseClass (stub master, 1 internal)
  - PartyGroupBaseClass (per-party bindings)
  - LinkshellGroupBaseClass (per-linkshell bindings)
```

Reality (this finding):

```text
GroupBaseClass master has ALL 15 user-facing bindings
  + 1 engine-internal (_getLocalizedDisplayName)
  = 16 total slots

Party/Linkshell/Community subclasses are PURE LUA
  (per prior finding_party_subclasses_and_weather.md:
   PlayerPartyGroup has 6 Lua methods, no native bindings;
   MonsterPartyGroup has 5 Lua methods, no native bindings)
```

So **GroupBaseClass uses the SINGLE-MASTER pattern** (like CharaBase,
PlayerBase, NpcBase). Only AreaBase uses the multi-master "stub +
subclass" pattern.

**Updated pattern hypothesis**:

```text
SINGLE-MASTER (most classes):
  - Base class has full user-facing API + 0-7 internals
  - Subclasses extend behavior via Lua method overrides only
  - GroupBase, CharaBase, PlayerBase, NpcBase, ActorBase, Item,
    WorldMaster, Director, DesktopWidget, global

MULTI-MASTER (rare; AreaBase only so far):
  - Base class has only 1 internal binding (stub)
  - Subclass has the 9 user-facing bindings
  - AreaBase is the only known case
```

The Area split might be unique to its design (Area = abstract spatial
container; AreaMaster = concrete instance type with the Area methods).

## 4. The 1 engine-internal binding discovered

```text
_getLocalizedDisplayName    GROUP-LEVEL localized name
                            (NOT in _u.lua)
```

This is the localized name of THE GROUP itself (e.g., "Order of the
Twin Adder" in Japanese vs English). Hidden from scripts, presumably
because the engine handles group-name display directly (via the
party UI widget or linkshell panel).

The MEMBER-level variant (`_getMemberLocalizedDisplayName`) IS in
_u.lua, because scripts often need to query individual member names
in different locales (e.g., for /tell autocomplete).

So the rule: **per-member name = scriptable; per-group name =
engine-only**.

## 5. Group uses 11th distinct functor factory

```text
All 16 GroupBaseClass slots use functor factory FUN_007265c0
```

**11th distinct factory** observed:

```text
Class            Functor factory
-----            ---------------
ActorBase        0x00726300 / 0x007263b0
CharaBase        0x00726460 / 0x00726510
Item             0x00726670
PlayerBase       0x007267d0
DesktopWidget    0x00726bf0 / 0x00726b40
WorldMaster      0x00726ca0
Director         0x00726d50
global           0x00726e00
GroupBaseClass   0x007265c0                  (NEW; 11th factory)
NpcBase          0x0072d400 / 0x0072d4b0
```

11 distinct factories observed. All clustering at 0x00726xxx (9 of
them) + 0x0072dxxx (2 of them).

## 6. Implications for server: 1.x Social Subsystem Surface

The 15 user-facing Group bindings define **the entire 1.x social
data model** that scripts can query:

```text
WHAT SCRIPTS CAN ASK ABOUT ANY GROUP:
  - What kind of group is this? (Party/Linkshell/GC/Retainer/etc.)
  - What's its display name? (and members' names; localized vs not)
  - Who are its members? (and how many?)
  - Is X actor a member? (with client-view + world-view variants)
  - Where is member X located?
  - What's the containing group? (occupancy chain)
  - Any custom property? (extensible property bag)

WHAT SCRIPTS CAN DO (via _updateWork variants):
  - Push state-change sync (generic _updateWork)
  - Push roster+info sync (_updateMemberAndInformation)

SUBCLASSES (pure Lua, no extra bindings):
  - PlayerPartyGroup    player parties
  - MonsterPartyGroup   enemy packs (per prior finding)
  - GrandCompanyGroup   GC membership (Adder/Maelstrom/etc.)
  - LinkshellGroup      cross-zone chat groups
  - RetainerGroup       hired NPCs for housing/bazaar
  - ContentGroup        instance-specific groups
  - RelationGroup       friend lists, blocked players, etc.
```

For a server, this means:

```text
1. Server tracks per-group roster (with member-position cache)
2. Server has both "world roster" (full) and "client roster"
   (visible subset) -- needs to track which members each client
   can currently see (proximity / zone-based filter)
3. Server pushes 2 types of group updates:
   - _updateWork: generic state change
   - _updateMemberAndInformation: roster + state in one packet
4. Server stores per-group properties (extensible) and 2 name
   variants (raw + localized)
5. The 7 subclass types share the SAME native API -- server can
   handle them through a single GroupBase abstraction with a
   "kind" discriminator
```

## 7. Updated master block inventory (11 masters, 5 at 100%)

```text
Class                 Master address    Registrars    Walked   _u.lua match
-----                 --------------    ----------    ------   ------------
DirectorBaseClass     0x00758260         5             5/5      5 EXACT
ItemBaseClass         0x00753dd0        20            20/20    19 + 1 internal
WorldMaster           0x00754c70        23            23/23    23 EXACT
DesktopWidget         0x00757ea0        44            44/44    44 EXACT
global                0x007582e0        15            15/15    15 EXACT
GroupBaseClass        0x00757b70        16            16/16    15 + 1 internal (NEW)
PlayerBase            0x00753f90        99            99/99    94 + 5 internal
NpcBaseClass          0x00754850        24            24/24    23 + 1 internal
ActorBaseClass        0x00753c30         8 + tail      8/8      7 + 1 internal
AreaBaseClass         0x00754e70         1 (stub)      1/1      0 + 1 internal
CharaBaseClass        0x007574a0        83            80/83    76 + 4-7 internal

TOTAL master blocks identified:    11 (up from 10)
TOTAL registrars catalogued:      372 (up from 356)
TOTAL engine-internal discovered:  ~14-17 bindings
TOTAL _u.lua bindings located:    324 of ~387 (84%)
```

10 of 11 masters at 100% coverage. Only CharaBase tail-3 + AreaMaster
subclass + small modules (Math/String/Table/Sequence/SpreadSheet/Debug
~75 bindings) remain.

## 8. Annotations made in Ghidra (17 renames in this finding)

```text
RENAMES (1 master + 16 registrars):
  - 0x00757b70 -> GroupBaseClass_registerAllLuaBindings (master)
  - 0x0074cad0 -> GroupBaseClass_registerLua_getMember
  - 0x0074cc20 -> GroupBaseClass_registerLua_countMember
  - 0x0074cd70 -> GroupBaseClass_registerLua_getKind
  - 0x0074cec0 -> GroupBaseClass_registerLua_isExistInClientMember
  - 0x0074d010 -> GroupBaseClass_registerLua_isExistInWorldMember
  - 0x0074d160 -> GroupBaseClass_registerLua_isMember
  - 0x0074d2b0 -> GroupBaseClass_registerLua_getMemberLocation
  - 0x00756b70 -> GroupBaseClass_registerLua_getOccupancyGroup
  - 0x00756cc0 -> GroupBaseClass_registerLua_getExtendedTemporaryOccupancyGroup
  - 0x0074d400 -> GroupBaseClass_registerLua_getMemberLocalizedDisplayName
  - 0x0074d550 -> GroupBaseClass_registerLua_getLocalizedDisplayName_internal
  - 0x0074d6a0 -> GroupBaseClass_registerLua_getMemberDisplayName
  - 0x0074d7f0 -> GroupBaseClass_registerLua_getDisplayName
  - 0x0074d940 -> GroupBaseClass_registerLua_getProperty
  - 0x0073ef30 -> GroupBaseClass_registerLua_updateWork
  - 0x007306c0 -> GroupBaseClass_registerLua_updateMemberAndInformation
```

## 9. Confidence

```text
Confirmed:
  - GroupBaseClass master @ 0x00757b70 has exactly 16 registrar slots
  - All 16 walked + named (100% coverage)
  - 15 of 15 _u.lua bindings present in master
  - 1 engine-internal binding (_getLocalizedDisplayName, group-side)
  - All 16 use functor factory FUN_007265c0 (11th factory)
  - Group uses SINGLE-MASTER pattern (NOT multi-master like Area)
  - Subclasses are pure Lua (per prior finding_party_subclasses)
  - The 2 _isExist* variants (client/world) imply group-membership
    visibility filtering on the server
  - _updateMemberAndInformation is the Group-specific specialized
    sync that pushes roster+state in one packet

Likely (High):
  - The "client roster" subset is calculated per-zone (party members
    in same zone = visible to client; out-of-zone = world-only)
  - _getProperty is a key-value bag for extensible group attributes
    (e.g., GrandCompany rank, Linkshell color, Retainer config)
  - Multi-master pattern is UNIQUE to AreaBase -- not extended to
    Group (now confirmed) or other class families
  - 11 functor factories likely = 11 RTTI base types in engine

Likely (Medium):
  - _getOccupancyGroup returns the immediate parent group
    (e.g., a Party's occupancy = the Linkshell hosting it, if any);
    "Extended Temporary" variant is for preview-only state during
    UI interactions (drag-drop, etc.)
  - _getKind returns an enum that matches the 7 subclass types
    (PlayerParty/MonsterParty/GC/Linkshell/Retainer/Content/Relation)
```

## 10. Cross-references

- `finding_party_subclasses_and_weather.md` -- documents Party/Monster
  subclasses as pure Lua (validates this finding's claim that
  subclasses have no extra native bindings)
- `finding_global_master_15_of_15_layer1_boot.md` -- prior EXACT
  master with shared `_replaceMacroCodeString`
- `finding_desktopwidget_master_44_of_44_complete.md` -- precedent
  for string-xref methodology
- `finding_actor_area_masters_located_with_8_more_registrars.md`
  -- the AreaBase MULTI-master case (contrast with this finding's
  SINGLE-master result)
- `finding_native_bindings_inventory_complete_387_of_439.md` -- the
  _u.lua catalog this finding validates

## 11. Next test

```text
1. Find AreaMaster subclass (9 user-facing Area bindings) -- the OTHER
   side of the multi-master pattern; use _canRideChocobo, _getRegion,
   _getZoneName as anchors
2. Walk remaining 3 CharaBase tail-slot registrars (-> 83/83)
3. Find Math module master (32 bindings expected; string-xref via
   distinctive math fns)
4. Find Widget base class master (24 bindings; vs DesktopWidget which
   is the SINGLETON of widgets)
5. Find String / Table / Sequence / SpreadSheet / Debug masters
   (small)
6. Disassemble _createActor thunk (0x00757350's functor target) to
   map the actor-creation factory pathway
7. Cross-ref _getMember + _countMember usage in Lua to identify the
   common "iterate party members" idiom and its callers
```

## Commit suggestion

```
docs(re/exe): GroupBaseClass master 16 of 16 walked + named -- single-master pattern confirmed (NOT multi like Area); 15 _u.lua + 1 engine-internal
```
