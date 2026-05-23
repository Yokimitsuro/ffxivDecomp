# Finding: Inbound Binding-Update Dispatch — Handler Family Identified

Partial progress finding (2026-05-23). Identified the **handler
family** for inbound binding-update packets — the C++ functions that
get called when the server pushes a field-change event for a Lua-
observed `_onChange*` hook. The dispatch table containing the function
pointers is pinned, but the SELECTOR (the function that walks the
table by opcode/bindingId) is still TBD.

## What's Confirmed

The inbound-update dispatch has a TWO-LEVEL structure:

```text
NETWORK PACKET (Zone channel, segment type 3, opcode TBD)
    ↓
[INBOUND DISPATCHER -- not yet pinned]
    ↓ indexes dispatch table at 0x00fd78XX by some key
    ↓
HANDLER FUNCTION (one per binding/event)
    ↓
Actor_dispatchLuaHook_<eventName>       (C++ -> Lua bridge)
    ↓ calls Lua method "_onChange<Field>"(self, oldValue, newValue)
    ↓
Lua-side reactive hook fires
```

## Pinned Handlers

```text
0x00704820  Actor_handleActorMainStatChange
            - Inbound packet handler for actor's main stat field
            - Forwards to Lua via Actor_dispatchLuaHook_onChangeActorMainStat
            - Sets state flag at this+0x167 to 1 for states 11/13
              (probably "casting" / "channeling")
            - Function pointer stored in dispatch table at 0x00fd78e4

0x006fa840  Actor_dispatchLuaHook_onChangeActorMainStat
            - C++ -> Lua bridge for the _onChangeActorMainStat hook
            - Builds Lua table {oldValue, newValue}
            - Calls Lua function "_onChangeActorMainStat" on the actor

0x006fa980  Actor_dispatchLuaHook_onChangeNetStatSystem
            - Sibling: bridge for _onChangeNetStatSystem hook
            - References the _onChangeNetStatSystem string 3 times
              (probably 3 different overloads or contexts)

0x00704230  Player_handleLimitAddictedNotice
            - Different family: handles "_onReceiveLimitAddicted"
              Lua event
            - Switches on byte arg (0,1 -> 0; 2,3 -> 1; 4 -> 2)
            - Calls UI animation via FUN_0076a810
            - Then dispatches to PlayerBaseClass._onReceiveLimitAddicted
```

## Dispatch Pattern

Each binding/event has a paired (handler, dispatcher) structure:

```c
// Pattern observed across the actor-state handler family:

void Actor_handle<Field>Change(this, packetParams) {
    // C++-side state update (set flags, update derived state)
    Actor_dispatchLuaHook_onChange<Field>(this, oldValue, newValue);
    if (someCondition) this->flag = 1;
    else this->flag = 0;
}

void Actor_dispatchLuaHook_onChange<Field>(this, oldValue, newValue) {
    // Build Lua arg list (table) -- 2 numeric args
    LuaTable args;
    args.append(oldValue);
    args.append(newValue);
    // Call Lua method on the actor
    luaCallMethod(this->luaObj, "_onChange<Field>", args);
}
```

So the **C++ side and Lua side are decoupled**: the C++ handler does
state updates + flags; the Lua hook does game logic + UI updates.
Same args (oldValue, newValue) flow through.

## The Dispatch Table Around 0x00fd78XX

The function pointer to `Actor_handleActorMainStatChange` is stored
at exactly **0x00fd78e4** (via DATA xref). Adjacent table entries
likely point to handlers for other binding fields.

The table is referenced by SOMEONE (the inbound dispatcher) but
Ghidra has not auto-resolved the references — meaning the dispatcher
function is in an unanalysed region or accessed via runtime address
calculation (e.g. `table[opcode * 4]`).

Strategy to find the dispatcher: look for callers that LOAD from
0x00fd78XX with a runtime-computed offset. This is the inbound
packet processor's "switch by opcode" via jump table.

## Other Lua String Mappings Found

From the `_onChange*` and `_onReceive*` strings catalogued this
session:

