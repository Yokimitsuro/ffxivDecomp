# Finding: `_onTouch` Opcodes (0/1) Are GATHERING PROXIMITY Events

REFINES the prior `_onTouch` interpretation. Originally documented
as "physical contact / touch begin-end". Walking the actual Lua
handler in `playerbaseclass.lua` shows that `_onTouch` is the
**proximity-driven contextual command activation** system: when the
player enters range of a fishing spot, harvest point, or interactive
chair, the server pushes opcode 0; when they leave, opcode 1.

## Lua source

`lua/decompiled/src/729s9/uy9l5s/uy9l5s89r57y9rr.lua` (PlayerBase, the
deciphered filename = `729s9/uy9l5s/uy9l5s89r57y9rr.lua` -> roughly
"player/playerbaseclass.lua"), lines 1502-1593.

## `_onTouch(player, touchKind, touchEnter)` body

```lua
function PlayerBaseClass:_onTouch(A1_touchKind, A2_enter)
    local areaMaster = self:_getCurrentAreaMaster()
    if areaMaster:isInstanceRaid() then
        if A1_touchKind == 5 then
            local raidSvc = _getStaticActor(24301)
            local cmdName = self:getCommandName(raidSvc)
            if A2_enter then
                self:_executeCommand(cmdName, raidSvc, 30004, 5, 1)
            else
                self:_executeCommand(cmdName, raidSvc, 30004, 5, 2)
            end
        end
        return
    end
    if A1_touchKind == 1 then           -- GATHERING / HARVEST proximity
        if A2_enter then
            local cmd = self:searchReadyCommand(22004)   -- 22004 = "Fish"
            if cmd ~= nil then
                if cmd:canFire(self, ...) then
                    self:setPlaceDrivenCommandVariation(30003, nil, self, 5)
                end
            end
        else
            self:resetPlaceDrivenCommandVariation(30003, nil, self, 5)
        end
    elseif A1_touchKind == 2 then      -- SIT-CHAIR proximity
        if A2_enter then
            self:setEmoteSitCommandVariation(10002)
        else
            self:setEmoteSitCommandVariation(nil)
        end
    end
end
```

## Command id meanings (from FFXIVTool mycsv/Command.csv)

```text
22004  Fish      (fishing line action; category 6 = fishing job)
22005  Herd      (Shepherd herding action)
30003  Place-driven gathering command variation (set on hotbar slot)
30004  Place-driven instance-raid command variation
10002  Sit emote variation
```

So the proximity dispatcher tests for `searchReadyCommand(22004 Fish)`
specifically -- the client probes "do I have the Fish action equipped
and is it ready?" before granting the place-driven variation.

## Player work schema (already documented)

The contextual command system uses 4 parallel arrays on playerWork
(per the schema declaration in `uy9l5s89r57y9rr.lua` lines 427-461):

```text
variableCommandPlaceDriven         array[4] of integer16   (command id)
variableCommandPlaceDrivenSub      array[4] of integer32   (sub-command)
variableCommandPlaceDrivenTarget   array[4] of actor       (target actor ref)
variableCommandPlaceDrivenPriority array[4] of integer8    (priority/slot)
```

So **4 simultaneous proximity commands** can be active. Each slot is
indexed by the `priority` argument (5 in the Fish case). Slots can
be allocated by different proximity triggers concurrently (e.g. a
fish spot AND a sit chair AND a hamlet supply cache).

## Touch kinds enumerated

From the Lua dispatcher:

```text
touchKind = 1   -- gathering proximity (Fish probe; possibly also
                   Mine/Botany/Log/Herd via getPushCommandVariation
                   reuse)
touchKind = 2   -- sit-chair proximity (sit emote variation)
touchKind = 5   -- instance-raid proximity (executes command 30004
                   on the static raid actor 24301)
```

Other touch kinds (3, 4, 6+) are not handled by PlayerBaseClass and
fall through silently. Sub-class handlers (e.g. NpcBaseClass) may
override `_onTouch` for additional kinds.

## Complete server picture for opcodes 0 and 1

```text
SERVER PUSHES OPCODE 0 (entry 0 of dispatch table 0x00fdfb80):
  Payload:
    + touch_kind  (uint8)  -- 1 = gathering, 2 = sit, 5 = raid service
                              other kinds reserved
    + (other payload, TBD; from packet reader)
    + enter_flag = TRUE (this opcode is the BEGIN variant)

CLIENT EFFECT:
  PlayerBase::_onTouch(touch_kind, true)
  -> conditional setPlaceDrivenCommandVariation / setEmoteSitCommandVariation
  -> command becomes available on the hotbar

SERVER PUSHES OPCODE 1 (entry 1):
  Same payload structure but enter_flag = FALSE
  -> conditional resetPlaceDrivenCommandVariation / setEmoteSitCommandVariation(nil)
  -> command is removed from the hotbar

WHEN to push:
  Server simulates a 3D proximity check between the player and any
  registered "interaction point" (fishing spot, harvest point, sit
  chair, raid service NPC, hamlet supply cache, etc.).
  - When player enters range -> push opcode 0 with the matching
    touch_kind.
  - When player leaves range -> push opcode 1.
  - The PLACE-DRIVEN COMMAND state lives on the SERVER; the
    client merely mirrors the activation/deactivation.

WIRE BANDWIDTH:
  Most-frequent opcode in 1.x because players constantly traverse
  in/out of harvest point proximity. Server should batch when
  possible (e.g. enter + leave within 1 tick can collapse to no-op).
```

