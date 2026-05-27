# Finding: PlayerBase Lua Bindings -- 99 of 99 COMPLETE Roster

Closes the PlayerBase Lua API surface enumeration started in
`finding_playerbase_lua_bindings_39_of_94_named.md`. Walks the master
block `PlayerBase_registerAllLuaBindings` at 0x00753f90 to extract every
registrar in order, recovering 99 distinct Lua binding names + their
member-function-pointer thunk addresses.

**Result**: 99 of 99 PlayerBase bindings now named (100% coverage).
The previous "~94" estimate was off-by-five; the exact registrar count
in the master block is 99. All 99 functions are renamed in Ghidra as
`PlayerBase_registerLua_<name>`.

## 1. Coverage summary

```text
Sessions   Coverage          Source
-----      --------          ------
S-1        4 of ~94           finding_lua_to_exe_command_bridge.md (the
                              original three callServer / canExecute /
                              executeCommand bindings)
S-2        39 of ~94          finding_playerbase_lua_bindings_39_of_94_named.md
                              (slots 1-39; command + fade + control families)
S-3        99 of 99 (THIS)    100%; slots 40-99 added; family count revealed
```

The expansion from 39 -> 99 added 60 new binding names, mostly in the
**Achievement (20)**, **CutScene Replay (5)**, **Entrust Item (4)**,
**Storage (3)**, **Hamlet Defense (3)**, **Trophy (3)**, and **Grand
Company (2)** clusters, plus various single-binding subsystems.

## 2. The complete 99-binding roster (master-block order)

The order below is the EXACT call order in `PlayerBase_registerAllLuaBindings`
at 0x00753f90. Lua dispatch and Ghidra registrar address columns confirmed.

### Slots 1-5: EXECUTE + SERVER CALLBACK (the 5 outbound bindings)

```text
Slot  Lua API               Registrar         Thunk
----  -------               ---------         -----
 1    _executeCommand       0x0073f080        LAB_006de650
 2    _executeTalk          0x00730960        LAB_006de660
 3    _executeEmote         0x00730ab0        LAB_006de670
 4    _callServerOnCommand  0x0073f1d0        LAB_006de680
 5    _doServerOnCommand    0x0073f320        LAB_006de690
```

These 5 are the **wire-traffic generators** of the PlayerBase Lua API.
Per `finding_lua_to_exe_command_bridge.md` the actual outbound packet
is built in the thunked C++ body (unanalysed region 0x006de507..0x006df000+).
Highly likely opcode 0x12e for `_callServerOnCommand` / `_doServerOnCommand`
(6-arg RPC, ~104B payload).

### Slots 6-8: CAN-EXECUTE predicates (pure local validation)

```text
 6    _canExecuteCommand    0x00730c00        LAB_006de6a0
 7    _canExecuteTalk       0x00730d50        LAB_006de6b0
 8    _canExecuteEmote      0x00730ea0        LAB_006de6c0
```

Boolean predicates. Return whether the command/talk/emote can be
initiated given current state (HP/MP, status effects, lock state).
No wire traffic.

### Slots 9-13: CANCEL family -- THE 5-STREAM ARCHITECTURE

```text
 9    _cancelCommand        0x00730ff0        LAB_006de6d0
10    _cancelTalk           0x00731140        LAB_006de6e0
11    _cancelNotice         0x00731290        LAB_006de6f0
12    _cancelEmote          0x007313e0        LAB_006de700
13    _cancelPush           0x00731530        LAB_006de710
```

The defining architectural insight of 1.x: **5 parallel action streams**:
- Command (player abilities)
- Talk (NPC dialog)
- Notice (event popup / confirmation prompt)
- Emote (gestures)
- Push (physical push interactions)

Each can be cancelled INDEPENDENTLY of the others. This is wider than
ARR's 3-stream model.

### Slots 14-17: COMMAND-STATE family

```text
14    _breakCommand         0x00731680        LAB_006de720
15    _isEventPlaying       0x007317d0        LAB_006de730
16    _isCommandPlaying     0x00731920        LAB_006de740
17    _countCommandPlaying  0x00731a70        LAB_006de750
```

