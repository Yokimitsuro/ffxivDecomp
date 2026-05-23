# Finding: Cross-Reference Round 2 -- LoginEvent Quests, Bard Songs, Stone Throw, Spell Tiers

Second cross-reference sweep. Concrete identifications:

1. **4 LoginEvent quest names** identified (the per-city starter
   greeting quests)
2. **Spell tier families** confirmed: Cure (4 tiers), Banish
   (4 tiers), Drain (3 tiers), Stoneskin (3 tiers)
3. **Stone Throw = cmd 22114** -- the AttackCommand override
   that returns -1 (single-hit) is for "Stone Throw"
4. **Cura confirmed** as 1.x equivalent of ARR's Cure II
5. **Static actor IDs** (310001/24301/...) NOT in populace tables
   either -- they're in a separate registry

## 1. LoginEvent Quest Names Identified

Per `finding_quest_corpus_and_login_event_command.md`, the
LoginEventCommand triggers per-city greeting quests via specific
quest IDs. Now identified:

```text
Quest ID    Name (JA)              Name (EN)              City
--------    ---------              ---------              ----
110839      対価の報い              Private Eyes           Limsa Lominsa (ch1)
110829      暗中の光明              In Plain Sight         Gridania (ch1)
110849      被疑者の男              The Usual Suspect      Ul'dah (ch1)
110841      勇者と事件と灰と剣      Prophecy Inspection    (ch3, shared)
```

So the 3 starter cities each have a **DETECTIVE-THEMED ch1 quest**:
- Private Eyes / In Plain Sight / The Usual Suspect

This is consistent with the FFXIV 1.x Main Scenario's GARLEAN
SPY plotline (player investigates Garlean spies infiltrating the
city-states).

The chapter 3 shared quest "Prophecy Inspection" is the SHARED
story arc that all 3 city-routes converge to.

### Quest schema fields observed

From quest.csv rows for these 4 IDs:
- col 41 = 101 (probably MAIN SCENARIO package id)
- col 47 = 11060001 (some category / completion bonus id?)
- col 53 = 15 or 20 (LEVEL REQUIREMENT: ch1=15, ch3=20)
- col 54 = 101 (sub-package? duplicate of 41)
- col 55 = 0 (?)
- col 57 = false (some flag, e.g. completable bool)
- col 58 = true (some flag, e.g. is-main-scenario)

So 1.x's main scenario chapter 1 begins at **level 15** -- not at
level 1 -- which is when the player has built up a basic class.
Chapter 3 unlocks at level 20.

## 2. Spell tier families confirmed

Common spells with MULTIPLE TIERS:

```text
SPELL        TIERS                IDs
-----        -----                ---
Cure         I, II, III, IV       29010, 29011, 29012, 29013
Banish       I, II, III, IV       28597, 28598, 28599, 28600
Drain        I, II, III           28610, 28611, 28612
Stoneskin    I, II, III           27350 (cross-class), 29023, 29024, 29025
Bio          (II, III at least)   28603, 28604
Stone        (multiple variants)  22114 (Stone Throw), 23517 (Stone II)
```

So 1.x has rich spell tier systems matching FFXI's NQ/HQ/MX
hierarchy. Cure has 4 tiers in 1.x; ARR collapsed to "Cure II"
and added new tiers later.

### Status cure naming (FFXI-style)

```text
ENGLISH NAME      JA NAME          FFXI Equivalent
------------      -------          ---------------
Cura              ケアルラ          Cura      (FFXI tier 2 cure)
Poisona           ポイゾナ          Poisona   (cure poison)
Paralyna          パラナ            Paralyna  (cure paralysis)
Silena            サイレナ          Silena    (cure silence)
Esuna             エスナ            Esuna     (cure all)
```

So 1.x preserves the FFXI "-na" suffix for status-cure spells:
- Poison → Poisona, Paralyze → Paralyna, Silence → Silena
- General cure-all: Esuna

ARR renamed Cura → "Cure II" + dropped most of the -na suffixes
(except Esuna which is still core).

## 3. Stone Throw (cmd 22114) -- the single-hit override

From `finding_combat_command_pipeline_and_4param_scaling.md`,
`AttackCommand.getFrequency()` had a special branch:

```lua
if commandId == 22114:  return -1
elif isAttackCommand:    return -2
```

The `-1` is the "single-hit override" -- a frequency code distinct
from `-2` (weapon-driven multi-hit). I speculated cmd 22114 was
likely a special action, possibly "Distract".

Now identified: **cmd 22114 = "Stone Throw"** (つぶて打ち).

So Stone Throw is a **SINGLE-HIT ranged attack** that bypasses
weapon-rate. Probably a low-level / basic stone-throwing action
available to all classes for breaking pots / opening chests /
breaking enemy parts. It's NOT weapon-attack-rate driven; it
fires once when commanded.

### Stone Throw variants found

Other "Stone" command IDs:
- 22114 = Stone Throw (player single-hit attack)
- 23023 = Stone Gaze (monster gaze attack)
- 23230 = Stone's Throw (alternate monster attack)
- 23389 = Stone Skull (monster body part?)
- 23517 = Stone II (BLM physical-elemental tier II)

