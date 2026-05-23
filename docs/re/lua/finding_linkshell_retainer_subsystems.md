# Finding: Linkshell + Retainer Social/Economic Subsystems

Maps the two major social/economic subsystems in 1.x:
**Linkshell** (player chat groups; 11 widgets) and **Retainer**
(player-owned NPC + market vendor; 8 widgets). Combined ~25,000+
lines of Lua dedicated to these two systems.

## Linkshell widget family (cipher decoded)

```text
CIPHERED NAME                            DECODED                 LINES
---------------------------------------- ----------------------- -----
y1wzr25yyy1rqn1635q.lua                  LinkshellListWidget     217
y1wzr25yyy1rqrp8n1635q.lua               LinkshellListSubWidget  324
y1wzr25yyx5x85sry1rqn1635q.lua           LinkshellMembersListWidget 441
y1wzr25yyx5wpn1635q.lua                  LinkshellMenuWidget     349
y1wzr25yyx5wprp8n1635q.lua               LinkshellMenuSubWidget  522
y1wzr25yy17vwy1rqn1635q.lua              LinkshellIconListWidget 134
9rz/y1wzr25yyy1rqn1635q.lua              LinkshellListWidget (Ask) 350
9rz/y1wzr25yyw9x1w3n1635q.lua            LinkshellNamingWidget   334
9rz/y1wzr25yyr5y57q17vwn1635q.lua        LinkshellSelectionWidget 312
9rz/y1wzr25yy7vw41sxn1635q.lua           LinkshellConfirmWidget  139
wu7y1wzr25yyy1rqn1635q.lua               NpcLinkshellListWidget  416
yv3n1635q.lua                            LogWidget (chat log)    1853

11 LINKSHELL WIDGETS + LogWidget = 5391 lines total.
```

## Retainer widget family (cipher decoded)

```text
CIPHERED NAME                            DECODED                  LINES
---------------------------------------- ----------------------- -----
s5q91w5sy1rqn1635q.lua                   RetainerListWidget        785
s5q91w5sqs965n1635q.lua                  RetainerTradeWidget      3836  (!)
s5q91w5su9lx5wqn1635q.lua                RetainerPaymentWidget     251
s5q91w5s65q91yn1635q.lua                 RetainerDetailWidget      279
s5q91w5s1q5xy1rqn1635q.lua               RetainerItemListWidget   9508  (prior finding)
9rz/s5q91w5s1q5xy1rqn1635q.lua           RetainerItemListWidget (Ask) 6661
9rz/s5q91w5sw9x1w3n1635q.lua             RetainerNamingWidget      578
9rz/s5q91w5s61rx1rr9yn1635q.lua          RetainerDismissalWidget    58

8 RETAINER WIDGETS = ~21,956 lines total.
```

Plus a related Grand Company widget:
```text
9rz/3s9w67vxu9wlv441719y0v1wn1635q.lua  GrandCompanyOfficialJoinWidget 93
```

## LinkshellMenuSubWidget operation schema (work._temp)

```text
askType    integer8     operation kind (kick / appoint / demote / etc.)
rank       integer8     target's member rank
memberID   integer16    target member's id
isLogin    boolean      is target online?
```

So linkshell management actions are enum-keyed by `askType`. Each
button on the LinkshellMenuSubWidget corresponds to one askType
value. The widget collects (askType, rank, memberID, isLogin) then
yields the choice back to the caller.

## RetainerListWidget per-retainer schema (24 methods)

```text
NAME COMPONENTS:
  getNickNameName / getNickNameTitleName    nickname + title prefix
  
LEVEL DISPLAY:
  getLvName / getLvNameTitle                level + title prefix

LOCATION:
  getLocationName / getLocationTitleName    location + title prefix

STATUS:
  getStatusName                              current status text
  setRetainerCondition                       condition update (idle / busy / etc.)

RENDERING:
  setRetainerLineData                       full per-retainer row
  setRetainerName / setRetainerLevel /
  setRetainerLocation                        per-field setters
  setRetainerListMax                         array bound (probably 8 retainers max)

UI INTERACTION:
  processUICommandEvent                      button press
  setAskResult / getAskResult                modal yield I/O
  setEventMode / getEventMode                modal state
  setListItemVisible                         row visibility
  setInfomation (sic = "Information")        UI text

LIFECYCLE:
  init                                       widget init
  setInitialData                             populate from server data
  updateRetainerData                         post-server-push refresh
  processWaitCallFunction                    async wait wrapper
```

