# Finding: Judge System -- NOT a Permission Gate, but the Data-Provider + Depiction (Nameplate) Layer

**Corrects the interpretation of the "judge" system.** The 5 judge
categories (Common/Battle/Craft/Harvest/Negotiation) that CommandBase
references are NOT a permission/validation gate as initially assumed.
The judge system is the **shared CSV data-provider for game
calculations + the visual depiction (nameplate/relationship) resolver**.

Judge dir (0p635): JudgeBaseClass (111) + DepictionJudge (814) +
CommonJudge (51) + a few context judges (chocobo/tutorial) + mostly
EMPTY per-category subdir stubs.

## 1. The judge categories are mostly thin stubs

```text
Per-category judge subdirs are 8-line _defineClass STUBS:
  0p635/89qqy5/ (BattleJudge)        -- stub
  0p635/7s94q/ (CraftJudge)          -- stub
  0p635/97q1vw/ (ActionJudge)        -- stub
  0p635/39x579y7py9q5/ (GameCalculate)-- stub
  0p635/89qqy5usv75rr/ (BattleProcess)-- stub
  0p635/9pqv9qq97z/ (AutoAttack)     -- stub
  0p635/w53vq19q1vw/ (Negotiation)   -- stub
  0p635/1q5x/ (Item)                 -- stub

So the judge CATEGORIES exist as classes but the per-category logic
is NOT centralized in the judge system. The actual validation +
calculation is DISTRIBUTED into:
  - Command canFire/fire (per CommandBase finding)
  - Status/item level-adjust formulas (per Status finding)
  - charabaseclass judgeRelation (combat hostility, prior finding)
```

## 2. CommonJudge = the shared calc-table data provider

```text
CommonJudge.init loads the SHARED game-calculation CSVs:
  itemData         item stats
  equipment        equipment data
  weapon           weapon stats
  armor            armor stats
  accessory        accessory stats
  gameCommand      command/action definitions
  gameCommandBasic basic command data
  compatibility    item/level compatibility curves
  exp_BPCost       experience / battle-point costs

CommonJudge is the DATA HOLDER -- it loads (via prepareSpreadSheet ->
SpreadSheet actors) the tables that ALL game calculations reference:
  - Item stat calc (itemData/equipment/weapon/armor/accessory)
  - Command potency (gameCommand/gameCommandBasic)
  - Level-adjust growth (compatibility)
  - Cost/exp formulas (exp_BPCost)

So "isJudgedAtCommonJudge" means: this command uses the CommonJudge's
data tables for its calculations. The judge CATEGORY = which CSV
data context the command/calc uses, NOT a permission check.
```

## 3. DepictionJudge = nameplate / relationship resolver

```text
DepictionJudge (814 lines) -- the substantial judge. Determines how
an actor is VISUALLY DEPICTED (nameplate icon/color) based on the
viewer's relationship to it:

DepictionJudge.judgeNameplate(self, targetActor):
  myPlayer = worldMaster:_getMyPlayer()
  party = myPlayer:getPlayerParty()
  contentGroup = myPlayer:getCurrentContentGroup()

  IF in a content group (kind 30001 or 30006):
    if target is a content member + property 3 enabled:
      target:_setNameplateIcon(1, 1, 246)   -- content member icon

  ELSE if target isPlayer:
    - get linkshell icon
    - check net stat system (online status, mode 2)
    - set nameplate based on linkshell / online state

  (continues for party / enemy / npc relationship -> nameplate colors)

So DepictionJudge resolves the FRIEND/PARTY/CONTENT/LINKSHELL/ENEMY
visual state -> nameplate icon + color. This is the visual side of
judgeRelation (charabaseclass), applied to nameplates.

Content group kinds: 30001, 30006 (instance content rosters)
```

## 4. Corrected judge system model

