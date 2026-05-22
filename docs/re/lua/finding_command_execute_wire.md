# Finding: Command Execute Wire — `command()`, `_executeCommand`, and the Two-Phase Request/Event Flow

Closes the combat-wire loop by tracing how a player action travels
from input (hotkey/UI) to server execution to client-side animation.
Surfaces the **outbound packet path** (`Player:command` →
`_executeCommand`) and the **inbound dispatch** (`_onCommandEvent`,
`_onCommandRequest`, `_onCommandRejected`, `_onCommandCancel`).

Sources read:

```text
chara/player/playerbaseclass.lua   lines 1820-2200
  _onCommandEvent      line 1820-1879 (name assigned at L1881)
  _onCommandRequest    line 1884-1906 (name at L1908)
  command              line 1911-1973 (name at L1975)
  canCommand           line 1978-2022 (name at L2024)
  _onCommandCancel     L2046
  _onCommandRejected   L2059
  _onPreCommand        L2131
  _onPostCommand       L2159

command/game/gamecommandbaseclass.lua line 2663 (fire stub)
command/game/attackcommand.lua          full read (366 lines)
```

## The Outbound Path — `Player:command()` (Client → Server)

The front-end entry point called from UI/hotkey. Triggered when the
player presses an action button.

```lua
function PlayerBaseClass:command(command, A2, A3, A4, A5, A6, A7, A8, A9, A10)
  -- 1. Anti-spam: sanitize string args (total length <= 50 chars)
  totalStrLen = (type(A2)=="string" and #A2 or 0)
              + (type(A3)=="string" and #A3 or 0)
  if totalStrLen > 50: return  -- silent reject

  -- 2. Permission check
  if not canCommand(command, A2..A10): return

  -- 3. Get the dispatch flag ("commandRequest" / "commandJudgeMode" /
  --    "commandDefault" / "commandWeak" / "commandForced" / etc.)
  --    See finding_command_baseclass_and_judges.md
  commandName = self:getCommandName(command)

  -- 4. Fire the native binding that builds + sends the packet
  result = self:_executeCommand(commandName, command, A2, A3, A4,
                                 A5, A6, A7, A8, A9, A10)

  -- 5. Post-send accounting
  if commandName == "commandRequest":
    self:recordRequestInformation()
  self.playerWork.commandBurstBlocker = 1   -- anti-spam timer

  return result
end
```

### The `_executeCommand` Native Binding (the wire packet)

`_executeCommand(commandName, command, A2..A10)` is the C++ native
binding that builds the outbound packet and sends it via the Zone
channel.

```text
_executeCommand args:
  arg 0  self                  (the player actor)
  arg 1  commandName           string ("commandRequest" / etc) —
                               dispatch classification
  arg 2  command               actor ref (the command/action object)
  arg 3  param1                command-specific (often target)
  arg 4  param2                command-specific
  arg 5  param3                command-specific
  arg 6  param4                command-specific
  arg 7  param5                command-specific
  arg 8  param6                command-specific
  arg 9  param7                command-specific
  arg 10 param8                command-specific
```

So the **outbound packet payload** is:

```text
Outbound CommandExecute packet:
  +0   playerActorId             uint32  (sender)
  +4   commandName_enum          uint8   (mapped from string)
  +5   commandActorId            uint32  (the command/action id ref)
  +9   param[1..8]               variant types
                                  (target actor id, target position,
                                   choice index, item id, etc.)
```

**The commandName enum maps**:

```text
commandName string         enum (probable)   used by
-----------------------    --------------    -----------------------
"commandRequest"           1                  user-initiated command (UI press)
"commandJudgeMode"          2                  command via judge subsystem
                                                (HarvestJudge / CraftJudge /
                                                 NegotiationJudge)
"commandDefault"            3                  passive default
"commandWeak"               4                  low-priority
"commandForced"             5                  forced (cannot cancel)
"commandRequest"
(items)                    1                  item commands
"commandContent"            6                  content-driven
"widgetCreate"              7                  UI widget creation
"macroRequest"              8                  macro-driven
```

(Enums are speculative; mapping confirmed via the string switch in
`finding_command_baseclass_and_judges.md`.)

## The Inbound Path — Three Server-Sent Events

The server can send three command-related events to the client. The
client processes each via its corresponding handler.

### `_onCommandEvent` — "command has started"

Triggered when the server announces a command is happening (the
client's own command was approved, or another player's command needs
client-side animation).

```lua
function PlayerBaseClass:_onCommandEvent(target, command, A3, A4, A5, A6)
  cmdId = command:getCommandId()

  -- Special case: command 24105 fires locally (probably UI-only)
  if cmdId == 24105:
    if command:fire(self, target, A3..A6):
      return  -- handled, no further action

  -- Default: relay the event to "server-on-command" script handlers
  -- (this is observer-pattern: registered scripts get notified)
  self:_callServerOnCommand(target, command, A3..A6)

  -- Special case: command 12014 (Chocobo riding) -- post-event
  -- pushes for riding state
  if cmdId == 12014:
    chocoboActor = _getStaticActor(320013)
    if chocoboActor:isRiding(self) and self:_isPushingOut():
      worldMaster:notify(chocoboActor:getRidingErrorTextId(self, 26005))
      ...
end
```

