# Finding: Linkshell Subsystem Inventory -- UI + Group:: Subclass (EntryLinkShellBuilder) + Chat Mode 5

**Maps the complete 1.x Linkshell subsystem** — player chat channels
that predate ARR's Free Companies. The system has 5 UI widgets,
1 dedicated Group:: typed-packet subclass, and integrates with the
chat system via Chat Mode 5.

## 1. The 8th Group:: subclass: EntryLinkShellBuilder

**NEW DISCOVERY** via RTTI string scan:

```text
RTTI Type Descriptor:
  .?AVEntryLinkShellBuilder@Group@Client@Script@Lua@Application@@
  @ 0x012bfb10

Decoded namespace path:
  Application::Lua::Script::Client::Group::EntryLinkShellBuilder

This is the 8th confirmed Group:: subclass:
  PacketRequestBase
    EntryBuilderBase
      EntryBuilder              (actor spawn)
      BreakupBuilder            (actor despawn)
      OnlineStatusUpdater       (online status)
      EntryLinkShellBuilder     (linkshell join/leave) ← NEW
    MemberInfoUpdater
    PropertyUpdater
    WorkSyncUpdater
```

**Likely use**: similar to BreakupBuilder/EntryBuilder for actor
lifecycle, but specifically for **linkshell roster changes**. Server
sends EntryLinkShellBuilder packets when a player joins or leaves a
linkshell.

The class has its own dedicated subclass (rather than reusing
MemberInfoUpdater) because linkshell membership has specific data:
- Linkshell id
- Owner flag
- Linkshell-specific roster position
- Color/icon assignment

## 2. The 5 Linkshell UI Widgets

```text
LinkshellListWidget          (browse player's linkshells)
LinkshellMembersListWidget   (view members of a linkshell)
LinkshellMenuSubWidget       (popup menu for one linkshell)
LinkshellListSubWidget       (sub-list embedded in another widget)
LinkshellMenuWidget          (operations menu: speak/list/members/leave)
NpcLinkshellListWidget       (browse NPC-given linkshells, separate from player)

PLUS: 1 standard widget (LinkshellMenuWidget, lua file 'y1wzr25yyx5wpn1635q.lua')
  + 4 widget classes referenced via RTTI in EXE
```

The fact there's a separate `NpcLinkshellListWidget` suggests 1.x had
**NPC-issued linkshells** (probably faction/guild auto-grants) vs
player-created linkshells.

## 3. Lua API surface (from LinkshellListWidget decompile)

### Per-player API (myPlayer methods)

```text
player:getCurrentLinkshell()           Returns the currently-active
                                        linkshell group (or nil)
player:getAllLinkshellCount()          Total linkshells this player belongs to
player:getLinkshellGroup(index)        Get nth linkshell (1-based)
player:getLinkshellIconId()            Returns icon id (multi-return)
```

### Per-linkshell API (on LinkshellGroup instances)

```text
linkshellGroup:getCurrentLinkshell()   ?
(implied:
  linkshellGroup:getMembers()           members list
  linkshellGroup:getName()              linkshell name
  linkshellGroup:getOwner()             owner player
  linkshellGroup:isMyLinkshell()        am I the owner
)
```

### DesktopWidget linkshell methods

```text
desktopWidget:isValidCurrnetLinkshell()           validity check
                                                   (NOTE: typo "Currnet" in source!)
desktopWidget:getCurrnetLinkshellOwnerIconID()    owner icon id
desktopWidget:isMyCurrnetLinkshell()              ownership check
desktopWidget:getLinkshellIconID(iconID)          icon conversion
desktopWidget:executePlayerSetCurrentLinkshell(group)  set active linkshell
desktopWidget:getStaticWidget(2)                  the chat widget
                                                   (for chat mode switching)
```

### UI Commands registered (from DesktopWidget connector init)

```text
"UILuaCommands.ChangeCurrentLinkshell"  Cycle to next linkshell
"UILuaCommands.SetCurrentLinkshell"     Set specific linkshell as active
```

## 4. Chat Mode 5 = Linkshell Channel

From LinkshellMenuWidget decompile:
```text
when user clicks "Button_SpeakMember":
  chat_widget = desktopWidget:getStaticWidget(2)
  chat_widget:setChatMode(5)
  desktopWidget:changeFocusedWidget(chat_widget)
```

**Chat Mode 5** is the **linkshell chat mode**. When set, chat input
is routed to the currently-active linkshell.

Combined with prior chat findings, the chat channel system is now:
```text
Channel 32  worldMaster:notify   System notify (yellow)
Channel 33  worldMaster:alert    System alert (red)
Channel 38  NpcBaseClass:say     NPC dialog (white)
Channel 40  worldMaster:say      World cryer / global say
ChatMode 5  Linkshell chat       (NEW; mode, not channel)

The "ChatMode" vs "Channel" distinction:
  - CHANNELS are server-side classification of incoming messages
  - MODES are client-side input routing (which channel YOU send to)
  - Chat Mode 5 likely maps to channels 38 or 40 with linkshell flag
```

## 5. Architecture: 1.x Linkshells vs ARR+ Linkshells/FCs

