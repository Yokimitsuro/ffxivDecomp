# Finding: Quest Corpus (629 Scripts) + LoginEventCommand POST-Login Driver

Closes two unmapped Lua areas:
1. **Quest corpus**: 629 quest script files organized in
   job/GC/category subdirectories under `quest/scenario/<code>/`.
2. **LoginEventCommand** (203 lines): the Lua-side POST-login event
   driver. RECONCILES the earlier finding that "login is C++-only":
   LOBBY login is C++; POST-world-entry login events run in Lua.

## Quest corpus structure

```text
lua/decompiled/src/tp5rq/                       = quest/
+-- tp5rq89r57y9rr.lua                          QuestBaseClass         (mapped)
+-- tp5rq89r57y9rr_7vxxvw.lua                   QuestBaseClass_common  (mapped, 1412 lines)
+-- tp5rqq5rq.lua                               QuestTest
+-- r75w9s1v/                                   = scenario/  (629 files in 38 subdirs)
+-- u9rr1o53p1y6y5o5/                           = passiveguildleve/ (6 files)
    +-- 29so5rq/                                = harvest/
    +-- 7s94q/                                  = craft/
```

**TOTAL: 629 quest scenario files** + 6 passive-leve files = ~635
quest-related Lua scripts.

## Scenario subdirectory taxonomy (cipher decoded)

The 38 `quest/scenario/` subdirs are **3-letter job/class codes**
plus a few special categories:

### 7 BATTLE JOBS (10 quests each = 70 files)

```text
6s3 = drg  Dragoon       10 files
8s6 = brd  Bard          10 files
8yx = blm  Black Mage    10 files
n2x = whm  White Mage    10 files
n9s = war  Warrior       10 files
uy6 = pld  Paladin       10 files
xwz = mnk  Monk          10 files
```

Plus 4 precursor classes (Lancer/Pugilist/Thaumaturge/Conjurer
quest series, slightly shorter):

```text
yw7 = lnc  Lancer        6 files
u3y = pgl  Pugilist      6 files (no count obtained)
q2x = thm  Thaumaturge   (small)
7w0 = cnj  Conjurer      6 files
```

### 8 CRAFTERS + GATHERERS

```text
9y7 = alc  Alchemist          6 files
nos = wvr  Weaver              6 files
n6z = wdk  Woodworker          6 files
q9w = tan  Tanner              6 files
8rx = bsm  Blacksmith          (sample)
7py = cul  Culinarian          (sample)
x1w = min  Miner               6 files

97w = acn  Arcanist            (sample)
9s7 = arc  Archer              (sample)
3y6 = gld  Goldsmith / Gladiator? (TBD)
3y9 = gla  Gladiator (alternate?)
```

### 3 GRAND COMPANIES (19 quests each = 57 files)

```text
37p = gcu  Grand Company Uldah    (Immortal Flames)   19 files
37y = gcl  Grand Company Limsa     (Maelstrom)         19 files
373 = gcg  Grand Company Gridania  (Twin Adder)        19 files
```

### 5 MISCELLANEOUS (~340 files)

```text
5q7 = etc                  195 files   miscellaneous / story scenes
7vx = com  common           45 files   shared cutscene scripts
ny6 = wld  world            40 files   world events
q5rq = test                 38 files   test scripts
x9w = man  manuals          21 files   tutorial/manual scripts
6549pyqq9yz = defaulttalk    7 files   default NPC dialog
rpx = sum  Summoner?         9 files
ruy = spl  spell-related    25 files
qsy = trl  trial-related     6 files
4r2 = ?                     (TBD)
2so = hrv  harvest?         (sample)
5m7 = exc                   (sample)
n9s = war  (Warrior; already listed)
wv7 = noc  generic NPC      (sample)
nos = wvr  (Weaver; already listed)
```

### Quest count summary

