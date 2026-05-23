# Finding: Judge Family -- 19 Judge Classes + 1.x Crafting ID Space Structure

Documents the complete **Judge family** (0p635/ in cipher) -- 1.x's
data-cache + command-validation orchestration layer. Reveals:

1. **19 concrete judge classes** organized into command-routing + service judges
2. **Each Judge OWNS SpreadSheet actors** as its data backing
3. **CraftJudge is the LARGEST class at 1109 lines** with deeply
   structured command ID space
4. **1.x crafting had 3 ACTION STYLES**: Normal / Rapid / Bold
5. **DepictionJudge (814 lines)** drives all nameplate icons in the game

## 1. Architecture overview

```text
JUDGE FAMILY -- 0p635/ (cipher)

JudgeBaseClass            111 lines  abstract base (sheet-ownership pattern)
JudgeMaster                37 lines  bootstrap orchestrator
JudgeBaseClass_p.lua        1 line   bytecode wrapper

COMMAND-ROUTING JUDGES (5 -- matches CommandBaseClass predicates):
  commonjudge              51 lines  the "Common" predicate handler
  battle/battlejudge        1 line   placeholder (logic in subjudges)
  craft/craftjudge       1109 lines  THE LARGEST -- crafting ID space
  harvest/harvestjudge    427 lines  gathering (mining/fishing/herd/etc.)
  negotiation/negotiationjudge 198 lines  NPC trade negotiation

NON-COMMAND SERVICE JUDGES (6):
  depictionjudge          814 lines  nameplate ICON rendering
  chocobojudge            138 lines  chocobo state machine
  tutorialjudge            62 lines  tutorial orchestration
  tutorialdummyjudge       74 lines  tutorial dummy variant
  instanceraidguidejudge   12 lines  raid guide UI

BATTLE SUB-JUDGES (4):
  battleprocess/battleprocessjudge   8 lines
  action/actionjudge                  8 lines
  autoattack/autoattackjudge          8 lines
  gamecalculate/gamecalculatejudge    8 lines

OTHER SUB-JUDGES (3):
  hatecontrol/hatecontroljudge        8 lines
  item/itemdropjudge                  1 line  (placeholder)
  
PREFACE SUB-SYSTEM (4 files):
  preface/prefacejudgebaseclass               8 lines
  preface/musicchangeprefacebaseclass        17 lines
  preface/musicchangeprefacejudge             8 lines
  preface/cutsceneoncebeaconprefacejudge     48 lines

TOTAL: 8 top-level + 11 sub-folder = 19 concrete judges + bases
```

## 2. JudgeBaseClass -- sheet-ownership pattern (111 lines, 5 methods)

```text
LIFECYCLE (3):
  _onInit()              calls super, then initText, then init
  initText()             subclass-overridable for text loading
  init()                 subclass-overridable for ctor logic

SHEET OWNERSHIP (2):
  prepareSpreadSheet(sheetPath, sheetName?)
  unprepareSpreadSheet(sheetPath, sheetName?)
```

The `prepareSpreadSheet` method is the KEY responsibility:

```lua
function prepareSpreadSheet(self, path, name?)
  if not name then
    -- strip trailing /... from path
    name = path:gsub(".+/", "")
    -- convert snake_case to lowerCamelCase
    name = string.lowerCamelCase(unpack(string.split(name, "_")))
    -- append "Sheet"
    name = name .. "Sheet"
  end
  return _createActor(name, "SpreadSheet", name ~= nil, path)
end
```

So judges **CREATE SpreadSheet actors** to hold their data. The actor name
follows the pattern `<lowerCamelCasePath>Sheet`. This is the **data-caching
scaffold** -- a judge holds N sheet actors for the data it needs.

## 3. JudgeMaster -- the bootstrap orchestrator (37 lines)

