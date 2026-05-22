# Finding: NPC Event System — Talk / Emote / Push Flow + Chara Scheduler IDs

After the player work-sync system, the next-most-impactful client
surface area for a server is **NPCs**. This finding catalogs the NPC
base class, its event dispatch (Talk / Emote / Push), the
"client-turn" dialog protocol, and the per-emote chara-scheduler ids
that drive NPC body language during conversation.

Sources read:

```text
chara/npc/npcbaseclass.lua            12.7 KB  (parent class for all NPCs)
chara/npc/npcbaseclass_event.lua      21.6 KB  (dialog + event flow)
chara/npc/npcbaseclass_u.lua           4.4 KB  (native binding table; not read in
                                                detail here)
chara/npc/npcbaseclass_battle.lua      2.0 KB  (battle behaviour additions)
chara/npc/npcdefault.lua               0.4 KB  (concrete default NPC stub)
```

Deciphered from `729s9/wu7/` on disk.

## Three event types, three (request, event, rejected) triples each

`NpcBaseClass` implements three orthogonal interaction types, each
with its own 3-stage flow:

```text
Type     Request hook            Event hook              Rejected hook
-------  ----------------------  ----------------------  ----------------------
Talk     _onTalkRequest          _onTalkEvent            _onTalkRejected
Emote    _onEmoteRequest         _onEmoteEvent           _onEmoteRejected
Push     _onPushRequest          _onPushEvent            _onNoticeRejected
                                                          (re-used for push)
```

Plus shared support:

```text
_onEventCancel                event externally cancelled (server pull-out)
_onReaction                   reaction to another actor's nearby action
delegateEvent                 route an event between actors
```

So the **request -> event -> (accepted | rejected)** state machine
is mirrored across all three interaction types. A typical flow:

```text
1.  Local player presses interact key on an NPC
    -> client sends a "talk request" packet to server
2.  Server validates (player in range? NPC available?)
3.  If accepted:
    -> server sends NPC:_onTalkEvent(...) -> NPC runs its dialog
    -> Lua handles say/ask UI; player sends back chosen index
4.  If rejected:
    -> server sends NPC:_onTalkRejected(reason)
    -> NPC's _onTalkRejected logs / shows error
5.  Either side can cancel mid-flow:
    -> _onEventCancel fires, both sides cleanup
```

## "Client-turn" dialog protocol

The dialog turn protocol is documented across four NpcBaseClass_event
methods:

```text
startCliantTalkTurn(self, mode, player)        -- (sic "Cliant" typo preserved)
startCliantTalkTurnNoWait(self)
waitCliantTalkTurn(self)
finishCliantTalkTurn(self)
```

(Yes, the binary really does spell it "Cliant" instead of "Client".)

`startCliantTalkTurn(self, mode, player)`:

```text
mode == 1:  full body turn + look
  - get player position via player:_getPos()
  - get NPC current direction via self:_getDir()
  - compute relative orientation via self:_getOrientation(playerPos)
  - if orientation > 1.047 rad (~60deg) or < -1.047 rad:
       turn the NPC body via self:_turnDir(currentDir + orientation)
  - look at player via self:_lookAtCharacter(player, 1)
mode == 2:  look only (no body turn)
  - self:_lookAtCharacter(player, 0.5)
mode == 3:  no-op (already facing)
```

`finishCliantTalkTurn`:

```lua
self:_turnBack()         -- restore original facing
self:_cancelLookAt()     -- release look constraint
```

So a typical "NPC turns to face you when you talk" sequence is:

```text
client_turn_start (mode 1)
  -> body rotates if angle > 60deg
  -> head lock onto player
[dialog plays out]
client_turn_finish
  -> body returns to original facing
  -> head lock releases
```

Native bindings used in this flow:

```text
_getPos        on actor: returns (x, y, z)
_getDir        on actor: current facing radians
_getOrientation(targetX, targetY, targetZ): radians delta needed to face target
_turnDir(absoluteRad)     turn body to absolute angle
_lookAtCharacter(target, headWeight)   lock head to target with weight 0..1
_waitForTurning           yield until turn completes
_turnBack                 restore body facing
_cancelLookAt             release head lock
_runCharaScheduler(id)    play a CharaScheduler animation by id
```

