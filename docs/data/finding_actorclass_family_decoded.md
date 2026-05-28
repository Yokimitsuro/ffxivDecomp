# Finding: actorclass Family Decoded (actorClassId -> name + appearance + map-object)

**Decodes the actorclass table family** -- the actor-class master that
the spawn system keys on. Resolves the open gap from the 99-table audit
(actorclass was sparse in decode_csv). Confirmed: **actorclass.csv maps
actorClassId -> displayName id** (the localized NAME); the richness lives
in the sibling tables actorclass_graphic (appearance) and
actorclass_mapObj (map-object params). raw_csv and decode_csv are
identical here -- actorclass.csv genuinely IS a thin id->name map.

## 1. actorclass.csv (7984 rows) -- the actor-class master

```text
Structure: actorClassId -> ONE s32 = displayName id
  (6 columns, only the last col populated; same in raw_csv and decode_csv)

CONFIRMED by resolving the ref through xtx_displayName.csv:
  actorClass 1000001 -> displayName 1900006 -> "Y'shtola"  (ヤ・シュトラ)
  actorClass 1000002 -> displayName 1600179 -> "Sthalmann" (スタルマン)
  actorClass 1000003 -> displayName 1600217 -> "Waekbyrt"
  actorClass 1000005 -> displayName 1600150 -> "Rostnsthal"
  actorClass 6000001 -> displayName 1500032 -> "Dedela"

So actorclass.csv is the ID -> NAME spine: every spawnable actor class
(NPC, monster, object, PC template) maps to its localized display name.
The name itself is in xtx_displayName (5-language, CLIENT-LOCAL).

WHY decode_csv was "sparse": there is no text IN this table to decode;
it holds a single numeric ref. decode_csv == raw_csv. The table is
simply thin by design -- the detail is split into the sibling tables.
```

## 2. actorClassId TYPE TAXONOMY (2-digit key prefix)

```text
The actorClassId's leading 2 digits classify the actor type:

Prefix  Count   Type (inferred from resolved names)
------  -----   -----------------------------------
10      2979    NAMED NPCs (story/Scions: Y'shtola, Sthalmann, ...)
21      1392    monster family A
22      1190    monster family B
12       557    NPCs (secondary)
15       437    NPCs / named (Dedela = 15xxxxx name range)
60       372    objects / special class A
30       226    class C
91       190    class (event/system?)
16       145    NPCs
69       120    objects B
50       101
23        80
65        48
17        44
59        38
68        35
92        24
90         5

The prefix is the actor CATEGORY selector. (Exact category labels need
cross-reference with the spawn class-name strings in the 0x17c packet,
but the named-NPC cluster (10/12/15/16) vs monster clusters (21/22) vs
object clusters (60/68/69) is clear from sampled names.)
```

## 3. actorclass_graphic.csv (7831 rows) -- the APPEARANCE block

```text
Same actorClassId key -> 40-col s32 appearance/customization block
(active cols 6-46). The character LOOK data the client renders.

Column clusters (from samples):
  cols 6-8    body selectors: race/tribe, model-type, gender/size
              0(template): 1,2,2   1000001(Y'shtola): 8,2,4
  col 11      skeleton/scale flag (32 for real actors vs 2 template)
  cols 21-23  color/feature indices (hair/skin/eye): 17,11,9 / 20,6,12
  col 24-25   PACKED appearance/equipment bits (large ints):
              331351046 / 147850241 / 243270686
  cols 33-36  model part / color values: 4387,5347,1024,5443
              (1024 = default; template row is all 1024)

This is the NPC's full visual customization: race/gender/body +
hair/skin/eye + equipment + model parts. CLIENT-LOCAL (the server
spawns by class id; the client renders the look from this table).
```

## 4. actorclass_mapObj.csv (160 rows) -- map-OBJECT params

