# Finding: `DepictionJudge` Is the Actor Nameplate Renderer

Read of the deciphered `judge/depictionjudge.lua` (23 KB, 814 lines).
Despite its size and rank as the biggest top-level judge, it
implements **a single method**: `judgeNameplate(self, actor)`.

The name "depiction" was misleading: it doesn't handle weather /
lighting / time-of-day. It handles **how each visible actor's
nameplate is decorated** — which icons, in which slots, in which
colours — based on the actor's state and its relation to the local
player.

Source read:

```text
judge/depictionjudge.lua    0p635/65u17q1vw0p635.lua    (23 KB, 814 lines)
```

## Headline result

A nameplate has **4 icon slots** plus a **nameplate colour** for each
slot. `DepictionJudge:judgeNameplate(actor)` is the function the
client runs **per visible actor per frame (or per relevant tick)** to
decide the entire nameplate appearance.

Method shape:

```text
judgeNameplate(self, actor):
  fetch local context:
    myPlayer        = worldMaster:_getMyPlayer()
    myParty         = myPlayer:getPlayerParty()
    myContent       = myPlayer:getCurrentContentGroup()
    myOccupancy     = myParty:_getOccupancyGroup()

  for each slot in 1..4:
    decide iconId based on actor's queries + my-context
    actor:_setNameplateIcon(slot, layer=1, iconId)

  for each colour band:
    decide colour based on actor's queries
    actor:_setNameplateColor(slot, colour)
```

**No server traffic**. The function is a pure local renderer: it
queries the actor's state (which the actor object holds because the
server already pushed it via Player/Chara updates) and writes into
the actor's nameplate via two native primitives.

## The four nameplate slots and their decision logic

### Slot 1 — Group / Identity / Linkshell

```text
if (myContent kind == 30001 or 30006) and myContent:isMember(actor)
    and actor:isPropertyEnabled(3):
  -> icon 246   (content-group member-indicator)

elif actor:isPlayer():
  if actor:_getNetStatSystem(2):  -> icon 312   (system net-status flag 2)
  elif actor:_getNetStatSystem(1): -> icon 313  (system net-status flag 1)
  elif actor:_getNetStatUser(...):  -> icon 314  (user net-status flag)
  elif actor:getLinkshellIconId() > 0:
        -> icon (40000 + linkshellIconId)  -- LS icon range 40001..
  else: -> icon 0  (clear)

else (NPC):
  catIcon, ... = actor:getCategoryIcon()
  -> icon catIcon   (NPC category)
  or clear
```

### Slot 2 — Vendor / Combat marker

```text
if actor:isRetailDealer():
  -> icon 220   (vendor)

elif not actor:isPlayer() and actor:isPropertyEnabled(3)
     and actor:getBattalion() ~= 1:    -- not friendly
  if actor:getAggro() > 0:
    -> icon 517   (NM with aggro on me)
  else:
    -> icon 518   (NM idle)
else:
  -> icon 0  (clear)
```

### Slot 3 — Crafting service

```text
if actor:getRepairType() ~= 0:
  -> icon 928   (player offering repair service)

elif actor:isRepairDealer():
  -> icon 380   (NPC repair dealer)

elif actor:isMateriaAttachDealer():
  -> icon 929   (materia melder)
else:
  -> icon 0
```

### Slot 4 — Target / Retainer marker

```text
if actor:isPropertyEnabled(3):
  if actor:getTargetInformationOpenThinking() ~= 0
     and myParty:_isMember(actor):
    -> icon (304 + openThinking - 1)
        -- 304..305..   "thinking" sub-state, party-member only
  elif actor:getTargetInformationPartyTarget() ~= 0
       and myContent:_getKind() == 30001  -- party raid
       and myContent:_isMember(actor):
    -> icon (296 + partyTarget - 100)
        -- 197..       party-target sub-state
  else:
    -> icon 0

elif not actor:isPlayer() and actor:isRetainer()
     and actor:_getSystemFlag(1):
  -> icon 456   (active retainer)

else:
  -> icon 0
```

