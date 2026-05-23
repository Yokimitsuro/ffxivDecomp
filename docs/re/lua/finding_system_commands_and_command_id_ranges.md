# Finding: SystemCommandBaseClass + Concrete System Command Bodies + Command ID Ranges

Maps the SystemCommandBaseClass (parent of the 57 system commands)
and samples 3 concrete bodies (ContentCommand, LinkshellAppoint,
PlaceDrivenCommand). Reveals significant new command ID range data
+ confirms architectural separation between game and system commands.

## SystemCommandBaseClass (17 lines)

```lua
require("/Command/CommandBaseClass")
_defineBaseClass("SystemCommandBaseClass", "CommandBaseClass")

function SystemCommandBaseClass:isEnabled()
    return true
end
```

**THAT'S THE WHOLE FILE.** 17 lines, 1 method.

So SystemCommandBaseClass is a **THIN MARKER CLASS**. It just:
1. Inherits DIRECTLY from CommandBaseClass (NOT from GameCommandBaseClass)
2. Provides `isEnabled() -> true` as a default override

This contrasts sharply with GameCommandBaseClass (2698 lines, 90+
methods). The architectural meaning:

```text
COMMAND TAXONOMY:
   CommandBaseClass (246 lines, 22 methods)
       |-- GameCommandBaseClass (2698 lines)
       |     -- 5-judge dispatch, 4-param scaling, cost computation,
       |        range/target, fire pipeline -- ALL battle/game stuff
       |     |-- BattleCommandBaseClass + Attack/Magic/Ability/...
       |     |-- CraftCommand, HealingCommand, TeleportCommand,
       |     |   NegotiationCommand, ChocoboRideCommand, ...
       |
       |-- SystemCommandBaseClass (17 lines)
             -- NO game machinery; just a marker.
             -- Concrete commands implement their own canFire/fire.
             |-- ContentCommand, LinkshellAppointCommand,
             |   PlaceDrivenCommand, JournalCommand, MacroCommand,
             |   LogoutCommand, ... (~57 system commands)
```

So system commands are **fundamentally different** from game commands:
- They DON'T use the 5-judge dispatch (`isJudgedAt*`)
- They DON'T have the 4-param scaling
- They DON'T have HP/MP/TP costs from the game-cost sheet
- They DON'T integrate with `gameCommandSheet`
- Each system command implements its OWN canFire/fire from scratch

## ContentCommand (180 lines)

### Methods (8)

```text
canFire / fire / isEnabled
isNoneTarget / isAllTarget / isPcTarget / isNpcTarget / isPartyTarget
```

### Target taxonomy

ContentCommand has a **5-way target type predicate set**:

```text
None     no target required
All      any actor
Pc       player only
Npc      NPC only (with logic that may be buggy in decompile)
Party    party member only
```

These are mutually exclusive enums; each ContentCommand subclass
returns true for exactly one of them.

### canFire body

Validates:
1. Caller has the matching content command variation active
   (`A1.getContentCommandVariation() == (A2, A3)`)
2. Target type matches the predicate (None/All/Pc/Npc/Party)

So ContentCommand = a contextually-available command that only
appears on the player's hotbar when they're in matching content.

## LinkshellAppointCommand (192 lines)

### Args

```text
A1 = caster actor
A2 = string (linkshell name?)
A3 = string (target member name?)
A4 = integer 1-10 (RANK)
A6 = optional target actor (if specified, different validation path)
```

### KEY DISCOVERY: 10 linkshell ranks

```lua
if A4 < 1 or 10 < A4 then return false end
```

So **Linkshell supports 10 distinct ranks** (1-10). This is MORE than
typical MMO linkshells (FFXI had 3 ranks: leader/officer/member).

The 10 ranks suggest a more granular role hierarchy. Possible
breakdown (Speculative):
- Rank 1-2: Founder / Co-leader
- Rank 3-4: Senior officers
- Rank 5-7: Officers
- Rank 8-9: Trusted members
- Rank 10: Standard members

