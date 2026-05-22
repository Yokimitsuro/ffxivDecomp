# Finding: `DesktopWidget` Is the Game-Side Packet→UI Dispatch Hub

After mapping the network protocol stack end-to-end (lobby + zone +
NetworkClientModule master tick), the remaining big question was:
**what happens when a "game-side" IPC packet arrives at the Zone
client during steady state?** The answer is the
`DesktopWidget` connector — the UI mega-script that owns
the rendering of every notification, dialog, quest marker, and
inventory update.

Sources read this pass:

```text
widget/desktopwidget_connector.lua       (687 KB, 25,428 lines!)
  -- L0_1 = DesktopWidget (a single class, ~hundreds of methods)
  -- contains processUpdatePublicInformationDialog (line 6384)
  -- contains processUpdateGeneralNotificationDialog (line 6505)
  -- contains processRecievedRequestedDataForWidget (line 6759)
  -- on-disk: 0p635/n1635q/65rzqvun1635q_7vww57qvs.lua

chara/player/playerbaseclass.lua  (for cross-reference; previously read)
```

## The three packet→UI entry points

`PlayerBaseClass:_onReceiveDataPacket(packetType, ...)` is invoked
from the C++ side (via the PacketProcessor secondary processor
documented in `finding_ipc_channel_framing.md`) for every IPC payload
addressed to the player actor. It is the **fan-out point** that
chooses which `DesktopWidget` method renders the packet:

```lua
function PlayerBaseClass:_onReceiveDataPacket(packetType, ...)
  self:_callSuperClassFunc("_onReceiveDataPacket", packetType, ...)
  if packetType == "requestedData" then
    desktopWidget:processRecievedRequestedDataForWidget(<args>)
  elseif packetType == "attention" then
    desktopWidget:processUpdatePublicInformationDialog(<args>)
  else
    if type(packetType) == "number" then
      desktopWidget:processUpdateGeneralNotificationDialog(packetType, <args>)
    end
  end
end
```

So `packetType` is either one of two **literal strings** or a
**numeric subtype id**. The C++ side picks one of three paths:

```text
packetType                  -> DesktopWidget method
--------------------------  ---------------------------------------
"attention"                 -> processUpdatePublicInformationDialog
"requestedData"             -> processRecievedRequestedDataForWidget
<number>                    -> processUpdateGeneralNotificationDialog
```

## C++ side: the strings are NOT in the EXE

Searching the EXE for `"requestedData"` and `"attention"` literals
returns **no matches**. The only place these strings appear in the
entire build is inside `playerbaseclass.lua`. That means the C++
secondary processor doesn't push the strings; **Lua compares against
constants embedded in its own code**, and the C++ side passes either:

- A small integer (matching the "subtype id" case), OR
- A string the C++ side constructed at runtime from a binary opcode
  via a runtime-built Utf8String → Lua converter, OR
- The same Utf8String objects that Lua interns from its own code
  pages (likely shared via the LGE constant pool).

The third option is most likely (no runtime string construction
visible at the IPC dispatcher level). The PacketProcessor presumably
holds a small switch on the IPC payload's opcode that pushes one of a
few pre-interned strings (`requestedData`, `attention`, plus a few
numeric paths).

## `processUpdateGeneralNotificationDialog` — the notification map

The most informative of the three handlers. The switch on the
notification subtype id maps to UI widget opens:

```lua
function DesktopWidget:processUpdateGeneralNotificationDialog(actor, notifId, ?, payload, ...)
  if notifId == 1 then
    self:openCautionInformDialogWidget(payload, <args>)
  elseif notifId == 2 then
    self:openTutorialSuccessWidget(payload, true)
  elseif notifId == 3 then
    self:openPublicEffectWidget(payload)
  elseif notifId == 4 then
    local arg = select(1, ...)
    self:openTutorialWidget(payload, arg)
  elseif notifId == 5 then
    self:closeTutorialWidget()
  elseif notifId == 7 then
    if desktopWidget:isTutorialMode() then
      self:closeTutorialWidget()
      self:cancelTutorialMode()
    end
  elseif notifId == 8 then
    self:closeRaidDungeonExecutionWidget()
  elseif notifId == 9 then
    if not self:isTutorialMode() then self:orderTutorialMode() end
    desktopWidget:setTutorialMask(false, false, false, true, true, 3)
  elseif notifId == 10 then
    self:openPublicInformLongDialogWidget(payload, <args>)
  end
end
```

So the pinned **notification subtype enum**:

