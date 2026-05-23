# Finding: `ContentGroupBaseClass` — Content Membership / Director Linkage

The `ContentGroup` is the **player roster of an active content
instance** in 1.x. It links the player set to a Director (e.g. an
active InstanceRaid or CaravanGuard event), tracks content-induced
restrictions, and drives UI side-effects when membership changes.

This is the missing piece connecting the **Director pattern**
(content state) with the **Group pattern** (player set).

Sources read:

```text
group/ContentGroup/ContentGroupBaseClass.lua    411 lines
```

## Three-Way Linkage

```text
ContentGroup (player roster)
    │
    │ _globalTemp.director  -> ref to Director
    ↓
Director (content state)
   e.g. CaravanGuardDirector, InstanceRaidBaseClass instance
```

So:
- The **Director** holds the game-mechanical state (caravan path,
  dungeon timer, etc.)
- The **ContentGroup** holds the player membership (who's currently
  inside)
- A `ContentGroup.getDirector()` returns the linked Director

Both share the same lifecycle: created together, destroyed together
when the content ends.

## `contentGroupWork` Schema (inferred from references)

```text
contentGroupWork._globalTemp:
  director  actor ref  -- back-pointer to the Director instance
  property  bitmap     -- content restrictions (synced;
                          property bits modify player abilities while
                          inside this content)
```

The exact schema declaration is in lines 1-160 (not fully read this
pass). The references in the code clearly show these fields exist.

## `_onUpdateWork(field, sub)` — Restriction UI Refresh

```lua
function ContentGroupBaseClass:_onUpdateWork(field, sub)
  super._onUpdateWork(field, sub)
  if sub == "_init" or (field == "contentGroupWork" and sub == "property"):
    desktopWidget:processUpdateMyPlayerRestrictionByContents()
end
```

So when the `property` bitmap changes (e.g. a phase boss removes
ability X), the desktopWidget UI refreshes to reflect the new
ability set.

This is **how dungeons can restrict abilities mid-fight** — the
server changes `contentGroupWork.property`, the client refreshes
the action bar.

## `_onUpdateMember(memberActor, op)` — Nameplate Refresh

When a new member joins or leaves:

```lua
function ContentGroupBaseClass:_onUpdateMember(memberActor, op)
  super._onUpdateMember(memberActor, op)
  if myPlayer:isMember(self):       -- am I in this content?
    if memberActor:isInstanceOf("CharaBaseClass"):
      myPlayer:getDepictionJudge():judgeNameplate(memberActor)
      -- Refresh the new/leaving member's nameplate
    if memberActor == myPlayer:
      desktopWidget:processUpdateMyPlayerRestrictionByContents()
      -- If I joined/left: refresh my own restriction UI
end
```

