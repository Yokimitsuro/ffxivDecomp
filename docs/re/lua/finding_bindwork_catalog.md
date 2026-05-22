# Finding: Complete `_bindWork` Catalog — Server→Client Sync Bindings

Following on from `finding_player_work_sync_system.md`, this finding
catalogs **every `_bindWork` callsite in the corpus**. Each one
represents a server-driven field-update channel: when the server
sends an IPC packet tagged with one of these binding ids, the C++
PacketProcessor writes the payload directly into the corresponding
field of an actor's work struct.

Sources scanned (grep `_bindWork`):

```text
chara/charabaseclass.lua                                  21 bindings
chara/player/playerbaseclass.lua                          17 bindings
chara/player/player.lua                                    1 binding
chara/npc/npcbaseclass.lua                                 1+ bindings
widget/desktopwidget_connector.lua                         4 bindings
group/partygroup/partygroupbaseclass_battle.lua            1 binding
group/relationgroup/traderelationgroup.lua                 2 bindings
group/relationgroup/groupinvitationrelationgroup.lua       2 bindings
group/communitygroup/companygroup.lua                      1 binding (+nesting)
actorbaseclass_u.lua                                       (binding inline declarations only)
```

## Signature

```text
_bindWork(actorId, structName, slotCategory, fieldName, [defaultValue])

actorId       uint   the SOURCE actor id (a server-side system actor)
                     that owns/produces updates for this field.
structName    str    the local struct on this actor (work / charaWork /
                     playerWork / partyGroupWork / npcWork)
slotCategory  str    sub-region within the struct (_globalTemp,
                     _memberSave, parameterSave, battleSave, eventTemp,
                     property, command, ...)
fieldName     str    the specific field name within the slot category
                     (sometimes omitted -- means "the whole slot")
default       opt    initial value if the server hasn't pushed yet
```

There is also `_bindWorkNestingArray(actorId, struct, slot, field, ...)`
for fields that are nested arrays (e.g. per-member rank lists). Same
shape; emits the same packet structure on the wire but the runtime
treats updates as array element changes.

## Full binding catalog (sorted by source actor id)

### Range 1000–1099 — CharaBase base stats (`charaWork.parameterSave.*`)

```text
1001  state_mainSkill                  current job/class id
1002  constanceCommandSlot_commandId   passive (constance) command slot id
1003  giftCommandSlot_commandId        gift command slot id
1004  abilityCostPoint_used            ability TP used
1005  abilityCostPoint_max             ability TP max
1006  constanceCostPoint_used          passive TP used
1007  constanceCostPoint_max           passive TP max
1008  giftCostPoint_used               gift TP used
1009  giftCostPoint_max                gift TP max
1010  hp                               current HP
1011  hpMax                            max HP
1012  state_mainSkillLevel             current main-skill level
```

These are the actor's combat-relevant numeric stats. Every HP update
on any chara on screen flows through binding 1010.

### Range 2000–2099 — CharaBase battle state (`charaWork.battleSave.*`)

```text
2001  skillLevel                       current skill level (per-stat?)
2002  potencial                        (sic; potential / breakdown stat)
```

### Range 3000–3099 — CharaBase command/property (`charaWork.*`)

```text
3001  commandAcquired                  bitmap of acquired commands
                                       (EXE-confirmed via
                                        Actor_isCommandAcquired @
                                        0x00573760; the wire idx is
                                        cmdId - 26001, validating the
                                        +26000 rebase from finding_
                                        actor_work_schemas.md)
3002  command                          equipped commands (array)
3003  commandCategory                  per-slot category
3004  commandBorder                    per-slot BASE INDEX into command[]
                                       (used as offset start by
                                        Actor_getCommandAt_complex @
                                        0x005737a0; NOT a UI color
                                        flag as initially assumed)
3005  ?? bazaar-related master flag    NEW BINDING DISCOVERED
                                       (Actor_isBazaarDealer @ 0x573460
                                        reads 3005 as a gate, then
                                        checks 4001/4002. Likely
                                        charaWork.eventSave.bazaar
                                        master flag bound through
                                        slot 3005, not 4xxx as the
                                        Lua-side schema implied.)
3006  property                         actor property bitset (32 bools)
                                       (EXE-confirmed via
                                        PlayerBase_check_charaWork_state_
                                        via_binding_ids @ 0x006de510)
```

### Range 4000–4099 — CharaBase eventTemp (`charaWork.eventTemp.*`)

```text
4001  bazaarRetail                     bazaar retail mode
4002  bazaarRepair                     bazaar repair mode
```