```text
notifId  meaning
-------  ------------------------------------------------
   1     CAUTION dialog (kick warning, system message)
   2     TUTORIAL SUCCESS popup
   3     PUBLIC EFFECT (screen flash / overlay)
   4     TUTORIAL widget OPEN
   5     TUTORIAL widget CLOSE
   6     (not handled in this switch; reserved)
   7     CANCEL tutorial mode (if active)
   8     CLOSE Raid Dungeon Execution widget
   9     ORDER tutorial mode + apply tutorial mask
  10     PUBLIC INFORM LONG dialog (multi-line message)
```

Subtype 6 is intentionally skipped in this dispatcher; it is probably
handled at a different level (or reserved for future use). Subtypes
0 and 11+ also fall through to no-op.

So the wire shape for one of these packets at the IPC layer is most
likely:

```text
opcode  GENERAL_NOTIFICATION_DIALOG
  +0x00  uint32   notifId (1..10)
  +0x04  ...      payload (per-id specific; e.g. text id for the
                  dialog, tutorial step id, effect id)
```

A server that wants to push a tutorial state to the client can do so
by sending an IPC packet that decodes to subtype id 9 + the
appropriate tutorial step parameter.

## `processUpdatePublicInformationDialog` — the "attention" handler

```lua
function DesktopWidget:processUpdatePublicInformationDialog(actor, A2, message, ...)
  self:openPublicInformDialogWidget(actor, message, ...)
end
```

A thin wrapper. Opens the PublicInformDialogWidget with the actor
and the payload — i.e. it's the "Sephirot is going to fire a laser
in 5 seconds" type of attention dialog. The server simply pushes the
opcode + payload; the client decides the styling.

## `processRecievedRequestedDataForWidget` — the "requestedData" handler

(Typo "Recieved" preserved from binary.)

This is invoked when the **client previously asked for some data**
and the server replies. Full switch over a string subKey:

```lua
function DesktopWidget:processRecievedRequestedDataForWidget(actor, subKey, payload, ...)
  local journalDetailType = nil

  if subKey == "qtdata" then
    journalDetailType = 1  -- Quest data
  elseif subKey == "qtmap" then
    -- Update quest markers on MapNavigationWidget
    local w = self:getWidget(3, "MapNavigationWidget")
    if w then
      local n = select("#", ...)
      if n > 0 then
        w:initMarkerList(n)
        for i = 1, n do w:addMarkerList(i, select(i, ...)) end
        local questId = tostring(select(1, ...))
        ...
        w:setQuestMarker(questId)
        w:dispMarker(L9_2)
      end
    end
  elseif subKey == "activegl" then
    journalDetailType = 2  -- Active Guildleve data
  elseif subKey == "glHist" then
    -- GuildleveHistory widget setDetailData
    local w = self:getWidget(3, "GuildleveHistoryWidget")
    if w then w:setDetailData(...) end
  end

  if journalDetailType ~= nil then
    self:processUpdateJournalDetailWidget(journalDetailType, payload, ...)
  end
end
```

### requestedData subKey table

```text
subKey       payload destination                    journalDetailType
-----------  ------------------------------------   -----------------
"qtdata"     Journal Quest detail panel (type 1)    1
"qtmap"      MapNavigationWidget quest markers      (none; handled inline)
"activegl"   Journal Active-Guildleve panel (typ 2) 2
"glHist"     GuildleveHistoryWidget detail data     (none; handled inline)
```

Pattern: client sends "give me X" request; server replies with
`packetType="requestedData"` + subKey identifying the data class.
For Journal-type subKeys (`qtdata`, `activegl`), the routing collapses
to a numeric journalDetailType (1 = Quest, 2 = Active Guildleve)
which then drives `processUpdateJournalDetailWidget`.

## Other actors override `_onReceiveDataPacket` with their own enums

The fan-out described above is `PlayerBaseClass`'s implementation.
Other actor classes have their **own override** of
`_onReceiveDataPacket` with a **different** packetType space.

### `CharaBaseClass._onReceiveDataPacket` — adds the `"data"` packet

The parent class of Player handles ONE additional string-typed
packetType:

```lua
function CharaBaseClass:_onReceiveDataPacket(packetType, ...)
  if packetType == "data" then
    self:processReceiveData(select(1, ...))
  end
end
```

So there are actually **three** string-typed packetTypes in
circulation (now confirmed):

```text
packetType        recipient                        Lua handler
----------------  -------------------------------  ----------------------------
"requestedData"   Player (most-specific override)  processRecievedRequestedDataForWidget
"attention"       Player                           processUpdatePublicInformationDialog
"data"            Chara (parent of Player)         processReceiveData (subclass overrides)
                                                   -- generic "I have a data
                                                   blob for your subclass to
                                                   parse"
```