## NPC `normalTalkStep0` — the chara-scheduler emote map

When an NPC starts a normal-talk dialog, the LUA invokes a CharaScheduler
animation chosen by an emote variation index passed in the packet.
Pinned mappings (emote index `A3` -> scheduler id):

```text
emoteIdx   scheduler id  delta from baseline
--------   ------------  -------------------
 -1        (none; silent talk)
  0        403087360     baseline + 5*0x1000
  1        403066880     baseline (= 0x18098000)
  2        403070976     baseline + 0x1000
  3        403075072     baseline + 2*0x1000
  4        403079168     baseline + 3*0x1000
  5        403083264     baseline + 4*0x1000
  6        403087360     baseline + 5*0x1000  (same as idx 0)
  7        403091456     baseline + 6*0x1000
  8        403095552     baseline + 7*0x1000
  (8 dup)  403099648     baseline + 8*0x1000  (dead branch; duplicate case 8)
```

So **scheduler ids are 0x1000-spaced in a flat array**:

```text
0x18098000  emote variant 1
0x18099000  emote variant 2
0x1809A000  emote variant 3
0x1809B000  emote variant 4
0x1809C000  emote variant 5
0x1809D000  emote variant 6 (default = idx 0 and idx 6)
0x1809E000  emote variant 7
0x1809F000  emote variant 8
0x180A0000  emote variant 9 (unreachable; duplicate case 8)
```

The `0x180XXXXX` prefix is the "Chara Scheduler timeline" ID space; the
lower bits index into the per-NPC schedule table. A server that wants
an NPC to perform a specific gesture during a dialog line can include
the emote index 0..8 in the talk-event packet payload.

After playing the scheduler, `normalTalkStep0` calls
`desktopWidget:showMessage(npc, 38, msg, ...)` with channel **38**:

```text
desktopWidget channel id    purpose            invoked by
------------------------    -----------------  ----------------------
32                          notify log         WorldMaster:notify
33                          alert log          WorldMaster:alert
38                          NPC say            NpcBaseClass:normalTalkStep0 + say
40                          chat say           WorldMaster:say
```

So channel 38 is the **NPC dialog channel** (vs 40 for player-side chat).

## `say` and the choice-dispatching `ask` family

`NpcBaseClass:say(message, ...)` — variadic message + extras. Wraps
`desktopWidget:showMessage(self, 38, message, ...)`.

`NpcBaseClass:ask(...)` and variants (`askRestrictChoices`,
`askExtendWidget`, `askForCustomizeOption`) parallel the WorldMaster
ask family: they call `desktopWidget:askForEventMode(...)` and yield
the NPC's coroutine until the player picks an option. Return value is
the choice index (or -3 for cancel, normalised to nil).

So NPC dialog uses **the same UI primitives** as WorldMaster /
HarvestJudge / NegotiationJudge — `desktopWidget:askForEventMode` is
the universal "show dialog, wait for choice" yield point in the
client.

## Native binding map (high-impact subset, from npcbaseclass_u.lua)

(Not fully read, but the pattern matches WorldMaster / PlayerBase. The
single binding already pinned:)

```text
5001  npcWork.actorClassId   -- the NPC's class id (see finding_bindwork_catalog.md)
```

Other NPC bindings likely exist (face stat, allegiance, scheduler
default, etc.); a full inventory would require reading
npcbaseclass_u.lua in its entirety.

## `getCategoryIcon` and the nameplate hook

`NpcBaseClass:getCategoryIcon()` returns the category icon used by
`DepictionJudge:judgeNameplate` (see `finding_depiction_judge_nameplate.md`)
slot 1 when the actor is an NPC. The implementation is a sheet lookup
on a per-NPC class id, returning multiple icons for sub-categories.