### Range 5000–5999 — Npc bindings (`npcWork.*`)

```text
5001  actorClassId                     the NPC's actorClassId
                                       (the "kind" of NPC)
```

(There are likely more 5xxx bindings in the npc subclasses; only the
base actorClassId is shown here from the npcbaseclass.lua scan.)

### Range 100000–100999 — Player (`playerWork.*`)

ALL EXE-confirmed via the dedicated getter functions in the
0x005738b0..0x00573940 range (one C function per binding id).

```text
100001  variableCommandConfirmRaise    confirm-on-raise toggle
        (getter: Player_getVariableCommandConfirmRaise @ 0x005738b0)
100002  variableCommandConfirmWarp     confirm-on-warp toggle
        (getter: Player_getVariableCommandConfirmWarp  @ 0x005738d0)
100003  variableCommandContent         content-flag bitfield
        (getter: Player_getVariableCommandContent      @ 0x005738f0)
100004  variableCommandPlaceDriven     place-driven action mode
        (getter: Player_getVariableCommandPlaceDriven_at_idx @ 0x573910)
                                       takes idx arg (array)
100005  variableCommandEmoteSit        sit-emote variant
        (getter: Player_getVariableCommandEmoteSit_default10001 @
                  0x00573940)
                                       DEFAULT = 10001 if unset
                                       (1.x base "sit" emote id)
100006  (unused)                       confirmed unused (no EXE getter)
100007  initialTown                    the player's chosen starting town
```

### Range 101000–101099 — Player guildleve (`playerWork.guildleveId`)

```text
101001  guildleveId                    guildleve slot ids (array[16])
```

(From `player.lua`. The actorId hints at a "GuildleveMaster" system
actor that produces all guildleve updates.)

### Range 200000–200099 — Relation groups (`work._globalTemp.*`)

```text
200001  host                           the group host actor id
200002  variableCommand                group variable command state
```

Used by both `TradeRelationGroup` and `GroupInvitationRelationGroup`
(shared ids — same packet shape, different recipient groups).

### Range 300000–300099 — Community groups (`work._memberSave.*`)

```text
300001  rank                           per-member rank in the community
                                       group (nested array; uses
                                       _bindWorkNestingArray)
```

Used by `CompanyGroup` (the Free Company analogue in 1.x).

### Range 400000–400099 — Party groups (`partyGroupWork._globalTemp.*`)

```text
400001  owner                          the party leader/owner actor id
```

Used by `PartyGroupBaseClass` (`initForBattle` step).

### Range 500000–500099 — DesktopWidget (`work.*`)

```text
500001  tutorialMenuType               which tutorial menu is active
500002  tutorialFlag                   tutorial-stage flag
500003  tutorialLockFlag               tutorial lock state
500004  mainTargetDecidedFlag          "main target is set" toggle
```

The DesktopWidget itself uses _bindWork to receive tutorial-state
updates from the server (probably the WorldMaster's tutorial-control
actor).

## ID range allocation summary

```text
id range          purpose
----------------  ----------------------------------------------
1000–1099         CharaBase parameterSave  (combat numerics)
2000–2099         CharaBase battleSave     (battle-specific)
3000–3099         CharaBase command/prop   (skill/command bindings)
4000–4099         CharaBase eventTemp      (event-driven temp state)
5000–5999         NpcBase                  (NPC class metadata)
100000–100099     PlayerBase variableCommand (toggles + initialTown)
101000–101099     Player guildleve         (the guildleve slot array)
200000–200099     RelationGroup            (host + variableCommand)
300000–300099     CommunityGroup (company) (per-member nested arrays)
400000–400099     PartyGroup               (owner)
500000–500099     DesktopWidget            (tutorial + UI flags)
```

Banding looks **carefully designed**: each subsystem gets its own
1000-id range with subdivisions inside. The lowest range (1xxx) is
the most data-heavy (per-frame HP updates flow through 1010); the
highest ranges (5xxxx) are UI-state singletons.

## What this means for a server