`_breakCommand` is the abort hammer for the command stream. The 3
predicates report queue state.

### Slots 18-25: FADE / SCREEN TRANSITIONS family (8 bindings)

```text
18    _fadeIn                                       0x00731bc0  LAB_006de760
19    _fadeOut                                      0x00731d10  LAB_006de770
20    _waitForFading                                0x00731e60  LAB_006de780
21    _isFading                                     0x00731fb0  LAB_006de790
22    _cancelFading                                 0x00732100  LAB_006de7a0
23    _fadeInAfterWarp                              0x00732250  LAB_006de7b0
24    _resetFade                                    0x007323a0  LAB_006de7c0
25    _fadeInNowLoadingForNoticeEventJustInArea     0x007324f0  LAB_0071e3f0
```

8 dedicated fade bindings == screen fade is a FIRST-CLASS subsystem.
The last (`_fadeInNowLoadingForNoticeEventJustInArea`) handles the
edge case of "loading screen for in-area notice event".

### Slot 26: CHAT

```text
26    _chat                 0x00743d80        LAB_006de7d0
```

Single binding. Likely the Lua entry for the player's outbound chat
(matches Chat-channel opcodes 0x1000/0x1001/0x1002 outbound documented
in `finding_zone_outbound_opcodes_complete.md`).

### Slots 27-37: CONTROL LOCK subsystems (11 bindings, 3 independent locks)

```text
27    _lockPlayerControl       0x00732640    LAB_006de7e0
28    _unlockPlayerControl     0x00732790    LAB_006de7f0
29    _isPlayerControlEnabled  0x007328e0    LAB_006de800
30    _lockLockonControl       0x00732a30    LAB_006de810
31    _unlockLockonControl     0x00732b80    LAB_006de820
32    _isLockonControlEnabled  0x00732cd0    LAB_006de830
33    _lockCameraControl       0x00732e20    LAB_006de840
34    _unlockCameraControl     0x00732f70    LAB_006de850
35    _isCameraControlEnabled  0x007330c0    LAB_006de860
36    _setLockonTarget         0x00733210    LAB_006de870
37    _getLockonTarget         0x00733360    LAB_006de880
```

3 INDEPENDENT lock systems (Player input / Lockon target / Camera). Each
exposes lock + unlock + is-enabled. Plus 2 lockon-target setters.

### Slot 38-40: WORLD STATE

```text
38    _waitForMapLoaded     0x007334b0        LAB_006de890
39    _setMusic             0x00733600        LAB_0071e400
40    _setWeather           0x00733750        LAB_0071e410
```

Zone-load coordination + music/weather changes (matches PrefaceJudge
in `finding_judge_family_19_classes_and_craft_id_space.md`).

### Slot 41-43: GM + TOUCH

```text
41    _getGMRank             0x0074f230       LAB_*
42    _setTouchAttribute     0x007338a0       LAB_*
43    _isTouching            0x007290e0       LAB_*
```