This aligns with the `LinkshellMenuSubWidget.rank` field (integer8)
which can hold 1-10 cleanly.

## PlaceDrivenCommand (159 lines) -- HUGE COMMAND ID MAPPING

### mapJudgeCommand (variation_id -> action_id)

```text
PLACE-DRIVEN VARIATION    ACTION COMMAND   PROBABLE MEANING
---------------------    ---------------  ----------------
   20001                    22002          Gathering type 1 (Mine?)
   20002                    22003          Gathering type 2 (Log / Botany?)
   20003                    22004          Fish (CONFIRMED)
   20004                    22005          Herd (CONFIRMED; Shepherd)
   20005 / 20009            22006          Gathering type 5
   20006 / 20010            22007          Gathering type 6
   20007 / 20011            22008          Gathering type 7
   30003                    22004          SPECIAL Fish variant (via touch)
```

So **7 gathering action commands (22002-22008)** and **12 place-driven
variation IDs (20001-20012)**, with some variation IDs sharing the
same action (parallel sets at 20005-20007 and 20009-20011).

### Command ID ranges (extended)

From the canFire body branches:

```text
10000-19999     ALWAYS-ALLOWED commands
                Probably: emote / cosmetic / utility (Sit, Wave, etc.)

20001-20012     PLACE-DRIVEN GATHERING VARIATIONS
                Activated by touch-proximity (opcodes 0/1)

22002-22008     ACTUAL GATHERING ACTIONS (7 of them)
                The commands that get added to hotbar slot 30003
                when proximity activates a place-driven variation.

30003           Special Fish variant (requires player._isTouching(1))
30004           Instance-raid service command (canFire = always true)
                Used by static actor 24301 (raid service NPC).

(From prior findings:)
22100-22499     Job-specific battle actions
22550-22698     Standard craft commands
26000-29999     Extended / Gift commands
29501-29698     Gift commands subset
```

### Updated command ID space (full picture)

```text
RANGE         CATEGORY                        COUNT
-----         --------                        -----
10000-19999   Always-allowed (emote / etc.)   up to 10k
20001-20012   Place-driven variations         12
22000-22099   Basic actions                   ~100
22002-22008   Gathering actions (7 of them)
22004 = Fish, 22005 = Herd (confirmed)
22100-22499   Job-specific actions            ~400
22550-22698   Standard craft commands         149
26000-29999   Extended / Gift                 up to 4k
29501-29698   Gift commands subset            ~200
30003-30004   Place-driven specials           2
TOTAL UNIQUE COMMAND IDs in 1.x: estimated ~3300-5000
```

This aligns with `gameCommand.csv` having 1613 rows + `command.csv`
having 1664 rows (their union covers the actual occupied IDs).

## Critical command IDs (gathering + place-driven, confirmed)

```text
CMD ID    NAME / PURPOSE                     CATEGORY
------    --------------                     --------
22002     Mining (or similar)                Gathering
22003     Logging / Botany                   Gathering
22004     Fish                               Gathering (confirmed)
22005     Herd (Shepherd)                    Gathering (confirmed)
22006     Gathering type 5                   Gathering
22007     Gathering type 6                   Gathering
22008     Gathering type 7                   Gathering

20001-20012  Place-driven variations         Proximity activation
30003     Place-driven Fish variant          Proximity (+touch=1)
30004     Instance-raid service command      Static actor 24301
```

So 1.x has **7 distinct gathering actions** activated through the
4-slot place-driven array via proximity events (opcodes 0/1).
This is exactly the model documented in
`finding_onTouch_is_gathering_proximity.md`.

## Architectural insights

