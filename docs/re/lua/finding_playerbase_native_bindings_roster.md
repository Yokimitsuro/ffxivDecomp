# Finding: PlayerBaseClass — Complete 94 Native Binding Roster

The master inventory of PlayerBaseClass's Lua-exposed C++ native
bindings. Reading `playerbaseclass_u.lua` (941 lines, 94 binding
declarations at +10 line increments) gives the **complete API
surface** that Lua scripts can call on the player.

This validates the earlier finding `finding_lua_to_exe_command_bridge.md`
which counted "~94 PlayerBase bindings via FUN_00753f90 master block"
— now EXACTLY confirmed at 94.

Sources read:

```text
chara/player/playerbaseclass_u.lua    941 lines
                                       (94 binding stub declarations)
```

## Convention

Each binding is declared as a 10-line stub block:

```lua
L0_1 = PlayerBaseClass
function L1_1(...)  -- stub body (calls C++)
end
L0_1._<name>_inl = L1_1
```

The `_inl` suffix is the "Lua-binding inline thunk" — the actual
C++ implementation lives in the binding registration block
(FUN_00753f90, see EXE finding).

## Categorized Roster (94 bindings)

### Event / Talk / Emote / Push (9)

```text
_isEventPlaying(eventType_str)        is the player in this event mode?
_executeTalk(...)                      initiate talk event
_canExecuteTalk(...)                   check if talk is allowed
_executeEmote(...)                     initiate emote event
_canExecuteEmote(...)                  check if emote is allowed
_cancelTalk()                          cancel ongoing talk
_cancelNotice()                        cancel notice popup
_cancelEmote()                         cancel emote
_cancelPush()                          cancel push interaction
```

### Player Identity / Status (5)

```text
_getGMRank()                           GM (Game Master) rank (0 = player,
                                        >0 = staff)
_getWarpRecastTime()                   teleport cooldown remaining
_getChocoboGrade()                     chocobo class/grade
_getChocoboRidingGrade()               chocobo riding skill grade
_isEnabledGoobbue()                    goobbue mount available?
```

### Inn / Bed (2)

```text
_setPosDirInn(...)                     set inn-room position + facing
_readyInnBed()                          ready inn bed (logout to inn)
```

### Camera (1)

```text
_forceCameraTPSMode(bool)              force third-person camera mode
```

### Command System (8) — THE KEY SUBSYSTEM

```text
_executeCommand(...)                   FRONT-END for player command
                                       execution (see finding_command_
                                       execute_wire.md)
_callServerOnCommand(...)              call server's command-handler
                                       (PROBABLY the actual network send)
_doServerOnCommand(...)                fallback server-side execution
_cancelCommand()                       cancel ongoing command
_isCommandPlaying(...)                 command currently in progress?
_canExecuteCommand(name)               can this command category fire?
_countCommandPlaying()                 number of commands currently
                                       executing (probably 0 or 1)
_breakCommand()                        forcibly break command
```

### Touch Attribute (2)

```text
_setTouchAttribute(slot, enabled)      enable/disable touch ability
_isTouching()                          currently touching something?
```

### Fade Effects (8)

```text
_fadeIn(duration)                      screen fade in
_fadeInAfterWarp()                     fade in after zone warp
_fadeOut(duration)                     screen fade out
_waitForFading()                       wait until fade completes
_isFading()                            currently fading?
_cancelFading()                        cancel ongoing fade
_resetFade()                           reset fade state
_fadeInNowLoadingForNoticeEventJustInArea()
                                       "Now Loading" fade for events
```

### Chat (1)

```text
_chat(channel, msg, ...)               send chat message (player side)
```

### Control Locks (9)

```text
_lockPlayerControl() / _unlockPlayerControl() / _isPlayerControlEnabled()
_lockLockonControl() / _unlockLockonControl() / _isLockonControlEnabled()
_lockCameraControl() / _unlockCameraControl() / _isCameraControlEnabled()
```

Three control axes (movement, lockon target, camera) each with
lock / unlock / query. Used during cutscenes and tutorial to
restrict player input.

### Lockon (2)

```text
_setLockonTarget(targetActor)          set lockon target
_getLockonTarget()                     get current lockon target
```

### World Effects (2)

```text
_setWeather(weatherId)                 force weather for this player
_setMusic(musicId)                     override BGM for this player
```

### Map Loading (1)

```text
_waitForMapLoaded()                    yield until current zone is loaded
```

### Trophy / Achievement (3 simple)

```text
_canGetTrophy()                        eligible for trophy/achievement?
_isAchievedTrophy(id)                  has earned trophy id?
_achieveTrophy(id)                     award trophy id
```