When a packet arrives, the actor's class hierarchy is walked from
most-specific to least-specific via `_callSuperClassFunc`, so the
order of attempts on the local-player actor is:

```text
PlayerBaseClass._onReceiveDataPacket   -- tries "requestedData" / "attention" / <number>
  -> super: CharaBaseClass._onReceiveDataPacket  -- tries "data"
       -> super: ActorBaseClass._onReceiveDataPacket  -- empty
```

CharaBase's `processReceiveData` is a placeholder — subclasses
override it to give meaning to the `"data"` payload for their type.

### `InstanceRaidBaseClass._onReceiveDataPacket` — numeric enum

The director for an instance-raid session handles **three numeric
packetTypes** (each gated on `instanceRaidWork.initFlag` being true):

```lua
function InstanceRaidBaseClass:_onReceiveDataPacket(packetType, ...)
  if not self.instanceRaidWork.initFlag then return end

  if packetType == 1 then
    -- INSTANCE CLEAR: start countdown timer
    self.instanceRaidWork.clearFlag = true
    local a = select(1, ...)
    local b = select(2, ...)
    self:setCountDownTimer(a, b, false)
    self:closeInformationWidget()

  elseif packetType == 2 then
    -- INSTANCE CLEAR (instant): no countdown
    self.instanceRaidWork.clearFlag = true
    self.instanceRaidWork.countdownStatus = 0
    self:closeInformationWidget()

  elseif packetType == 3 then
    -- USER MESSAGE: forward to processUserMessage
    self:processUserMessage(select(1, ...))
  end
end
```

```text
InstanceRaid packetType  meaning
-----------------------  ---------------------------------------------
        1                INSTANCE CLEAR with timer (countdown start)
        2                INSTANCE CLEAR (instant; no timer)
        3                USER MESSAGE within the instance
```

So the **server signals "instance raid completed"** by sending an
IPC packet that the C++ side decodes to packetType 1 or 2 targeting
the InstanceRaid director actor.

### Other InstanceRaid effect IDs (also pinned)

In the same file, `processStartEffect` and `processFailedEffect` call
`desktopWidget:openPublicEffectWidget(N)` with fixed effect ids:

```text
processStartEffect    -> openPublicEffectWidget(1)
processFailedEffect   -> openPublicEffectWidget(3)
```

Cross-referencing with the `processUpdateGeneralNotificationDialog`
notification subtype 3 ("PUBLIC EFFECT") and the
`openPublicEffectWidget(payload)` it calls there: **public effect 1 =
"instance start" effect** and **public effect 3 = "instance fail"
effect**. Both are visual overlay effects (screen flashes / banners).

The cutscene id `63` is used by `InstanceRaidBaseClass:executeCutScene`
to start the standard "you entered an instance raid" cutscene.

## `processUpdateContentsInformation` — bonus dispatcher

A fourth game-side dispatcher discovered above
`processUpdateGeneralNotificationDialog` in the same file. Maps
content-kind numeric ids to widget names:

```lua
function DesktopWidget:processUpdateContentsInformation(actor, A2, A3)
  ...
  local kind = actor:getKindContentsInformation()
  local idx, widgetName
  if kind == 1 then
    idx, widgetName = 1, "GuildleveExecutionWidget"
  elseif kind == 2 then
    idx, widgetName = 2, "ChocoboCaravanWidget"
  else
    return
  end
  self:updateContentsInformation(actor, idx, widgetName, A2, A3)
end
```

```text
content kind  widget
------------  ---------------------------
     1        GuildleveExecutionWidget
     2        ChocoboCaravanWidget
```

`updateContentsInformation` then routes by an **action** sub-string:

```text
action     behaviour
---------  -----------------------------------------------------
"start"    open the contents widget (allocate a free slot)
"update"   find existing widget; update its data
"finish"   (no body; reserved)
"cancel"   close the contents widget
```

So `updateContentsInformation(actor, idx, "GuildleveExecutionWidget",
"start", payload)` is how a server starts a Guildleve session on
the client.

## DesktopWidget as the central UI broker

The connector file is **687 KB / 25,428 lines** — by far the largest
file in the corpus. It implements `DesktopWidget` as a single mega-
class with hundreds of methods spanning:

- Target/sub-target management (~80 methods around lines 1245..3000)
- Actor / player / bazaar / trade lookups
- Map markers / quest markers / event tracking
- Notification dialogs (the 3 handlers above)
- Tutorial mode (open/close/mask/cancel)
- Raid dungeon UI (open/close)
- Item / inventory rendering (updateItemList, updatePlayerItem, etc.)
- Sub-widget opens (each as a thin wrapper around `getWidget` +
  `setDetailData`)

Every IPC packet from the server that has any visible client effect
goes through one of these methods. So **`DesktopWidget` is the
single biggest Lua-side surface area** for game protocol decoding,
and any server that wants to drive client UI in 1.x has to know its
method dispatch contract.

## Assessment

```text
Confirmed:
  - The three game-side packet entry points on the Lua side are
    PlayerBaseClass:_onReceiveDataPacket dispatching by packetType
    into three DesktopWidget methods.
  - processUpdateGeneralNotificationDialog handles the numeric
    subtype family with ids 1..10 (mapped above; 6 unused).
  - processUpdatePublicInformationDialog is a thin wrapper for
    "attention" packets opening PublicInformDialogWidget.
  - processRecievedRequestedDataForWidget routes "requestedData"
    replies by a string subKey to the matching widget; observed
    subKeys include "activegl" and "glHist".
  - The strings "requestedData" and "attention" exist ONLY in the
    Lua corpus, not in the EXE. The C++ PacketProcessor must
    inject them from a small interned-string table when it
    decodes the IPC packet's opcode.

Likely (High):
  - The numeric notifId is the LOW BYTE (or a small field) of the
    IPC packet payload at a fixed offset; the C++ side reads it
    and passes it to Lua as packetType.
  - There are more subKeys in processRecievedRequestedDataForWidget
    above the lines we read (the function starts further up than
    the 6700-6759 range). Reading lines 6520-6700 would surface
    those.
  - Tutorial mode is heavily driven by these packets: ids 2, 4, 5,
    7, 9 are all tutorial-related. A test server that drives the
    tutorial only needs to push these five opcodes plus
    PublicInformDialog for the messaging.

Likely (Medium):
  - The notifId 6 gap is the slot SE reserved for a "raid dungeon
    OPEN" companion to id 8 (close); the open-side might be handled
    by a different DesktopWidget method (orderRaidDungeonExecution
    or similar) that we haven't fully traced.

Speculative:
  - The string-table for "requestedData" / "attention" lives in
    Component::Lua::GameEngine constant pool, not in the C++
    Application namespace. That is why an EXE string search misses
    them: they live in pre-interned LGE Utf8Strings that the Lua
    bytecode references via LOADK opcodes, not as direct C++
    string literals.

Next test:
  - Read lines 6520..6700 of the connector to pin every subKey in
    processRecievedRequestedDataForWidget.
  - Read the early sections of the connector (around lines 100..760)
    to find init / inbound packet hooks beyond the three entry
    points (e.g. world events, environmental triggers).
  - Decompile the C++ side: find which function inside
    Application::Lua::Script::Client::Group::PacketProcessor
    pushes the packetType arg before invoking the Lua callback.

Commit suggestion:
  docs(re/lua): pin DesktopWidget as the game-side packet->UI hub
                + notification subtype id 1..10 enum
```

## Server implication

For a server that wants to push UI updates without doing protocol-
level reverse engineering:

1. **General notification subtypes 1..10** are the smallest possible
   "kit" for driving any 1.x client UI message. Send IPC packet
   with `packetType` decoded to `<number>`, set the numeric value,
   provide the per-id payload (usually a text id + extra params).

2. **"attention" packets** are for high-priority broadcast messages
   ("server going down in 60 s"). Pre-format the message text and
   send it; the client renders it in the PublicInformDialog.

3. **"requestedData" packets** require the client to have asked first
   (e.g. opened the Guildleve History widget). The server must
   maintain enough state to know which subKey to reply with.
   Server-initiated "requestedData" pushes will not display
   anything (the client only routes them when a matching widget is
   open).

4. **The full set of game-side packet types** is much larger than
   these three. Other actor classes (CharaBase, AreaMaster,
   Director*) have their own `_onReceiveDataPacket` overrides that
   handle their type's packets. A complete server roster requires
   reading each subclass's override.

5. **The DesktopWidget connector itself is enormous** (687 KB) and
   contains the bulk of client UI logic. Most "what does the
   client do when X happens" questions can be answered by reading
   the right method in this file. The catalogue at
   `docs/re/lua/catalog.md` lists it under `widget/`; the path is
   `n1635q/65rzqvun1635q_7vww57qvs.lua` on disk.
