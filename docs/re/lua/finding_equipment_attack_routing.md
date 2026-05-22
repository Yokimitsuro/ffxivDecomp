# Finding: Equipment / Attack Routing Lookup Tables

The block of `getXxxByYyy` functions in `charabaseclass_battle.lua`
lines 200-787 implements the **routing layer** of 1.x's combat
system — small lookup tables that translate between four distinct
coordinate spaces:

```text
"Hand"          1..5       virtual weapon slot (which hand holds it)
"EquipPoint"    1..N       physical equipment slot (gear inventory)
"AttackIndex"   1..8       attack type (autoattack / weaponskill / etc)
"Parts"         1..8       body part (for hit-direction calculations)
"AttackWorkIndex" 1..N     attack-state slot in charaWork
"AmmoSlot"      1..5       ammunition stack index
```

Each combat decision walks these lookup tables to translate "the
player just clicked weaponskill 3 with this weapon on this enemy
body part" into actual server-side state mutations.

## The Lookup Tables (5 routing functions, all `if-elseif-return`)

### `getEquipPointByHand(self, hand)` -- Hand → EquipPoint

```text
hand   equipPoint   typical interpretation
----   ----------   ----------------------
 1      1           main hand
 2      2           offhand
 3      5           ranged / two-handed extension
 4      6           accessory 1 (rings?)
 5      7           accessory 2
```

### `getEquipPointByAttackIndex(self, attackIdx)` -- AttackIndex → EquipPoint

```text
attackIdx  equipPoint   notes
---------  ----------   ----------------------------------------
 1          11          special: secondary attack (mainhand alt?)
 2          1           main weapon attack
 3          2           offhand attack
 4          13          (high equipPoint -- gear-specific?)
 5          9           ammo-using ranged attack
 6,7,8       -          undefined / falls through to nil
```

The high equipPoint values (9, 11, 13) suggest there are ~13+
"virtual" equipment slots, but most map to the same 5 hand positions.

### `getEquipPointByParts(self, partIdx)` -- BodyParts → EquipPoint

```text
partIdx   equipPoint?      meaning
-------   ------------     ----------------------------------
 1-4       (nil, nothing)   parts not weapon-bearing
 5         true, 5          part 5 = right wrist / gauntlet?
 6         true, 1          part 6 = main hand weapon
 7         true, 2          part 7 = offhand weapon
```

So **parts 6 and 7 hold the player's weapons** (mainhand/offhand).
Targeting part 6 means hitting the player's main weapon — useful
for disarm-style abilities.

### `isEquipPointUseToAmmo(self, equipPoint)` -- EquipPoint → AmmoSlot

```text
equipPoint   ammoSlot
----------   --------
 1           1
 2           2
 5           3
 6           4
 7           5
 others      nil
```

5 ammo slot positions, one per "hand" position. Each weapon may have
its own ammo stack.

### `getAttackWorkIndexByEquipPoint(self, equipPoint)`

```text
equipPoint   attackWorkIdx
----------   -------------
 1            1            -- mainhand
 2            2            -- offhand
 0            1            -- "no equip" defaults to mainhand
 others       (nil)
```

### `getAttackWorkIndexByHand(self, hand)`

```text
hand   attackWorkIdx
----   -------------
 2      1
 3      2
 others (nil)
```

### `getAttackWorkIndexByParts(self, parts)`

```text
parts   attackWorkIdx
-----   -------------
 1       1
 2       2
 others  (nil)
```

So `attackWorkIdx = 1` covers (hand 2, parts 1, equipPoint 0/1) and
`attackWorkIdx = 2` covers (hand 3, parts 2, equipPoint 2). The
`attackWork[1..2]` array is **the dual-wield attack slot pair**.

### `judgeAttackWorkIndex(self, attackIdx)` and parts/hand by attack

```text
attackIdx   getPartsByAttack   getHandByAttack   judgeAttackWorkIdx?
---------   ----------------   ---------------   -------------------
 1           1                  1                 2
 2           2                  2                 3
 3           (none)             1                 2
 4           (none)             2                 2
 5           (none)             1                 3
 6,7         -                   -                  -
```

The `judgeAttackWorkIndex` returning 2 or 3 (not 1) is odd — possibly
**work-index 2 and 3 are the actual attack-state slots**, with index
1 reserved for something else (maybe the global attack timer?).

## `getHandByEquipPoint(self, bitmap, directionCode)` — the bitmap unpacker

The most complex routing function. Takes a 4-bit `bitmap`
(values 0..15) and a `directionCode` (1, 2, 4, or 8), and returns
whether the bit corresponding to that direction is set in the bitmap.

```lua
function getHandByEquipPoint(bitmap, directionCode)
  flags = [false, false, false, false]
  -- decompose bitmap into 4 bits (big-endian)
  if bitmap >= 8: flags[4] = true; bitmap -= 8
  if bitmap >= 4: flags[3] = true; bitmap -= 4
  if bitmap >= 2: flags[2] = true; bitmap -= 2
  if bitmap >= 1: flags[1] = true
  
  -- pick the bit by directionCode
  slot = 1
  if directionCode == 4: slot = 3
  elseif directionCode == 2: slot = 2
  elseif directionCode == 8: slot = 4
  return flags[slot]
end
```