### Movement (1)

```text
_turn(angle)                           rotate player to angle
```

### Time / Content Tracking (4)

```text
_getOccupancyContentsTime()            time spent in current content
_getNormalBehestTime()                 next normal Behest cooldown
_getCompanyBehestTime()                next Company Behest cooldown
_getBelongGrandCompany()               which GC does player belong to?
                                       (returns GC id: Maelstrom/TwinAdder/
                                        ImmortalFlames)
_getGrandCompanyRank()                 player's rank within their GC
```

**Notable**: `_getBelongGrandCompany` + `_getGrandCompanyRank`
explicitly named — confirms that 1.x's "Company" system is the
**Grand Company**, not Free Company. And **Behest** is the precursor
of ARR's FATE system — a public event with cooldown timer.

### Combat State (2)

```text
_isPushingOut()                        is player in "push out" state?
                                       (probably knockback / dismounted)
_haveEnmityCharacters()                does player have aggro from
                                       any chara?
```

### NM Rush (1)

```text
_getNMRushUpdateTime()                 timer for NM (Notorious Monster)
                                       rush update (probably the
                                       respawn / world-rotation timer)
```

### Achievement System (21) — Major Subsystem

```text
ENUMERATION:
  _countAchievementCategory()              # of categories (Combat/Craft/Gather/etc)
  _getAchievementCategoryId(idx)           category id at index
  _countAchievementItem(catId)             # of achievements in category
  _getAchievementItemId(catId, idx)        achievement id at category index

STATE QUERIES:
  _isDoneAchievement(achievementId)        is this achievement earned?
  _getAchievementPoint(achievementId)      points awarded by this achievement
  _getAchievementTitle(achievementId)      title awarded by this achievement
  _setAchievementTitle(titleId)            equip a player title

TITLES:
  _countEnableAchievementTitle()           # of titles player has earned
  _getEnableAchievementTitle(idx)          title id at index
  _hasAchievementTitle(titleId)            has this specific title?

ITEMS (reward items from achievements):
  _hasAchievementItem(itemId)               has this achievement-reward item?
  _getAchievementSheetDataPoint(achievementId)  point value (sheet lookup)
  _getAchievementSheetDataIcon(achievementId)   icon (sheet lookup)
  _getAchievementSheetDataTitle(achievementId)  title (sheet lookup)
  _getAchievementSheetDataItem(achievementId)   reward item (sheet lookup)

PROGRESS RATES:
  _getAchievementRate(achievementId)         progress % for this achievement
  _clearAchievementRateCache()               clear cached progress values
  _countAchievementRateList()                # of in-progress achievements
  _getAchievementRateList(idx)               achievement id at index
  _isDoneAchievementRateList(idx)            is this in-progress achievement
                                              done now?
```

So 1.x had a **full achievement system** comparable to ARR's: 21
native bindings to navigate categories, query state, equip titles,
track progress.

### CutScene Replay System (5)

```text
_isCompletedCutSceneReplayQuest(questId)  has player seen this CS?
_getCutSceneReplaySnpcNickname(idx)        snpc nickname (idx 1..N)
_getCutSceneReplaySnpcCoordinate(idx)      snpc world coordinate
_getCutSceneReplaySnpcSkin(idx)            snpc appearance skin
_getCutSceneReplaySnpcPersonality(idx)     snpc personality params
```

So players can **replay cutscenes** with their character "starring"
in them — sNPC = "scenario NPC" = the player's customized
representation in cutscenes. These bindings let the replay
re-render with the right nickname / position / skin / personality
parameters.

### Item Storage (3)

```text
_canStoreItem()                          can store more items?
_countStoredItem()                       # of stored items
_getStoredItem(idx)                      stored item at index
```

Storage = personal item stash (probably the retainer's inventory,
or a global player stash).

### Hamlet Defense Score (3)

```text
_countHamletDefenseScore()               # of Hamlet Defense entries
_getHamletDefenseScore(idx)              score at index
_getHamletDefenseScoreAll()              total cumulative score
```

So the **Hamlet Defense event has a scoring/ranking system** —
players accumulate scores across attempts, displayed in a ladder.

## Architecture Insights

```text
Total binding count: 94 native methods exposed to Lua.

Bandwidth breakdown:
  - Network-touching: ~10 (executeCommand family,
                           callServerOnCommand, etc.)
  - Pure local query: ~50 (achievements, fade, controls,
                           identity getters)
  - Local mutators: ~30 (locks, fade, set targets,
                          set weather, etc.)
  - Wait/yield: ~4 (waitForFading, waitForMapLoaded, etc.)
```

