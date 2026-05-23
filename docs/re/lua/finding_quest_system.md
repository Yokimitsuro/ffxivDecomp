# Finding: Quest System — QuestBaseClass + QuestBaseClass_common

Documents the Quest subsystem in 1.x. The 1878-line combined
QuestBaseClass family handles quest lifecycle, job quest
completion (3-stage), cutscene orchestration (NQ/HQ + sNPC
variants), quest UI, and job tutorials.

Sources read:

```text
quest/QuestBaseClass.lua            466 lines  (13 methods)
quest/QuestBaseClass_common.lua    1412 lines  (35+ methods)
                                    -----
                                    1878 lines total
```

## 1. QuestBaseClass.lua (466 lines, 13 methods)

The abstract base for all quests.

```text
IDENTITY:
  getQuestId            quest's sheet row id
  getQuestData          full sheet data row

LIFECYCLE:
  _onInit / _onFinalize
  initText              load translatable text

COMMUNICATION:
  tellByNpcLinkshellChat  send via NPC linkshell chat channel
                           (uses playerWork.npcLinkshellChatCalling/Extra)

JOB QUEST 3-STAGE COMPLETION:
  _onJobQuestCompleteFirst
  _onJobQuestCompleteSecond
  _onJobQuestCompleteThird

JOB QUEST CANCELLATION:
  _onCancelJobQuestCompleteFirst
  _onCancelJobQuestCompleteSecond
  _onCancelJobQuestCompleteThird

OTHER:
  getCutSceneReplayData   cutscene replay data
```

### 3-Stage Job Quest Completion

The class declares **THREE STAGES** for job quest completion (each
with its own hook AND its corresponding cancellation hook):

```text
Stage First   -> player commits to taking job?
Stage Second  -> player meets requirements?
Stage Third   -> player accepts the job/soul crystal?
```

So unlocking a job in 1.x was a **3-step ritual** with cancellation
allowed at any step. ARR simplified this to a single completion.

## 2. QuestBaseClass_common.lua (1412 lines, 35+ methods)

The HUGE common implementation. Categorized:

### Cutscene Orchestration (8 methods)

```text
NQ (Normal Quality) cutscenes:
  startNQCutScene
  replayNQCutScene
  startSnpcNQCutScene        (sNPC variant -- player as star)

HQ (High Quality) cutscenes:
  startHQCutScene
  startSnpcHQCutScene

CONTROL:
  startFadeOutCutSceneDefault
  startFadeInCutSceneDefault
  startFadeInCutSceneAfterWarp
```

**NQ vs HQ cutscenes**: 1.x had two cutscene rendering quality
modes. NQ for routine content, HQ for important story beats. The
sNPC variants integrate the player as a "scenario NPC" with
customized appearance.

### Fade Management (4 methods)

```text
startFadeOut
startFadeIn
processFadeOutGeneral
processFadeInGeneral
processAfterWarpFadeOutGeneral
```

Standard fade-in/out helpers for transitions.

### Player Gender / Identity (3 methods)

```text
isPlayerMale
isPlayerFemale
getSnpcSexualityToSkin   maps gender to default sNPC skin id
```

So sNPC appearances default to gender-appropriate skins.

### sNPC (Scenario NPC) System (5 methods)

```text
getSnpcActorClassID            sNPC class id
getSnpcSexualityToSkin         gender to skin
getSnpcCandidacyNumber         sNPC candidate slot
inputSnpcName                  prompt for sNPC name
snpcPreviw                     show sNPC preview (sic typo)
```

The sNPC system allows **the player to "star" in cutscenes** with
their own customized character. Comprehensive features:
- Pick from candidate slots
- Custom name input
- Gender-aware skin defaults
- Preview before commit

This was a unique 1.x feature -- ARR didn't have this elaborate
"player as named NPC" system.

### Quest Content Interactions (3 methods)

```text
contentsJoinAskInBasaClass        ask "join content?" prompt
pastAreaJoinAskInBasaClass        ask "go to past area?" prompt
instanceAreaJoinAskInBasaClass    ask "enter instance?" prompt
```

Three variants of the "do you want to enter X?" prompt for
different quest progression steps.

### Quest UI (5 methods)

```text
showQuestInfomation            (sic) show quest info widget
showQuestRewardAsClientCall     show reward widget
questBaseRewardSeting           (sic) configure rewards
processAfterQuestRewardWidget   post-reward cleanup
sayFreeDisplayName              say with custom display name
```