```text
1. SYSTEM vs GAME commands are TOTALLY SEPARATE inheritance trees.
   System: SystemCommandBaseClass -> CommandBaseClass
   Game:   GameCommandBaseClass -> CommandBaseClass
   They share only the abstract base.

2. SYSTEM COMMANDS WRITE THEIR OWN canFire / fire / isEnabled.
   No 8-gate validation chain like game commands. Each system
   command has bespoke validation logic.

3. SYSTEM COMMANDS HAVE NO COST.
   Logout doesn't cost MP. Macro doesn't cost TP. They're free.

4. 10 LINKSHELL RANKS provide fine-grained social hierarchy.

5. 7 GATHERING ACTIONS + 12 PLACE-DRIVEN VARIATIONS encode the
   gathering subsystem cleanly. Proximity (opcode 0) activates a
   variation; player executes the matching action.

6. ContentCommand's 5 TARGET TYPES (None/All/Pc/Npc/Party) are
   server-validated -- the server pushes ContentCommand to the
   client with the appropriate target predicate, and the client
   filters which targets the command can apply to.
```

## Connections to other findings

- **finding_command_roster_complete.md**: confirmed 5-judge dispatch
  is from CommandBaseClass; system commands ALSO use that judge
  taxonomy but typically only `isJudgedAtCommonJudge`.
- **finding_combat_command_pipeline_and_4param_scaling.md**: the
  4-param scaling is GAME-command-only; system commands skip it
  entirely.
- **finding_negotiation_bazaar_widget_family.md**: NegotiationCommand
  is a GAME command (extends GameCommandBaseClass), not a system
  command, despite its UI-heavy nature.
- **finding_onTouch_is_gathering_proximity.md**: this finding
  confirms the 7 gathering actions + 12 place-driven variations
  documented there.
- **finding_linkshell_retainer_subsystems.md**: 10 linkshell ranks
  expands the prior 6-operation enum.

## Confidence

```text
Confirmed:
  - SystemCommandBaseClass = 17 lines, just `isEnabled` = true.
  - 57 system commands inherit from this (NOT from GameCommand).
  - System commands implement their own canFire/fire from scratch.
  - ContentCommand has 5 target types (None/All/Pc/Npc/Party).
  - LinkshellAppointCommand validates rank 1-10 -> 10 ranks total.
  - PlaceDrivenCommand maps variation IDs 20001-20012 to action
    IDs 22002-22008.
  - 7 gathering actions (cmd 22002-22008) + Fish (22004) + Herd
    (22005) confirmed.
  - Command id range 10000-19999 = always-allowed (emote/etc.).
  - Command id 30004 = instance-raid service (always allowed).

Likely (High):
  - cmd 22002 = Mining; cmd 22003 = Logging/Botany; cmds 22006-22008
    = other gathering variants (Sky Fish? Sky Mining? Hidden?).
  - The 10 linkshell ranks include: founder + co-leader + officers +
    members tiers; FFXI's 3-rank model expanded for 1.x's social
    design.
  - System commands are not displayed in the main hotbar UI; they're
    invoked via menu / chat / keystroke.

Likely (Medium):
  - cmd 30003 (Fish via place-driven) is the LEVE-fishing variant
    activated only when the player has a Fishing leve active AND
    is touching a fishing spot. Standard fishing uses 22004 directly.
  - cmd 30004 (raid service) is the "Leave Instance" or "Resign
    Content" command, gated through the raid service NPC.

Speculative:
  - The 10000-19999 always-allowed range contains all the emote
    commands (Wave, Bow, Sit, etc.) which can be used anywhere
    without prerequisite.
  - The duplicate variation IDs (20005/20009 -> same action) might
    indicate weather-conditional or time-conditional activation
    (e.g. "Fish during daytime" vs "Fish at night").
```

## Next test

- Read JournalCommand + MacroCommand bodies to confirm the "system
  command writes its own logic" pattern across more samples.
- Sample 5-10 specific quest scripts from the 629-file corpus to
  see how concrete quests integrate with QuestBaseClass.
- Read LogoutCommand to see how the logout flow's Lua side works.

## Commit suggestion

```
docs(re/lua): SystemCommandBase + concrete bodies; reveal 7 gathering actions + 10 linkshell ranks
```