So **most native bindings are LOCAL** — they query/mutate client
state without server roundtrip. Only the command family and
direct server calls (`_callServerOnCommand`, `_doServerOnCommand`)
touch the wire.

## Notable Subsystems Surfaced

```text
1. ACHIEVEMENT (21 bindings, 22% of API)
   The largest subsystem -- 1.x took achievements seriously.
   Per-achievement: title + reward item + icon + point value.

2. CUTSCENE REPLAY (5 bindings)
   Players can re-watch cutscenes with their character.
   sNPC = scenario NPC, the player's CS representation.

3. GRAND COMPANY (2 bindings + Behest x2)
   Confirms 1.x had Grand Companies, not Free Companies.
   Behest = 1.x's FATE precursor.

4. CONTROL LOCKS (9 bindings)
   Three axes (player movement / lockon / camera) each with
   lock/unlock/query. Used heavily during cutscenes.

5. COMMAND EXECUTION (8 bindings)
   The hot-path for combat actions. Documented separately in
   finding_command_execute_wire.md.

6. HAMLET DEFENSE SCORE (3 bindings)
   Per-event scoring system; matches the elaborate Hamlet Defense
   mechanics documented in finding_hamlet_and_retainer.md.
```

## Assessment

```text
Confirmed:
  - EXACTLY 94 native bindings (validates prior EXE finding's count).
  - 21 achievement-related bindings -- a major subsystem.
  - _getBelongGrandCompany + _getGrandCompanyRank confirm Grand
    Company (not Free Company).
  - _getNormalBehestTime + _getCompanyBehestTime confirm "Behest"
    as 1.x content (FATE precursor).
  - 9 control lock bindings (3 axes x 3 operations) for cutscene
    + tutorial state control.

Likely (High):
  - The non-network bindings (~85% of total) reflect the LOCAL-FIRST
    design philosophy of the client: most queries hit local cached
    state, not the server.
  - Achievement state is server-pushed when changed; client caches
    locally. The "ClearAchievementRateCache" binding suggests
    progress rates are cached and need explicit invalidation.
  - CutScene Replay was a major selling point of 1.x (player
    starring in their own story); 5 bindings for the snpc
    customization layer reflects this investment.

Likely (Medium):
  - The category id space for achievements is finite (~20-50
    categories) covering combat / craft / gather / explore /
    quest / community categories.
  - The sNPC skin/personality are stored persistently per
    character (not regenerated each replay).

Speculative:
  - Behest time bindings being separated into "Normal" and "Company"
    suggests two parallel cooldown timers. Maelstrom Behest vs
    independent Behest had different cooldowns -- standard MMO
    design to encourage organization-aligned play.
  - The "Goobbue" check (_isEnabledGoobbue) suggests goobbue
    mounts were unlock-able via specific questline (vs chocobo
    which was the baseline mount).
```

## Open Questions

```text
1. What is the cipher meaning of the suffix "_inl" -- "inline"
   or "instance native lookup"? Most native bindings use this
   convention.

2. The 94 count matches FUN_00753f90's registration loop. Map
   each Lua-side _inl to its specific C++ function pointer for
   a complete cross-reference table.

3. The Achievement category id space could be enumerated by
   reading a sheet of achievements (achievementSheet probably).

4. Other base classes (CharaBase, NpcBase, GroupBase) have their
   own _u.lua files with native bindings. Documenting all of them
   would close the entire Lua-to-C++ API surface.
```

## Server Implementation Picture

For a server, this 94-binding surface defines **what the client
will query the server for during gameplay**:

```text
DIRECT NETWORK BINDINGS (~10):
  _executeCommand          -- network send (probably 0x12f / 0x130 / 0x131)
  _callServerOnCommand     -- alternate network send
  _doServerOnCommand       -- fallback network send
  _setLockonTarget         -- (probably server-validated)
  _setAchievementTitle     -- title change (persistent)
  _achieveTrophy           -- trophy earn (rare; server validates)

LOCAL CACHE BINDINGS (~85):
  All achievement queries, fade controls, control locks, etc.
  Server pushes state changes; client caches; bindings query cache.
  No network ping per binding call.

SERVER MUST IMPLEMENT:
  Achievement progress tracking (state pushed to client)
  CutScene replay state (sNPC snapshot saved)
  Grand Company membership (pushed via charaWork/playerWork sync)
  Hamlet Defense score history (server-persistent)
  Behest cooldowns (server-tracked)
```

The 1.x server is mostly a **state holder + change broadcaster**:
holds the persistent data, pushes deltas to clients, lets client
side handle ~85% of queries locally.