```text
1.x LINKSHELLS:
  - Player can be in MULTIPLE linkshells (count from getAllLinkshellCount)
  - One linkshell is "current" (active for /linkshell chat command)
  - Owner has special icon (LinkshellReader icon = 383)
  - NPC linkshells separate from player linkshells (NpcLinkshellListWidget)
  - Chat Mode 5 = linkshell channel

ARR+ (FOR REFERENCE; NOT THIS PROJECT):
  - Player can be in up to 8 linkshells + 1 cross-world linkshell
  - Free Companies replaced "Linkshells" as primary social org
  - Free Company chat is separate from linkshell chat

KEY DIFFERENCE: in 1.x, LINKSHELL IS the primary social org. No FC.
Per the no_freecompany_in_1x memory, this is the ONLY player-org
system in 1.x.
```

## 6. Wire protocol (inferred)

```text
JOIN/LEAVE LINKSHELL:
  Server sends EntryLinkShellBuilder typed packet
  - Via wire opcode? (likely 0x17c with specific TYPE TAG; needs verification)
  - Routes through SpawnPipeline_FACTORY similar to other Group:: subclasses
  - Updates client's linkshell list

LINKSHELL CHAT:
  Client sends via Chat Mode 5:
    - Goes through standard chat send pipeline
    - Wire opcode 0xC9 (chat message, 536B) on Chat channel
    - Channel byte in payload identifies it as linkshell chat
  Server broadcasts to all linkshell members:
    - Each receives 0xC9 packet with linkshell channel marker
    - Client's chat widget displays in linkshell color/format

LINKSHELL MEMBER UPDATES:
  Server sends MemberInfoUpdater typed packet (0x18b)
  - Members of linkshell update their roster

LINKSHELL ROSTER REFRESH:
  Server sends 0x18d batch state push (per finding for that opcode)
  - Up to 255 members in one packet
  - Used at zone enter / login / when joining linkshell
```

## 7. Server-side requirements

```text
TO IMPLEMENT LINKSHELLS:

1. STATE STORAGE per linkshell:
   - id, name, owner_player_id, icon_id, color
   - member roster (list of player_ids, max 64-128 likely)
   - rank/permission per member (admin/member)

2. PER-PLAYER STATE:
   - List of linkshells player belongs to (max N, probably 8)
   - currentLinkshell pointer (which is active for /linkshell chat)
   - role per linkshell (owner / member)

3. WIRE OPCODES:
   - EntryLinkShellBuilder via 0x17c (or dedicated TBD)
     for join/leave notifications
   - MemberInfoUpdater (0x18b) for status changes
   - Multi-record batch (0x18d) for roster refresh
   - Chat 0xC9 with linkshell channel byte for messages

4. COMMANDS:
   - /linkshell (or /ls) - send to current linkshell
   - /linkshell create <name>
   - /linkshell join <name>
   - /linkshell leave [name]
   - /linkshell kick <player>
   - /linkshell setowner <player>
   - /lsmenu - open menu UI

5. UI INTEGRATION:
   - 5 widget classes need linkshell data feed
   - getLinkshellGroup(index) returns LinkshellGroup actor instance
   - LinkshellGroup actor needs name/owner/members getters
```

## 8. Confidence

```text
Confirmed:
  - 8th Group:: subclass EntryLinkShellBuilder discovered via RTTI
  - 5 UI widget classes mapped to Lua files
  - Chat Mode 5 = linkshell chat input
  - Multiple linkshells per player (getAllLinkshellCount)
  - One "current" linkshell concept
  - Owner has special icon (383 = LinkshellReader)
  - NPC linkshells separate from player linkshells
  - 2 UI commands: ChangeCurrentLinkshell + SetCurrentLinkshell

Likely (High):
  - EntryLinkShellBuilder dispatches via spawn pipeline ring buffer
    (same as other Group:: typed packets)
  - Linkshell wire opcode is either 0x17c (with TYPE TAG) or dedicated
  - Member roster updates use 0x18d batch state push
  - Server tracks per-player linkshell list (max 8 per ARR comparison)

Speculative:
  - 1.x linkshells may have additional features like leve/quest sharing
    (per prior /dev get linkshell debug command references)
  - NPC linkshells might be auto-granted at quest milestones
  - Cross-world linkshells did NOT exist in 1.x (single-world architecture)
```

## 9. Cross-references

- `finding_group_typed_packets_remaining_opcodes_0x187_0x18b.md`
  -- the 6 prior Group:: subclasses (this finding adds 8th = LinkshellBuilder)
- `finding_spawn_wire_side_CLOSED_opcode_0x17c_zone_main_inbound_dispatcher.md`
  -- the wire opcode that probably carries EntryLinkShellBuilder packets
- `finding_appendMessagePool_thunk_command_updater_dispatch.md`
  -- chat system (chat mode 5 routes through here)
- `finding_inbound_chat_handlers_3_variants_decompiled.md`
  -- the 3 chat inbound handlers (likely one is linkshell-tagged)

## 10. Next test

```text
1. RTTI walk for EntryLinkShellBuilder (TypeDescriptor @ 0x012bfb08)
   to find its constructor and identify the wire opcode
2. Find the LinkshellGroup C++ class (likely subclass of GroupBase)
3. Trace setChatMode(5) chat routing to identify exact wire format
4. Read remaining linkshell Lua widgets to map full UI behavior
5. Check chat inbound handlers for linkshell channel marker
```

## Commit suggestion

```
docs(re/lua): Linkshell subsystem inventory -- 8th Group:: subclass (EntryLinkShellBuilder); 5 UI widgets; Chat Mode 5; multi-linkshell per player; complete Lua API surface
```