`NpcBaseClass:isMapMarkerVisibleForTalkable()` and
`NpcBaseClass:getMapMarkerTypeForTalkable()` are the queries the
DepictionJudge uses to decide if the NPC gets a map marker. They are
**not implemented in the base class** in any detail in the lines
read; subclasses provide the body.

## `getHateType`, `getCategoryIcon` — Battle / depiction integration

```text
NpcBaseClass:getHateType()       -- consulted by DepictionJudge color
NpcBaseClass:getCategoryIcon()   -- consulted by DepictionJudge slot-1 icon
```

Both feed into the nameplate rendering documented earlier. A test
server populating NPCs needs to ensure both return sensible values for
each NPC instance.

## Assessment

```text
Confirmed:
  - NpcBaseClass implements 3 event types (Talk / Emote / Push) each
    with (request, event, rejected) variants -- 9 hook methods total
    plus shared eventCancel/Reaction/delegate.
  - The "client turn" dialog protocol is 3-state: startCliantTalkTurn
    (mode 1/2/3) -> dialog -> finishCliantTalkTurn (turn back +
    cancel look).
  - DesktopWidget channel 38 is the NPC dialog channel (38 vs 40 for
    player chat).
  - Chara scheduler ids 0x18098000..0x1809F000 are the NPC dialog
    emote variants (indices 1..8 in the talk-event packet payload).
  - NpcBaseClass uses the same desktopWidget:askForEventMode primitive
    as every other interactive subsystem.

Likely (High):
  - "Cliant" is a SE typo, not a different concept. The dialog turn
    flow is "Client" turn.
  - The 0x180XXXXX scheduler-id space is allocated in a structured
    way: each NPC class has its own scheduler block, and the dialog
    emote variants for that class are at offsets 0..8 within the block.
  - Each NPC class probably has a unique scheduler block; the 5001
    actorClassId binding determines which block applies.

Likely (Medium):
  - The "Push" event type means "physical bump / push" (not the
    HTTP-style push). A player walking into an NPC may trigger a
    pushRequest.
  - The "Reaction" event is the NPC reacting to a nearby action by
    a player (e.g. NPC says "Hey, watch it!" when player draws sword
    near them).

Speculative:
  - The scheduler-id base 0x18098000 might be a 1.x-specific
    convention; later FFXIV builds may have renumbered.
  - The duplicate case for emoteIdx 8 (two branches both labelled 8;
    second is unreachable) is probably a copy-paste bug in the
    decompiled source that maps to a single bytecode jump table.

Next test:
  - Read npcbaseclass.lua's initWork / initWorkSyncTag to find the
    full NPC work schema (similar to player_work.lua but for NPCs).
  - Read npcbaseclass_battle.lua for combat-side NPC bindings (the
    2 KB file).
  - Decompile npcbaseclass_u.lua (4.4 KB) for the complete native
    binding table.

Commit suggestion:
  docs(re/lua): NPC event system + talk dialog protocol + chara
                scheduler ids
```

## Server implication

A server that wants to populate a zone with interactive NPCs needs:

1. **Per-NPC initial state push**:
   - actorClassId via binding 5001
   - position + facing (via the C++ movement controller, not Lua)
   - hateType + categoryIcon (sheet lookups; the server just sets the
     actor's class)

2. **Talk dialog flow** (on player interact):
   - Receive `_onTalkRequest` from client.
   - Validate (range, NPC state).
   - Send `_onTalkEvent` with (npcActorId, scriptId, scriptParams).
   - Optionally include emote variation idx 0..8 in payload for body
     language.
   - Wait for player's choice indices (sent back via player's
     command/event channel).
   - Conclude via `_onEventCancel` or natural end.

3. **Push & emote interactions** follow the same pattern.

4. **Per-class scheduler ids** are pre-allocated in the client's
   sheet data; the server only needs to know the NPC's actorClassId
   and the emote index 0..8 to drive any animation. No custom
   animation pushes are needed.

5. **Nameplate rendering** requires the server to keep the actor's
   hateType + battalion + isNotoriousMonster + property bitset in
   sync via the bindings catalog
   (`finding_bindwork_catalog.md`).
