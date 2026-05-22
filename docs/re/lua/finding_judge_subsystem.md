# Finding: Judge Subsystem — Bootstrap, Base Class, "Everything Is An Actor" Pattern

Reading of the deciphered `judge/` corpus root: `judgemaster.lua`,
`judgebaseclass.lua`, `commonjudge.lua`, `chocobojudge.lua`. Companion
to `finding_command_baseclass_and_judges.md`.

Sources read:

```text
judge/judgemaster.lua          0p635/0p635x9rq5s.lua          (743 B)
judge/judgebaseclass.lua       0p635/0p63589r57y9rr.lua       (2.3 KB)
judge/commonjudge.lua          0p635/7vxxvw0p635.lua          (1.1 KB)
judge/chocobojudge.lua         0p635/72v7v8v0p635.lua         (2.4 KB)
```

Plus directory listing of `judge/` (16 top-level scripts + 11 subdirs).

## Headline insights

1. **Everything in the client is an actor.** Commands, SpreadSheets,
   Judges, World service, Player, NPCs — all are actor objects with
   either a static id (system singletons) or a dynamic name.
2. **`JudgeMaster:_onInit` is the bootstrap** for the whole outcome
   subsystem: it pre-loads the command and status sheets, the
   tutorial judge, the chocobo rider, and crucially calls
   `_prepareAllCommandStaticActor()` which materialises every
   command in the sheet as a live static actor.
3. **`prepareSpreadSheet(self, name)`** on JudgeBaseClass is the
   factory for sheet actors. It builds the name
   `"<lowerCamelCase(name)>Sheet"` and calls
   `_createActor(actorName, "SpreadSheet", isValid, source)` to spawn
   a live actor that wraps the sheet.
4. **Not every "judge" computes outcomes.** Some judges (CommonJudge)
   are pure data-prep singletons; others (ChocoboJudge) are
   state-query helpers; the *real* outcome math lives in subdirs
   under `judge/battle/`, `judge/craft/`, `judge/harvest/`,
   `judge/negotiation/`, `judge/action/`, etc.

## JudgeMaster bootstrap

```lua
require("/Judge/JudgeBaseClass")
_defineClass("JudgeMaster", "JudgeBaseClass")

function JudgeMaster:_onInit()
  self:_callSuperClassFunc("_onInit")
  self:prepareSpreadSheet("command")    -- the commandSheet documented elsewhere
  self:prepareSpreadSheet("status")     -- statusSheet (TBD)
  _getStaticActor(320001)               -- another system singleton (TBD)
  _getTutorialJudge()                   -- preload tutorial judge
  _getStaticActor(320013)               -- Chocobo Rider (known)
  _prepareAllCommandStaticActor()       -- materialise every command actor
end
```

Native bindings used (Lua-side names; the `_cpp` thunks live in EXE):

```text
_getStaticActor(id)              fetch a static actor by id
_createActor(name, type, ...)    create a dynamic actor
_getActorByName(name)            fetch a dynamic actor by name
_getTutorialJudge()              shortcut: fetch the tutorial judge actor
_prepareAllCommandStaticActor()  walk commandSheet and spawn each command
```

New static actor pinned:

```text
320001   <unknown system singleton, fetched at JudgeMaster boot>
```

The previously-pinned 320013 (Chocobo Rider) is also touched here,
confirming Chocobo Rider exists at boot regardless of whether the
player owns a chocobo.

`_prepareAllCommandStaticActor` is **the** big lever: after it runs,
every command id from the sheet exists as a live static actor that
Lua scripts can fetch via `_getStaticActor(id)`. This is why
`CommandBaseClass:getCommandId()` is identical to
`self:_getStaticActorID()` — the actor IS the command.

## JudgeBaseClass shape

```lua
function JudgeBaseClass:_onInit()
  self:_callSuperClassFunc("_onInit")
  self:initText()        -- subclass override
  self:init()            -- subclass override
end

-- both empty defaults
function JudgeBaseClass:initText() end
function JudgeBaseClass:init()     end

function JudgeBaseClass:prepareSpreadSheet(pathOrName, overrideName)
  local actorName = overrideName
  if not actorName then
    -- "/Sheet/foo/item_data" -> "itemDataSheet"
    local leaf = pathOrName:gsub(".+/", "")              -- last path comp
    local parts = string.split(leaf, "_")
    actorName = string.lowerCamelCase(unpack(parts)) .. "Sheet"
  end
  return _createActor(actorName, "SpreadSheet", actorName ~= nil, pathOrName)
end

function JudgeBaseClass:unprepareSpreadSheet(pathOrName, overrideName)
  -- inverse: derive name, then _getActorByName(name):_delete()
end
```