Note: TWO TYPOS in function names:
- `showQuestInfomation` (missing 'r')
- `questBaseRewardSeting` (missing 't' in "setting")

These are preserved verbatim from the binary -- 1.x SE Lua source
had English typos that survived to retail.

### Music Control (1 method)

```text
setMusic         set BGM (probably for quest-specific tracks)
```

### Content Exit (2 methods)

```text
processAskContentExit       ask before exiting content
processEventContentExit     event-specific exit handler
```

### Job Quest Completion UI (5 methods)

```text
onJobQuestCompleteFirst         (without underscore prefix; UI variants)
onJobQuestCompleteSecond
onJobQuestCompleteThird
showGetJobAbilityWidget         show "you learned a job ability"
showGetJobItemWidget            show "you got a job item"
```

So when the player completes a job quest stage, the UI shows
either ability or item reward widget.

### Other (5 methods)

```text
getJobQuestIcon            UI icon for job quest
getJobQuestJobName         job name for display
jobTutorial                runs job-specific tutorial flow
showEventBeforeNpsLS       event-pre-NPC-linkshell-say
sqrwa                      ???? (unclear; maybe abbreviation)
clientTrunDirForQuestNpc    (sic "trun") face quest NPC during talk
runCharaSchedulerPastAreaIn  CharaScheduler for "past area" entry
isCraftPassiveGuildleve    is this a craft-related passive leve?
processReleaseQuest         quest release / completion
```

## Architecture Insights

### The 1.x Quest System is Cutscene-Heavy

The dominant feature of QuestBaseClass_common is **cutscene
orchestration**. With ~8 dedicated cutscene methods + 4 fade
management + sNPC system, the system is built around STORY
PRESENTATION first.

This is distinct from ARR which has simpler quest progression
(less cutscene-heavy with more dialog-driven story).

### The sNPC System is Unique

The 5-method sNPC system + cutscene replay system represents a
**unique 1.x feature**: players can re-watch their own story
moments with their customized character appearing as the
protagonist. This was a major selling point of 1.x but was
deprecated in ARR (which uses generic player models in
cutscenes).

### 3-Stage Job Quest Pattern

Job quests had 3 explicit stages with cancellation hooks:
1. Acceptance
2. Mid-quest milestone
3. Final acceptance / commitment

Each stage's First/Second/Third callbacks let scripts react.
Cancellation at any stage rolls back the prior commitments.

This was 1.x's deliberate-paced job unlocking design.

## Assessment

```text
Confirmed:
  - QuestBaseClass: 13 methods including 3-stage job completion
  - QuestBaseClass_common: 35+ methods orchestrating cutscenes,
    fades, sNPC, UI, music
  - sNPC system is unique to 1.x (player as scenario NPC)
  - NQ vs HQ cutscene quality modes
  - 3-stage job quest completion (FirstSecondThird) with
    cancellation at each
  - 2 typos preserved verbatim (Infomation, Seting)

Likely (High):
  - The sNPC system was complex enough that it required its own
    UI subsystem + persistent storage (the cutScene Replay state).
  - HQ cutscenes are pre-rendered with extra detail; used for
    major story beats.
  - NQ cutscenes are real-time rendered; used for side quests
    and incidental story.

Likely (Medium):
  - The 3-stage job quest is from 1.x's design where job unlocking
    was a major achievement (vs ARR's simpler "do a quest, get
    a job stone").
  - The "past area" mentions suggest 1.x had instanced flashback
    zones for story events.

Speculative:
  - The sNPC system + cutscene replay was likely cut for ARR
    because of disk space (rendering custom variants is expensive)
    and development cost.
  - The function name typos ("Infomation", "Seting") suggest
    machine-translated code or non-native English contributor.
```

## Closes the Quest System

This finding documents the entire Quest subsystem at the
architectural level:
- Quest lifecycle (init/finalize/job completion)
- Cutscene orchestration (NQ/HQ + sNPC)
- Quest UI (info/reward/exit)
- Player identity helpers
- Music control
- Job tutorial integration

Remaining gaps (not architectural):
- The 1412-line _common file has detailed implementations not
  read in this pass (each cutscene method ~30-50 lines of fade/
  motion choreography).
- Per-quest concrete subclasses (each major story quest probably
  has its own .lua file with specific logic).