```text
A SUBSET of actor classes (ids 1080078+) that are MAP OBJECTS
(doors, elevators, gimmicks, interactables) rather than characters.
-> 2 s32 (cols 47-48): (objectType, gimmickGraphicId)

  1080078 -> 303, 10405
  1080079 -> 301, 12386
  1080080 -> 301, 12391
  1080123 -> 0, 0        (no gimmick)

objectType ~300-303 = object category; second value = the gimmick/
graphic id (ties to the gimmick* / object* event scripts, per the
zone-object Lua findings). 160 map-object classes total.
```

## 5. The complete actor-class model

```text
A SPAWNABLE ACTOR CLASS is composed across 3 tables, keyed by actorClassId:

  actorclass.csv          -> NAME (displayName id -> xtx_displayName)
  actorclass_graphic.csv  -> APPEARANCE (race/gender/body/colors/model)
  actorclass_mapObj.csv   -> MAP-OBJECT params (for object-type classes)

SPAWN LINKAGE (ties to the wire protocol):
  - Server sends spawn 0x17c with a CLASS NAME string (+0x44 in packet)
  - Client resolves class name -> Lua class -> actorClassId
  - Client looks up NAME (actorclass) + LOOK (actorclass_graphic) locally
  - Client renders the actor; server never sends name or appearance

This is the CLIENT-SIDE-CONTENT principle AGAIN (7th confirmation):
  SERVER: spawns by class id/name + tracks state (WorkSync)
  CLIENT: owns the actor's name + full appearance (these tables)

SERVER DATA NEED: the server needs the actorClassId SPACE (which classes
exist + their type) to spawn correctly -- but NOT the name or graphic
columns (client-local). actorclass.csv's id list = the spawn registry;
the displayName/graphic refs are presentation the client resolves.
```

## 6. Confidence

```text
Confirmed:
  - actorclass.csv = actorClassId -> displayName id (verified: Y'shtola,
    Sthalmann, Waekbyrt, Rostnsthal, Dedela all resolve correctly)
  - raw_csv == decode_csv for actorclass (single numeric ref; no text)
  - actorclass_graphic = 40-col appearance block (cols 6-46), same key
  - actorclass_mapObj = 160 map-object classes -> (objType, gimmickId)
  - 2-digit key prefix = actor type category

Likely (High):
  - graphic cols 6-8 = race/model-type/gender; cols 21-23 = hair/skin/eye
  - graphic col 24-25 = packed equipment/appearance bits
  - mapObj objType ~300-303 = object category; col48 = gimmick graphic
  - prefix 10/12/15/16 = NPCs, 21/22 = monsters, 60/68/69 = objects

Speculative:
  - exact race/tribe enum values in graphic cols 6-8
  - the packed-int encoding in graphic cols 24-25
  - precise category label per actorClassId prefix (needs spawn-string xref)
```

## 7. Cross-references

- `finding_99_data_tables_verification_audit.md` -- this closes the
  actorclass gap noted there
- `finding_spawn_wire_side_CLOSED_opcode_0x17c_...md` (docs/re/exe) --
  the 0x17c spawn packet carries the class NAME string (+0x44) that
  resolves to actorClassId
- `finding_gear_variant_tables_are_localized_text_CORRECTION.md` --
  xtx_displayName (the name table actorclass references)
- `finding_populace_and_shop_csv_structure.md` -- populace (NPC instances)
  vs actorclass (NPC class definitions)
- `finding_npc_event_talk_turn_flow_client_side.md` -- NPC behavior (Lua)

## 8. Note on populace vs actorclass

```text
Two related but distinct masters:
  actorclass.csv  = actor CLASS definitions (the "type": name + look)
                    7984 classes
  populace.csv    = NPC INSTANCES placed in the world (4209)
A populace NPC instance references an actorClass for its name/appearance,
then adds placement/behavior (talk type, zone). actorclass = the template;
populace = the placed instance.
```

## Commit suggestion

```
docs(data): decode actorclass family -- actorclass=actorClassId->displayName id (verified: Y'shtola/Sthalmann/...); actorclass_graphic=40-col appearance; actorclass_mapObj=160 map-object params; raw==decode (thin id->name map); closes audit gap
```