Two name-mangling rules confirmed:

- Path-to-name: keep last segment after the last `/`.
- Underscores split the name into words, each word is then
  lowerCamelCased and concatenated, with `"Sheet"` appended.

So a sheet referenced as `"/Sheet/Common/item_data"` becomes the actor
named `"itemDataSheet"`. This explains the `itemDataSheet`,
`equipmentSheet`, `weaponSheet`, ... actors that judges look up.

## CommonJudge = data-prep only

```lua
_defineClass("CommonJudge", "JudgeBaseClass")
function CommonJudge:init()
  self:prepareSpreadSheet("itemData")
  self:prepareSpreadSheet("equipment")
  self:prepareSpreadSheet("weapon")
  self:prepareSpreadSheet("armor")
  self:prepareSpreadSheet("accessory")
  self:prepareSpreadSheet("gameCommand")
  self:prepareSpreadSheet("gameCommandBasic")
  self:prepareSpreadSheet("compatibility")
  self:prepareSpreadSheet("exp_BPCost")
end
```

**No `canFire`, no `fire`, no `judge` method, no `_onReceiveDataPacket`**.
CommonJudge is a *singleton whose only job is to prepare the 9 sheets
that other judges will consult*. The name "Common" refers to the
shared sheets, not to a "common decision routine".

`isJudgedAtCommonJudge = true` (commandSheet col 30) on a command
therefore does NOT mean "outcome is computed by CommonJudge". It means
"this command's outcome computation will need access to the common
sheets (item, equipment, weapon, ...)". The actual decision is done by
whichever specific judge under the command's category.

## ChocoboJudge = state-query helper

```lua
_defineClass("ChocoboJudge", "JudgeBaseClass")

ChocoboJudge:isRiding(actor)
  -- actor:_getActorMainStat() == 15 ?
ChocoboJudge:isRidingChocobo(actor)
  -- mainStat == 15 AND _getChocoboRidingGrade(actor) ~= 257
ChocoboJudge:isRidingGoobbue(actor)
  -- mainStat == 15 AND _getChocoboRidingGrade(actor) == 257
ChocoboJudge:hasWhistle(actor)
  -- _getChocoboGrade(actor) ~= nil
ChocoboJudge:hasGoobbueWhistle(actor)
  -- _isEnabledGoobbue(actor) is truthy

ChocoboJudge:getRidingErrorTextId(actor, baseTextId)
  -- if riding Goobbue (grade 257), remap error text ids:
  --   26005 -> 26022     26013 -> 26029
  --   26010 -> 26024     26014 -> 26030
  --   32507 -> 32508     (default)
```

Pinned constants from this judge:

```text
actor main-stat enum value 15 = "riding" state
_getChocoboRidingGrade result 257 = Goobbue (vs any other = Chocobo)
text ids 26005/26010/26013/26014 are Chocobo-flavoured riding errors
text ids 26022/26024/26029/26030 are Goobbue-flavoured equivalents
text id 32507 = generic riding error; 32508 = generic goobbue-riding error
```

ChocoboJudge has no outcome logic at all. It is a **shared query
service**: any script that needs to check "is this actor currently
riding?" calls into the chocobo judge instead of duplicating logic.

This pattern recurs across the rest of the judge corpus: many judges
are query/utility wrappers, and only the math-heavy ones (battle,
craft, harvest, negotiation in their subdirs) compute outcomes.

## The full judge directory (16 top-level + 11 subdirs)

Top-level scripts (already deciphered in the catalogue):

```text
judgemaster                    boot + sheet preload
judgebaseclass                 parent
judgebaseclass_u               override (small)
commonjudge                    9 shared sheets preload
chocobojudge                   chocobo/goobbue state queries
tutorialjudge                  tutorial mode queries
tutorialdummyjudge             tutorial NPC dummy queries
depictionjudge                 23 KB - the biggest top-level - likely
                               weather / lighting / time-of-day
                               outcome routing
instanceraidguidejudge         instance-raid wayfinding
```

Subdirectories (each presumably contains specialised judges):

```text
judge/item            crafting/repair items
judge/negotiation     dialogue/persuasion outcomes
judge/gamecalculate   shared math helpers
judge/craft           craft mechanic outcomes
judge/hatecontrol     aggro/enmity adjustments
judge/harvest         gathering yield rolls
judge/battle          attack/damage rolls
judge/autoattack      auto-attack tick math
judge/predict         ??? (single dir, unread)
judge/battleprocess   battle phase transitions
judge/action          action-bar action outcomes
```

## "All is an actor" — actor id partitions (running list)

Updated tabulation:

