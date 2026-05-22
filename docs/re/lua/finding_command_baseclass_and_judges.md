# Finding: `CommandBaseClass` Root + the Judge Dispatch System

Read of the deciphered `command/commandbaseclass.lua` — the root parent
of every Command class in the client. Companion to
`finding_game_command_pipeline.md`.

Source read:

```text
command/commandbaseclass.lua    7vxx9w6/7vxx9w689r57y9rr.lua  (4.4 KB)
```

## Headline results

1. **A Command IS a static actor.** `CommandBaseClass:getCommandId(self)`
   is literally `self:_getStaticActorID()`. The command's id on the
   wire and its identity as a Lua-side object are the same thing.
2. **All command properties are read from a single `commandSheet`**
   keyed by command id. The columns are stable indices (26..34 listed
   below), not field names.
3. **The 1.x decision system is the "Judges".** A command declares
   (via sheet flag columns) which judges it routes through. Each judge
   is itself a `.lpb` script under `judge/...judge.lua`.

## Class boilerplate

```lua
function CommandBaseClass:getCommandId()
  return self:_getStaticActorID()
end

function CommandBaseClass:getCommandData(col)
  return commandSheet:_getData(self:getCommandId(), col)
end

function CommandBaseClass:_onInit()
  self:_callSuperClassFunc("_onInit")
  local id = self:_getStaticActorID()
  commandSheet:_loadKeySemipermanently(id, id)
  self:init()
end

function CommandBaseClass:_onFinalize()
  self:_callSuperClassFunc("_onFinalize")
  local id = self:_getStaticActorID()
  commandSheet:_unloadKey(id, id)
  self:processFinalize()
end

-- empty placeholders for subclasses
function CommandBaseClass:init()              end
function CommandBaseClass:processFinalize()   end
function CommandBaseClass:canFire(...)        return false end
function CommandBaseClass:fire(...)           return false end
function CommandBaseClass:command(self, A1, ...) return false end
```

Important: every method in the base except the sheet getters returns
`false`. The base class is a contract surface; **all behaviour comes
from subclasses**.

## `commandSheet` columns

Pinned by direct reads in this file:

```text
col  meaning                            method
---  ---------------------------------  -----------------------------
 26  isOnlyServer                       isOnlyServer
 27  needsAcquired                      needsAcquired
 28  needsEquipped                      needsEquipped
 29  getPriority                        getPriority    (priority value)
 30  isJudgedAtCommonJudge              isJudgedAtCommonJudge
 31  isJudgedAtBattleJudge              isJudgedAtBattleJudge
 32  isJudgedAtCraftJudge               isJudgedAtCraftJudge
 33  isJudgedAtHarvestJudge             isJudgedAtHarvestJudge
 34  isJudgedAtNegotiationJudge         isJudgedAtNegotiationJudge
```

Note `GameCommandBaseClass` adds two more (already documented):

```text
 37  actor main-stat requirement        (read via getGameCommandData)
 38  main skill id                      getCommandMainSkill
 39  level                              getCommandLevel
```

So **columns 1..25 are still TBD** — they're whatever the parent class
fields share with all `Command`-like objects (probably name/id/icon
text-ids, range basics, ...) and are likely sheet-id text references.

## The Judge dispatch system

Columns 30..34 declare which "Judge" subsystem a given command routes
through:

```text
isJudgedAtCommonJudge        --> judge/CommonJudge*
isJudgedAtBattleJudge        --> judge/BattleJudge*
isJudgedAtCraftJudge         --> judge/CraftJudge*
isJudgedAtHarvestJudge       --> judge/HarvestJudge*
isJudgedAtNegotiationJudge   --> judge/NegotiationJudge*
```

Cross-reference with `docs/re/lua/catalog.md` "judge" section
(18 scripts under `judge/`):

```text
judgemaster
commonjudge
craftjudge       /  cmncraftjudge
harvestjudge     /  cmnharvestjudge
battlejudge*     (multiple variants — actionjudge / autoattackjudge /
                  battleprocessjudge / hatecontroljudge / actionjudge)
negotiationjudge
chocobojudge
depictionjudge
instanceraidguidejudge
tutorialjudge / tutorialdummyjudge
gamecalculatejudge
```

These are the *outcome engines* of 1.x: a command goes in, a judge
script computes the result (damage roll, craft quality delta, harvest
yield, negotiation outcome, etc.) and produces a result packet. The
sheet-flag columns 30..34 tell the dispatcher which judge to consult.

**A command can be judged by more than one.** Nothing in the code
makes them mutually exclusive — a craft action might be both
`isJudgedAtCommonJudge = true` and `isJudgedAtCraftJudge = true`.

## What "isOnlyServer" means (col 26)

The literal flag the client reads to decide "this command's result is
computed exclusively by the server; the client must not even try a
local fire". Combined with the chains in `_onCommandEvent` /
`_onCommandRequest` (see `finding_game_command_pipeline.md`):