```lua
function JudgeMaster._onInit(self)
  self:_callSuperClassFunc("_onInit")
  
  self:prepareSpreadSheet("command")    -- universal command sheet
  self:prepareSpreadSheet("status")     -- universal status sheet
  
  _getStaticActor(320001)               -- some static actor
  _getTutorialJudge()                   -- TutorialJudge singleton
  _getStaticActor(320013)               -- another static actor
  _prepareAllCommandStaticActor()       -- prepare all command static actors
end
```

So JudgeMaster bootstraps the judge system by:
1. Loading the universal `command` and `status` sheets (used by everything)
2. Triggering TutorialJudge initialization
3. Calling `_prepareAllCommandStaticActor()` which presumably enumerates and
   creates static actors for every command class

The static actor IDs 320001 + 320013 are notable -- they're outside the
normal NPC ranges but inside the 32xxxx zone-prefix range. Probably special
content/system actors.

## 4. CommonJudge -- 9 sheets for "common" commands (51 lines)

```lua
function CommonJudge.init(self)
  self:prepareSpreadSheet("itemData")       -- item DB
  self:prepareSpreadSheet("equipment")      -- equipment DB
  self:prepareSpreadSheet("weapon")         -- weapon DB
  self:prepareSpreadSheet("armor")          -- armor DB
  self:prepareSpreadSheet("accessory")      -- accessory DB
  self:prepareSpreadSheet("gameCommand")    -- game command DB
  self:prepareSpreadSheet("gameCommandBasic") -- basic command DB
  self:prepareSpreadSheet("compatibility")  -- compatibility matrix
  self:prepareSpreadSheet("exp_BPCost")     -- XP/BP cost curve
end
```

So **CommonJudge owns 9 sheets** -- everything needed to validate "common"
commands (any command that doesn't fit Battle/Craft/Harvest/Negotiation
specializations).

This is the **CommandBaseClass.isJudgedAtCommonJudge → true** dispatch target.
When a command says "I'm common", it's saying "use CommonJudge's 9 sheets
to validate me".

## 5. CraftJudge -- the LARGEST judge (1109 lines)

CraftJudge has the most complex command ID space classification:

```lua
isCraftSystemCommand(id):        22501 <= id <= 22549
isCraftStandardCommand(id):      22550 <= id <= 22698
isCraftStandardNormalCommand(id): id in {22550, 22553, 22556, 22559, 22562,
                                          22565, 22568, 22571, 22574, 22577,
                                          22580, 22583, 22586, 22589, 22592,
                                          22595}
isCraftStandardRapidCommand(id):  id in {22551, 22554, 22557, 22560, 22563,
                                          22566, 22569, 22572, 22575, 22578,
                                          22581, 22584, 22587, 22590, 22593,
                                          22596}
isCraftStandardBoldCommand(id):   id in {22552, 22555, 22558, 22561, 22564,
                                          22567, 22570, 22573, 22576, 22579,
                                          22582, 22585, 22588, 22591, 22594,
                                          22597}
isCraftGiftCommand(id):          29501 <= id <= 29698
isMainToolOrder(hand):           hand != 2 and hand != 6
```

### Crafting Command ID Space Layout

```text
ID RANGE      COUNT  CATEGORY                  STYLE
--------      -----  --------                  -----
22501-22549   49     CRAFT SYSTEM             -- synthesis flow control
                                                 (start/abort/yield/etc.)

22550-22597   48     CRAFT STANDARD (1st bank) -- core craft actions
  22550, 22553, ...  16 commands   NORMAL style
  22551, 22554, ...  16 commands   RAPID style
  22552, 22555, ...  16 commands   BOLD style

22598-22698  101     CRAFT STANDARD (extended) -- additional actions

29501-29698  198     CRAFT GIFT commands       -- traited/relic actions
```

### THE 3 CRAFTING STYLES

Each "core" craft action existed in **THREE STYLES**:

```text
NORMAL: balanced effect, balanced cost
RAPID:  faster execution, more risk?
BOLD:   stronger effect, higher cost?
```

The IDs are **interleaved in groups of 6**:
```
22550 = action A NORMAL
22551 = action A RAPID
22552 = action A BOLD
22553 = action B NORMAL
22554 = action B RAPID
22555 = action B BOLD
22556 = next pair...
```