```text
THE JUDGE SYSTEM IS:
  1. DATA PROVIDER (CommonJudge): loads the shared calculation CSVs
     (itemData/equipment/weapon/armor/gameCommand/compatibility/exp_BPCost)
     used by ALL game calculations
  2. DEPICTION RESOLVER (DepictionJudge): nameplate/relationship visuals
  3. CONTEXT JUDGES (chocobo, tutorial, etc.): specific-context data

THE JUDGE SYSTEM IS NOT:
  - A command permission gate (that's command canFire + server validation)
  - A centralized combat calculator (that's distributed in commands/status)

The command's "isJudgedAtXJudge" flag = which DATA CONTEXT / calc-table
set the command uses, routing to the appropriate judge's loaded CSVs.

This fits the client-side-content principle:
  - Judge = client-side CSV data aggregation + visual depiction
  - The CSVs (itemData/equipment/gameCommand/etc.) are client-local
  - The server has its own copies for authoritative calculation
```

## 5. Server-side implications

```text
The judge system clarifies what CALC DATA the server needs:

SHARED CALCULATION TABLES (CommonJudge's set):
  itemData, equipment, weapon, armor, accessory  -- item/gear stats
  gameCommand, gameCommandBasic                  -- command potency
  compatibility                                  -- level-adjust curves
  exp_BPCost                                     -- exp/cost formulas

These are the tables the SERVER needs for authoritative calculation
(damage, stat totals, command potency, level-adjust). The client uses
them for prediction/display; the server uses them for authority.

DEPICTION (nameplate) is PURELY CLIENT-SIDE:
  - The server provides relationship STATE (party membership, content
    group, linkshell, online status -- via WorkSync/group packets)
  - The client computes the nameplate icon/color (DepictionJudge)
  - The server NEVER sends nameplate colors -- only the relationship data

This reinforces the principle: server sends STATE (who's in your party,
what content group), client computes PRESENTATION (nameplate visuals).
```

## 6. Confidence

```text
Confirmed:
  - Per-category judge subdirs are 8-line _defineClass stubs
  - CommonJudge loads 9 shared calc CSVs (itemData..exp_BPCost)
  - DepictionJudge (814) resolves nameplate/relationship visuals
  - Content group kinds 30001/30006 (instance rosters)
  - judge = data provider + depiction, NOT permission gate

Likely (High):
  - The "isJudgedAtXJudge" flag = which calc-data context applies
  - Combat validation is distributed (command canFire + judgeRelation +
    server), not centralized in BattleJudge
  - The calc CSVs are the server's authoritative calculation tables
  - DepictionJudge is purely client-side (server sends state, not visuals)

Speculative:
  - The empty per-category judges may have been fuller in other 1.x
    patches (or the logic moved to commands)
  - Nameplate icon (1,1,246) = a specific content-member indicator
  - exp_BPCost = the battle-point / experience cost curves for actions
```

## 7. Cross-references

- `finding_commandbaseclass_action_model.md` -- the 5 judge categories
  commands reference (clarified here as data contexts)
- `finding_combat_relations_and_potencial.md` -- judgeRelation (the
  combat-hostility logic; DepictionJudge is its visual counterpart)
- `finding_statusbaseclass_status_effect_engine.md` -- uses the
  compatibility / growth curves CommonJudge loads
- `finding_csv_complete_correlation_132_of_164_critical_mapped.md` --
  the 9 CSVs CommonJudge loads (server calc tables)
- `finding_relation_group_family.md` + content groups (DepictionJudge
  uses getCurrentContentGroup)

## 8. Next test

```text
1. Read the rest of DepictionJudge (party/enemy/npc nameplate cases)
2. Confirm the calc CSVs map to server-authoritative formulas
3. Move to remaining base mechanics: item (1q5x) or group (3svpu)
4. Map nameplate icon codes (friend/party/enemy/content colors)
```

## Commit suggestion

```
docs(re/lua): judge system clarified -- NOT a permission gate; CommonJudge = shared calc-CSV data provider, DepictionJudge = nameplate/relationship resolver; per-category judges are stubs
```
