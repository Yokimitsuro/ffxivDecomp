# Finding: CommandBaseClass -- Action Model (command.csv-backed actors, 5 judge categories, abstract fire interface)

**Maps the command/action base mechanics** — CommandBaseClass, the
base for all commands/actions (abilities, weaponskills, spells, item
use, system commands). Completes the action model: commands are
command.csv-backed actors validated by one of 5 judge categories,
with an abstract canFire/fire/command interface that concrete commands
override.

CommandBaseClass (7vxx9w689r57y9rr.lua, 246 lines, 21 functions).

## 1. Command as a data-backed actor

```text
_onInit(self)                                          [155]
   -> _callSuperClassFunc("_onInit")  (ActorBase init)
   -> id = _getStaticActorID()
   -> commandSheet:_loadKeySemipermanently(id, id)
      (load this command's command.csv row -- cached while actor lives)
   -> init()

_onFinalize(self)                                      [192]
   -> commandSheet:_unloadKey(id)  (release the CSV row)
   -> processFinalize()

getCommandId / getCommandData    identity + command.csv row

A command is an ACTOR backed by command.csv. It loads its definition
row on init (semipermanent caching) and unloads on finalize. The
"commandSheet" is the SpreadSheet actor for command.csv.
```

## 2. The 5 judge categories

Each command declares WHICH judge system validates it:

```text
isJudgedAtCommonJudge        common/general validation
isJudgedAtBattleJudge        combat command (target, range, hostility)
isJudgedAtCraftJudge         crafting command (DoH)
isJudgedAtHarvestJudge       gathering command (DoL)
isJudgedAtNegotiationJudge   negotiation/trade command

These route to the Judge system (0p635 dir). Before a command fires,
its judge category validates it:
  - Battle: is the target valid? in range? hostile?
  - Craft: do you have materials? at a crafting station?
  - Harvest: at a gathering node? right tool?
  - Negotiation: valid trade target?
  - Common: general prerequisites

The judge type determines BOTH client-side pre-validation AND the
server-side validation category.
```

## 3. Command flags

```text
isOnlyServer        command MUST go to server (no local execution)
needsAcquired       must be learned/unlocked to use
needsEquipped       requires specific gear equipped
getPriority         command priority (queue/conflict resolution)
isBattleCommand     is a combat action
isHostilityCommand  generates enmity / is hostile
isDesktopCommandMode runs in desktop/UI command mode
```

**isOnlyServer** is the key distinction: server-only commands always
send to the server (via _executeCommand -> 0x12d); others may run
client-side first (the "try local, fall back to server" pattern from
getSystemCommand).

## 4. Abstract execution interface

```text
canFire(self, caster, ...)   [228]  -> BASE returns false (abstract)
fire(self, caster, ...)      [231]  -> BASE returns false (abstract)
command(self, ?, ...)        [240]  -> BASE returns false (abstract)

ALL THREE are ABSTRACT in the base class -- each concrete command
subclass overrides them with its specific logic:
  canFire  = "can this command execute right now?" (pre-check)
  fire     = "execute the command effect" (the action logic)
  command  = the command entry point

This is the interface the player command flow calls:
  player:command(cmdObj) -> cmdObj:canFire() -> cmdObj:fire()
  (per the playerbaseclass command flow finding)
```

## 5. The complete action model (assembled)