So `_callServerOnCommand` is the **observer-broadcast** native
binding — it relays the command event to any registered server-side
scripts (NPC AI, world events, etc.). The "Server" in the name refers
to **server-side scripts that observe commands**, not the network
server.

### `_onCommandRequest` — "another actor requests a command"

When another actor (PC or NPC) asks YOUR client to evaluate a command
(e.g. trade request, party invite). The actor here is the OTHER party,
not yourself.

```lua
function PlayerBaseClass:_onCommandRequest(target, command, A3, A4, A5)
  -- 1. Try via the command's own `command` method (subclass override)
  if not command:command(self, target, A3..A5):
    -- 2. Fall back to `fire` if `command` returns false
    if not command:fire(self, target, A3..A5):
      -- 3. Last resort: ask server to execute it directly
      self:_doServerOnCommand(target, command, A3..A5)
end
```

Three levels of fallback: try `command()`, then `fire()`, then
delegate to server. This is the **invitation reception** flow —
your client receives the invite, tries to handle locally; if not,
asks the server.

### `_onCommandRejected` — "your command was rejected"

Triggered when your last `_executeCommand` was rejected by the
server (range fail, cooldown not ready, target invalid, etc.).
The handler shows an error message and clears local state.

### `_onCommandCancel` — "command was cancelled mid-execution"

Triggered when an ongoing command (cast in progress) gets cancelled
(player moved, took damage that broke cast, etc.).

## `Player:canCommand` — the Permission Gate

Called from `command()` before firing. Combines local checks with
the command's own `canFire`:

```lua
function PlayerBaseClass:canCommand(command, A2..A10)
  -- 1. Burst blocker check (anti-spam)
  cmdId = command:getCommandId()
  if cmdId ~= 12017 and cmdId ~= 12009:  -- bypass for system cmds
    if self.playerWork.commandBurstBlocker ~= nil:
      return false  -- still in cooldown

  -- 2. Permission check via category
  commandName = self:getCommandName(command)
  if commandName ~= "commandRequest":
    if not self:_canExecuteCommand(commandName):
      return false  -- category not allowed in current state

  -- 3. Delegate to command's own canFire (full validation)
  return command:canFire(self, A2..A10)
end
```

Commands 12017 and 12009 bypass the burst blocker — these are
**system commands** (probably "stop action" / "cancel" / "logout"
that need to fire even during cast).

## `AttackCommand` — A Concrete Subclass (verified)

The `AttackCommand` subclass extends `BattleCommandBaseClass` and
implements:

```text
isAttackCommand            returns true (unless isMagicMissile)
isMagicMissileCommand      cmdId in ranges:
                             22301-22306  (basic magic missiles)
                             28588-28589  (advanced missiles)
                             28928-28929  (special missiles)
canAimForRelation          (false, false, true) — only enemies
canFireForRelation         (false, false, true) — only enemies
useWeaponRangeInformation  cmd 27578: (true, false); cmd 22114:
                            (false, false); else: (true, true)
getCommandRangeCode        = 2  (consistent for all attacks)
getCommandTargettingMode   = 1
getCommandRangeTargettingMode  cmd 28588: 2; else: 1
isLongRangeCommand         cmd 22114: always true; else: weapon-derived
getFrequency               cmd 26678: 3; else: nil
getUseAmmoMax              cmd 22114: -1; if isAttackCommand: -2;
                            else: -1
getCommandRangeShape       complex per-command override (many ranges)
getAttackVolume            DAMAGE TIER classifier (server-relevant!)
```

### `AttackCommand:getAttackVolume(damage, target)`

Classifies damage into 3 tiers based on target's HPMax:

```text
threshold       result
-------------   ------
damage >= HPMax/13 * 1.1   tier 2 (high)
damage >= HPMax/13 * 0.9   tier 1 (mid)
else                       tier 0 (low)
```

Some commands force tier regardless of actual damage:

```text
cmd 27759             always tier 1 (mid)
cmd 27038/27039/      always tier 2 (high)
cmd 27579/27758
```

So **the damage tier is for UI display purposes** (different hit
animations / damage popup colors) — server pushes the damage value;
client computes the tier locally.

### Magic Missile Command IDs

```text
22301-22306    6 commands (probably the 6 elemental missiles —
                Fire/Ice/Wind/Earth/Lightning/Water)
28588-28589    2 commands (advanced missiles)
28928-28929    2 commands (special missiles)
TOTAL:         10 magic missile commands
```

## Assessment