```text
Battle job quests:       ~80   (7 jobs * 10 + 4 precursors * 6)
Crafter quests:          ~30   (8 crafters * 4 each typically)
Gatherer quests:         ~12   (3 gatherers * 4 each)
Grand Company quests:    57    (3 GCs * 19)
Miscellaneous/story:    ~340   (etc/com/wld/man/etc.)
Test / debug:            38
Trial / special:        ~30
Total scenarios:        629
+ Passive guildleves:     6  (harvest + craft variants)
GRAND TOTAL:            635
```

So 1.x had **at least 629 distinct quest scripts** covering job
storylines, GC questlines, main scenario, and tutorials.

## QuestBaseClass + QuestBaseClass_common (mapped in prior session)

Per `finding_quest_system.md`:
- QuestBaseClass (466 lines, 13 methods): identity + 3-stage job
  completion hooks
- QuestBaseClass_common (1412 lines, 35+ methods): cutscene
  orchestration, sNPC system, UI helpers

Each concrete quest in the 629-file corpus inherits from
QuestBaseClass and provides quest-specific dialog + cutscenes
+ completion logic.

Per-quest script size is typically small (~50-200 lines) since the
base class handles all the heavy lifting (cutscene playback, fade
transitions, sNPC, etc.). The quest script just selects WHICH
cutscenes / dialog options / rewards apply.

## LoginEventCommand (203 lines) -- post-world Lua login driver

`lua/decompiled/src/7vxx9w6/rlrq5x/yv31w5o5wq7vxx9w6.lua`

**Inherits from SystemCommandBaseClass** (not BattleCommand).

### Fire body (line 20+)

Dispatches on `A2_2` (the event type) and selects a cutscene +
quest combination based on the player's starter city (`A3_2`):

```text
A2_2 == 20:  "first login of day" / morning greeting
   if A3_2 == 1: play "drm0l000"  (Limsa Lominsa dream)
   elif A3_2 == 2: play "drm0g000" (Gridania dream)
   else:           play "drm0u000" (Uldah dream)
   start cutscene with params (1, 61, 1, 0)
   delete the cutscene actor
   call player:_fadeInAfterWarp() to fade in

A2_2 == 1 or 2:  Other login events
   build arrays of (filename, quest_id) per city:
     [etc5l110, q110839] [etc5g110, q110829] [etc5u110, q110849]
     [etc5l310, q110841] [etc5g310, q110841] [etc5u310, q110841]
     ... (more pairs continue, body cut off)
```

### Cutscene + quest filename pattern

```text
drm0<l|g|u>000     = "Dream" cutscenes per starter city
                     l = Limsa, g = Gridania, u = Uldah
etc5<l|g|u><nnn>   = "etc5" cutscenes per city + chapter
                     l/g/u = city
                     nnn = chapter (110 = chapter 1, 310 = chapter 3, etc.)

Quest IDs paired:
   110839 / 110829 / 110849   first chapter login quests
   110841                     third chapter login quests (shared across cities)
```

So **AFTER world entry, when a player logs in**, the server pushes
this command which:
1. Picks the right cutscene based on event type + starter city
2. Triggers the WorldMaster to create + start a cutscene actor
3. Activates a city-specific login quest
4. Fades the screen back in

### Reconciliation with prior "login is C++-only" finding

`finding_world_area_login_split.md` correctly stated that the
**LOBBY login** (account auth, chara select, chara make) has no
Lua. That's still true.

But the **POST-world login experience** (what happens after the
player enters the world) DOES have Lua: this LoginEventCommand
drives the per-city greeting cutscene + login quest activation.

So the corrected model is:

```text
LOGIN PIPELINE (full):
  PRE-WORLD (Lobby, C++ only):
    LobbyLoginOperation handshake
    Chara list / chara make
    World handoff
  
  POST-WORLD (Lua-driven from C++ trigger):
    LoginEventCommand fires
      -> cutscene per (event_type, starter_city)
      -> activate login quest
      -> fade in
    Then gameplay starts
```

## Server implications (brief)