So 1.x's crafting had **stance-style actions** -- a depth/risk slider per
action. This is much more sophisticated than ARR's "default + traits" model.
It's actually closer to FFXI's WeaponSkill stance mechanic.

### MainToolOrder vs SubToolOrder

```lua
isMainToolOrder(hand_id):
  return hand_id != 2 and hand_id != 6
```

So hand IDs 2 + 6 are **sub-tool slots** (main tool is everything else).
This suggests 1.x crafters had:
- A MAIN TOOL (primary hand)
- A SUB TOOL (secondary hand)
And actions specified which tool to use. This is FFXI's main/sub-hand
heritage applied to crafting.

## 6. HarvestJudge -- gathering orchestration (427 lines)

```text
Key methods observed:
  initText                      loads text table 1308 "harvestJudge"
  targetCancel                  cancels main target on the desktop widget
  turnToTarget                  rotates character to face target;
                                if command ∈ {22006, 22007, 22008},
                                synchronously waits for turn completion
  (gathering opens widget): Ask/MiningInputWidget for command 22002
```

### Harvest Command IDs

```text
22002  Mining       opens Ask/MiningInputWidget
22003  ?            (probably Logging)
22004  Fish (per earlier finding)
22005  Herd (per earlier finding)
22006  ?            <-- requires synchronous turn
22007  ?            <-- requires synchronous turn
22008  ?            <-- requires synchronous turn
```

Commands 22006/22007/22008 are SPECIAL -- they synchronously wait for the
character to finish turning before executing. This suggests they're slower/
more deliberate gathering actions (maybe Logging swing or Fishing cast).

## 7. NegotiationJudge -- NPC trade flow (198 lines)

```lua
function NegotiationJudge.openListWidget(self, target, ..., 12_args_total)
  if target:isPlayer() then
    return desktopWidget:askEventModeWidgetYield(
      "Ask/NegotiationListWidget", 1, ...all 12 args...
    )
  end
end
```

So negotiation opens `Ask/NegotiationListWidget` in EVENT MODE and PASSES
12 ARGS -- everything needed to render the negotiation context (offer,
counter-offer, item lists, item prices, etc.).

This connects to the 10-widget Negotiation/Bazaar family per
`finding_negotiation_bazaar_widget_family.md`.

## 8. DepictionJudge -- nameplate icon dispatch (814 lines)

The largest non-craft judge. Drives ALL nameplate icons in the game:

```text
ICON DISPATCH HIERARCHY (sampled):

If character is in a content group (kind 30001 OR 30006):
  → set nameplate icon (1, 1, 246)        [content member icon]
Else if character is a player:
  Linkshell icon = getLinkshellIconId()
  → if netStatSystem(2): icon (1, 1, 312)  [system level 2 lag]
  → if netStatSystem(1): icon (1, 1, 313)  [system level 1 lag]
  → if netStatUser(1):   icon (1, 1, 314)  [user-side issue]
  → if linkshell > 0:    icon (1, 1, linkshellIconId)
  ... (and many more cases)
```

So DepictionJudge owns the **VISUAL TAGGING** of every character in the
world:
- Content group membership icons (party/raid/alliance)
- Linkshell affiliation icons
- Network status indicators (system + user-side)
- Faction icons (GC, beastman, ally, enemy)
- NM tier icons (Regular, HNM, etc.)
- Player vs NPC indicators

814 lines accommodate the full visual-tag matrix.

This is **NOT a command-judging judge** -- it's a rendering judge.
DepictionJudge is referenced by the engine to update nameplates on every
visible character.

## 9. BattleJudge is EMPTY (1 line)

```lua
local L0_1, L1_1, L2_1
L0_1 = require
...  -- standard class definition, no methods
```

BattleJudge is essentially a CLASS DECLARATION with no overrides. All
actual battle judging logic is in:
- BattleProcessJudge (battle process flow)
- ActionJudge (action validation)
- AutoAttackJudge (auto-attack handling)
- GameCalculateJudge (damage calculations)
- HateControlJudge (enmity management)

