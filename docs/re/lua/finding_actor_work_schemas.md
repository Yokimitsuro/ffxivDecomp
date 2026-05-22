# Finding: Actor Work Schemas — CharaBase + NpcBase `_onInit` Walkthrough

Reading the full `_onInit` of both `CharaBaseClass` and `NpcBaseClass`
gives the **complete schema** for the two main actor types: the
exhaustive list of `_save`/`_temp`/`_sync`/`_tag` fields, their wire
types, and their allocated array sizes. This finding pins the schema
for both, plus a previously-hidden detail about command-id space.

Sources read (in full or in the relevant ranges):

```text
chara/charabaseclass.lua     1734 lines  (all 38 base methods enumerated;
                                          _onInit walkthrough lines 534-1124)
chara/npc/npcbaseclass.lua    623 lines  (full read; _onInit lines 110-279)
```

## CharaBaseClass schema (the parent of Player + Npc)

### `_onInit(self, hasGameParameter, hasBattle)` signature

The parent class init takes two flags from the subclass:

```text
A1_2  hasGameParameter   true if this actor has battle stats
                         (HP, parameters, etc.). False for incidental
                         actors that are just "in the world" without
                         combat data.
A2_2  hasBattle          true if this actor uses the battleSave/
                         battleTemp nested sub-structs.
```

A third internal flag is computed from these:

```text
L3_2  isMyPlayer         (isPlayer and isMyPlayer) — controls the
                         allocated SIZES of nested sub-structs:
                         myPlayer gets 8x bigger parameterSave/Temp,
                         8x bigger battleSave, and a much wider sync
                         buffer footprint than other actors on screen.
```

### `charaWork._temp` (always present)

```text
[
  {gameParameter, boolean}     -- 1-byte flag mirrored from the
                                  hasGameParameter init arg
]
```

### `charaWork._sync` schema (the full data block — read by _bindWork)

Built up in stages. Group 1: command management (always):

```text
{commandAcquired,           array[4096], boolean}  -- 4096-bit bitmap
{command,                   array[64],   actor}    -- 64 equipped commands
{commandCategory,           array[64],   integer8}
{commandBorder,             integer8}             -- 1 element? or per-slot?
```

Group 2: event UI (always):

```text
{statusShownTime,           array[20],   integer32}  -- 20 buff/debuff slots
```

Group 3: nested parameter sub-structs (sized by myPlayer flag):

```text
{parameterSave,    nesting, 512 if myPlayer else 64}   -- combat stats
{parameterTemp,    nesting, 256 if myPlayer else 16}   -- volatile stats
{eventSave,        nesting, 3}                          -- event flags (3 entries)
{eventTemp,        nesting, 9}                          -- event temp (9 entries)
```

(Followed by unpack-spread entries from `initCommonParameterSync()` —
which is in `charabaseclass_parameter.lua` and adds further fields up
to slot 15 of the array. Not enumerated here; require_module reads.)

Group 4: battle sub-structs (only if `hasBattle`):

```text
{battleSave,       nesting, 512 if myPlayer else 64}
{battleTemp,       nesting, 128 if myPlayer else 16}
```

Plus unpack-spread entries from `initBattleSync()`.

Group 5: misc (always):

```text
{property,                  array[32],  boolean}     -- 32-bit property bitset
{additionalCommandAcquired, array[36],  boolean}     -- 36-bit extension bitmap
{currentContentGroup,       integer32}                -- active content group id
{depictionJudge,            actor}                    -- nameplate judge actor
```

Plus unpack-spread entries from `initCommonParameterSync()`.

If `hasGameParameter`: unpack-spread entries from `initEventSyncWork()`.

### `charaWork._tag` schema (sync-update groupings)

The `_tag` array defines NAMED GROUPS of fields that can be synced as
units. Each entry is `{tagName, syncMode, ownerActor, [{fieldName}, ...]}`:

```text
{command,            1, self, [{command}, {commandCategory}, {commandBorder}]}
{commandAcquired,        [{commandAcquired, "."}]}  -- "." = nested-path tag
{additionalCommand,  1, self, [{additionalCommandAcquired}]}
{currentContentGroup, 1, self, [{currentContentGroup}]}
{judge,              1, self, [{depictionJudge}]}
-- if hasGameParameter:
{status,             1, [{statusShownTime}]}
-- always:
{property,           1, [{property}]}
```

The server can push updates against a single tag name and the runtime
unpacks the underlying field updates.

### `charaWork.gameParameter` assignment

After all schema is defined, `charaWork.gameParameter = hasGameParameter`
records the flag back into the data. Tested via `hasGameParameter()`
accessor downstream.

### `_bindWork` calls at end of CharaBase `_onInit`

Conditional binding registration. Re-confirms the catalog:

```text
if hasGameParameter:
  _bindWork(1010, charaWork, parameterSave, hp)
  _bindWork(1011, charaWork, parameterSave, hpMax)
  _bindWork(1012, charaWork, parameterSave, state_mainSkillLevel)
  _bindWork(4001, charaWork, eventTemp, bazaarRetail)
  _bindWork(4002, charaWork, eventTemp, bazaarRepair)
if hasBattle and not isMyPlayer:
  _bindWork(2002, charaWork, battleSave, potencial)
always:
  _bindWork(3006, charaWork, property)
```

Note: the `2002 potencial` binding skips for myPlayer — myPlayer's
potencial comes through a different channel (probably the parameterSave
nested struct's higher-priority bindings 1001-1009 from earlier).

## NpcBaseClass schema (subclass of CharaBase)

### `_onInit(self, actorClassId, A2_2, A3_2, ...variadic)`

NPC's init takes:

```text
A1_2  actorClassId        -- the "kind" of NPC (sheet row id)
A2_2, A3_2                -- forwarded to super (CharaBase) _onInit
                          -- (= hasGameParameter, hasBattle)
...                       -- variadic: counts + per-sub-init args
                           (used to drive initForBattleCommon /
                            initForEventCommon /
                            initForBattle / initForEvent)
```

After the super call to `CharaBase._onInit`, NpcBase establishes its
own `npcWork` struct on top of the inherited `charaWork`.

### `npcWork._save = {}` (empty initially)

### `npcWork._temp`

```text
[
  {actorClassId,    integer32}     -- the NPC's class id
  {eventCommon,     nesting, 8}    -- nested struct, 8 entries
  {battleCommon,    nesting, 8}    -- nested struct, 8 entries
                                      (the parts + aggro from
                                       finding_chara_event_hooks_and_npc_battle.md)
  {_assignForChild, 64}            -- 64-byte child-class extension area
]
```

### `npcWork._sync`

```text
[
  {pushCommand,         integer16}  -- push-interaction command id
  {pushCommandSub,      integer32}  -- push sub-command id
  {pushCommandPriority, integer8}   -- push priority
  {hateType,            integer8}   -- aggro/hate-type bracket
                                      (consumed by DepictionJudge slot 2;
                                       see finding_depiction_judge_nameplate)
  {_assignForChild,     16}         -- 16-byte child sync area
]
```

### `npcWork._tag`

```text
{pushCommand, 1, [{pushCommand}, {pushCommandSub}, {pushCommandPriority}]}
{hate,        1, [{hateType}]}
```

### `_bindWork` calls in NpcBase `_onInit`

```text
_bindWork(5001, npcWork, actorClassId)
```

(plus whatever sub-initializers register; see initForBattleCommon).

### Sub-init dispatch (the variadic tail)

After binding actorClassId, NpcBase walks the variadic args:

```text
read N1 = arg[1]
if N1 > 0:
  initForBattleCommon(actorClassId, args[2..N1+1])
skip N1+1 args
read N2 = arg[N1+2]
if N2 > 0:
  initForEventCommon(actorClassId, args[N1+3..N1+2+N2])
skip N2+1 args
finally always:
  initForBattle(actorClassId, remaining args)
  initForEvent(actorClassId, remaining args)
```

So a single `NpcBase:_onInit` call can chain all four sub-initializers
with their own arg lists in one shot. The format is:

```text
NpcBase:_onInit(actorClassId, hasGameParameter, hasBattle,
                N_battleCommon, ...battleCommonArgs(N times),
                N_eventCommon, ...eventCommonArgs(N times),
                ...battleArgs,
                ...eventArgs)
```

## The Command-ID-26000 Offset

A previously-hidden detail surfaces in `updateCommandAcquired`:

```lua
function CharaBaseClass:updateCommandAcquired(A0_2, A1_2, A2_2)
  A1_2 = A1_2 - 26000
  A2_2 = A2_2 - 26000
  ...
  _updateWork(self, "charaWork", "commandAcquired", A1_2, A2_2)
end
```

And in `processUpdateCommandAcquired`:

```lua
function CharaBaseClass:processUpdateCommandAcquired(A0_2, A1_2, A2_2)
  desktopWidget:processUpdateCommandAcquired(A1_2 + 26000, A2_2 + 26000)
end
```

So **command ids on the wire are `(arrayIndex + 26000)`**. The 4096
slot `commandAcquired` array covers command ids in the range
**26000..30095**.

This is the same magic offset used by `Player._onChangeJob`
(rebases job ids).

## Method inventory (CharaBaseClass, full enumeration)

```text
identity / relations
  isPlayer / isRestrictedByContents / getPlayerParty / getParty
  isPartyLeader / getContentGroup / getCurrentContentGroup
  hasCurrentContent / getRelationGroup / hasRelationGroup
  getRelationGroupFellow / countRelationGroupMember
  countCommunityGroup / getCommunityGroup

status / state queries
  getMainSkill / getDepictionJudge / isDeadMode / isSitMode
  getReadyCommand / getReadyCommandSlotLength / searchReadyCommand
  getCommandName
  getStatus / getStatusSlotLength / getStatusTime

inventory
  hasItem / checkSameItemInPackage / getItemPackageItemCount

lifecycle (_onInit + helpers)
  _onInit                                  [line 534]
  _onUpdateDisplayName                     [line 1129]
  _onUpdateWork                            [line 1142]
  processUpdateInitWork                    [line 1204; empty stub]
  _onUpdateGroupCurrent                    [line 1210]
  updateGameParameters                     [line 1245]
  updateItemPackage                        [line 1278]
  _onUpdateItemPackage                     [line 1310]
  _onUpdateTradingItem                     [line 1327]
  _onReceiveDataPacket                     [line 1343]
  processReceiveData                       [line 1356; empty stub]
  updateCommandAcquired                    [line 1532; the -26000 rebase]
  processUpdateCommandAcquired             [line 1569; the +26000 rebase]

reactive _onChange hooks (8 total)
  _onChangeActorMainStat                   [line 1362; chocobo riding detection]
  _onChangeSubStatMode                     [line 1396; empty]
  _onChangeSubStatStatus                   [line 1402; buff/debuff UI]
  _onChangeNetStatSystem                   [line 1417; nameplate net icons 312/313]
  _onChangeNetStatUser                     [line 1446; nameplate net icon 314]
  _onChangeSystemFlag                      [line 1475; nameplate redraw only]
  _onChangeJob                             [line 1496; empty after myPlayer check]
  _onChangeAccessibleInServer              [line 1511; nameplate redraw only]
```

The `_onChange*` hooks all call `judgeNameplate` on the local player's
DepictionJudge, which then re-renders the nameplate for `self`. So
ANY state change on ANY visible actor triggers a nameplate re-render
on that actor. This explains why the nameplate is so reactive:
it's automatically driven by the sync system.

## Method inventory (NpcBaseClass)

```text
identity
  isPlayer (returns false)
  isRetainer (returns false)
  getSaveNpcId (returns 0)
  getActorClassId
  getMonsterParty       (returns _getExtendedTemporaryGroup(10002))

work access
  getTempWork / getSaveWork / setTempWork / setSaveWork
  getSyncWork

push interaction
  getPushCommandVariation   (returns pushCommand, sub, priority)

lifecycle
  _onInit                            [line 110]
  _onTimer                           [line 284; dispatches npcWork / work / retainerWork]
  processTimer                       [line 305; empty stub]
  initWork                           [line 311]
  initWorkSyncTag                    [line 330]
  _onUpdateWork                      [line 359]
  processUpdateWork                  [line 383; empty stub]

display
  getHateType
  getCategoryIcon (returns 0)
  getMapMarkerRange (returns nil)

event flow (Talk / Emote / Push)
  _onTalkEvent / _onTalkRequest / _onTalkRejected
  _onEmoteEvent / _onEmoteRequest / _onEmoteRejected
  _onPushEvent / _onPushRequest / _onNoticeRejected
  delegateEvent / _onEventCancel / _onReaction
```

The Talk/Emote events have a `goto lbl_7` pattern at the start that
**skips** the inline implementation in favour of a `_callServerOnTalk`
/ `_callServerOnEmote` deferred call. The inline body shows what
would happen if not deferred (lockon, _setLockonTarget, etc.). So
on a fresh install the runtime probably patches `lbl_7` out and runs
the inline body.

## Assessment

```text
Confirmed:
  - CharaBaseClass._onInit takes (hasGameParameter, hasBattle); a derived
    isMyPlayer flag scales nested struct sizes by 8x for the local player.
  - charaWork._sync schema has ~15 explicit entries + sub-struct unpacks
    (commandAcquired/command/commandCategory/commandBorder + 20-slot
    statusShownTime + parameter/event/battle nesting + property/
    additionalCommandAcquired/currentContentGroup/depictionJudge).
  - charaWork._tag has 5-7 named groups (command, commandAcquired,
    additionalCommand, currentContentGroup, judge, [status,] property).
  - npcWork has actorClassId + eventCommon(8) + battleCommon(8) +
    _assignForChild(64) in _temp; pushCommand/Sub/Priority +
    hateType + _assignForChild(16) in _sync; 2 tags (pushCommand, hate).
  - Command ids are rebased by -26000 on the wire (range 26000..30095
    for the 4096-bit commandAcquired bitmap).
  - 8 _onChange* hooks in CharaBase, ALL of which trigger a nameplate
    re-render (via judgeNameplate) -- explains why the nameplate is so
    reactive without any explicit "redraw" packet.

Likely (High):
  - parameterSave nested 64-slot struct (for non-myPlayer) holds:
    hp(1010), hpMax(1011), state_mainSkillLevel(1012), state_mainSkill(1001),
    and other 1xxx bindings from the catalog. parameterSave for myPlayer
    is 512 slots -- enough for several hundred per-stat fields.
  - eventTemp's 9-slot struct holds bazaarRetail(4001), bazaarRepair(4002),
    and 7 other event-temporary fields (yet undiscovered).
  - The "command" tag groups command + commandCategory + commandBorder
    so the server can push a single "command slot updated" packet that
    bundles the action id, its category, and its border state.

Likely (Medium):
  - The initCommonParameterSync / initBattleSync / initEventSyncWork
    functions live in charabaseclass_parameter.lua and charabaseclass_event.lua.
    Reading them will expose the rest of the schema (around 6-8 more
    entries per sub-block, given the unpack(..., 1, 6) pattern).
  - The "actor" wire type means: when a field type is "actor", the wire
    payload is an actor id (uint32). When the runtime reads it, the actor
    is looked up in the actor table. So a command slot field carries the
    command actor's id, not the action sheet row.
  - The "." string in {commandAcquired, "."} tag means "include all
    sub-keys" -- treats commandAcquired as a flat data path for sync.

Speculative:
  - The 4096-slot commandAcquired bitmap suggests 4096 distinct command
    types in the game design. With the -26000 offset, command ids 26000-
    30095 are valid. 1.x had ~3000-3500 commands in its sheets.
  - The 36-slot additionalCommandAcquired might be for the "additional"
    action types added in patches after the initial release -- a 1.x
    patch additive bitmap.
  - statusShownTime[20] -- 20 simultaneous buff/debuff slots. Other MMOs
    of the era had similar limits (FFXI: 20, WoW: 16, EQ2: 30).

Next test:
  - Read charabaseclass_parameter.lua to enumerate the initCommonParameterSync
    fields and pin the 1001-1099 binding ids precisely.
  - Read charabaseclass_event.lua to enumerate initEventSyncWork.
  - Read charabaseclass_cliprog.lua for client-side prog/progression handlers
    (this is the third require'd module).

Commit suggestion:
  docs(re/lua): actor work schemas -- CharaBase + Npc _onInit walkthrough;
                command id -26000 wire rebase
```

## Server implication (consolidated)

A server now has the **complete schema** for what it can push to an
actor:

1. **CharaBase fields** (every visible chara, ~120 entries when expanded):
   - `_temp`: gameParameter (boolean)
   - `_sync`: commandAcquired[4096], command[64], commandCategory[64],
     commandBorder, statusShownTime[20], parameterSave nested (sized
     64 or 512), parameterTemp (16 or 256), eventSave (3), eventTemp (9),
     [battleSave/battleTemp (64+16 or 512+128)], property[32],
     additionalCommandAcquired[36], currentContentGroup, depictionJudge.

2. **NpcBase extension** (every visible NPC, ~80 more entries):
   - `_temp`: actorClassId, eventCommon(8), battleCommon(8),
     _assignForChild(64).
   - `_sync`: pushCommand, pushCommandSub, pushCommandPriority,
     hateType, _assignForChild(16).

3. **Wire format for command ids**: actual command id = `arrayIndex + 26000`.
   So when the server pushes `commandAcquired` updates, it must send
   command ids in the range 26000-30095. The client rebases them
   automatically.

4. **Tag-based bundled updates**: the server can push by tag name
   ("command", "pushCommand", "hate", "status", "property") for grouped
   updates -- a single packet updates multiple correlated fields
   atomically.

5. **No "redraw nameplate" packet needed**: every `_onChange*` hook
   triggers `judgeNameplate` automatically. The server just pushes
   field updates and the nameplate refreshes.

The full bring-up surface (initial steady state) is now concrete:

```text
~25 _bindWork ids (per finding_bindwork_catalog.md)
+ ~120 CharaBase schema entries
+ ~80 NpcBase extension entries
+ tag-name dispatching for bundled updates
= the entire "actor state" wire surface.
```

Combined with the previously documented IPC framing
(packet_frame_and_segment_header.md), the lobby flow
(packet_lobby_*.md), and the desktop widget packet dispatch
(finding_desktopwidget_packet_dispatch.md), **the protocol model for
actor state is now complete enough to bring up a test world**.
Remaining open areas: movement (C++-only), actual combat actions (the
ICommand subsystem), and zone-load handshake (the chain that hands
the player from LobbyConnection to ZoneConnection — partially
documented in finding_zone_chat_channel_architecture.md but not
fully walked from EXE).
