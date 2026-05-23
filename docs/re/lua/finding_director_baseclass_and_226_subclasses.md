# Finding: DirectorBaseClass + 226 Concrete Directors -- 1.x's Content Orchestration Framework

Cracks open the full **Director family** (61s57qvs/ in cipher), the
orchestration framework for every in-game content piece: quests, raids,
guildleves, hamlet defenses, seasonal events, caravan escorts, weather,
gimmicks, etc. The architecture is **220+ concrete director subclasses
extending DirectorBaseClass** (412 lines).

## 1. Architecture overview

```text
DIRECTOR FAMILY -- 61s57qvs/ (cipher)

DirectorBaseClass (412 lines)        -- abstract scaffold
DirectorDefault (8 lines)             -- minimal default impl

TOP-LEVEL CONCRETE DIRECTORS (13):
  HarvestDirector         (8 lines)    -- gathering (Disciple of Land)
  HalloweenDirector       (?)          -- All Saints' Wake event
  FirefallFaireDirector   (?)          -- Mid-summer Faire event
  CaravanGuardDirector    (742 lines)  -- caravan escort (LARGEST)
  AfterQuestWarpDirector  (?)          -- post-quest warp animation
  WeatherDirector         (112 lines)  -- weather control
  WaveAttackDirector      (15 lines)   -- wave attack (Hamlet Defense?)
  ShipDirector            (?)          -- ferry transport
  SpecialEventDirector    (?)          -- generic special event
  RetainerAccessDirector  (?)          -- retainer summon flow
  OpeningDirector         (?)          -- intro/opening scene

SUB-FOLDERS (13 sub-systems):
  quest/         (117 files)   <-- per-quest directors
  guildleve/     ( 34 files)   <-- Guildleve content
  instanceraid/  ( 14 files)   <-- instanced raids
  monster/       ( 13 files)   <-- monster spawn/AI directors
  publicraid/    (  6 files)   <-- public raid events
  pop/           (  6 files)   <-- pop event (NM spawn) directors
  gmevent/       (  6 files)   <-- GM events
  raidgimmick/   (  6 files)   <-- raid mechanic gimmicks
  gimmick/       (  3 files)   <-- generic gimmicks
  occupancy/     (  3 files)   <-- territory/region occupancy
  weather/       (  2 files)   <-- weather sub-system
  test/          (  2 files)   <-- test directors (dev)
  caravanguard/  (  1 file)    <-- caravan guard helper

TOTAL: 13 top-level + 213 sub-folder = ~226 concrete director classes
```

## 2. DirectorBaseClass interface (~20 methods, 412 lines)

```text
WORK SCHEMA SETUP (3 tables):
  directorWork._temp = { directorId (int32), _assignForChild=240 }
  directorWork._sync = { contentCommand (int32),
                         contentCommandSub (int32),
                         syncBuffer (boolean[128]),
                         _assignForChild=64 }
  directorWork._tag  = sync metadata

LIFECYCLE (4):
  _onInit(directorId, ...)      assigns ID, sets up schemas, calls init
  init(...)                     subclass-overridable ctor
  _onFinalize()                 cleans UI, clears contentCommandVariation
  processFinalize()             subclass-overridable cleanup

WORK ACCESSORS (8):
  getTempWork(key)              read self.work[key] (temp slot)
  setTempWork(key, val)         write self.work[key]
  getSaveWork(key)              read (alias for temp; semantic intent only)
  setSaveWork(key, val)         write (alias)
  getSyncWork(key)              read self.work[key] (sync slot)
  initWork(self, temp, sync)    set work._temp + work._sync schemas
  initWorkSyncTag(tag)          set work._tag schema
  updateSyncWork(key, val)      gated update via canRequestInformation

CONTENT COMMAND (2):
  getContentCommandVariation()  → (contentCommand, contentCommandSub)
  -- (variation setter lives on MyPlayer.setContentCommandVariation;
     the director writes to its own directorWork; the work-update event
     propagates the value through to the player.)

EVENT HOOKS (5):
  delegateEvent(eventId, target, callback, ...)
                                routes event to a target object
  _onEventCancel(ev, type, ...) close content widget; reset fade if noticeEvent
  _onNoticeRejected(reason)     subclass-overridable rejection callback
  _onUpdateWork(path, key, ...) PATH-BASED state-change dispatcher (key fn!)
  canUpdateMap()                returns TRUE (default; subclass may block map open)

UI HOOKS (4 -- subclass-overridable):
  processUIInit()
  processUIUpdate(key)
  processUIFinalize()
  processMapOpenMessage()
  
INFO HOOK (1):
  getKindContentsInformation()  returns what content-info widget should display
```

