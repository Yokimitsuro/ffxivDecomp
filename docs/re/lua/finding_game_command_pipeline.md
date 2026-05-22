# Finding: `GameCommandBaseClass` Pipeline + Player ↔ Server Command Round-Trips

Read of `command/game/gamecommandbaseclass.lua` (~57 KB, ~120 methods)
plus the two Player methods that drive command traffic in and out of
the client.

Sources read (deciphered paths):

```text
command/CommandBaseClass.lua                          parent (not read here)
command/game/gamecommandbaseclass.lua                 ~57 KB, ~120 methods
chara/player/playerbaseclass.lua                      _onCommandEvent / _onCommandRequest
```

This sits on top of:
- `docs/re/lua/finding_player_slots_and_craft_flow.md` (the 94+ Player
  native bindings; the empty `_craft/_harvest/_negotiation` slots).
- `docs/re/lua/finding_worldmaster_and_actor_packet_flow.md` (the
  `_onReceiveDataPacket` shape; how PacketProcessor delivers).

## Inheritance and data sources

```text
CommandBaseClass
  └─ GameCommandBaseClass         (this file)
        ├─ CraftCommand           (already documented)
        ├─ HarvestCommand         (TBD)
        ├─ AttackCommand          (TBD)
        ├─ MagicCommand           (TBD)
        ├─ AbilityCommand         (TBD)
        └─ ... etc.
```

`GameCommandBaseClass` derives static data from two SE sheets:

```text
gameCommandSheet            indexed by commandId
  col 37  actor main-stat requirement (raw enum)
  ... and many more columns indexed by getGameCommandData(self, col)

gameCommandBasicSheet       indexed by commandId
  col 38  main skill id     (getCommandMainSkill)
  col 39  required level    (getCommandLevel)
  ... and many more columns indexed by getGameCommandBasicData(self, col)
```

These sheets are the canonical client-side source of truth for every
command's stats. A compatible server must agree with these sheets on
command properties (recast, range, MP/TP cost, ...) or pre-validation
will diverge.

## Command-ID ranges (hardcoded category boundaries)

The base class identifies command categories by **hardcoded id
ranges**, not by sheet flags. Recovered ranges:

```text
22001                Harvest command (abstract / single id; isHarvestCommand)
22002                Mining           (subtype, dispatched by HarvestJudge)
22003                Felling          (subtype)
22004                Fishing          (subtype)
22005..22009         Other player-issued action commands (TBD)
22002..22009         "isPlayerCommand" range (player-issued action umbrella;
                     INCLUDES the three gathering subtypes above — see
                     finding_harvest_judge.md)
22012, 22016         Craft commands that REQUIRE a target on the wire
                     (pinned in CraftCommand override)
22502                Tutorial-only craft command (excluded from standard
                     craft list per CraftJudge inventory)
23000..23999         "isHostilityCommand = false" range  (non-hostile —
                     buffs / support / heal etc.)
24105                Client-only command (special-cased in
                     PlayerBaseClass:_onCommandEvent: command:fire()
                     runs locally and SUPPRESSES the server call)
12014                Chocobo ride toggle (special post-action: checks
                     rider state via static actor 320013)
```

> **Correction**: an earlier version of this document attributed
> `22002..22009` to "craft" based on `GameCommandBaseClass:isPlayerCommand`.
> That method name was misread — `isPlayerCommand` is a generic
> "player-issued action" umbrella, NOT "isCraftCommand". The base
> `isCraftCommand` returns `false` and is overridden by subclasses;
> the actual craft commands begin at 22012 / 22016 (target-required)
> and the tutorial craft id 22502 sits in a separate band. See
> `finding_harvest_judge.md` for the gathering-subtype evidence.

The base implementations of `isPlayerCommand` and `isAttackCommand`
likewise use range tests; subclasses (e.g. CraftCommand,
NegotiationCommand) override with `return true/false` literals.

## The `canFire` pipeline (client-side pre-validation)