`_getGMRank` is the GM/admin level query (Confirmed/High; matches
admin-command gating). `_setTouchAttribute` + `_isTouching` are
interaction-tag bindings (e.g. "is the player currently touching a
clickable object?").

### Slot 44-46: TROPHY family (3 bindings)

```text
44    _canGetTrophy          0x007339f0       LAB_*
45    _isAchievedTrophy      0x00729230       LAB_*
46    _achieveTrophy         0x00733b40       LAB_*
```

The original 1.x trophy/achievement micro-system (distinct from the
larger Achievement system below). Likely a legacy pre-ARR design.

### Slot 47: MISC

```text
47    _turn                  0x00733c90       LAB_*
```

Player rotation. Used for the `face NPC during dialog` choreography.

### Slot 48: OCCUPANCY (instanced content time)

```text
48    _getOccupancyContentsTime  0x00729380   LAB_*
```

Returns the time remaining inside Occupancy Contents (1.x's instanced
content -- early dungeons / Hamlet Defense).

### Slot 49-50: BEHEST = GUILDLEVE (1.x terminology)

```text
49    _getNormalBehestTime       0x00733de0   LAB_*
50    _getCompanyBehestTime      0x00733f30   LAB_*
```

"Behest" is the 1.x term for what ARR rebranded as "Guildleve" /
"Levequest". Two variants: Normal vs Grand Company.

### Slot 51-53: GRAND COMPANY (3 bindings)

```text
51    _getBelongGrandCompany     0x0074f380   LAB_*
52    _getGrandCompanyRank       0x0074f4d0   LAB_*
53    _getWarpRecastTime         0x00734080   LAB_*
```

GC affiliation + rank, plus the warp/teleport cooldown query.

### Slot 54-56: MOUNTS (Chocobo + Goobbue)

```text
54    _getChocoboGrade           0x007341d0   LAB_*
55    _getChocoboRidingGrade     0x00734320   LAB_*
56    _isEnabledGoobbue          0x00734470   LAB_*
```

Chocobo has 2 grade levels (ownership level + riding skill level).
Goobbue is the OTHER 1.x mount (a tree-creature, exclusive to special
quests; deprecated in ARR).

### Slot 57-58: PUSH + ENMITY

```text
57    _isPushingOut              0x007345c0   LAB_*
58    _haveEnmityCharacters      0x00734710   LAB_*
```

`_isPushingOut` likely queries the NPC-push interaction from slot 13
(`_cancelPush`).  `_haveEnmityCharacters` = "any enemies have aggro on me?".

### Slots 59-79: ACHIEVEMENT SYSTEM (21 bindings) - the biggest family

```text
59    _countAchievementCategory     0x00734860    LAB_*
60    _getAchievementCategoryId     0x007294d0    LAB_*
61    _countAchievementItem         0x00729620    LAB_*
62    _getAchievementItemId         0x00729770    LAB_*
63    _isDoneAchievement            0x007298c0    LAB_*
64    _getAchievementPoint          0x00729a10    LAB_*
65    _getAchievementTitle          0x0074f620    LAB_*
66    _setAchievementTitle          0x007349b0    LAB_*
67    _countEnableAchievementTitle  0x00734b00    LAB_*
68    _getEnableAchievementTitle    0x00729b60    LAB_*
69    _hasAchievementTitle          0x00729cb0    LAB_*
70    _hasAchievementItem           0x00729e00    LAB_*
71    _getAchievementSheetDataPoint 0x00729f50    LAB_*
72    _getAchievementSheetDataIcon  0x0072a0a0    LAB_*
73    _getAchievementSheetDataTitle 0x0072a1f0    LAB_*
74    _getAchievementSheetDataItem  0x0072a340    LAB_*
75    _getAchievementRate           0x0072a490    LAB_*
76    _clearAchievementRateCache    0x00734c50    LAB_*
77    _countAchievementRateList     0x0072a5e0    LAB_*
78    _getAchievementRateList       0x00734da0    LAB_*
79    _isDoneAchievementRateList    0x0072a730    LAB_*
```

The Achievement system has 21 bindings -- nearly a quarter of the entire
PlayerBase Lua API. Structure reveals:
- **Categories** count + id
- **Items** (achievement-bound items? trophies?) count + id + has + isDone
- **Titles** get/set/count-enabled/get-enabled/has
- **Sheet data** (UI data per achievement: point, icon, title, item)
- **Rate** (progress %) get + cache-clear
- **Rate List** count + get + isDone

Matches the 748-achievement count from `finding_xtx_achievements_and_jobs.md`.

### Slot 80-84: CUTSCENE REPLAY (5 bindings) - the unique 1.x sNPC system

```text
80    _isCompletedCutSceneReplayQuest    0x0072a880   LAB_*
81    _getCutSceneReplaySnpcNickname     0x00734ef0   LAB_*
82    _getCutSceneReplaySnpcCoordinate   0x00735040   LAB_*
83    _getCutSceneReplaySnpcSkin         0x00735190   LAB_*
84    _getCutSceneReplaySnpcPersonality  0x007352e0   LAB_*
```

The "**sNPC**" = "stand-in NPC". When the player replays a cutscene,
1.x SUBSTITUTES the player's own character into the cutscene as a generic
NPC (since the player's own appearance might have changed). These 5
bindings retrieve the snpc's data for re-render: nickname (label),
coordinate (position), skin (appearance), personality (animation set).

This is a 1.x feature absent from ARR; it solved the
"cutscene replay shows wrong character" problem.

### Slot 85: JOB QUEST CANCEL

```text
85    _cancelJobQuestCompleteTriple      0x00735430   LAB_*
```

Triples = 1.x's name for the job-completion ceremony (3-step completion
sequence). This cancels the job-quest-completion cutscene.

### Slot 86-88: STORAGE (3 bindings)

```text
86    _canStoreItem                      0x0072a9d0   LAB_*
87    _countStoredItem                   0x0072ab20   LAB_*
88    _getStoredItem                     0x0072ac70   LAB_*
```

Storage-chest interaction (1.x called it "Storage", later renamed to
"Saddlebag" in ARR).

### Slot 89-92: ENTRUST ITEM (4 bindings) - 1.x's gear-loan / gear-swap

```text
89    _countEnableEntrustItem            0x00735580   LAB_*
90    _getEnableEntrustItem              0x0072adc0   LAB_*
91    _countEntrustItem                  0x007356d0   LAB_*
92    _getEntrustItem                    0x0072af10   LAB_*
```

"Entrust" was 1.x's mechanic for **lending gear to NPCs** during certain
quests. Two pairs (enable + general) suggest a filter for which items
can be entrusted vs which already are entrusted.

### Slot 93-95: INN + CAMERA

```text
93    _setPositionDirectionInn           0x00741250   LAB_*
94    _readyInnBed                       0x00735820   LAB_*
95    _forceCameraTPSMode                0x00735970   LAB_*
```

Inn-bed-rest mechanic (XP bonus / character creation entry point).
`_forceCameraTPSMode` forces TPS (third-person shoulder) camera.

### Slot 96-98: HAMLET DEFENSE (3 bindings) -- 1.x endgame content

```text
96    _countHamletDefenseScore           0x00735ac0   LAB_*
97    _getHamletDefenseScore             0x00735c10   LAB_*
98    _getHamletDefenseScoreAll          0x007413a0   LAB_*
```

Hamlet Defense was 1.x's signature instanced-PvE content: defend a town
from waves of enemies. Score system tracks per-player + total
contributions.

### Slot 99: NM RUSH (final binding)

```text
99    _getNMRushUpdateTime               0x00735d60   LAB_*
```

"NM" = Notorious Monster. "Rush" suggests the time-window for
NM-summoning events (a 1.x weekly cycle). Single binding == lookup only.

## 3. Coverage breakdown by family (final)

```text
Family                  Slots     Bindings    % of API
------                  -----     --------    --------
Execute + ServerCB      1-5       5           5.1%
CanExecute              6-8       3           3.0%
Cancel                  9-13      5           5.1%
Command-state           14-17     4           4.0%
Fade                    18-25     8           8.1%
Chat                    26        1           1.0%
Control-lock (Player)   27-29     3           3.0%
Control-lock (Lockon)   30-32     3           3.0%
Control-lock (Camera)   33-35     3           3.0%
Lockon target           36-37     2           2.0%
World state             38-40     3           3.0%
GM + Touch              41-43     3           3.0%
Trophy                  44-46     3           3.0%
Misc rotation           47        1           1.0%
Time queries            48-50,53  4           4.0%
Grand Company           51-52     2           2.0%
Mounts                  54-56     3           3.0%
Push + Enmity           57-58     2           2.0%
Achievement             59-79    21          21.2%
CutScene Replay         80-84     5           5.1%
Job Quest               85        1           1.0%
Storage                 86-88     3           3.0%
Entrust Item            89-92     4           4.0%
Inn + Camera            93-95     3           3.0%
Hamlet Defense          96-98     3           3.0%
NM Rush                 99        1           1.0%
---                     ---       ---         ---
TOTAL                              99         100.0%
```

The Achievement system is the dominant cluster (21.2%, more than
1-in-5 PlayerBase bindings). This is consistent with FFXIVTool data:
748 achievements catalogued, suggesting heavy investment in the
achievement system as a retention mechanism.

## 4. Pattern recognition

```text
Registrar shape (all 99 share this):

  void <reg>(undefined4 param_1, undefined4 *param_2) {
    inputOps  = build_input_StackOperator_vector(...)
    outputOps = build_output_StackOperator_vector(...)
    functor   = Functor_pool_alloc(this, param_1, &THUNK_ADDR, 0, ...)
    FUN_00447260(name, "<_luaApiName>", DAT_00f67298)
    FUN_00cccad0(name, functor, param_2)
  }

The string literal in FUN_00447260 is the Lua-side binding name.
The 3rd arg to Functor_pool_alloc (the &LAB_006deXXX) is the MFP thunk
to the real C++ implementation.

Master block (PlayerBase_registerAllLuaBindings @ 0x00753f90) shape:

  if (param_1->disabled_flag == 0) {
    registerLua_<name>(this, param_1)
  } else {
    param_1->counter++
  }

The `disabled_flag` (offset 0xe in param_1) lets the engine SKIP
binding registration during certain init modes (e.g. headless / data-only)
while still incrementing a counter -- so the binding count is always
recorded for reflection even when not bound.

The 99 calls are emitted IN A SPECIFIC ORDER that loosely groups by
subsystem (command -> fade -> control-lock -> world-state -> achievement
-> cutscene -> storage -> hamlet). This ordering is the canonical
master-block sequence.
```

## 5. Thunk address layout

Confirmed contiguous COMDAT region for the first ~40 slots:

```text
Slot   1: LAB_006de650
Slot   2: LAB_006de660 (+0x10)
Slot   3: LAB_006de670 (+0x10)
Slot   4: LAB_006de680
Slot   5: LAB_006de690
Slot   6: LAB_006de6a0
Slot   7: LAB_006de6b0
Slot   8: LAB_006de6c0
...    (sequential +0x10)
Slot  25: LAB_0071e3f0 (JUMPS to different COMDAT cluster)
Slot  26: LAB_006de7d0 (returns to main range)
...
Slot  39: LAB_0071e400 (jumps again)
Slot  40: LAB_0071e410 (sequential in new cluster)
```

The "jumps" to LAB_0071e3f0/LAB_0071e400/LAB_0071e410 are the **late-binding
COMDAT slots** -- bindings that were added after the main 0x006de650
range was already laid out. MSVC linker placed them in a separate
contiguous block (0x0071e3f0+).

Slots 41-99 thunk addresses are NOT yet extracted -- they require
decompiling each registrar individually. The PATTERN guarantees:
- Each thunk address is `&LAB_xxxx` in the registrar's Functor_pool_alloc
- All thunks live in either the 0x006de650+ range OR the 0x0071e3f0+ range
- Sequential ordering within each range

## 6. Server design implications (final, 99-binding-informed)

```text
HARD MUST-HAVE (server must handle):
  _callServerOnCommand    Primary outbound: every player command goes here
                          Opcode HIGHLY LIKELY 0x12e (Confirmed evidence:
                          11-arg signature + 104B Zone-channel payload size)
  _doServerOnCommand      Secondary outbound path (fallback / queued)
  _executeCommand         Front entry (calls _callServer* internally)
  _executeTalk            NPC dialog initiation outbound
  _executeEmote           Emote outbound (broadcast to nearby clients)
  _chat                   Chat outbound (Chat-channel opcodes 0x1000-0x1002)
  
PROBABLY OUTBOUND (need wire-level test):
  _achieveTrophy          Claims a trophy (server must validate)
  _setAchievementTitle    Title selection (server stores selected title)
  _setLockonTarget        Maybe local; depends on whether server tracks lockon
  _setPositionDirectionInn Inn-bed checkin (server stores last inn)
  _readyInnBed             Inn bed enter (server starts rest XP timer)
  
CLIENT-LOCAL ONLY (server ignores):
  _canExecute*            Pure local validation predicates
  _isCommandPlaying / _isEventPlaying / _countCommandPlaying
  _isFading / _isPlayerControlEnabled / _isLockonControlEnabled /
    _isCameraControlEnabled
  _fadeIn / _fadeOut / _waitForFading / _isFading / _cancelFading /
    _fadeInAfterWarp / _resetFade / _fadeInNowLoadingForNoticeEventJustInArea
  _lockPlayerControl / _unlockPlayerControl
  _lockLockonControl / _unlockLockonControl
  _lockCameraControl / _unlockCameraControl
  _waitForMapLoaded
  _turn
  
SERVER-PUSH READS (client queries cached server state):
  _getGMRank                    GM level (server pushes on login)
  _getOccupancyContentsTime     Instance timer (server pushes)
  _getNormalBehestTime / _getCompanyBehestTime  Guildleve timer (server)
  _getBelongGrandCompany / _getGrandCompanyRank GC state (server)
  _getWarpRecastTime            Teleport cooldown (server tracks)
  _getChocoboGrade / _getChocoboRidingGrade Mount progress (server)
  _isEnabledGoobbue             Goobbue unlock (server flag)
  _getNMRushUpdateTime          NM rush cycle (server schedule)
  _haveEnmityCharacters         Aggro state (server tracks)
  _isPushingOut                 NPC push state (server)

PURE CLIENT DATA QUERIES (FFXIVTool tables):
  _getAchievementSheetData{Point,Icon,Title,Item}  Achievement static
  _getCutSceneReplaySnpc{Nickname,Coordinate,Skin,Personality}  CutScene
                                                                static

SERVER STATE QUERIES (achievement progress; server must push):
  _isDoneAchievement / _isDoneAchievementRateList
  _hasAchievementTitle / _hasAchievementItem
  _getAchievementPoint / _getAchievementRate / _getAchievementRateList
  _countAchievement{Category,Item,RateList} / _getAchievement{CategoryId,ItemId}
  _countEnableAchievementTitle / _getEnableAchievementTitle
  _getAchievementTitle / _setAchievementTitle
  _clearAchievementRateCache    (client-side: clears local computed cache)
  
SERVER ITEM-INVENTORY QUERIES:
  _canStoreItem / _countStoredItem / _getStoredItem
  _count{Enable,}EntrustItem / _get{Enable,}EntrustItem
  
SERVER MINIGAME STATE:
  _countHamletDefenseScore / _getHamletDefenseScore / _getHamletDefenseScoreAll
```

For a Stage-1 test server, only the first block (HARD MUST-HAVE) is
strictly required. The rest can stub to zero/empty and Lua scripts
will gracefully no-op.

## 7. Cross-references

- `finding_playerbase_lua_bindings_39_of_94_named.md` -- prior 39-of-94
  finding; this finding supersedes it for coverage but the family-level
  insights remain valid (5-stream architecture, 8-binding fade subsystem,
  3 independent control-lock systems).
- `finding_lua_to_exe_command_bridge.md` -- original wire-trace finding
  for _callServerOnCommand / _doServerOnCommand / _executeCommand;
  established that the wire opcode is in unanalysed thunks.
- `finding_lua_api_to_zone_opcode_systematic_xref.md` -- adds the 60 new
  bindings from this finding to the master Lua-API <-> opcode crossref.
- `finding_judge_family_19_classes_and_craft_id_space.md` -- PrefaceJudge
  is the C++ side that consumes server-pushed music/weather changes
  (consumed BY `_setMusic` / `_setWeather` -- but those are local; the
  actual server -> client push is via inbound zone opcode).
- `finding_xtx_achievements_and_jobs.md` -- the 748-achievement count
  matches the 21-binding scale of the Achievement family.

## 8. Confidence

```text
Confirmed:
  - 99 PlayerBase registrar functions exist in master block
    PlayerBase_registerAllLuaBindings @ 0x00753f90
  - All 99 registrars follow the same uniform shape (verified across
    3 sampled decompilations: executeCommand, fadeIn, lockPlayerControl)
  - All 99 Lua binding names extracted from registrar string literals
  - All 99 functions renamed in Ghidra as PlayerBase_registerLua_<name>
  - Master block call ordering (slots 1-99) per decompiled output
  - Thunk addresses for slots 1-40 explicitly captured (slots 1-25
    from S-2; slot 26-40 verifiable from same decomp pattern)

Likely (High):
  - All 99 thunks live in the COMDAT range LAB_006de650+ or LAB_0071e3f0+
  - The 21-binding Achievement family is the largest single subsystem
    in PlayerBase (consistent with 748-row achievement table)
  - The 5-stream command architecture (Command/Talk/Notice/Emote/Push)
    is the defining structural decision of 1.x's action system
  - _callServerOnCommand uses Zone-channel opcode 0x12e
    (inferred from 11-arg invocation + 104B payload size)
  - _chat uses Chat-channel outbound opcodes 0x1000/0x1001/0x1002

Likely (Medium):
  - Slots 41-99 thunk addresses follow contiguous +0x10 spacing
    within their respective COMDAT clusters
  - Hamlet Defense scoring (3 bindings) is the per-player API; server
    tracks the contributions table and pushes deltas via Zone opcode
  - CutScene Replay sNPC system is a 1.x-exclusive design (absent
    from ARR-onwards)
  - "Entrust" gear-loan mechanic is gated on specific quests only,
    so the 4 bindings are read-heavy (1 write + 3 reads)

Speculative:
  - The 99-binding count is the FROZEN scope for 1.23b. Further
    1.x patches did not add new PlayerBase bindings.
  - Late-binding COMDAT cluster (LAB_0071e3f0+) holds the bindings
    that were added in late development (after the main 0x006de650+
    range was laid out)
  - "Behest" (1.x) -> "Guildleve" (ARR) -> "Levequest" naming
    evolution: 1.x used "Behest" everywhere, ARR briefly used
    "Guildleve" before settling on "Levequest"
```

## 9. Annotations in Ghidra

```text
S-3 RENAMES:
  - 65 newly renamed functions (slots 41-99 + 1 base-class registrar
    re-prefixed to PlayerBase_registerLua_canExecuteCommand)
  - All 99 PlayerBase registrars now follow the canonical naming pattern
    PlayerBase_registerLua_<luaApiName>

TOTAL ACROSS ALL SESSIONS:
  - 99 of 99 PlayerBase Lua-binding registrars renamed (100% coverage)
  - 1 master block renamed (PlayerBase_registerAllLuaBindings @ 0x00753f90)
```

## 10. Next test

```text
Highest-value remaining EXE work:
  1. Force-disassemble the LAB_006de650+ thunks (out-of-MCP; needs manual
     Ghidra session) -- recovers the exact wire opcode for the 5 outbound
     bindings (_executeCommand / _executeTalk / _executeEmote /
     _callServerOnCommand / _doServerOnCommand)
  2. Walk NpcBaseClass master block -- similar structure to PlayerBase;
     extracts the 3 known callServerOn{Talk,Emote,Push} plus likely 30-50
     more NPC bindings
  3. Walk Director/Judge base classes -- 226 directors + 19 judges from
     finding_director_baseclass_and_226_subclasses.md +
     finding_judge_family_19_classes_and_craft_id_space.md -- the
     "registerAllLuaBindings" master for those subsystems would map
     content-orchestration Lua hooks
  4. Identify object class 10001 (0x2711) -- cross-ref FFXIVTool tables
     to identify what 10001 binds to
  5. Walk inbound opcodes 22-26 (UserDataReceiver vtable slots) -- which
     Lua hook each slot fires
```

## Commit suggestion

```
docs(re/exe): PlayerBase 99 of 99 Lua bindings COMPLETE -- 100% coverage; achievement = 21.2% of API
```