So **slot 4 is the "you-target-me" / "I'm-targeted-by-party" /
"retainer" indicator** — a combined indicator that takes priority
order over multiple meanings.

## Nameplate colour decisions (21 callsites)

`_setNameplateColor(slot, colour)` is invoked 21 times across the
function in branches gated by:

```text
isDeadMode             -> dead colour
isPlayer + relation    -> party / friend / hostile / neutral
getHateType            -> hate level colour (red gradients?)
isNotoriousMonster     -> NM colour
getBattalion           -> faction colour
isMapMarkerVisibleForTalkable + getMapMarkerTypeForTalkable
                       -> talk-target colour
getMapMarkerRange      -> in/out-of-range colour
isRetainer + _getSystemFlag(1)
                       -> retainer colour
```

Exact colour values were not extracted (would require reading the
specific branches). The branching depth shows colour rendering is
**at least as complex as icon rendering**, with weighted overrides
based on combat/relation/state.

## Actor-side query surface (the server's obligation)

For `judgeNameplate` to function correctly on every visible actor,
the server has to push enough state into each actor object that the
following client-side queries return useful values. Pinned in this
file:

```text
isPlayer                              true for player actors
isRetainer                            true for retainer actors
isRetailDealer                        NPC: sells items
isRepairDealer                        NPC: repairs gear
isMateriaAttachDealer                 NPC: attaches materia
isDeadMode                            actor is dead (no HP)
isNotoriousMonster                    NM flag
isPropertyEnabled(propertyId)         actor property bitset; id 3 seen
                                      ("important" / "trackable")
isMapMarkerVisibleForTalkable         shows a map marker when in range

getLinkshellIconId                    main linkshell icon id (1..N or 0)
getCategoryIcon                       NPC category icon (multi-return,
                                      additional icons for sub-classes)
getBattalion                          faction enum; 1 == friendly (others
                                      = neutral/hostile)
getAggro                              aggro level toward local player (0=none)
getHateType                           hate state enum (multiple levels)
getRepairType                         repair-service type the actor offers
getParty                              actor's own party (for inter-party
                                      colour decisions)
getTargetInformationOpenThinking      "thinking about being targeted"
                                      sub-state (1..N)
getTargetInformationPartyTarget       "party member is targeting me"
                                      sub-state (>=100 used as offset)
getMapMarkerTypeForTalkable           map-marker type for talkable NPCs
getMapMarkerRange                     range threshold for showing marker
_getSystemFlag(flagId)                actor system flag (flagId 1 used)
_getNetStatSystem(flagId)             net status system flag (1..2 used)
_getNetStatUser(...)                  net status user flag(s)
```

That's roughly **20 fields per visible actor** that the server has
to populate (or the client has to derive locally) for nameplates to
render correctly.

## Icon-id table (compact)

```text
0         clear / no icon

slot 1 (identity / linkshell / category)
  246    content-group member indicator (party-raid leader?)
  312    net-status system flag 2 (away/busy?)
  313    net-status system flag 1
  314    net-status user flag
  40001+ linkshell icons (one per LS)
  ...    NPC category icons (from getCategoryIcon, range TBD)

slot 2 (vendor / NM)
  220    retail dealer (vendor)
  517    NM with aggro on player
  518    NM without aggro

slot 3 (crafting services)
  380    repair dealer (NPC)
  928    player offering repair
  929    materia attach dealer

slot 4 (targeting / retainer)
  296+x  party-target sub-state (x = partyTarget - 100)
  304+x  party-member "thinking" sub-state (x = openThinking - 1)
  456    active retainer
```

## Content group "kind" values

```text
30001   party raid (a standard party-based content group)
30006   another content kind, distinct from 30001 (TBD; possibly
        Company / GC group or instance raid)
```

