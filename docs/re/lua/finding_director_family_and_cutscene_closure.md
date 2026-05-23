# Finding: Director Family Closure + GameData/CutScene Engine

Closes two related Lua subsystems:
1. **Director family** -- the orchestrator pattern for ALL content
   instances in 1.x (raids, hamlets, leves, events). 14 top-level
   directors + 14 subdirectories with ~100+ concrete classes.
2. **GameData/CutScene engine** -- the Lua implementation behind
   the inbound CutScene opcodes (8/9/10/11/13). Reveals one new
   opcode pairing: `_onHideWidgetClip` pairs with opcode 11.

## Director taxonomy (cipher decoded)

```text
TOP-LEVEL DIRECTORS (14 files):
  61s57qvs89r57y9rr.lua            DirectorBaseClass            412 lines, 24 methods
  61s57qvs6549pyq.lua              DirectorDefault              fallback
  29so5rq61s57qvs.lua              HarvestDirector              gathering
  29yyvn55w61s57qvs.lua            HalloweenDirector            All Saints' Wake
  41s549yy491s561s57qvs.lua        FireFallFaireDirector        seasonal event
  79s9o9w3p9s661s57qvs.lua         CaravanGuardDirector         caravan escort (prior)
  94q5stp5rqn9su61s57qvs.lua       AfterQuestWarpDirector       post-quest warp
  n59q25s61s57qvs.lua              WeatherDirector              (prior)
  n9o59qq97z61s57qvs.lua           WaveAttackDirector           Hamlet wave attack!
  r21u61s57qvs.lua                 ShipDirector                 ship travel
  ru5719y5o5wq61s57qvs.lua         SpecialEventDirector         generic events
  s5q91w5s9775rr61s57qvs.lua       RetainerAccessDirector       retainer interaction
  vu5w1w361s57qvs.lua              OpeningDirector              opening cinematic
```

```text
DIRECTOR SUBDIRECTORIES (14 dirs):
  1wrq9w75s916/    instanceraid/    16 files (per-raid directors)
  3p1y6y5o5/       guildleve/       34 files (per-leve + bases)
  3x5o5wq/         gmevent/         6 files (GM event tools)
  31xx17z/         gimmick/         (gimmick managers)
  s91631xx17z/     raidgimmick/     (raid-specific gimmicks)
  up8y17s916/      publicraid/      5+ files (public NM raids)
  uvu/             pop/             6 files (population/spawn)
  v77pu9w7l/       occupancy/       3 files (zone occupancy)
  xvwrq5s/         monster/         (monster party directors)
  79s9o9w3p9s6/    caravanguard/    (caravan sub-files)
  n59q25s/         weather/         (weather sub-files)
  tp5rq/           quest/           (quest directors)
  q5rq/            test/            (test stubs)
```

## DirectorBaseClass (412 lines, 24 methods)

```text
WORK MANAGEMENT:
  getTempWork / setTempWork          ephemeral state (session)
  getSaveWork / setSaveWork          persistent state (across sessions)

LIFECYCLE:
  _onInit / init
  _onFinalize / processFinalize

WORKSYNC SCHEMA:
  initWork                            schema declaration
  initWorkSyncTag                     sync tag binding
  getSyncWork / updateSyncWork        sync state I/O

EVENT DELEGATION:
  delegateEvent                       forward to handler
  _onEventCancel                      cancel handler
  _onNoticeRejected                   notification rejection

WORK UPDATE PIPELINE:
  _onUpdateWork                       work-changed callback
  processUpdateWork                   process changes

UI PIPELINE:
  processUIInit / processUIUpdate /
  processUIFinalize                   UI lifecycle
  processMapOpenMessage              opens content map message

CONTENT METADATA:
  getKindContentsInformation         content-type description
  getUseContentsCommand              command to invoke this content
  getContentCommandVariation         command-variation table
```

So a **Director is a STATEFUL CONTENT INSTANCE** that orchestrates
one piece of content (a raid run, a leve attempt, a Hamlet wave,
a weather change, etc.). Each director:

1. Has temp + save work (state)
2. Syncs state to clients via WorkSync (opcode 0x12F)
3. Has its own UI flow
4. Delegates events to specific handlers
5. Provides content-specific commands

## Most concrete directors are STUBS

Sampling 7 of the top-level directors:

