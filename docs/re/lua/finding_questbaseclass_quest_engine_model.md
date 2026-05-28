# Finding: QuestBaseClass -- Quest Engine Model (Director-orchestrated content; accept/complete server-gated; rewards via event-mode widget)

**Maps the quest base mechanics** — QuestBaseClass + questbaseclass_common,
the shared engine for all 629 quest scripts. Quests are Director-style
content actors backed by quest.csv, whose accept/complete transitions
are server-gated (notices), with cutscene + reward UI running client-side.

QuestBaseClass (tp5rq89r57y9rr.lua, 466 lines) + common
(tp5rq89r57y9rr_7vxxvw.lua, 1412 lines).

## 1. Quest as a content actor

```text
QuestBaseClass (base, thin):
  getQuestId / getQuestData    identity + quest.csv row data
  _onInit / _onFinalize        lifecycle (Director-style)
  initText                     localized text setup
  tellByNpcLinkshellChat       quest hints via NPC linkshell chat
  _onJobQuestComplete{First,Second,Third} + Cancel variants
                               3-stage job quest completion
  getCutSceneReplayData        cutscene replay data

A quest is a CONTENT ACTOR (like a Director subclass). Its identity
+ static data come from quest.csv (getQuestData). Each of the 629
quest scripts is a subclass with its specific objective logic.
```

## 2. Quest acceptance (join-ask confirmations)

```text
Quest accept uses the ask() choice-prompt primitive with worldMaster
message IDs:

contentsJoinAskInBasaClass(self, ?, target)            [576]
   -> target:ask(worldMaster, 25015, 2, questId)
      (content join confirmation -- "Join this content?")

pastAreaJoinAskInBasaClass(self, ?, target)            [590]
   -> target:ask(worldMaster, 51030, 2)
      (past-area / flashback join)

instanceAreaJoinAskInBasaClass(self, ?, target)        [604]
   (instance content join)

The "ask" returns the player's choice (yes/no). On yes, the quest
proceeds (and a server notice authorizes the actual join). The
message IDs (25015, 51030) are worldMaster localized strings.
```

## 3. Quest completion + reward flow

```text
showQuestRewardAsClientCall(self, player, ?)           [1016]
   -> player:_fadeInNowLoadingForNoticeEventJustInArea()
   -> startFadeInCutSceneDefault(player)
   -> _wait(0.5)

processAfterQuestRewardWidget(self, ?, ?, A3, A4, ...)  [1000]
   -> desktopWidget:askEventModeWidgetYield(
        "Ask/QuestRewardWidget", 1, questId, A3, A4, ...)
      (shows reward widget in EVENT MODE -- suspends coroutine until
       the player acknowledges; server grants rewards)

questBaseRewardSeting(self, ...) -> processEventContentExit  [1034]
   (content exit after reward acknowledged)

REWARD FLOW:
  1. Quest objectives complete (per-quest-script logic)
  2. showQuestRewardAsClientCall: fade + cutscene transition
  3. processAfterQuestRewardWidget: QuestRewardWidget (event-mode yield)
     -> the widget yields the script; player sees rewards + confirms
  4. SERVER grants rewards (notice-authorized; the event-mode wait is
     the authorization checkpoint)
  5. processEventContentExit: exit content, resume normal play
```

## 4. Job quest 3-stage completion

```text
Job quests (class quests) have a 3-STAGE completion:
  onJobQuestCompleteFirst   [1070]  -> showGetJobAbilityWidget (new ability)
  onJobQuestCompleteSecond  [1076]  -> showGetJobItemWidget (job item/gear)
  onJobQuestCompleteThird   [1082]  -> jobTutorial (tutorial for new ability)

Plus base-class _onJobQuestComplete{First,Second,Third} + Cancel
variants (the inbound callbacks; per the player module's
MyPlayer_invokeLua_onJobQuestComplete*_timeGated -- time-gated server
events).

So completing a job quest:
  1. Server fires onJobQuestCompleteFirst (time-gated) -> ability grant UI
  2. onJobQuestCompleteSecond -> item/gear grant UI
  3. onJobQuestCompleteThird -> tutorial for the new ability
  (the "time-gated" suffix from the EXE invokeLua means these fire
   on server-controlled timing, e.g. staggered reveals)
```

## 5. SNPC (Story/Special NPC) system

```text
Quests use SNPCs -- customizable story NPCs (likely the player's
avatar representation in cutscenes, or named story characters):
  getSnpcActorClassID       SNPC actor class
  getSnpcSexualityToSkin    map sex -> skin/appearance
  getSnpcCandidacyNumber    SNPC candidate selection
  inputSnpcName             name input (player names an SNPC?)
  snpcPreviw                SNPC preview
  sayFreeDisplayName        free-form display name in dialogue
  startSnpcNQCutScene / startSnpcHQCutScene

NQ/HQ = Normal Quality / High Quality cutscenes (different fidelity
tiers). The SNPC system handles customizable characters in quest
cutscenes.
```