So a retainer has these **per-retainer state fields**:
- name (with title prefix)
- level (with title prefix)
- location (with title prefix)
- status / condition (idle / busy / out / etc.)

The "title prefix" pattern (NickName + NickNameTitle, Lv + LvTitle,
Location + LocationTitle) suggests **localized formatting**:
- The "Title" parts are localized prefix strings ("Lv:", "Status:")
- The plain "Name" parts are the actual values

This lets the UI render in any language without changing the
data layout.

**Sic typo preserved**: `setInfomation` (should be "setInformation").
Per the previous findings on Quest typos, 1.x's English code base
has consistent misspellings that survived to retail.

## Retainer max count

```text
setRetainerListMax = ?  (probably 8 based on FFXIV 1.x player retainer
                          cap; needs body-read to confirm)
```

`ordinaryRetainer.csv` (FFXIVTool decode_csv) has 999 rows -- that
is the **pool of available retainer NPCs** (one per spawn slot in
the world). The PLAYER picks from this pool when hiring.

## RetainerTradeWidget (3836 lines) -- the biggest retainer widget

This is the largest retainer widget. Likely handles the full
trade flow:
- Open trade with retainer NPC
- Move items between player inventory / retainer inventory
- Set bazaar prices (per the `bazaarkind` + `rewardprice` schema
  in `finding_negotiation_bazaar_widget_family.md`)
- Confirm changes

A retainer in 1.x is essentially a **player-controlled vendor**:
- Player parks the retainer at a Retainer Counter NPC
- Retainer holds items on the bazaar with set prices
- Other players walk by and buy from the retainer's bazaar
- Server arbitrates the trade; player collects gil on return

## Linkshell architecture summary

```text
A LINKSHELL IS:
  - A named chat channel (custom name)
  - With an icon (selected via LinkshellIconListWidget)
  - With a member list (up to N members)
  - With a rank system (admin / regular / etc., per the
    LinkshellMenuSubWidget rank field)
  - With persistent join across logins

OPERATIONS (askType enum, values unknown):
  - Create linkshell (LinkshellNamingWidget for name input)
  - Join linkshell
  - Leave linkshell
  - Kick member (admin only)
  - Appoint admin (transfer ownership; per LinkshellAppointCommand
    documented in prior session)
  - Demote (per LinkshellKickCommand)
  - Toggle online visibility
  - Switch active linkshell channel
  - Disband linkshell

WIRE INTERFACE:
  - Outbound: chat messages on the channel use the chat opcodes
    (35/36/37/57 inbound for receiving; sending is via the
    generic chat forwarder at FUN_00db3e30 -- per
    finding_complete_3channel_opcode_inventory.md).
  - Management ops likely use the Zone channel via 0x12D with a
    discriminator byte for "linkshell-op".

NPC LINKSHELLS (NpcLinkshellListWidget):
  Per finding_chara_cliprog_and_event_extensions.md, NPCs have
  npcLinkshellChatCalling/Extra fields. Quest cutscenes use NPC
  linkshells for ambient communication ("Maelstrom Sergeant: We
  need reinforcements...").
```

## Retainer architecture summary

```text
A RETAINER IS:
  - A persistent NPC owned by the player (8 max)
  - Has its own inventory (separate from player's bag)
  - Has its own bazaar (items priced and available to other players)
  - Has a location (city of residence)
  - Has a status (idle / busy / out-on-task)
  - Persists across player logouts

OPERATIONS:
  - Hire (from ordinaryRetainer.csv pool of 999)
  - Name (RetainerNamingWidget)
  - Dismiss (RetainerDismissalWidget)
  - Trade items (RetainerTradeWidget; the biggest widget)
  - Pay for service (RetainerPaymentWidget -- retainer service fee?)
  - View detail (RetainerDetailWidget)
  - Browse items (RetainerItemListWidget)

WIRE INTERFACE:
  - Retainer state is a fork of NPC actor state -- the retainer
    is an NPC actor with the player as its owner.
  - Inventory updates flow via the multi-chunk update protocol
    (per finding_negotiation_bazaar_widget_family.md operateSell
    pattern).
  - Bazaar listings sync through periodic broadcast.

PERSISTENCE:
  - Per FFXIVTool ordinaryRetainer.csv: 999 retainer slots in the
    world's NPC pool. Each slot may be assigned to a player or
    remain free.
  - The mapping (slot -> player) is server-state, not in the static
    CSV.
```