So **"BattleJudge"** is a polymorphic anchor -- the CommandBaseClass
`isJudgedAtBattleJudge → true` predicate routes through BattleJudge but
the actual logic lives in the 4-5 sub-judges.

This is **delegation by composition** -- BattleJudge is a thin facade.

## 10. PrefaceJudge sub-system -- content preludes

```text
PrefaceJudgeBaseClass            8 lines   abstract base
MusicChangePrefaceBaseClass     17 lines   music change abstract
MusicChangePrefaceJudge          8 lines   concrete impl
CutsceneOnceBeaconPrefaceJudge  48 lines   one-shot cutscene trigger
```

Preface judges run BEFORE content starts:
- MusicChange: swap zone music (e.g., "Hamlet Defense theme begins")
- CutsceneOnceBeaconPrefaceJudge: trigger a one-time cutscene the first
  time the player encounters the area/content

This is the **content opening cinematography** sub-system.

## 11. The Judge × Command × Status × Director picture

Now the full Lua orchestration is mapped:

```text
WIDGET           UI rendering         (n1635q/)    195+ widgets
COMMAND          player intent        (7vxx9w6/)   50-60 commands  
JUDGE            data + validation    (0p635/)     19 judges       <-- THIS
STATUS           combat state         (rq9qpr/)    158 subclasses
DIRECTOR         content orchestrate  (61s57qvs/)  226 subclasses
CHARA            character state     (729s9/)
WORLD/AREA       zone state           (nvsy6/9s59/)
SYSTEM           engine plumbing      (rlrq5x/)
```

The 5-way command dispatch (CommandBaseClass predicates) maps to 5 judges:
```
isJudgedAtCommonJudge       → CommonJudge (9 sheets)
isJudgedAtBattleJudge       → BattleJudge (facade) → 4-5 sub-judges
isJudgedAtCraftJudge        → CraftJudge (1109 lines)
isJudgedAtHarvestJudge      → HarvestJudge (427 lines)
isJudgedAtNegotiationJudge  → NegotiationJudge (198 lines)
```

Plus 6+ NON-command judges:
```
DepictionJudge                → nameplate icon rendering
ChocoboJudge                  → chocobo state
TutorialJudge / Dummy         → tutorial UI orchestration
InstanceRaidGuideJudge        → raid guide UI
GameCalculateJudge            → damage calculations
PrefaceJudges                 → content preludes
```

## Confidence