So **content-co-members get a SPECIAL NAMEPLATE COLOR** (similar
to ARR's party-member ring). When someone joins your content, their
nameplate turns into the "content member" color; when they leave,
it reverts to default.

## `_onUpdateMemberInformation(memberIdx)` — Per-Member Nameplate

```lua
function ContentGroupBaseClass:_onUpdateMemberInformation(memberIdx)
  super._onUpdateMemberInformation(memberIdx)
  if myPlayer:isMember(self) and _isExistInClientMember(memberIdx):
    member = _getMember(memberIdx)
    if member:isInstanceOf("CharaBaseClass"):
      myPlayer:getDepictionJudge():judgeNameplate(member)
end
```

When a content member's info changes (e.g. role: tank/healer/DPS),
their nameplate gets re-rendered to reflect the new role icon.

## `_onFinalize` — Cleanup on Content End

```lua
function ContentGroupBaseClass:_onFinalize()
  super._onFinalize()

  if myPlayer:isMember(self):
    -- Refresh all members' nameplates (content color gone)
    for i = 1 to _countMember():
      if _isExistInClientMember(i):
        member = _getMember(i)
        if member:isInstanceOf("CharaBaseClass"):
          myPlayer:getDepictionJudge():judgeNameplate(member)
    -- Refresh my own restriction UI
    desktopWidget:processUpdateMyPlayerRestrictionByContents()

  -- Specific content kinds (30001, 30006) get a "left content" notice
  if myPlayer:isMember(self):
    kind = self:_getKind()
    if kind == 30001 or kind == 30006:
      worldMaster:notify(50012)  -- "You have left {content name}"
end
```

So **kind 30001 and 30006 fire the "left content" notification**;
other kinds finalize silently. This suggests:
- **30001** = a specific content type (probably "Story Instance")
- **30006** = another specific content type (probably "Raid Battle")

Other kinds (caravan event, world event, etc.) don't notify on
leave because the player can just walk away.

## Kind ID Space (Community Group Family)

We now have several kind IDs:

```text
kind          purpose / family
-----------   -----------------------------------
20001..20003  Community Groups (FC + Linkshell + Retainer Group)
30001         Content Group: Story Instance (best guess)
30006         Content Group: Raid Battle (best guess)
30002..30005  Content Group variants (caravan, dungeons, trials)
              -- specific ids TBD
```

The 30000 range is exclusively for ContentGroup subclasses, vs
20000 for CommunityGroup.

## `getDirector()` — The Bridge to State

```lua
function ContentGroupBaseClass:getDirector()
  director = contentGroupWork._globalTemp.director
  if director and director:_isAlive():
    return director
  return nil
end
```

So:
- ContentGroup has a back-pointer to its Director.
- Director is alive while content is active.
- When content ends, Director is destroyed; ContentGroup's getDirector
  returns nil.

## Assessment

```text
Confirmed:
  - ContentGroup is the player roster for an active content.
  - Each ContentGroup has a _globalTemp.director back-pointer.
  - property bitmap (synced) controls in-content ability restrictions.
  - 4 hooks: _onUpdateWork (property), _onUpdateMember (nameplate),
    _onUpdateMemberInformation (per-member nameplate), _onFinalize.
  - kind ids 30001 and 30006 fire "you left content" notice;
    others silent.

Likely (High):
  - ContentGroup is created when player ENTERS content; destroyed
    when content ENDS. Lives parallel to the Director.
  - Content-co-members get a special nameplate color via
    DepictionJudge:judgeNameplate (the "your party-mate in this
    content" indicator).
  - The property bitmap allows per-content ability gating: dungeon
    phase 2 can disable Healing abilities, etc.

Likely (Medium):
  - Kind 30001 = scenario/story instance (story-critical, hence
    the "you left" notice for narrative consistency).
  - Kind 30006 = raid battle (hard-mode content, players should
    know they left).
  - Kinds 30002..30005 are the various OTHER content types
    (dungeon, trial, caravan event, beacon battle, hamlet defense).

Speculative:
  - The "restrictionByContents" mechanism is how 1.x implemented
    "you can't use this ability in this dungeon" -- via property
    bits, not a separate mechanic.
  - ContentGroup probably also tracks per-member content-specific
    state (death count, contribution, etc.) -- not exposed in
    this 411-line file, but likely in subclasses.
```

## Server Implementation Picture

```text
CONTENT ENTRY (server-side):
  1. Player A enters Content X
  2. Server allocates:
     - Director (e.g. CaravanGuardDirector instance)
     - ContentGroup actor, with _globalTemp.director = directorRef
  3. Add Player A to ContentGroup.member array
  4. Push ContentGroup to player's client
  5. Client receives, fires _onUpdateMember -> nameplate refresh

DURING CONTENT:
  - Server pushes property changes via _onUpdateWork
  - Server adds/removes members via _onUpdateMember
  - Server may push per-member state via _onUpdateMemberInformation

CONTENT END:
  - Server marks ContentGroup as finalized
  - Push _onFinalize signal to all members' clients
  - Clients refresh nameplates back to default
  - If kind 30001 or 30006: show "you left" notice (msg 50012)
  - Server deallocates ContentGroup + Director together
```

This **closes the Director ↔ ContentGroup linkage** — the two
patterns work as a pair to implement content-based gameplay
restrictions, member tracking, and UI side-effects.

The Group + Director combo is **1.x's general-purpose framework
for instanced/event content**. The same patterns apply equally to:
- Dungeons (InstanceRaid + ContentGroup)
- Caravan events (CaravanGuardDirector + ContentGroup)
- Hamlet Defense (HamletDefenceDirector + ContentGroup)
- All future events SE could add

Future-proof design from 1.x's architecture.