```lua
function GameCommandBaseClass:canFire(actor, target, A3, attackParam, A5,
                                      A6, A7, A8, A9, A10)
  if not self:isHarvestCommand() then
    A6 = self:judgeAtForceTarget(actor, attackParam, A6)   -- target override
  end

  -- short-circuit chain (first failing check returns (false, errTextId))
  ok, err = self:processCanCommandForActorStat(actor)     -- alive? sit/sleep/etc
  ok, err = self:processCanCommandForSkill(actor, attackParam)
  ok, err = self:processCanCommandForRecastTime(actor, attackParam, A6)
  ok, err = self:processCanCommandForHpCost(actor, attackParam, A6)

  -- combo-discount MP check
  c1, c2, disc = actor:getComboInformation()
  id           = self:getCommandId()
  mpCost       = self:getCommandMPCost(actor)
  if c1 == id or c2 == id then
    mpCost = mpCost * (1 - disc)
  end
  if mpCost > actor:getMP() then return false, 32545 end   -- not enough MP

  -- combo-discount TP check
  tpCost       = self:getCommandTPCost(actor)
  if c1 == id or c2 == id then
    tpCost = tpCost * (1 - disc)
  end
  if tpCost > actor:getTP() then return false, 32546 end   -- not enough TP

  -- subclass-specific gate
  ok, err = self:canFireDetail(actor, target, ...)
  if not ok then return false, err end

  return true, 0
end
```

### Known error text ids

```text
32501  invalid actor state (sit / sleep / climb-walk-only)
32545  not enough MP
32546  not enough TP
```

Other `processCanCommandFor...` checks return their own ids (not
inspected here). The pattern is `(false, textId)` from any check, and
the UI then displays text-sheet entry `textId`.

### Combo system is **client-side**

The combo discount lives entirely on the client. The local actor must
expose `getComboInformation()` returning `(comboCmd1, comboCmd2,
discount)`. There is no separate combo packet — the server just sends
attack effects, and the client decides whether the next-allowed combo
slot matches the current command id.

For a server: combos do not require any new protocol; they are a
client-rendered consequence of attack-result packets that update the
local actor's combo state. The server only needs to keep combo
correctness for damage-side math (also client-evaluated against
sheets).

## Placeholder slots in the base class

These five methods are empty bodies in `GameCommandBaseClass` — they
exist only so subclasses can override:

```text
processCanCommandForMyCommandWork  -> always returns false
fire                               -> empty (the real wire-side
                                      action lives in subclasses)
isActionMenu                       -> always returns true
judgeAtForceTarget                 -> empty
sendMessageCommandErr              -> empty
sendMessageEquipErr                -> empty
canFireDetail                      -> always returns (true, 0)
```

i.e. by default a "Game" command:

- has no per-command work state (no override of
  `processCanCommandForMyCommandWork`),
- has an empty `fire` (the heavy lifting is in `CraftCommand`,
  `MagicCommand`, etc., or fully server-driven),
- belongs to the action menu (`isActionMenu = true`),
- delegates target-forcing to subclasses,
- shows no per-command error message (subclasses populate the text
  bindings).

## Targeting / range surface

These accessors are all overrideable but largely default to sheet
lookups via `getGameCommandData(self, col)`:

```text
getRange / getBestRange / getMinimumRange / getEffectRange
getRangeAngle / getRangeRotate / getRangeWidth
useWeaponRangeInformation     -- bool: derive range from weapon, not command
getCommandRangeCode
getCommandTargettingMode      -- spelling preserved from source ("Targetting")
getCommandRangeTargettingMode
getCommandRangeShape          -- 'circle', 'rect', etc.
getCommandRangeLength
getCommandRangeHeight
canUseCommandRangeAreaSelect
canAimForRelation             -- (true, requiresTarget, ?)
canFireForRelation            -- post-aim relationship check (hostile/friendly)
canAimParts
canFireForDeadTarget
canFireForLiveTarget
canFireOnDead                 -- whether actor in dead state can fire
aimWithSubTarget
getTargetControlMode
getPartsDamageAdjust
```

A compatible server doesn't need to compute any of this. The client
computes targeting locally; the server just receives "actor X targets
actor Y with command Z" and validates server-side.

## Cost + level adjustment surface (~30 methods)

Around lines 1372..1593, the base class defines a level-adjust system
for parameters 1..4 (`getCommandParamN`), used when the player's
casting level differs from the command's nominal level. Bands seen:

```text
getCommandLevelAdjustLevelMax
getCommandLevelAdjust
getCommandParam1AdjustForHighLevelUse  / ...Param2  / Param3 / Param4
getCommandParam1AdjustForLowLevelUse   / ...
getCommandParam1LevelAdjustGrow        / ...
getCommandParam1                       / Param2 / Param3 / Param4
```

All of these resolve to sheet lookups + arithmetic, with no server
contact. The server only needs to know the player's effective level,
not how the client massages the params.

## How a command actually moves over the wire

`PlayerBaseClass` has the two endpoints. The base `fire` in
`GameCommandBaseClass` is empty, so the wire interaction goes through
the Player:

### Outbound — `PlayerBaseClass:_onCommandEvent(name, command, ...)`

```lua
function PlayerBaseClass:_onCommandEvent(name, command, ...)
  local id = command:getCommandId()

  -- Command 24105 is client-only: try local fire() and stop if handled.
  if id == 24105 then
    local handled = command:fire(self, ...)
    if handled then return end
  end

  -- Default: ASK SERVER to run this command (the native binding
  -- _callServerOnCommand_cpp serialises through PacketRequestBase).
  self:_callServerOnCommand(name, command, ...)

  -- Post: command 12014 (chocobo ride toggle) needs a kick-out check
  if id == 12014 then
    local riderMgr = _getStaticActor(320013)   -- chocobo rider service
    if riderMgr:isRiding(self) and self:_isPushingOut() then
      worldMaster:notify(riderMgr:getRidingErrorTextId(self, 26005))
      local pushOutCmd = self:getCommandName(_getStaticActor(12015))
      self:_executeCommand(pushOutCmd, _getStaticActor(12015))
    end
  end
end
```

Key insights:

- The **outbound payload** going to the server through
  `_callServerOnCommand_cpp` carries at minimum:
  - the command-name string (some opaque slot or "ActionN" id used by
    the UI binding system),
  - the command object itself (from which the server-side will read
    `getCommandId()`),
  - the variadic args (target / sub-target / area-center etc.).
  This is the surface a compatible server has to deserialize.
- **Static actor `320013`** is the Chocobo Rider singleton (with
  methods `isRiding(player)` and `getRidingErrorTextId(player, code)`).
  Joins the previously-pinned `310001 = WorldMaster` and
  `24301 = Instance Raid service`.
- **Static actor `12015`** is the internal "push out from chocobo"
  command object (used to kick the player off the bird).
- **Error text id `26005`** is "chocobo riding error" prefix.

### Inbound — `PlayerBaseClass:_onCommandRequest(name, command, ...)`

```lua
function PlayerBaseClass:_onCommandRequest(name, command, ...)
  local handled = command:command(self, ...)        -- try command:command()
  if not handled then
    handled = command:fire(self, ...)               -- try command:fire()
    if not handled then
      self:_doServerOnCommand(name, command, ...)   -- fallback: bounce back
    end
  end
end
```

Key insights:

- The server can **push** a command request to the client (probably
  via an IPC packet whose Lua side translates into
  `_onCommandRequest`). The client tries to handle it locally in two
  steps:
  1. `command:command(self, ...)` — the high-level handler.
  2. `command:fire(self, ...)` — the lower-level firing.
  3. If neither returns truthy, fall back through
     `_doServerOnCommand_cpp`, which presumably ACKs back to the
     server "I couldn't handle this, you do it".
- This implements a **client-side scriptable response** to server
  command requests: a `.lpb` can intercept a server-requested command
  and run client-only logic without bouncing back to the server.

### So we have two distinct native bindings:

```text
_callServerOnCommand_cpp   client -> server : "please run cmd X"
_doServerOnCommand_cpp     client -> server : "I couldn't do cmd X
                                              locally; you handle it"
```

Both go to the *same* server endpoint behaviourally, but the second
is the **fallback / I-give-up** path triggered only by a
server-initiated request that the client decided not to handle.

## Assessment