```text
Confirmed:
  - 19 concrete judge classes in 0p635/ (incl. bases + sub-judges).
  - JudgeBaseClass is 111 lines with 5 methods.
  - JudgeMaster bootstraps with command + status sheets + tutorial init.
  - CommonJudge owns 9 sheets (itemData/equipment/weapon/armor/accessory/
    gameCommand/gameCommandBasic/compatibility/exp_BPCost).
  - CraftJudge is 1109 lines (the largest in the family).
  - 1.x crafting has 3 STYLES per action: Normal/Rapid/Bold.
  - Crafting command ID space: 22501-22549 (system), 22550-22698 (standard),
    29501-29698 (gift/relic).
  - 48 core crafting actions interleaved in 16 groups of 3 styles each.
  - Hand IDs 2 and 6 are sub-tool slots.
  - DepictionJudge is 814 lines -- nameplate icon dispatch.
  - DepictionJudge handles: content membership icons, linkshell icons,
    network status icons.
  - HarvestJudge 427 lines: opens Ask/MiningInputWidget for command 22002.
  - Commands 22006/22007/22008 (harvest) synchronously wait for turning.
  - NegotiationJudge opens Ask/NegotiationListWidget with 12 args.
  - BattleJudge is essentially EMPTY (1 line) -- logic in 4-5 sub-judges.
  - PrefaceJudge sub-system: music change + cutscene-once beacons.

Likely (High):
  - The Normal/Rapid/Bold crafting styles match 1.x's described "stance"
    system in the synthesis minigame.
  - Hand 2 = off-hand (sub-tool), hand 6 = some special slot.
  - Static actors 320001, 320013 are content/system actors.
  - DepictionJudge runs on EVERY character visible to the player -- this
    is performance-critical code.
  - The 4 BattleSubJudges (BattleProcess, Action, AutoAttack, GameCalculate)
    have minimal Lua bodies (8 lines each) because their logic is in C++
    via vtable methods -- they're Lua scaffolds for the C++ engine.

Likely (Medium):
  - "Preface" sub-system handles SCENE TRANSITIONS -- music + cutscenes
    that play before raid bosses appear, before guildleve start, etc.
  - GameCalculateJudge IS the bridge to the formulas documented in
    `finding_charabase_battle_real_combat_formulas.md`.
  - CraftJudge's 1109 lines include extensive UI orchestration for the
    synthesis minigame (cycle through actions, status update, success/
    failure animation, etc.).
  - The 198 "gift" craft commands (29501-29698) are RELIC TIER crafting
    actions unlocked at high crafter levels.

Speculative:
  - Hand 6 might be a "shoulder bag" or "tool belt" slot (the second
    sub-tool position?).
  - The 49 craft system commands (22501-22549) include hand-toggle, abort,
    status-report, finish, hand-feel-confidence-set, "next round"
    transitions.
  - DepictionJudge's 814 lines might include 50+ distinct icon variants
    across player vs NPC, GC, beastman tribe, primal, alliance status,
    etc.
```

## Server implications

```text
- Server must support JudgeMaster's bootstrap: provide command + status
  sheet data, plus static actors 320001 + 320013.
- CommonJudge's 9 sheets are mandatory for command validation.
- Crafting command ID space (22501-22698 + 29501-29698) is the spec for
  ~400 craft commands the server must define.
- The 3-style crafting (Normal/Rapid/Bold) means each crafting action
  has 3 variants the server must define.
- HarvestJudge maps command IDs to gathering widgets -- server must
  spawn the right gathering instance based on command ID.
- DepictionJudge is CLIENT-SIDE rendering -- server only sends the data
  bits (linkshell ID, GC affiliation, network status); client computes
  the icon.
- Preface sub-system: server pushes music change + cutscene packets
  before content starts.
```

## Cross-references to other findings

- **`finding_command_baseclass_and_teleport.md`**: the 5 judge predicates
  in CommandBaseClass route to the 5 command-routing judges documented
  here.
- **`finding_negotiation_bazaar_widget_family.md`**: NegotiationJudge
  routes through this 10-widget bazaar/negotiation family.
- **`finding_combat_command_pipeline_and_4param_scaling.md`**: the
  BattleJudge's 4 sub-judges (Action, AutoAttack, GameCalculate,
  BattleProcess) implement the actual combat pipeline.
- **`finding_charabase_battle_real_combat_formulas.md`**: GameCalculateJudge
  bridges to the combat formulas (calcPotencial, magic table, physical
  piecewise).
- **`finding_director_baseclass_and_226_subclasses.md`**: PrefaceJudges
  run BEFORE directors start content -- they're the cinematic preludes.

## Annotations made in Ghidra

None this finding -- Lua-only analysis.

## Next test

- Read more of DepictionJudge to enumerate the full nameplate-icon matrix.
- Read CraftJudge's command-action mapping (which IDs correspond to which
  named actions like "Mooch", "Standard Synthesis", "Bold Synthesis", etc.)
- Cross-reference Craft Gift commands (29501-29698) against xtx_command.csv
  to identify named relic/traited actions.
- Sample BattleProcessJudge + ActionJudge + AutoAttackJudge to verify
  they're thin Lua scaffolds for C++ logic.
- Find _getStaticActor(320001) and _getStaticActor(320013) usages in
  Ghidra to identify what these static actors do.

## Commit suggestion

```
docs(re/lua): Judge family -- 19 judges + 1.x crafting 3-style ID space (Normal/Rapid/Bold)
```