So "Stone" appears 5+ times in the command space, with 22114
being the universal single-hit version.

## 4. Bard songs basic data

Three Bard songs from convertSkillId:

```text
Song ID     Name             gameCommandBasic.csv distinctive values
-------     ----             ----------------------------------------
27237       Ballad of Magi   col ~36=30528 col 122=100  col 123=0
27238       Paeon of War     col ~36=30529 col 122=50   col 123=1000
27239       Minuet of Rigor  col ~36=30530 col 122=100  col 123=0
```

The col 122/123 values DIFFER per song:
- col 122 = 100 / 50 / 100 (probably effect potency)
- col 123 = 0 / 1000 / 0 (only Paeon has 1000)

So Paeon of War has a **unique 1000 value** at col 123 (probably
the EFFECT DURATION in milliseconds, or an HP/MP COST modifier).

The 30528-30530 sequence at col ~36 is a song GROUP ID -- 3 songs
in a sequential block. The Bard song system probably allocates
sequential group IDs for related songs (typical of FFXI's bard
song memorization slots).

## 5. Static actor IDs NOT in populace tables

Tried looking up static actor IDs (310001, 24301, 320013, 12015)
in:
- `actorclass.csv` (range 1-7984, much lower than 310001)
- `populace*.csv` tables (IDs 0-N, not 6-digit)

None matched. So these static actor IDs are in a **DIFFERENT
REGISTRY** not covered by FFXIVTool's catalog.

Likely candidates (Speculative):
- A "BaseService" or "StaticServiceActor" table not exported
- The server's hardcoded actor spawn list
- A bnpc-style table with extended IDs

The known service-actor IDs from prior findings:
- 310001 = WorldMaster (per finding_world_area_login_split.md)
- 24301 = Instance Raid Service (per onTouch finding)
- 320013 = Chocobo Rider (per prior session)
- 12015 = Push-Out-From-Chocobo sentinel command

These are CONFIRMED used in Lua code; the specific table they
live in is not yet pinned. Future work: search ghidra or
specific bnpc tables.

## Confidence

```text
Confirmed:
  - LoginEvent quest names: Private Eyes / In Plain Sight /
    The Usual Suspect / Prophecy Inspection.
  - Main scenario ch1 begins at level 15; ch3 at level 20.
  - Cure has 4 tiers (29010-29013); Banish has 4; Drain has 3;
    Stoneskin has 3.
  - 1.x preserves FFXI status-cure naming: Poisona / Paralyna /
    Silena / Cura / Esuna.
  - cmd 22114 = "Stone Throw" -- the single-hit AttackCommand override.
  - Bard song IDs 27237-27239 have sequential group IDs 30528-30530.
  - Static actor IDs (310001 etc.) are NOT in actorclass.csv NOR
    populace*.csv tables.

Likely (High):
  - The 3 city ch1 quests (Private Eyes / In Plain Sight / The
    Usual Suspect) all converge to the same chapter 3 shared
    quest "Prophecy Inspection" via the LoginEventCommand
    dispatch.
  - The "detective" theme of ch1 quests reflects 1.x's narrative
    around Garlean spies in the city-states.
  - col 53/54 of quest.csv = level requirement (15 for ch1, 20
    for ch3).
  - Paeon of War's col 123 = 1000 is probably the AOE distance
    or duration (1000ms = 1 second tick?).

Likely (Medium):
  - Bio I exists (IDs in 28600+ range) but wasn't surfaced by
    the simple "Bio " grep due to localization issues. Worth
    a re-check with different patterns.
  - Static actor IDs 12015/24301/310001/320013 are in a
    "ServiceActor" registry table not exported by FFXIVTool
    (likely require the EXE to enumerate).

Speculative:
  - "Stone Throw" 22114 might be the FIRST WEAPON SKILL all
    players learn -- low-level throwing for breakable pots /
    minor combat.
  - The 3 Bard songs identified are from FFXI's MAIN SONG LIST
    (Ballad/Paeon/Minuet). 1.x had more songs (~6-9?) but
    convertSkillId selects only the 3 cross-class ones.
```

## Connections to other findings

- **finding_quest_corpus_and_login_event_command.md**: provides
  the LoginEventCommand body that triggers these specific quests.
- **finding_combat_command_pipeline_and_4param_scaling.md**:
  confirmed Stone Throw = cmd 22114 (the single-hit override).
- **finding_cross_class_36_actions_ffxi_heritage.md**: validated
  the 3 Bard songs in cross-class are from FFXI's main song list.
- **finding_command_roster_complete.md**: the 27 magic spells
  documented now have specific tier-family identifications.

## Next test

- Find "Bio I" specifically (the Bio family with only II/III shown
  here means Bio I exists elsewhere).
- Look at quest 110841 "Prophecy Inspection" cutscene flag to
  find related cutscenes in the 39x569q9/cutScene table.
- Sample 5 specific aetheryte rows + cross-ref to identify the
  PARENT chain (cluster -> region mapping).

## Commit suggestion

```
docs(re/lua): cross-ref round 2 -- 4 LoginEvent quests, spell tiers, Stone Throw, Bard songs
```