```text
For every visible actor (player + chara + npc), the server must be
able to push updates against ANY of the following bindings:

  HP:                         id 1010 -> charaWork.parameterSave.hp
  HPMax:                      id 1011 -> charaWork.parameterSave.hpMax
  MainSkill (job change):     id 1001 -> charaWork.parameterSave.state_mainSkill
  MainSkillLevel:             id 1012 -> charaWork.parameterSave.state_mainSkillLevel
  Equipped commands:          id 3002 -> charaWork.command
  Acquired commands:          id 3001 -> charaWork.commandAcquired
  Actor property bitset:      id 3006 -> charaWork.property

For the local player only:
  Initial town:               id 100007 -> playerWork.initialTown
  Variable command flags:     ids 100001-100005
  Guildleve slot ids:         id 101001 -> playerWork.guildleveId (array[16])

For groups (when active):
  Party owner:                id 400001 -> partyGroupWork._globalTemp.owner
  Community member rank:      id 300001 -> work._memberSave.rank[*]
  Relation host:              id 200001 -> work._globalTemp.host
  Relation cmd:               id 200002 -> work._globalTemp.variableCommand

For tutorial UI:
  Tutorial menu type:         id 500001 -> work.tutorialMenuType
  Tutorial flag:              id 500002 -> work.tutorialFlag
  Tutorial lock flag:         id 500003 -> work.tutorialLockFlag
  Main target decided:        id 500004 -> work.mainTargetDecidedFlag
```

So **a minimal viable server steady-state push** for keeping the
client in sync requires sending updates with at least these ~25
binding ids. Anything else (movement, combat actions, AoE pulses)
goes through the other two dispatch paths
(`_onReceiveDataPacket` events and the C++-only movement controller
documented elsewhere).

## Assessment

```text
Confirmed:
  - _bindWork is the sync-binding API; signature is
    (actorId, structName, slotCategory, fieldName, [default]).
  - At least 25 distinct binding ids are explicitly catalogued above.
  - ID banding follows a structured allocation: 1xxx chara stats,
    2xxx battle, 3xxx commands, 4xxx event-temp, 5xxx npc, 100xxx
    player, 200xxx relations, 300xxx community, 400xxx party,
    500xxx widget.
  - The CharaBase HP/HPMax bindings (1010, 1011) are the highest-
    frequency sync points in the protocol.

Likely (High):
  - The slot category names are stable identifiers shared across
    Lua and C++: "parameterSave", "battleSave", "commandAcquired",
    "command", "commandCategory", "commandBorder", "property",
    "eventTemp", "_globalTemp", "_memberSave", "_save", "_temp",
    "_sync", "_tag" are the full set so far observed.
  - There are additional bindings in subclasses not yet read
    (especially specialized chara subclasses like CharaBase variants
    for monsters, retainers, beast tribes).

Likely (Medium):
  - The actorId in _bindWork ALSO acts as the OPCODE on the wire:
    when the server sends an IPC packet of type "actor data update",
    the payload's "field id" field matches the binding's actorId. So
    1010 is BOTH a system actor id AND the on-wire opcode for "HP
    update".
  - EXE-side validation: the WRITE counterpart (_updateWork) is
    pinned at FUN_006e85e0 (renamed in Ghidra to lua_updateWork_impl).
    It takes (structName, slotName, field0, field1) string args from
    ExecuteParameters and builds a WorkPath that is broadcast via
    FUN_006ce1c0 + FUN_00767fc0. The READ side (_bindWork) does NOT
    appear as a string literal in the EXE -- its name lookup probably
    bypasses the standard Lua-to-C++ string-name path. That is
    consistent with binding IDs being on-wire opcodes (numeric, no
    string round-trip needed at runtime).

Speculative:
  - The "id range" structure is so deliberate that there may be
    ranges reserved for content packs not yet shipped in 1.23b:
    6000-9999 looks like a gap for additional NPC subsystems;
    102000-199999 looks like a gap for additional player subsystems.

Next test:
  - Find the C++ side of _bindWork (FUN_006xxxxx; similar registration
    pattern to _executeCommand). Pinning it confirms the on-wire
    opcode mapping is 1:1 with the binding id.
  - Grep the rest of the corpus for additional _bindWork callsites
    in npc subclasses (monster, retainer, beast tribe) -- the 5xxx
    range probably has many more.

Commit suggestion:
  docs(re/lua): complete _bindWork catalog (25+ sync bindings; id ranges)
```

## Server implication

The server bring-up surface for **sync state** is now concrete: ~25
binding ids with their (struct, slot, field) addresses. A test
server that wants to put a player into a working zone state must:

1. Push initial values for ids 1010, 1011, 1012, 1001 (HP/HPMax/level
   /mainSkill) on the player actor.
2. Push initial command-slot state via ids 3001 (acquired), 3002
   (equipped), 3003 (category), 3004 (border).
3. For the local player, push 101001 (guildleveId array) at least
   once to populate the leve panel.
4. Push tutorial-state ids 500001..500004 if walking the player
   through the tutorial.

That's roughly **a dozen mandatory packets** to put a player into a
playable state — much smaller than the full opcode catalog of a
modern MMO.