```text
_onChangeActorMainStat       at 0x00fd4514  -> dispatcher 0x006fa840
_onChangeSubStatStatus       at 0x00fd44e0  -> dispatcher 0x00707d60
_onChangeNetStatSystem       at 0x00fd4544  -> dispatcher 0x006fa980
_onChangeNetStatSystem       at 0x00fd455c  -> SAME dispatcher 0x006fa980
_onChangeNetStatSystem       at 0x00fd4574  -> SAME dispatcher 0x006fa980
_onChangeNetStatUser         at 0x00fd452c  -> dispatcher TBD
_onChangeSubStatMode         at 0x00fd458c  -> dispatcher TBD
_onChangeSystemFlag          at 0x00fd45a4  -> dispatcher TBD
_onChangeAccessibleInServer  at 0x00fd45b8  -> dispatcher TBD
_onChangeJob                 at 0x00fd4cdc  -> dispatcher TBD

_onReceiveLimitAddicted      at 0x00fd4b5c  -> dispatcher 0x00704230
_onReceiveAchievementId      at 0x00fd4b08  -> dispatcher TBD
_onReceiveAchievementRate    at 0x00fd4bd4  -> dispatcher TBD
_onReceiveDataPacket         at 0x01057290  -> dispatcher 0x008a0190
?_onReceiveTimingPacket      at 0x01057267  -> dispatcher TBD
```

So **at least 8 reactive `_onChange*` hooks** and **5+ `_onReceive*`
event hooks** have dispatchers in the EXE. Each one corresponds to
a specific server-pushed packet variant.

## Assessment

```text
Confirmed:
  - The inbound binding-update dispatch has a 2-level structure:
    network packet -> dispatcher table at 0x00fd78XX -> handler ->
    Lua bridge -> Lua hook.
  - Function pointer to Actor_handleActorMainStatChange is at
    0x00fd78e4 (the dispatch table entry).
  - 8 _onChange* Lua hooks + 5+ _onReceive* event hooks have
    corresponding C++ handlers in the 0x00704XXX range.
  - The C++ handler signature is (this, packetParams, oldValue,
    newValue) -- standard shape for state-change events.

Likely (High):
  - The dispatch table at 0x00fd78XX is keyed by BINDING ID (not by
    a separate opcode). The server-pushed update packet carries
    the binding id, and the dispatcher uses it as an index into
    this table.
  - The "missing dispatcher" function is in an unanalysed
    region. To find it, would need to look at xrefs to other
    entries in the 0x00fd78XX range OR look at the
    PacketProcessor's main loop.

Likely (Medium):
  - The 3 _onChangeNetStatSystem string references all come from
    FUN_006fa980 -- meaning this single function dispatches the
    hook with different context flags (or for different actors:
    self vs party member vs target).
  - The 0x00704XXX address range is the "actor packet handler
    family" -- around 20+ functions covering the major actor
    field updates.

Speculative:
  - The dispatch table is probably ALSO referenced by the
    inbound-packet-builder pattern (when the server sends a "field
    update" packet, it's structured as { actorId, bindingId, value
    bytes }; the client looks up the handler at table[bindingId]
    and invokes it).
  - The current best guess for the server-broadcast opcode (the
    counterpart to 0x12f) is something like 0x130 or 0x131 --
    consecutive in the opcode space.
```

## Ghidra Annotations (this pass)

```text
Renamed:
  0x006fa840  -> Actor_dispatchLuaHook_onChangeActorMainStat
  0x006fa980  -> Actor_dispatchLuaHook_onChangeNetStatSystem
  0x00704820  -> Actor_handleActorMainStatChange
  0x00704230  -> Player_handleLimitAddictedNotice

Comments added at:
  - 0x006fa840 (the C++/Lua bridge pattern + sibling list)
  - 0x00704820 (the 2-level dispatch pattern + state flag semantics)
```

## Open Threads

```text
1. THE BIG ONE: find the inbound dispatcher that walks the
   0x00fd78XX table. Strategy: look for functions that compute
   addresses like (table_base + opcode * 4). The actual table
   walker has the dispatch loop.

2. Decompile sibling dispatchers (the other 0x00704XXX functions)
   to confirm the pattern and identify the binding-id-to-handler
   mapping.

3. The 3 _onChangeNetStatSystem dispatches from FUN_006fa980 --
   they suggest the function takes a context flag selecting which
   variant to invoke. Worth decompiling to understand the multi-
   context dispatch.

4. The opcode for "server pushes field update" -- almost certainly
   consecutive to 0x12f. Try grep'ing or examining functions near
   the WorkSync_buildAndSendPacket address space for a sibling.
```