```text
0..29999       gameplay commands (12014, 12015, 22001..22016, 23xxx, 24105)
24301..24999   instance/service objects (24301 Instance Raid)
30004          instance raid timer command
310001         WorldMaster
320001         ??? (new from JudgeMaster boot — TBD)
320013         Chocobo Rider service
```

Dynamic-name actors (no static id, fetched via `_getActorByName`):

```text
"<sheetName>Sheet"                e.g. "itemDataSheet", "equipmentSheet"
                                  - SpreadSheet wrappers around CSV-like
                                    sheet binaries
"CutScene"                        cutscene actors (createActor type)
"SpreadSheet"                     the type tag for all sheet wrappers
... plus many more TBD
```

The factory primitive on the EXE side is `_createActor(name, type,
isValid, sourceArg)`. Type tags observed so far: `"SpreadSheet"`,
`"CutScene"`. Many more exist (every actor class).

## Assessment

```text
Confirmed:
  - JudgeMaster:_onInit pre-loads commandSheet and statusSheet via
    prepareSpreadSheet, then materialises every command as a static
    actor via _prepareAllCommandStaticActor.
  - JudgeBaseClass:prepareSpreadSheet creates a SpreadSheet actor via
    _createActor(name, "SpreadSheet", ...).
  - The sheet name mangling rule is: leaf basename, underscores split
    into words, lowerCamelCase, append "Sheet".
  - CommonJudge has no outcome logic — only sheet preloading. The
    isJudgedAtCommonJudge flag therefore selects "needs common
    sheets", not "outcome computed by Common".
  - ChocoboJudge is a state-query helper, not an outcome computer.
    Pinned constants: mainStat 15 = riding, grade 257 = goobbue.

Likely (High):
  - The real outcome computers live in the 11 subdirectories under
    judge/. Of these, judge/battle/, judge/craft/, judge/harvest/,
    judge/negotiation/ are almost certainly the four flagged by
    commandSheet columns 30..34. The other dirs (action, autoattack,
    battleprocess, hatecontrol, gamecalculate, item, predict) are
    likely helper subsystems consumed by the main four.
  - 320001 is the JudgeMaster's own static actor id - JudgeMaster
    boot acquires the static actor to bind itself to it.

Likely (Medium):
  - depictionjudge (23 KB, the biggest top-level judge) handles
    visual depiction outcomes - weather, lighting, time-of-day
    transitions - hence its outsized size.
  - "predict" is a client-side prediction layer for combat (a kind of
    speculative outcome computation pending server confirmation).

Speculative:
  - That every isJudgedAt* command runs its judge LOCALLY on the
    client for prediction, then the server runs the same judge math
    authoritatively and ships a result packet that the client uses to
    correct. Confirming this requires reading a battle judge and a
    matching IPC handler.

Next test:
  - Read judge/battle/actionjudge.lua or judge/battle/battlejudge*.lua
    to see one concrete outcome computation. Look for damage roll,
    crit/miss check, enmity application.
  - Read judge/craft/craftjudge.lua to see the craft outcome math
    matching CraftProgressWidget.work (progress / quality deltas).
  - Inspect the EXE-side _createActor and _prepareAllCommandStaticActor
    bindings to learn the full actor-type registry.

Commit suggestion:
  docs(re/lua): document Judge subsystem and the "everything is an actor" pattern
```

## Server implication (additions)

1. **The server probably runs the same judge math as the client.**
   The judge subsystem is structured for *both* sides to compute
   outcomes from the same sheets — predict-on-client, authoritative-
   on-server. A clean server implementation can port the Lua judge
   directly (or, more efficiently, ship the sheets and let the
   client predict, then arbitrate only on divergence).
2. **Static actor 320001** must exist as some service object at
   server-recognised id. Treat it the same way as 310001
   (WorldMaster) and 320013 (Chocobo Rider): a system singleton with
   no spatial coordinates. Likely the JudgeMaster service itself.
3. **`_prepareAllCommandStaticActor` runs at boot**, meaning the
   client materialises every command from the sheet *before* any
   gameplay packet arrives. A server doesn't need to ship per-command
   "registration" packets; the sheet+id is enough.
4. **Sheet names matter.** The wire and the client agree on sheet
   names via the lowerCamelCase rule. If the server-side dump uses a
   different naming (e.g. snake_case literally), the actor names
   won't match. Pinned mappings:
   - `"item_data"  -> itemDataSheet`
   - `"gameCommand" -> gameCommandSheet`
   - `"gameCommandBasic" -> gameCommandBasicSheet`
   - `"exp_BPCost" -> expBpCostSheet`
   (note 'BP' becomes 'Bp' under lowerCamelCase — confirm by reading
   the actual sheet load if it matters.)
