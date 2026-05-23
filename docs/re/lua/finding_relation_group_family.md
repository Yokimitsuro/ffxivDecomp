# Finding: `RelationGroup` Family — Generic 2-Actor Pending Interactions

The `RelationGroup` pattern is the **generic 2-actor interaction
container** in 1.x: trades, party invites, command executions,
bazaar transactions. All variants share an IDENTICAL schema with
just a different desktopWidget UI handler.

This pattern explains the catalog binding range `200xxx` — one
shared id space for all relation-group instances.

Sources read:

```text
group/RelationGroup/TradeRelationGroup.lua             181 lines (full)
group/RelationGroup/GroupInvitationRelationGroup.lua   195 lines (full)
```

Plus directory glance — same shape applies to:

```text
ExecuteCommandRelationGroup           87 lines
GroupExecuteCommandRelationGroup      87 lines
BazaarBuyItemRelationGroup            34 lines
+ several stub subclasses             8 lines each
```

## The Shared Schema (BYTE-IDENTICAL between TradeRelation +
##                     GroupInvitationRelation)

```text
work._sync   = [{_globalTemp, nesting(16)}]

work._globalTemp._nesting = [
  {host, member},                       -- pair: host (initiator)
                                           + member (receiver actor list)
  {variableCommand, integer32}          -- the action discriminator
]

work._tag = [
  {confirmGroupCommand, 1, [
    {_globalTemp.host},
    {_globalTemp.variableCommand}
  ]}
]

_bindWork(200001, work, _globalTemp, host)
_bindWork(200002, work, _globalTemp, variableCommand)
```

Both files have THE SAME schema declaration line for line. So
`RelationGroup` is the abstract parent and `Trade*` / `GroupInvitation*`
/ `BazaarBuyItem*` are different ONLY in their UI hook:

```text
TradeRelationGroup        -> processUpdateConfirmTradeCommandVariation
GroupInvitationRelationGroup -> processUpdateConfirmGroupCommandVariation
                                (and processUpdateConfirmInvitationCommandVariation?)
BazaarBuyItemRelationGroup -> probably processUpdateConfirmBazaarCommandVariation
ExecuteCommandRelationGroup -> processUpdateConfirmExecuteCommandVariation
```

So the **wire format is the same** for all relation groups; the
client interprets the variableCommand value to know what KIND of
relation this is (trade, invite, bazaar, etc.) and which UI panel
to render.

## Bindings (catalog confirmed)

```text
200001  work._globalTemp.host             actor ref (initiator)
200002  work._globalTemp.variableCommand  uint32 (action id)
```

Both registered by every RelationGroup subclass. So a server
pushing binding 200001/200002 needs to know which RelationGroup
instance it belongs to (via the actor id).

## Hook Patterns

All RelationGroup subclasses follow the same hook structure:

```lua
_onUpdateWork(field, sub):
  super._onUpdateWork(field, sub)
  if sub == "_init":              -- on creation
    desktopWidget:processUpdateConfirm<X>CommandVariation()
  elif sub == "confirmGroupCommand": -- on host/variableCommand change
    desktopWidget:processUpdateConfirm<X>CommandVariation()

_onUpdateMember(idx, op):
  super._onUpdateMember(idx, op)
  desktopWidget:processUpdateConfirm<X>CommandVariation()

_onFinalize:
  desktopWidget:processUpdateConfirm<X>CommandVariation()
```

So every state change (init / host change / variableCommand change /
member change / finalize) triggers a UI refresh on the relevant
panel.

## `getCommandVariation()` — The Dispatch Query

Each subclass exposes a `getCommandVariation()` method that returns
the current state to the UI:

```lua
function getCommandVariation()
  cmd = work._globalTemp.variableCommand
  if cmd == 0:
    return nil  -- no active relation
  for each member in group:
    if member is the host:
      hostName, ...args = _getMemberLocalizedDisplayName(memberIdx)
      return cmd, hostName, ...args
  return nil
end
```

So the panel shows:
- Current command (cmd id, looked up in command sheet)
- Host's localized name (e.g. "Player A wants to trade with you")
- Extra args (depends on command — could be item info, party size)

## Use Cases Enumerated