## Server implications

```text
LINKSHELL SERVER REQUIREMENTS:
1. Linkshell entity:
   - linkshell_id (uint)
   - name (UTF-8 string)
   - icon_id (uint8)
   - owner_player_id
   - member list[N] = (player_id, rank, last_seen, is_online)
   - chat_history (last N messages, for new joiners)

2. Message broadcast:
   - On player chat-in-linkshell: deliver to all online members
     via inbound chat opcode (channel id = linkshell_id).
   - NPC linkshells: server-driven scripted messages during quests.

3. Admin operations:
   - askType enum values (TBD; reverse-engineer the
     LinkshellMenuSubWidget body for the exact values).
   - Each op generates an outbound 0x12D with a discriminator.

RETAINER SERVER REQUIREMENTS:
1. Retainer entity:
   - retainer_id (from ordinaryRetainer pool 0-998)
   - owner_player_id
   - name (custom, UTF-8)
   - level (per-retainer XP / skill?)
   - location (city id)
   - status (idle/busy/out)
   - inventory_list (items + counts)
   - bazaar_list (items + prices + bazaarkind)

2. Per-player retainer slots:
   - 8 retainer slots per player (per setRetainerListMax)
   - Each slot independent (can hire, dismiss separately)

3. Bazaar broadcast:
   - When other players walk near a retainer's Counter NPC, the
     retainer's bazaar listing is visible.
   - Server pushes the listing via the bazaar UI protocol.

4. Cross-player trade:
   - Buyer walks up to retainer Counter -> sees retainer's wares
   - Buyer purchases -> server transfers item to buyer, gil
     to retainer's owner
   - Owner collects gil on next retainer visit (or auto-deposit?)
```

## Confidence

```text
Confirmed:
  - 11 Linkshell widget files (5391 lines total) + 1 shared LogWidget.
  - 8 Retainer widget files (~21,956 lines).
  - LinkshellMenuSubWidget work schema: askType / rank / memberID /
    isLogin (4 fields).
  - RetainerListWidget has 24 documented method slots covering
    naming, level, location, status, list rendering.
  - Retainer per-field setters follow a "Name + Title" pattern for
    localized UI rendering.
  - Typo preserved: setInfomation (should be Information).

Likely (High):
  - The 999 rows in ordinaryRetainer.csv are the WORLD POOL of
    retainer NPC slots; each player can hire up to 8 from this
    pool.
  - askType enum values include: kick, appoint, demote, leave,
    disband, transfer-ownership. The exact values need a body
    read to enumerate.
  - The 8-retainer limit is server-enforced (per
    setRetainerListMax).

Likely (Medium):
  - Linkshell chat uses the generic chat forwarder (FUN_00db3e30)
    on outbound; specific inbound opcodes carry linkshell channel
    in their target field.
  - Retainer trade uses the multi-chunk update protocol (per
    operateSell pattern from finding_negotiation_bazaar_widget_family).
  - The 3836-line RetainerTradeWidget is the heavy I/O widget;
    most other retainer widgets are simple displays.

Speculative:
  - NPC linkshells (NpcLinkshellListWidget) are READ-ONLY display
    -- players can't talk in NPC linkshells, only observe story
    chatter.
  - The "Rank" enum in LinkshellMenuSubWidget probably has 3 levels:
    owner / officer / member.
  - Retainer "Level" may track Adventure Aide level or similar
    quasi-XP system from 1.x.
```

## Next test

- Read the body of LinkshellMenuSubWidget around `setButton` and
  `processUICommandOperate` to enumerate the askType enum values.
- Sample 5-10 specific rows of ordinaryRetainer.csv to confirm
  the schema (name, attributes per retainer NPC).
- Search for `_callServerOnLinkshell` / `_callServerOnRetainer`
  native bridge bindings to identify the outbound opcode flow
  for these subsystems.

## Commit suggestion

```
docs(re/lua): map Linkshell (11 widgets) + Retainer (8 widgets) subsystems
```