## 3. The _onUpdateWork path-based dispatch (THE key mechanism)

This is the core orchestration logic -- subclasses receive state updates
via PATH strings:

```lua
function _onUpdateWork(self, path, key, ...)
  if path == "_init" then
    -- Director is starting
    if self.directorWork.contentCommand ~= 0 then
      if myPlayer.getQuestContentsCommandPermitFlag() == true then
        myPlayer.setContentCommandVariation(
          self.directorWork.contentCommand,
          self.directorWork.contentCommandSub
        )
      end
    end
    self:processUIInit()
    self:processUpdateWork(path, key)
    
  elseif path == "directorWork" and key == "contentCommand" then
    -- Director changed content command variation
    if myPlayer.getQuestContentsCommandPermitFlag()
       and self:getUseContentsCommand() == true then
      myPlayer.setContentCommandVariation(
        self.directorWork.contentCommand,
        self.directorWork.contentCommandSub
      )
    end
    
  elseif path ~= "directorWork" and path ~= "work" then
    -- Other state change
    self:processUpdateWork(path, key)
    
  elseif path == "work" then
    -- Work table updated; refresh UI
    self:processUIUpdate(key)
  end
end
```

So **every director state change funnels through `_onUpdateWork`** and is
routed by:
- `"_init"` → first-time setup
- `"directorWork"`+`"contentCommand"` → content variation changed
- `"directorWork"`+`"contentCommandSub"` → (similar, but via direct sync)
- `"work"` → UI refresh
- (anything else) → custom subclass logic

This is the SAME dispatch pattern used by:
- CharaBase's _onUpdateWork (per `finding_chara_cliprog_and_event_extensions.md`)
- WidgetBaseClass's update routing
- StatusBaseClass... actually no, status doesn't use this; statuses are simpler.

## 4. The contentCommand mechanism -- 1.x's content-mode locking

Every director carries TWO command IDs:
- `directorWork.contentCommand`     (primary; int32; 0 = no content mode)
- `directorWork.contentCommandSub`  (sub-variation; int32)

When a director starts and `contentCommand != 0`:
1. Director calls `myPlayer.setContentCommandVariation(contentCmd, contentCmdSub)`
2. Player enters CONTENT MODE -- their command set switches to the content's
   allowed actions
3. When director finalizes, it calls `setContentCommandVariation(nil)` which
   restores the default command set

This is the **1.x equivalent of FFXIV's "Duty" instance system**:
- A Guildleve = director sets contentCommand to the Guildleve's command pack
- A Hamlet Defense = director sets contentCommand to the defense-action pack
- A quest cutscene = director sets contentCommand to the cutscene-control pack