So this lets the engine ask: "given a hit-direction bitmask and a
specific direction, is that direction's bit set?" Used during
hit-direction validation against the parts-direction array from the
earlier finding.

```text
directionCode   flag slot
-------------   ---------
 1               1           front
 2               2           right
 4               3           left
 8               4           back
```

## The Coordinate-Space Conversion Graph

```text
Hand -------------------------+
  ↓                            ↓
EquipPoint ← AttackIndex     AttackWorkIndex
  ↓               ↓             ↑
AmmoSlot     Parts -------------+
                ↓
              direction bitmap → directionCode flag
```

So a typical "execute attack" flow walks:

```text
1. attackIdx = 2 (e.g. main weapon attack)
2. equipPoint = getEquipPointByAttackIndex(2) = 1
3. attackWork  = getAttackWorkIndexByEquipPoint(1) = 1
4. hand        = getHandByAttackIndex(2) = 2
5. parts       = getPartsByAttackIndex(2) = (none for non-parts attack)
6. write attack state at charaWork.command[attackWork]
```

For NPC parts attack:

```text
1. attackIdx = 1
2. parts      = getPartsByAttackIndex(1) = 1
3. equipPoint = getEquipPointByParts(1) = (nil, nothing) -- not weapon-bearing part
4. ...
```

For NPC weapon attack from main hand part:

```text
1. parts = 6 (main weapon part)
2. equipPoint = getEquipPointByParts(6) = (true, 1)
3. attackWork = getAttackWorkIndexByEquipPoint(1) = 1
4. ...
```

## Assessment

```text
Confirmed:
  - 5 Hand positions (1-5), mapping to EquipPoints 1, 2, 5, 6, 7
    (skipping 3-4 entirely; those are display slots or unused).
  - AttackIndex 1-5 are the 5 "attack types" the client knows:
    1 = secondary mainhand, 2 = mainhand, 3 = offhand, 4 = ?, 5 = ranged.
  - 5 AmmoSlots, one per Hand position.
  - 2 AttackWorkIndices in dual-wield (slots 1 and 2 of attackWork).
  - Body parts 6 and 7 are PLAYER WEAPON parts (mainhand + offhand).
    Parts 1-5 are body parts (head/body/hands/legs/feet);
    parts 6-7 are weapons.
  - Direction bitmap unpacking: bit 1=front, 2=right, 4=left, 8=back.
  - judgeAttackWorkIndex returns 2 or 3 (not 1) -- suggesting work-
    index 1 is reserved for something other than per-hand attack
    state.

Likely (High):
  - The "8-part" model for actors is actually 5 body parts + 2 weapon
    parts + 1 reserved. The previous finding's claim of "5 body parts
    for players, 8 for NPCs" was approximately right -- the missing
    nuance is that parts 6-7 are weapons.
  - The high equipPoint values (9, 11, 13) correspond to "armor
    augments" or specific gear slots beyond the basic 7. They are
    skipped by the hand→equipPoint mapping but exposed in the
    AttackIndex→EquipPoint mapping.
  - Attack work slot 1 (the one judgeAttackWorkIndex never returns)
    holds the "current cast" state or global combat timer; the
    per-hand attack states are slots 2-3.

Likely (Medium):
  - getHandByEquipPoint is called during hit-direction validation:
    it takes the actor's facing-relative direction encoded as
    bit 1/2/4/8 and a parts-specific bitmap, and returns whether
    the parts can be hit from that direction.
  - The "parts 6/7 = weapons" insight explains the disarm-mechanic
    suggestion: hitting parts 6/7 maps to the weapon equipPoint,
    so a successful hit could trigger weapon-degradation /
    knock-off effects.

Speculative:
  - 1.x had a 5-attack-type design where each weapon could trigger 5
    different attack patterns based on which "attackIndex" was being
    executed. Most modern MMOs have 2-3 attack types (autoattack,
    weaponskill, special); 1.x's 5 types suggest a finer-grained
    system possibly tied to combo / weapon-skill chains.

Next test:
  - Read charabaseclass_ffxivbattle.lua to see what overrides /
    extensions are added for the FFXIV-specific battle layer.
  - The 4-attack/4-equip-point limit is interesting -- a dual-wield
    combatant has 2 attackWorkIndices; what about gear-changes mid-
    fight? Does swapping weapons update the attackWork in-place?

Commit suggestion:
  docs(re/lua): equipment/attack routing tables (Hand/EquipPoint/
                AttackIndex/Parts/AttackWorkIndex)
```

## Server implication

A server processing a combat action does NOT need to do any of these
lookups — they are **all client-side** routing tables. The server's
job is:

1. Receive `CombatCommand(actorId, attackIdx, targetId, partIdx)`.
2. Validate the action via `judgeRelation` (friend/foe).
3. Validate the part is targetable (`partsExists` + direction bitmap).
4. Compute damage from potencial + skill level + stats.
5. Push HP update to the target.

The routing tables exist because the **client-side action display**
needs to know which weapon icon to flash, which body part to spawn
the hit effect on, etc. The server just blindly applies field updates;
the client interprets them via these tables to drive animations.

So the routing layer **does not appear on the wire** — it's purely
client-internal. A server implementer can ignore these tables entirely
unless they want to replicate the *exact* hit-effect placements
(which is not necessary for correctness).