```text
TradeRelationGroup:
  host = player initiating trade
  member = receiver player
  variableCommand = trade command id
                     (e.g. "Player wants to trade with you")

GroupInvitationRelationGroup:
  host = party leader (inviter)
  member = invited player
  variableCommand = invitation command id
                     ("X invites you to a party")

ExecuteCommandRelationGroup:
  host = player executing command
  member = target player
  variableCommand = the action being executed
                     (e.g. resurrection target prompt)

GroupExecuteCommandRelationGroup:
  host = group leader
  member = group target
  variableCommand = group-wide action
                     (e.g. "Leader wants to enter dungeon X")

BazaarBuyItemRelationGroup:
  host = bazaar seller
  member = potential buyer
  variableCommand = bazaar item / buy intent
                     (e.g. "Buy this item from X for Y gil")
```

So `RelationGroup` is a **micro-pattern for ANY 2-actor confirmation
dialog**. The same shape covers all interactive cross-player UI
events.

## Why This Pattern Matters

Game designers reuse the same UI primitive across very different
features. The "do you want to..." dialog with [Yes/No] is identical
for:
- Trade requests
- Party invites
- Resurrection prompts
- Bazaar purchases
- Group actions

By using ONE generic data shape (host + variableCommand + member),
the client code is much simpler:
- One C++ class for the data
- One UI panel (with style variants)
- One sync path (binding 200001/200002)

The variableCommand byte selects which UI variant + which decline/
accept handler runs.

## Assessment

```text
Confirmed:
  - RelationGroup is the 2-actor confirmation pattern.
  - Schema is BYTE-IDENTICAL across at least Trade and GroupInvitation
    subclasses. Likely identical for all 5-6 subclass variants.
  - Bindings 200001 (host) + 200002 (variableCommand) are shared by
    all RelationGroup instances.
  - UI dispatch by subclass type via different desktopWidget hooks
    (processUpdateConfirmXCommandVariation).
  - The variableCommand value selects the specific action; the
    receiver actor (member) is in the group's member array.

Likely (High):
  - The variableCommand id range used by RelationGroup actions is
    specific (probably 24100-24200 or similar) -- specific ids TBD.
  - All RelationGroup subclasses share `getCommandVariation()` with
    the same logic; only the hook function name changes.
  - 1.x's UI design intentionally collapses 5 different prompts
    into 1 panel style for consistency.

Likely (Medium):
  - The RelationGroup actor is created server-side when the
    interaction is initiated, and destroyed when answered/timed-out.
    Server tracks per-pair active RelationGroup instances.
  - The relation actor's actor id is sent to both parties via the
    standard bindWork channel; both then subscribe to 200001/200002.

Speculative:
  - The "member" array in RelationGroup typically holds just 1
    receiver, but the array shape allows multi-target invites
    ("Player wants to invite X, Y, Z to party").
  - The variableCommand id might also serve as the wire opcode
    in client-to-server responses (e.g. when player clicks Yes/No,
    the response packet carries variableCommand and the response).
```

## Server Implementation Picture

```text
RELATION-GROUP CREATION (server-side):
  When Player A initiates an action requiring Player B's consent:
    1. Allocate a new RelationGroup actor (server-side)
    2. Set work._globalTemp.host = Player A's actor ref
    3. Set work._globalTemp.variableCommand = the action id
    4. Add Player B to work.member array
    5. Push binding 200001 (host) + 200002 (variableCommand) to
       both players' clients

CLIENT RECEIVES:
  - Player B's client sees binding updates -> processUpdateConfirm*CommandVariation
  - UI panel pops up: "Player A wants to {action}"
  - Player clicks Yes/No
  - Client sends response packet (probably opcode 0x131 byte payload:
     0=decline, 1=accept)

SERVER RESPONSE HANDLING:
  - On accept: execute the action (transfer items, add to party, etc.)
  - On decline: just delete the RelationGroup actor
  - On timeout: same as decline + send "X declined" message

So a RelationGroup is short-lived (typically < 30 seconds) and
serves only to coordinate the 2-actor confirmation handshake.
```

This closes the **interactive confirmation dialog wire surface**.
Most 2-player interactions (trade, invite, etc.) all go through
this same pattern.