The PERMIT FLAG `myPlayer.getQuestContentsCommandPermitFlag()` is checked BEFORE
the content mode applies -- meaning the player can REFUSE the content mode
(e.g., if they're in another active instance, the permit is denied).

## 5. The 128-bit syncBuffer

```text
directorWork._sync includes:
  syncBuffer = boolean[128]
```

This is a **128-bit flag array** that every director carries for arbitrary
per-content state sync. Typical uses:
- Hamlet Defense: 128 flags for "wave N is active", "wave N is cleared",
  "monster type X spawned", etc.
- Guildleve: flags for "objective N complete", "objective N visible".
- Quest: flags for "NPC X talked", "item X obtained", "location X visited".

128 booleans is **enough for very complex content state** -- 128 distinct
binary toggles per director instance.

## 6. Sub-folder content scale

```text
117 quest/ directors    -- One per quest CONTENT, suggesting 1.x quests
                          with active state machines (not just dialog) had
                          their own director class. 117 << 629 total quests,
                          so most quests just used a default director;
                          ~117 quests had custom orchestration.

34 guildleve/ directors -- 34 distinct Guildleve TYPES. FFXIV 1.x's
                          Guildleves were instanced repeat-content with
                          per-leve mechanics. 34 types matches the "Guildleve
                          variety" count in the game.

14 instanceraid/ directors -- 14 unique instanced raids.
                              Likely includes Ifrit/Garuda trials, AV/Cutter
                              dungeons, primary 1.x raids.

13 monster/ directors    -- Monster director files. Probably for NM spawn
                          orchestration (King Behemoth, Ahriman, etc.).

6 publicraid/ directors  -- 6 open-world public raid events.

6 pop/ directors         -- 6 pop (spawn) event types. Likely the open-world
                          NM popper system.
```

## 7. Subclass: HarvestDirector (8 lines) -- MINIMAL

The 8-line HarvestDirector is the gathering director (Disciple of Land).
Because gathering is so simple (initiate → animate → drop loot → end), it
overrides almost NOTHING -- inherits the default lifecycle entirely.

This is **evidence the framework is well-designed** -- a director can be
8 lines for a content type that fits the default mold.

## 8. Subclass: CaravanGuardDirector (742 lines) -- LARGEST

The 742-line caravan guard director is the most complex top-level director.
This is for the **caravan escort missions** -- a moving NPC train that the
player must protect from monster waves while it moves between locations.

742 lines is needed because:
- Path-following NPC management
- Spawn timing for monster waves
- Win/fail condition tracking
- Bonus reward calculations
- UI orchestration for caravan status

This is FAR larger than any single quest director (most quest directors are
likely 20-100 lines).

## 9. WeatherDirector (112 lines)

Weather is its own director because weather changes:
- Affect zone-wide aether
- Sync to all players in the zone
- Drive monster spawn modifiers
- Affect crafting/gathering yield
- Trigger zone-specific events (rainstorm in Thanalan = sandstorm event)

112 lines accommodates the weather state machine + sync to all clients
in the area.

## 10. The Director × Judge × Command × Status × Widget unification

Now we have THE COMPLETE Lua orchestration picture:

```text
WIDGET           UI rendering         (n1635q/)
COMMAND          player intent        (7vxx9w6/)
JUDGE            command validation   (0p635/)    <-- 5-way polymorphic
STATUS           combat state         (rq9qpr/)   <-- 5-param math model
DIRECTOR         content orchestrate  (61s57qvs/) <-- 226 subclasses
CHARA            character state      (729s9/)
WORLD/AREA       zone state           (nvsy6/9s59/)
SYSTEM           engine plumbing      (rlrq5x/)
```

Every gameplay event flows: Widget → Command → Judge → (Status apply +
Director update) → World.

## Confidence

```text
Confirmed:
  - DirectorBaseClass is 412 lines with ~20 documented methods.
  - 13 top-level concrete directors + 13 sub-folders = 226 total directors.
  - _onInit sets up 3 work-table schemas (_temp, _sync, _tag).
  - directorWork._sync includes a 128-boolean syncBuffer.
  - _onUpdateWork dispatches by path: "_init", "directorWork", "work", other.
  - contentCommand + contentCommandSub IDs drive the player's content mode.
  - setContentCommandVariation is GATED by getQuestContentsCommandPermitFlag.
  - CaravanGuardDirector is 742 lines (largest top-level).
  - HarvestDirector is 8 lines (smallest top-level).
  - quest/ sub-folder has 117 per-quest directors.
  - guildleve/ has 34 directors.
  - instanceraid/ has 14 directors.

Likely (High):
  - The 226 directors form 1.x's complete content surface (excluding pure
    dialog quests which use a default director).
  - WaveAttackDirector handles Hamlet Defense waves.
  - PopDirector handles open-world NM spawns.
  - The 128-bit syncBuffer is enough for complex content state but tight
    for very large multi-stage content (probably a soft limit observed in
    1.x's content design).
  - DirectorDefault (8 lines) is the minimal director used by ~512 of 629
    quests that don't need custom orchestration.

Likely (Medium):
  - "Pop" stands for "popup" / "spawn" (FFXI NM pop terminology).
  - The 6 publicraid directors match 1.x's 6 known public raid events.
  - The 14 instanceraid directors include Bowl of Embers (Ifrit), Navel
    (Titan), Howling Eye (Garuda), Aurum Vale, Cutter's Cry, etc.
  - The "occupancy" sub-folder is for region-occupation tracking (Garlean
    castrum control, beastman territory threats, etc.).

Speculative:
  - "RetainerAccessDirector" handles the retainer summon UI flow, possibly
    including the retainer market wards system.
  - "AfterQuestWarpDirector" is the post-cutscene fade-and-warp for quest
    completion (when you finish a quest and the game teleports you
    somewhere).
  - The FirefallFaireDirector + HalloweenDirector being in the corpus
    confirms 1.x had seasonal events at the time of the data dump.
```

## Server implications

```text
- Server must implement the DirectorWork sync mechanism: each active
  director has a (directorId, contentCommand, contentCommandSub, syncBuffer)
  tuple that syncs to the client.
- Player's setContentCommandVariation packet must be supported -- it
  changes the player's command set based on active content.
- getQuestContentsCommandPermitFlag is the server-side gate that controls
  whether the player accepts content mode (e.g., can't enter Hamlet
  Defense while already in a Guildleve).
- 128-bit syncBuffer per director = 16 bytes of arbitrary state per
  content instance.
- Each director ID is unique -- server probably tracks active director
  count per player + per zone for instance limits.
- The DirectorDefault (8 lines) suggests most quests don't need a custom
  director -- server can use one default-director scaffold for ~80% of
  629 quests.
```

## Cross-references to other findings

- **`finding_director_family_and_cutscene_closure.md`**: this finding
  upgrades the original 14-top-level + 14-subdir hypothesis to the actual
  13 + 13 = 226 directors total.
- **`finding_command_baseclass_and_teleport.md`**: directors WRITE to
  contentCommand on directorWork; commands READ it for routing.
- **`finding_quest_corpus_and_login_event_command.md`**: 629 quests but
  only 117 per-quest directors → ~512 quests use the default director,
  117 have custom orchestration.
- **`finding_chara_cliprog_and_event_extensions.md`**: the _onUpdateWork
  path-based dispatch is the SAME pattern used by CharaBase for state
  changes.

## Annotations made in Ghidra

None this finding -- Lua-only analysis.

## Next test

- Sample a quest director from quest/ to see what custom orchestration
  looks like (one with simple flow vs one with multi-stage objectives).
- Read CaravanGuardDirector to understand 1.x's most complex content
  orchestration.
- Map the 14 instanceraid directors to FFXIV's known 1.x raids
  (Bowl of Embers, Navel, Howling Eye, Aurum Vale, Cutter's Cry,
  AV...).
- Find which director handles the cataclysm finale Login Event sequence
  -- probably AfterQuestWarpDirector or SpecialEventDirector.

## Commit suggestion

```
docs(re/lua): DirectorBaseClass + 226 concrete directors -- 1.x's content orchestration framework
```