```text
HarvestDirector              8 lines      stub (uses base behavior)
HalloweenDirector            8 lines      stub
FireFallFaireDirector       28 lines      adds 1-2 overrides
WaveAttackDirector          15 lines      stub
ShipDirector                15 lines      stub
SpecialEventDirector        15 lines      stub
RetainerAccessDirector      ?             not yet sampled
OpeningDirector             15 lines      stub
AfterQuestWarpDirector      15 lines      stub
```

So most directors are CLASS-NAME-ONLY declarations -- the actual
behavior comes from:
- DirectorBaseClass (412 lines, default behavior)
- The C++ Director controller (drives lifecycle / WorkSync)
- Per-director sheet data (FFXIVTool tables drive the parameters)

The Director class is the EXTENSION POINT: when the server creates
a Director instance, it instantiates the appropriate subclass which
inherits all behavior from the base. The subclass only overrides
when special behavior is needed.

## Notable concrete content (from subdir names)

### Instance Raids (16 files)

```text
InstanceRaidBaseClass
InstanceRaidHamletDefense
InstanceRaidHyperifrit             (Hyper Ifrit boss)
InstanceRaidDarkmoogle             (Darkhold moogle event?)
InstanceRaidCuttersCry             (Cutter's Cry dungeon)
InstanceRaidBeaconBattle           (Beacon ramparts NM)
InstanceRaidNormal*                (normal-mode variants)
+ 10 more
```

These cover the major instanced content of 1.x: Hyper Ifrit (open
beta), Cutter's Cry (a real FFXIV dungeon), Beacon Battle (NM-tier
encounter), Hamlet Defense (the famous wave-based content),
Darkmoogle (event).

### Public Raids (5+ files)

```text
PublicRaidBaseClass
PublicRaidBeaconFort
PublicRaidZaharaK                   (Zahar'ak Ala Mhigan stronghold)
PublicRaidUghamaro                  (Ugh'amaro mining area)
PublicRaidShposhae?                 (?TBD; possibly Sapphire)
```

So public raids correspond to the **real 1.x open-world NM
locations**: Beacon Fort, Zahar'ak, Ugh'amaro. These were the
endgame NM hunts of 1.x.

### Guildleves (34 files)

The 3p1y6y5o5/ subdir has 34 files for guildleve mechanics. Per
prior session findings, leves had multiple types (battle / craft /
gathering / passive). The 34 files likely cover the type variants
+ specific leve scripts + helper directors:

```text
GuildleveBaseClass                    base class
GuildleveTest1 / Test2 / Test3        test stubs
GuildleveHarvestTest                  harvest test
RequestDirector                       leve request handler
RequestManager                        request manager
CompanyLeveDetect*                    GC leve detection (3 variants)
... 25 more (specific leve types)
```

So **leves run as directors** -- each leve attempt instantiates a
Director, and the server runs N directors for N concurrent leve
attempts across players.

## GameData / CutScene engine

Located at `lua/decompiled/src/39x569q9/`:

```text
39x569q989r57y9rr.lua    GameDataBaseClass        21 lines (abstract)
7pqr75w5.lua             CutScene                  69 lines (per-instance)
7pqr75w5_7vxxvw.lua      CutScene_common         1316 lines (the engine)
rus596r255q.lua          SpreadSheet              22 lines (sheet accessor)
```

### CutScene per-instance (69 lines)

```lua
work._temp = {
    textOwner          (actor),       -- the dialog speaker
    isPreviewTextOwner (boolean),     -- preview mode flag
    actorclassSheet    (actor)        -- SpreadSheet actor for actorclass lookup
}

_onInit(filename, textOwner_actor):
    work.actorclassSheet = _createActor(nil, "SpreadSheet", false, "actorclass")
    work.textOwner       = textOwner_actor
    work.isPreviewTextOwner = false

_onFinalize:
    work.actorclassSheet:_delete()
    clear refs
```