```text
Confirmed:
  - GameCommandBaseClass is a thin abstract layer over a sheet-driven
    command system. ~120 methods, the vast majority are sheet
    getters.
  - canFire is a client-side validation pipeline; first failure
    short-circuits with an error text id. MP / TP errors are
    32545 / 32546; invalid actor-state error is 32501.
  - Combo discount is purely client-side: actor:getComboInformation()
    returns (c1, c2, disc) and canFire multiplies cost by (1 - disc)
    when the current command id matches c1 or c2.
  - Crafting / harvest categorisation is by hardcoded ID range
    (22001 harvest; 22002..22009 craft; 22012, 22016 craft-with-target).
  - The base class `fire`, `sendMessageCommandErr/EquipErr`,
    `judgeAtForceTarget`, `canFireDetail`, `processCanCommandForMyCommandWork`
    are placeholders for subclasses.
  - PlayerBaseClass owns the wire endpoints. Outbound:
    _onCommandEvent -> _callServerOnCommand_cpp. Inbound:
    _onCommandRequest -> tries local command:command/fire, falls back
    to _doServerOnCommand_cpp.

Likely (High):
  - The "command name" argument to _callServerOnCommand is the UI
    slot identifier (e.g. "Action1", "Macro7"); the actual command
    is reconstructed server-side from command:getCommandId().
  - Command id 24105 is the only true client-only command in the
    base flow. Subclasses may special-case more.
  - The id 23000..23999 range is the support / buff / heal family
    (since they don't ever count as hostile for AoE/relationship
    purposes).

Likely (Medium):
  - Static actor 320013 = Chocobo Rider service; static actor 12015
    = "push out from chocobo" sentinel. These belong to a wider table
    of system actors (cf. 310001 = WorldMaster, 24301 = Instance Raid
    service). All such ids fit either the 1xxxx/2xxxx (gameplay
    services) or 3xxxxx (singletons) banding.

Speculative:
  - That `command:command(self, ...)` (the first try inside
    _onCommandRequest) is a method name reserved for "this is the
    high-level reaction to a server-initiated command request" — the
    name shadows the class field. Confirmation needs reading a
    subclass that overrides it.

Next test:
  - Decompile chara/player/playerbaseclass.lua around _onCommandEvent
    upstream callers (where in the UI does it originate? probably
    widget code).
  - Pick one of the heavier subclasses (AttackCommand, MagicCommand)
    to extract its `fire` implementation - that is where the actual
    targeting + damage roll happens. The wire payload to
    _callServerOnCommand carries those args.
  - Verify on the EXE side that PacketRequestBase serialises
    _callServerOnCommand args into segment-3 IPC payload; this
    closes the loop with finding_ipc_channel_framing.md.

Commit suggestion:
  docs(re/lua): document GameCommand pipeline + Player command wire endpoints
```

## Server implication (consolidated)

A server bring-up that wants commands to flow needs:

1. **Accept inbound** `_callServerOnCommand_cpp` IPC: deserialise
   `(slot_name, command_id, ...variadic_targeting_args)`. The slot
   name is opaque metadata; the command id is the routing key.
2. **Accept inbound** `_doServerOnCommand_cpp` IPC: same shape,
   semantically "I gave up locally, please do it". For an early
   server, treat both identically.
3. **Push outbound** "execute this command" requests (the inverse of
   `_onCommandRequest`): the client will try its local fire/command
   first; only if it can't will it bounce back. So a server-pushed
   command can be silently swallowed by Lua scripts — be ready for
   no ACK.
4. **Respect the ID partitions**:
   - 12014 (chocobo) triggers a kick-out check on the client side.
     Server must understand the "I'm pushing out" reply.
   - 22001 (harvest) / 22002..22009 (craft) move through specialised
     widgets. Server should send the appropriate `CraftProgressWidget`
     updates (see craft finding).
   - 22012 / 22016 (craft-with-target) require a target actor id on
     the wire.
   - 24105 is **never** sent to the server. If a packet for it
     arrives at the server, the client did NOT initiate it.
5. **Don't compute combos for the client**. The client already does
   the cost discount; the server just needs to advance the next-allowed
   combo slot via attack-result packets.
6. **Sheets must agree.** Range, cost, recast, level, main-skill, and
   actor-stat requirements are sheet-driven on the client; the server's
   command balance has to match these sheets or pre-validation
   diverges and commands get rejected silently.
7. **Static service actors to register**:
   - 310001 WorldMaster
   - 320013 Chocobo Rider
   - 24301  Instance Raid Service
   - 12015  Push-Out-From-Chocobo internal command
   plus whichever others surface in later script reads.