```text
COMMAND = command.csv-backed actor with judge-validated abstract interface.

DEFINITION:
  - command.csv row (id, judge category, flags, level, params, costs)
  - loaded via commandSheet:_loadKeySemipermanently
  - concrete subclass implements canFire/fire/command

EXECUTION FLOW (assembled from player + command findings):
  1. Player triggers command (UI/hotkey/macro)
  2. player:command(cmdObj, params):
     - commandBurstBlocker anti-spam check
     - cmdObj:canFire(player, params) -- judge-category pre-validation
  3. player:_onCommandRequest:
     - 50-char limit + canCommand
     - if isOnlyServer OR not locally-resolvable:
       _executeCommand -> 0x12d (CHECKSUMMED for abilities)
     - else: cmdObj:fire() runs locally (client prediction)
  4. SERVER validates (judge category) + computes result
  5. SERVER responds: action result (0x148/0x149) + WorkSync state
  6. Client applies result (damage, status via StatusBase, etc.)

COMMAND CATEGORIES (by subdir + judge):
  Battle commands  (abilities/weaponskills/spells) -> BattleJudge
  Craft commands   (DoH synthesis)                 -> CraftJudge
  Harvest commands (DoL gathering)                 -> HarvestJudge
  Item commands    (1q5x7vxx9w6 = item use)        -> CommonJudge?
  System commands  (rlrq5x/ = menu/cancel/etc.)    -> CommonJudge
  Negotiation      (trade)                          -> NegotiationJudge
```

## 6. Server-side requirements

```text
COMMAND VALIDATION (server-authoritative):
  - command.csv: command definitions (id, judge category, level,
    cost, cast time, recast, target type, params)
  - On receiving 0x12d command:
    * route to the command's judge category (Battle/Craft/Harvest/
      Negotiation/Common)
    * validate: acquired? equipped? resources? target valid? range?
    * isOnlyServer commands: always validate (no client trust)
  - Compute result + respond (0x148/0x149 + WorkSync)

WHAT'S CLIENT-LOCAL:
  - The 5 judge implementations (client pre-validates for responsiveness)
  - canFire/fire logic (the concrete command scripts)
  - command.csv (client has it; server has its own copy)

SERVER DATA NEEDED:
  - command.csv (+ gameCommand.csv, gameCommandBasic.csv per CSV findings)
  - command -> judge category mapping (for validation routing)
  - acquired-command + equipped-gear state per player (for needsAcquired/
    needsEquipped checks)
```

## 7. Confidence

```text
Confirmed:
  - CommandBaseClass = command.csv-backed actor (commandSheet load)
  - 5 judge categories (Common/Battle/Craft/Harvest/Negotiation)
  - 7 command flags (isOnlyServer, needsAcquired, needsEquipped,
    getPriority, isBattleCommand, isHostilityCommand, isDesktopCommandMode)
  - canFire/fire/command abstract in base (concrete subclasses override)
  - _loadKeySemipermanently caching (loaded while command actor lives)
  - 21 functions enumerated

Likely (High):
  - The judge category routes both client pre-validation and server validation
  - isOnlyServer = always-server-validated (no client trust)
  - Item/system commands use CommonJudge
  - Concrete commands in subdirs (39x5 game, rlrq5x system) + chara
    command files

Speculative:
  - getPriority resolves command queue conflicts (GCD/animation lock)
  - needsAcquired ties to the player's learned-command list
  - The command level + level-adjust (per status/item findings) applies
    to command potency too
```

## 8. Cross-references

- `finding_playerbaseclass_command_flow_and_player_module.md` -- the
  command flow that calls cmdObj:canFire/fire (player:command)
- `finding_executeCommand_outbound_path_CLOSED_0x12d_checksummed.md` --
  the wire path commands take (0x12d)
- `finding_statusbaseclass_status_effect_engine.md` -- statuses applied
  by commands (same level-adjust model)
- `finding_csv_complete_correlation_132_of_164_critical_mapped.md` --
  command.csv / gameCommand.csv (server command definitions)
- `finding_combat_command_pipeline_and_4param_scaling.md` -- combat
  command scaling (prior finding)
- (next) judge system (0p635) -- the 5 judge categories' validation logic

## 9. Next test

```text
1. Read the judge system (0p635) -- the 5 judge categories' validation
2. Read a concrete battle command (ability/weaponskill) canFire/fire
3. Map command.csv columns (judge category, flags, level, cost, params)
4. Read item command (1q5x7vxx9w6) for item-use mechanics
5. Trace getPriority -> command queue / GCD resolution
```

## Commit suggestion

```
docs(re/lua): CommandBaseClass action model -- command.csv-backed actors, 5 judge categories (Common/Battle/Craft/Harvest/Negotiation), 7 flags, abstract canFire/fire/command interface
```