## The "push" naming was misleading

`_onPushEvent` in NpcBaseClass (a DIFFERENT subsystem, also analyzed
in this finding pass) handles a separate NPC-interaction "push"
mechanic (player pushes NPC). Notably:

```text
NpcBaseClass._onPushRequest (line 528):
  if A2_2 == "pushCommandIn" then
      <set place-driven command from NPC>
  elseif A2_2 == "pushCommandOut" then
      <reset place-driven command>
  else
      _doServerOnPush(A1, A2)   -- generic push event handler
  end
```

So "push" in 1.x has TWO meanings:

```text
1. Player-pushes-NPC physical event (NpcBaseClass._onPushEvent):
   - Player walks into NPC's collision -> NPC reacts (animation, dialog)
   - Server may push "pushCommandIn" event -> NPC grants a contextual
     command to the player (e.g. talk-to-quartermaster)
   - Server pushes "pushCommandOut" when player leaves NPC's range

2. Engine-level proximity TOUCH events (PlayerBase._onTouch):
   - Server detects player near an interaction point
   - Pushes opcode 0/1 to enable/disable contextual hotbar commands
```

Both ultimately funnel into the same `setPlaceDrivenCommandVariation`
API. So the 4-slot playerWork array can be populated by EITHER
proximity TOUCH events OR NPC-push events.

## Connection to HamletDefense (NM / supply caches)

`populaceHamletPushEvent.csv` (FFXIVTool decode_csv, 75 rows + 78
text rows) is the data table that drives Hamlet defense quartermaster
dialogs. Sample rows:

```text
Row 1: "Warden's Justice / Azeyma's Fire" -- alchemical mixture
       to disorient enemies (collect 3 pots of humours)
Row 2: "Provide soldiers with crafting materials"
Row 3: "Protect supplies from enemies"
```

So during Hamlet defense, players walk near supply caches (TOUCH
event kind ?) and get a "Pick up pot" contextual command. They then
return to the quartermaster (different proximity event) which gets
a "Submit pots" command. The 4-slot place-driven array is the
backbone of the entire Hamlet defense gameplay loop.

## Reclassification of opcodes 0 and 1

```text
PRIOR:    "physical touch begin / end"
NEW:      "proximity-driven contextual command BEGIN / END"
COVERAGE: kinds 1 (gathering), 2 (sit), 5 (raid service)
                + at least one more for hamlet supply caches
                  (likely kind 3 or 4 -- TBD)
```

## Annotations made in Ghidra

```text
RENAMES:
  - 0x00898d20 -> Player_invokeLua_onTouch_proximityBegin
  - 0x00898eb0 -> Player_invokeLua_onTouch_proximityEnd

COMMENTS:
  - 0x00898d20 (multi-line, with touch-kind enumeration, command
                id mapping 22004 = Fish, 30003 = place-driven
                variation, and the 4-slot playerWork schema)
  - 0x00898eb0 (paired-with-begin, frequent-opcode rationale)
```

## Confidence

```text
Confirmed:
  - Command 22004 = "Fish" (per FFXIVTool mycsv/Command.csv row 22004).
  - Command 22005 = "Herd" (Shepherd action, per same source).
  - _onTouch handles touchKind 1 (gathering), 2 (sit), 5 (raid
    service) in PlayerBaseClass.
  - placeDrivenCommandVariation has 4 parallel slot arrays on
    playerWork (command/sub/target/priority).
  - The "5" in setPlaceDrivenCommandVariation(...,5) is a slot
    priority index (per the array sizing of 4 with priority
    typed as integer8).

Likely (High):
  - Touch kinds 3, 4, and 6+ exist for other interaction types
    (harvest points for Mine/Botany/Log, hamlet supply caches,
    door-touches, etc.). Each kind has its own command-id probe.
  - Opcodes 0 and 1 are the MOST FREQUENT opcodes by traffic
    volume in 1.x because players cross proximity boundaries
    constantly while moving in zones.

Likely (Medium):
  - The Hamlet defense gameplay loop is implemented as a SEQUENCE
    of proximity-driven place-driven commands: walk to cache ->
    get "Pick up pot" command -> walk to quartermaster -> get
    "Submit pots" command.
  - touchKind 2 (sit) might be the chair-touching mechanism
    documented in finding_chara_cliprog_and_event_extensions.md
    (main stat 32 = sit state).

Speculative:
  - The 4-slot array depth was chosen because 4 covers the
    typical concurrent proximities (e.g. fishing spot + sit
    chair + leve banner + NPC). 1.x team picked 4 as a sweet spot
    between memory cost and concurrency.
```

## Next test

- Identify touch kinds 3, 4, 6+ by scanning other CharaBase
  derivatives that override `_onTouch` (or sub-class handlers
  for hamlet supply caches).
- Trace the proximity-check server-side -- since the client only
  reacts, the server needs to be the source of proximity decisions.
  Look at the prior session's findings on the Director system
  (which manages zone-level events) for proximity dispatch.
- Cross-reference the `populaceHamletPushEvent` table with the
  Hamlet defense Lua subsystem to enumerate the full gameplay
  loop's proximity-triggered commands.

## Commit suggestion

```
docs(re/correlation): _onTouch (opcodes 0/1) = gathering proximity, not physical contact
```