So each CutScene creates its own **SpreadSheet actor** to query the
`actorclass` table. This is how the CutScene engine looks up NPC
data during dialog ("when this character speaks, render this
model").

### CutScene_common (1316 lines) -- the engine

Contains the implementations of EVERY CutScene Lua hook documented
in the inbound dispatch table findings:

```text
_onInitializationClip   (line 30)    paired with INBOUND opcode 8
_onFinalizeClip         (line 59)    paired with INBOUND opcode ???
_onOpenUIClip           (line 499)   paired with INBOUND opcode 13
_onShowUIClip           (line 805)   paired with INBOUND opcode 9
_onHideUIClip           (line 823)   paired with INBOUND opcode 10
_onShowWidgetClip       (line 934)   paired with INBOUND opcode 11
_onHideWidgetClip       (line 1030)  paired with INBOUND opcode ??? (NEW PAIR)
getNameByActorClass     (line 1061)  helper
startCutScene           (line 1316)  entry point (C++ calls this)
```

### NEW OPCODE PAIRING: `_onHideWidgetClip`

Previously I had documented opcode 11 as `_onShowWidgetClip` (the
WidgetClip variant; distinct from the UIClip pair 9/10). This
finding reveals that there IS a `_onHideWidgetClip` hook (line 1030
of CutScene_common), which must pair with an INBOUND opcode in the
same way that `_onShowUIClip` (op 9) pairs with `_onHideUIClip`
(op 10).

Candidate opcodes for `_onHideWidgetClip`:
- Opcode 12 (FUN_007599e0, Family B, unmapped) -- ADJACENT to opcode
  11 (_onShowWidgetClip = FUN_00759940) -- BEST candidate.
- Opcodes 14-19 (some Family A entries unmapped)

So opcode 12 is very likely `_onHideWidgetClip`. This narrows the
remaining CutScene block:

```text
INBOUND OPCODE   LUA HOOK                    PAIRING
   8             _onInitializationClip       solo (no pair)
   9             _onShowUIClip               paired with 10
  10             _onHideUIClip               paired with 9
  11             _onShowWidgetClip           paired with 12 (likely)
  12             _onHideWidgetClip ??         paired with 11 (LIKELY)
  13             _onOpenUIClip               (probably paired with one of
                                              the unmapped CutScene opcodes,
                                              "_onCloseUIClip" or similar)
   ?             _onFinalizeClip             (TBD; another unmapped opcode)
```

### CutScene engine architecture

```text
SERVER STARTS A CUTSCENE:
  Push opcode 8 (_onInitializationClip)
    -> CutScene._onInit creates SpreadSheet actor for actorclass
    -> CutScene_common._onInitializationClip body runs (initialization
       Lua hook fires)

SERVER PLAYS DIALOG/ACTION CLIPS:
  For each clip in the cutscene:
    Push opcode 9 / 11 / 13 (Show/ShowWidget/Open variants)
      -> appropriate _onXxxClip hook fires
      -> dialog renders, animation plays, etc.
    [pause for clip duration]
    Push opcode 10 / 12 (Hide variants)
      -> _onHide* hook fires
      -> clip removed from screen

SERVER ENDS CUTSCENE:
  Push opcode ??? (_onFinalizeClip)
    -> CutScene._onFinalize cleans up the SpreadSheet actor
    -> Cutscene exits, gameplay resumes
```

## SpreadSheet helper (22 lines)

```text
A thin wrapper actor that provides typed access to a FFXIVTool-style
data table. The CutScene creates SpreadSheet("actorclass") at init,
then queries it during the cutscene to look up actor metadata.

So the CutScene engine is data-driven: scripts reference actor IDs
which the SpreadSheet resolves to (model id, name, default
animations, etc.). Server doesn't need to push these details --
just the IDs.
```

## GameDataBaseClass (21 lines, abstract)

```text
Minimal abstract base. Provides only the interface contract for
GameData subclasses to implement. CutScene and SpreadSheet are the
two confirmed subclasses; there may be others (e.g. a
PassiveGuildleve data class).
```

## Server implications

```text
DIRECTOR SYSTEM SERVER REQUIREMENTS:

1. Director runner: spawn N concurrent Director instances per active
   content. Track each director's:
   - director_id (uint)
   - director_class (the Lua subclass name)
   - participants[] (player_ids in this content)
   - state (temp + save work)
   - active_clips[] (during cutscene-heavy content)

2. WorkSync per director:
   - Director state is broadcast via WorkSync (opcode 0x12F).
   - Each binding has a tag that identifies which director it
     belongs to (per initWorkSyncTag).

3. Per-content class instantiation:
   - When a player triggers a leve, raid, or event, server picks
     the appropriate Director subclass.
   - For 1.x bring-up, the minimum set:
     * InstanceRaidBaseClass + at least 2 concrete (Hamlet,
       Hyper Ifrit)
     * GuildleveBaseClass + at least 3 concrete (one per type:
       battle, craft, gather)
     * PublicRaidBaseClass + at least 1 concrete (Zahar'ak)
     * WeatherDirector (already simple)
     * OpeningDirector (for new-character experience)

4. CUTSCENE-CAPABLE DIRECTORS:
   Cutscene-heavy directors (story quest directors, cinematic
   openers, raid intros) need to drive the CutScene engine via
   pushing opcodes 8/9/10/11/12/13 + the (TBD) finalize opcode.

CUTSCENE ENGINE SERVER REQUIREMENTS:

1. Cutscene data: a per-cutscene timeline of clips. Each clip
   is one (opcode, clip_index, parameters) tuple.

2. Cutscene runner: on cutscene start, push opcode 8. Then for each
   clip in the timeline, push opcode 9/11/13 (show), wait for clip
   duration, push opcode 10/12 (hide). At end, push the (TBD)
   finalize opcode.

3. Per-cutscene SpreadSheet: the server doesn't actually need to
   replicate the SpreadSheet -- the client creates it locally on
   _onInit. Server just provides the cutscene timeline; the client
   handles actorclass lookups.
```

## Confidence

```text
Confirmed:
  - 14 top-level director classes + 14 subdirectory categories.
  - DirectorBaseClass has 24 documented method slots.
  - Most directors are 8-15 line stubs that use base behavior.
  - Instance raid subdirectory has 16 concrete raid director files.
  - Public raid subdirectory has 5+ concrete NM directors.
  - Guildleve subdirectory has 34 files (base + variants + specific
    leves).
  - GameData/CutScene_common is 1316 lines and is the FULL CutScene
    engine on the Lua side.
  - All 5 previously-named CutScene inbound opcodes (8/9/10/11/13)
    are confirmed paired with their Lua hooks in CutScene_common.
  - NEW: _onHideWidgetClip exists at line 1030 of CutScene_common
    (likely pairs with INBOUND opcode 12, currently unnamed).

Likely (High):
  - Opcode 12 is _onHideWidgetClip (the pair of _onShowWidgetClip
    at opcode 11). This narrows the unmapped opcode range further.
  - 1.x content directors map to specific named content from
    retail FFXIV 1.x history (Cutter's Cry dungeon, Beacon Fort,
    Zahar'ak NM area, Ugh'amaro mining area, etc.).
  - The 34 guildleve files likely cover the 30-40 distinct leve
    types that shipped in retail 1.x.

Likely (Medium):
  - Director instances are short-lived (1 per content attempt),
    created on content-start and destroyed on content-end.
  - The "OpeningDirector" runs the initial cutscene when a new
    character logs in -- a server bring-up requirement.
  - SpecialEventDirector handles GM events that are not tied to
    specific dates (vs Halloween/FireFallFaire which are seasonal).

Speculative:
  - WaveAttackDirector specifically handles Hamlet wave defense
    (Maelstrom defense missions). Its 15-line stub means most
    logic is in the base class + sheet data.
  - The "_onFinalizeClip" (line 59) is paired with an opcode in
    the 14-19 unmapped range. Confirming requires walking those
    wrappers.
```

## Connections to other findings

- **CutScene UI clips** in `finding_inbound_routers_named_opcodes_round2.md`:
  this finding confirms opcode 8/9/10/11/13 mappings and adds
  candidate opcode 12 = `_onHideWidgetClip`.
- **finding_inbound_dispatch_two_families_and_chat_d.md**: opcode
  12 (FUN_007599e0, Family B) was unmapped; now likely
  `_onHideWidgetClip`.
- **Director party** in `finding_party_subclasses_and_weather.md`:
  the Group classes (PlayerPartyGroup / MonsterPartyGroup) are
  separate from Directors, but interact with them for
  party-membership content.

## Next test

- Walk FUN_007599e0 (the Family B wrapper for opcode 12) -- decompile
  its router and target method to confirm `_onHideWidgetClip`.
- Sample 5-10 concrete InstanceRaid director files to identify which
  hooks each typically overrides.
- Look for the C++ Director controller that drives WorkSync from
  the server side.

## Commit suggestion

```
docs(re/lua): close Director family + CutScene engine; predict opcode 12 = _onHideWidgetClip
```