Both kinds satisfy the slot-1 "content-group member indicator"
branch. The exact distinction would clarify whether each is "party
raid" vs "company raid" vs "behest" vs "instance raid".

## Assessment

```text
Confirmed:
  - DepictionJudge implements exactly one method, judgeNameplate.
  - The method has no server traffic; it is a pure local renderer
    reading actor state and writing nameplate icon/colour via two
    native primitives _setNameplateIcon and _setNameplateColor.
  - There are 4 icon slots per nameplate, each with its own
    decision branch.
  - There are ~20 actor-side queries the function relies on; the
    server must keep these populated for nameplates to render.

Likely (High):
  - DepictionJudge is invoked by the C++ side on every relevant
    actor-state change (the actor is "depicted" -> nameplate
    refreshed). It is not a sheet-loader judge and not on a server
    sink. It is the "rendering policy" for the nameplate.
  - The icon IDs 246, 220, 517/518, 928/929, 380, 456 are stable
    text/icon sheet entries the client expects to find in its icon
    sheet at boot. Server doesn't need to send them.

Likely (Medium):
  - Content-group "kind" 30001 is "party-raid"; 30006 is one of
    "company raid" / "behest" / "instance-raid". Confirmation
    requires reading the few callsites of _getKind in other judges.
  - Slot 1 also serves as the GC/grand-company icon slot when the
    actor is a player with no other competing indicator; the
    branching shows linkshell icon as the fallback rather than the
    primary, suggesting the upstream GC branch is in a code path I
    haven't read (probably 580..814 of this file or somewhere in
    the actor's property bag).

Speculative:
  - The reason DepictionJudge alone among judges is hooked to the
    isJudgedAtCommonJudge / etc. flag system is because every
    visible-actor refresh runs it without command id selection:
    no command id implies "use the depiction default". This would
    explain why it's listed under judges/ even though it doesn't
    consume server packets like CraftJudge / NegotiationJudge.

Next test:
  - Read lines 350..814 of this judge to extract the nameplate
    colour decision tree (21 setNameplateColor sites) and any
    further property-id / icon-id constants.
  - Read judge/hatecontrol/hatecontroljudge.lua to learn how
    getHateType is computed (the source of slot-1's colour band).
  - Read CharaBaseClass to find the schema entries backing each of
    the ~20 actor queries (which playerWork / charaWork fields each
    is a façade for).

Commit suggestion:
  docs(re/lua): DepictionJudge implements judgeNameplate (4 icon
                slots + 21 colour rules; ~20 actor queries)
```

## Server implication (consolidated)

1. **Every nameplate update is server-pushed indirectly.** A server
   doesn't send "set nameplate icon X" packets; it sends actor-state
   updates (party, linkshell, dead, aggro, hate, system flags) and
   the client's DepictionJudge re-renders the nameplate. The
   server's responsibility is **the underlying state**, not the
   visual layer.
2. **~20 fields per visible actor** must be kept current. Highest
   wire priority among them are the ones that change frequently:
   `getAggro`, `getHateType`, `isDeadMode`, `getTargetInformationPartyTarget`,
   `_getNetStatSystem`. The rest are infrequent or boot-time.
3. **`isPropertyEnabled(3)` is the universal "this actor is
   important / trackable"** gate that opens slot 4 (targeting
   indicator). Without it, the actor renders as a "background" actor
   with no targeting marker. Bots and ambient NPCs probably leave
   this disabled.
4. **Linkshells are first-class on slot 1.** The icon range 40001+
   suggests up to N linkshells per server with stable icon ids.
   Server bring-up needs LS icon ids to be consistent with what the
   client's sheet contains, or LS icons will display wrong.
5. **No client-side computation of the actor's "name" itself** is
   visible here. Nameplate icons + colour are the depiction;
   the name string comes from the actor's own data (getName,
   getTitle, getFreeCompany) which DepictionJudge does not touch.
   Those are likely set directly via actor-state packets.