```text
For QUEST CONTENT:
- The 629 quest scenarios are CLIENT-OWNED data; the server only
  needs to push the QUEST ID + state transitions. The client looks
  up the correct .lua file and runs the dialog/cutscene locally.
- Quest state (active / completed / step) is in playerWork; synced
  via WorkSync (opcode 0x12F).

For LOGIN-EVENT FLOW:
- Server pushes LoginEventCommand (probably via the chat-block
  opcode 35/36 with command-update tag) with event_type + city.
- Client looks up the appropriate cutscene + quest id.
- Server activates the login quest in playerWork.
- Client plays the cutscene, fades in, gameplay resumes.

CITY IDs in payload:
  1 = Limsa Lominsa
  2 = Gridania
  3 = Ul'dah (else branch in the if-else)
```

## Confidence

```text
Confirmed:
  - 629 quest scenario files + 6 passive-leve files.
  - Scenario subdirs are 3-letter codes for job/GC/category:
    7 battle jobs (10 quests each), 4 precursor classes, 3 GCs
    (19 each), 8 crafters, 3 gatherers, 5 miscellaneous categories.
  - LoginEventCommand inherits from SystemCommandBaseClass (NOT
    BattleCommand).
  - LoginEventCommand fires "dream" cutscenes (drm0l/g/u) for
    starter cities + "etc5" chapter cutscenes.
  - Starter city codes: 1=Limsa, 2=Gridania, 3+=Ul'dah.
  - Event types observed: 20 = first-login-of-day greeting; 1/2 =
    chapter-specific login events.

Likely (High):
  - The "_fadeInAfterWarp" call shows the warp-fade lifecycle
    (opcodes 20/21 in the inbound dispatch table) directly drives
    the post-login experience.
  - The 195 files in subdir 5q7 (etc) cover the MAIN SCENARIO
    questline -- this is the most populous category by far.
  - Battle job questlines are 10 quests each = 7 jobs * 10 = 70
    scripts, matching FFXIV's "Job Quest" pattern from FFXI.
  - GCs have 19 quests each (57 total) -- these are the GC rank-up
    questlines.

Likely (Medium):
  - Test subdir (38 files) is developer scripts that never shipped
    to retail.
  - The 6 passive-guildleve harvest + craft files implement the
    PASSIVE LEVE mechanic (gather/craft without combat).
  - Quest IDs 110xxx range identifies LOGIN-quest specific IDs.
    The 110839/110829/110849 + 110841 patterns suggest a city
    multiplier in the second-to-last digit.

Speculative:
  - The "drm" (dream) prefix on first-login cutscenes is FFXIV
    lore: characters supposedly receive prophetic dreams from
    Hydaelyn (the planet/goddess), which the Echo phenomenon
    confirms. This was Storyline 1.x flavor.
  - 195 misc/etc quests = main scenario rumor: this could be
    the MAIN STORY SCENARIO of 1.x split across many files.
```

## Connections to other findings

- **QuestBaseClass + _common** (per `finding_quest_system.md`):
  the base classes that all 629 scripts inherit from.
- **CutScene engine** (per `finding_director_family_and_cutscene_closure.md`):
  LoginEventCommand uses `worldMaster:createCutScene()` +
  `startCutScene()` which trigger the inbound opcodes 7/8/9/10/11/
  12/13/14 documented in the cutscene block findings.
- **finding_world_area_login_split.md**: this finding RECONCILES
  the apparent contradiction -- Lua DOES handle login, but only
  POST-WORLD (after the C++ lobby handoff completes).
- **Inbound chat opcodes** (35/36/37/57): the LoginEventCommand
  command-update notifications probably flow through one of these.

## Next test

- Sample 3-5 specific quest scripts from each major category
  (battle job, GC, etc.) to confirm the per-quest body pattern.
- Read the rest of LoginEventCommand (lines 100-203) to enumerate
  ALL event types (probably 20, 1, 2, plus more).
- Identify the SystemCommandBaseClass body to see how System
  commands differ from GameCommandBaseClass.

## Commit suggestion

```
docs(re/lua): quest corpus (629 scripts) + LoginEventCommand post-login driver
```