```text
isOnlyServer == true  -> client always _callServerOnCommand, never
                         attempts command:fire() / command:command()
                         locally. Pure server-driven.
isOnlyServer == false -> client may try local fire() (e.g. the 24105
                         path) and only falls back to server if it
                         couldn't handle locally.
```

So the wire shape for the two cases is the same packet, just the
trigger is different.

## Why this matters

The previously documented `_onCommandEvent` chain has a special case
for command id `24105`:

```lua
if id == 24105 then
  local handled = command:fire(self, ...)
  if handled then return end       -- skip the server call
end
```

That special case is essentially **a manual override of the
`isOnlyServer` decision**: command 24105 is client-only regardless of
its sheet. Every other client-only behaviour is data-driven via column
26.

## Static-actor IDs are command IDs

Pulled into one place:

```text
id            interpretation
------------  ------------------------------------------------
12014         chocobo ride toggle  (game command)
12015         push-out-from-chocobo internal command
22001         harvest                  (game command)
22002..22009  craft (variants)         (game commands)
22012, 22016  craft-with-target        (game commands)
23000..23999  non-hostile range        (game commands)
24105         client-only command      (game command)
24301         Instance Raid service    (static service actor)
30004         instance raid timer cmd  (game command)
310001        WorldMaster              (static service actor)
320013        Chocobo Rider            (static service actor)
```

Every entry is the same kind of object on the Lua side: a static actor.
The id partitions are conventional, not enforced by code:

- `0..29999`           — gameplay command objects
- `30000..99999`       — instance/raid commands and timers
- `1xxxxx`             — likely gameplay/scripted singletons (e.g. instance services)
- `2xxxxx`             — service objects (e.g. 24301, 24105)
- `3xxxxx`             — system / world singletons (e.g. 310001, 320013)

These bands are inferred from the few ids seen; not confirmed against
a full registry.

## Assessment

```text
Confirmed:
  - Command id IS the static actor id. There is no separate command
    registry — commandSheet is keyed on the actor id.
  - The commandSheet exposes a fixed column index per property
    (26..34 mapped above; 37..39 added by GameCommandBaseClass).
  - The base class is an empty contract: canFire / fire / command
    all return false by default.
  - The 1.x "Judge" subsystem (5 judge categories: Common, Battle,
    Craft, Harvest, Negotiation) is selected per-command via boolean
    sheet columns 30..34.

Likely (High):
  - isOnlyServer (col 26) is the client-side switch for "skip local
    fire, always ask server". Command 24105's hardcoded override is
    the lone exception and is most likely a leftover from a
    pre-sheet refactor.
  - The judge directory in the corpus (judge/CommonJudge,
    judge/BattleJudge, judge/CraftJudge, ...) is the dispatch target.
    Each judge script computes a result packet that the server then
    consumes / mirrors.

Likely (Medium):
  - The judge scripts implement deterministic math the SERVER also
    runs — the client runs them locally for prediction (visual
    response), and the server runs them authoritatively. Server and
    client output must match for "no rubber-banding". Without
    running both, this is structural inference; would need to read
    a judge's actual code and a packet log to confirm.

Speculative:
  - That the static-actor id banding (12xxx gameplay, 24xxx service,
    310xxx world, 320xxx avatar) is the SE convention across all
    static objects, not just commands. Reading a couple more static
    actor decls would confirm or deny.

Next test:
  - Read judge/CommonJudge.lua and judge/BattleJudge*.lua to learn
    the actual outcome computation surface (damage roll, hit/miss,
    enmity application).
  - Read judge/judgemaster.lua to find the dispatch table that maps
    sheet flags 30..34 to judge invocations.
  - In Ghidra, search for the C++ side of "commandSheet" -- likely a
    bound table at a known static address - to inventory all
    command ids in the live build.

Commit suggestion:
  docs(re/lua): document CommandBaseClass + Judge dispatch system
```

## Server implication (additions)

1. **The command sheet is authoritative.** Any server-side balance
   change (range, cost, cooldown, judge routing) MUST be reflected in
   `commandSheet` or the client will mis-predict.
2. **The judge category for each command is in column 30..34 of the
   sheet**. A server bring-up that wants to support, say, only crafting
   can ship just `CraftJudge` and ignore the rest. Every command
   whose sheet has `isJudgedAtCraftJudge=true` needs that judge to be
   present on both sides.
3. **`isOnlyServer = true` commands** always travel the
   `_callServerOnCommand` path; the server can rely on always seeing
   them (no client predictions to reconcile).
4. **`isOnlyServer = false` commands** may be ack'd locally with no
   server packet (e.g. cosmetic emotes, UI commands). The server should
   not assume every command results in a wire transaction.
5. **No separate "command table" packet is needed.** Both sides resolve
   command id -> actor by static-actor lookup. The id appears in the
   IPC payload and the receiver uses its own commandSheet for the
   rest.