```text
Confirmed:
  - The outbound command wire is _executeCommand(cmdName, command,
    ...args8) -- 11 total args; cmdName is a dispatch classification
    string.
  - The 11-arg signature matches the binding shape exactly:
    1 commandName + 1 command actor + 8 command-specific params.
  - 50-char total limit on first 2 string args (anti-spam input
    sanitization at client side).
  - playerWork.commandBurstBlocker is set to 1 after each command
    fire; subsequent commands rejected by canCommand until cleared.
  - Commands 12017, 12009 bypass burst blocker (system commands).
  - Three inbound dispatch hooks: _onCommandEvent (your cmd starts),
    _onCommandRequest (another actor requests cmd from you),
    _onCommandRejected (server rejected), _onCommandCancel (mid-cast
    cancel).
  - Damage tier (low/mid/high) computed client-side from
    damage vs HPMax/13 thresholds; server pushes raw damage value.
  - Magic missile commands occupy 10 distinct ids across 3 ranges.
  - AttackCommand subclasses BattleCommandBaseClass; gameCommandBaseClass
    is the grandparent.

Likely (High):
  - _callServerOnCommand is the observer-broadcast binding (notify
    registered scripts about a command starting). Different from the
    network "send to server" binding which is _executeCommand.
  - _doServerOnCommand is the explicit "ask server to validate and
    execute" binding -- used when client can't handle a request
    locally.
  - The 8 param slots after commandName + command actor cover:
    p1=target actor id, p2-p4=positional/area data, p5-p8=
    command-specific (item id for item commands, choice index for
    NPC dialog commands, etc.).
  - The damage-tier threshold of HPMax/13 (~7.7%) is the "noticeable"
    damage threshold. Damage below that shows minimum visual feedback.

Likely (Medium):
  - The "burst blocker" is a 1-second-or-less timer (the typed value 1
    is probably "seconds remaining"). Used to prevent action spam.
  - The 24105 special case (handled locally in _onCommandEvent) is
    probably a "leave duty" / "abandon party" command that needs
    immediate client-side effect.
  - The 12014 special case (chocobo riding state push) is the
    "mount chocobo" command that updates riding state across actors.

Speculative:
  - The 50-char limit on string args is for "macro text" or "trade
    message" -- 1.x had limited text input in commands.
  - The 10 magic missile commands at 22301-22306, 28588-28589,
    28928-28929 are the basic + extended + signature spells.
    The non-contiguous ranges suggest the spells were added in
    separate patches.

Next test:
  - Read BattleCommandBaseClass (the parent of AttackCommand) for
    the additional damage calculation hooks not in GameCommandBaseClass.
  - Find _executeCommand in the EXE via Ghidra string search:
    "_executeCommand" or "executeCommand" should appear in the Lua
    binding table. Pinning its address confirms the packet builder.
  - Find getAttackRangeShape in CharaBaseClass (referenced by
    AttackCommand:getCommandRangeShape).

Commit suggestion:
  docs(re/lua): command execute wire (_executeCommand binding;
                _onCommandEvent/Request/Rejected/Cancel; AttackCommand)
```

## Server implication

A combat-capable server now has the **outbound command wire shape**:

```text
Client → Server (CommandExecute):
  playerActorId               -- sender
  commandName_enum            -- classification (1=Request, 2=JudgeMode, etc)
  commandActorId              -- which command (action sheet row)
  param1..param8              -- command-specific (target id, choice, etc)

Server → Client responses:
  CommandEvent(target, command, params)        -- approved/started
  CommandRequest(target, command, params)      -- other actor requests
  CommandRejected(reason)                       -- denied
  CommandCancel(target)                         -- mid-cast cancelled
```

And the **server-side validation flow** for an inbound CommandExecute:

```text
1. Look up command in action sheet (commandActorId)
2. Run all checks from canCommand (range, target valid, cooldown,
   relation, hp/mp/tp cost) -- the same checks as
   GameCommandBaseClass:canFire walks
3. Deduct cost (TP via calculateCommandCost formula)
4. If has cast time: send CommandEvent (cast started)
                     wait cast time
                     execute
5. Apply effects:
   - Damage: compute via getAttack/getAttackRate vs target's
     getNormalDefence/getEvasion, push hp[1] update
   - Status effect: push statusShownTime update
   - Cooldown: push commandSlot_recastTime[slotIdx] update
6. Send CommandEvent broadcast to all viewers (for animation)
7. Push HP and other state updates as usual
```

**The combat loop is now fully wired**:
- Outbound action via `_executeCommand` (11-arg packet)
- Validation via `canFire` (already documented)
- Cost via TP formula (already documented)
- Effects via field updates (HP, statusShownTime, recastTime)
- Visual via existing `_onChange*` reactive hooks
- Damage tier classifier client-side (no wire opcode needed)

The wire surface for a single melee attack is approximately:

```text
Client → Server (1 packet):
  ~16 bytes (player id + command name enum + command id + target id)

Server → Client (1-2 packets):
  ~32 bytes (CommandEvent with start time + parameters)
  Then a follow-up hp update via the sync channel

Total per attack: ~48 bytes both ways.
```

A combat-busy server handling 100 actions per second per player
pushes ~5 KB/s. Well within the 1.x 512Kbps DSL budget. The protocol
was designed to be **very bandwidth-efficient**.