## 6. Cutscene + presentation control (bulk of common)

```text
startNQCutScene / startHQCutScene / replayNQCutScene
startFadeOut / startFadeIn / startFadeOutCutSceneDefault /
startFadeInCutSceneDefault / startFadeInCutSceneAfterWarp
setMusic
processFadeOutGeneral / processFadeInGeneral /
processAfterWarpFadeOutGeneral

The bulk of questbaseclass_common is CUTSCENE + FADE + MUSIC
orchestration -- all CLIENT-SIDE presentation. The quest script
calls these to play cutscenes; the server isn't involved in
presentation (only in triggering the quest event + granting rewards).
```

## 7. The quest model (server perspective)

```text
A QUEST = Director-orchestrated content actor. End-to-end:

1. AVAILABILITY: server tracks which quests are available (quest.csv
   prerequisites + completion flags). Client shows quest markers.

2. ACCEPT:
   - Player talks to quest NPC -> ask (join confirmation, msg 25015 etc.)
   - On yes -> server notice (callServerOnTalk/Command) authorizes
   - Server records quest as STARTED (quest progress flag)

3. PROGRESSION (per-quest-script + Director):
   - Objectives tracked via WorkSync (director._sync / quest flags)
   - Client runs the quest's objective logic (kill X, talk to Y, etc.)
   - Server validates objective completion (notices)

4. COMPLETE + REWARD:
   - Objectives done -> QuestRewardWidget (event-mode yield)
   - Server grants rewards (items/exp/gil/unlocks) on notice
   - Job quests: 3-stage (ability + item + tutorial), time-gated

5. CUTSCENES: client-side (NQ/HQ + fades + music); server triggers only

SERVER DATA NEEDED:
  - quest.csv: quest definitions (id, prerequisites, rewards, NPCs)
  - quest_reward.csv: reward tables
  - Per-player quest state: started/progress/completed flags
  - The 629 quest SCRIPTS are CLIENT-LOCAL (objective logic + cutscenes)

SERVER ROLE: track quest state, authorize accept/objective/complete
notices, grant rewards. The quest LOGIC + presentation run client-side.
```

## 8. Confidence

```text
Confirmed:
  - QuestBaseClass = content actor with getQuestId/getQuestData (quest.csv)
  - Join-ask confirmations use worldMaster msg IDs (25015 content, 51030 past)
  - Reward via askEventModeWidgetYield("Ask/QuestRewardWidget") event-mode
  - Job quest 3-stage completion (ability/item/tutorial)
  - SNPC system for customizable story NPCs (NQ/HQ cutscenes)
  - Bulk of common = client-side cutscene/fade/music orchestration
  - 629 quest scripts inherit this base

Likely (High):
  - Quest accept/objective/complete are server-gated via notices
  - quest.csv + quest_reward.csv drive server-side quest state
  - The 629 scripts are client-local objective logic (not server-pushed)
  - Job quest stages are time-gated server events (staggered reveals)

Speculative:
  - SNPC = player avatar in cutscenes + named story characters
  - inputSnpcName = naming a companion/story NPC
  - NQ/HQ cutscene tiers = quality/length variants per quest importance
```

## 9. Cross-references

- `finding_directorbaseclass_content_orchestration_model.md` -- quests
  are Director-style content (same orchestration model)
- `finding_server_notify_family_and_notice_authorization.md` -- the
  notice mechanism that gates quest accept/complete
- `finding_npc_event_talk_turn_flow_client_side.md` -- quest NPCs use
  the talk-turn flow
- `finding_csv_complete_correlation_132_of_164_critical_mapped.md` --
  quest.csv + quest_reward.csv (server quest data)
- `finding_playerbaseclass_command_flow_and_player_module.md` --
  getScenarioQuest/getGuildleveQuest + _onJobQuestComplete* callbacks

## 10. Next test

```text
1. Read a concrete quest script (tp5rq subdirs) to see real objective
   logic + how it uses the base
2. Map quest.csv columns (server quest definitions)
3. Trace the quest-start notice wire path (accept -> server record)
4. Read the scenario quest subdir (r75w9s1v) for main-story structure
5. Document guildleve quest mechanics (u9rr1o53p1y6y5o5 = passiveGuildleve)
```

## Commit suggestion

```
docs(re/lua): QuestBaseClass quest engine model -- Director-orchestrated content actors; accept/complete server-gated (notices); rewards via event-mode widget; job-quest 3-stage; SNPC + cutscene client-side
```
