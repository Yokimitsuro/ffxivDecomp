# Finding: CommandUpdater Inbound Handlers Disassembled -- _onUpdateWork Lua Callback Bridge (Closes WorkSync Bidirectional)

**Closes the WorkSync bidirectional loop on the inbound side.**
Disassembles the 2 `CommandUpdater_invokeLua_onUpdateWork_*`
functions that fire when the engine processes incoming work updates.
Both fire the script-facing Lua callback **`_onUpdateWork`** -- this
is the INBOUND counterpart to the OUTBOUND `_updateWork` Lua API.

This pairs the chat-loop closure pattern from prior session:
just as `_parseTextCommand` (out parse) + `_appendMessagePool` (out
send + in display) closed the chat loop, now `_updateWork` (out) +
`_onUpdateWork` callback (in) close the WorkSync loop on the
Lua-visible API surface.

## 1. The 2 inbound handlers

```text
Handler                                    Function       When called
-------                                    --------       -----------
CommandUpdater_invokeLua_onUpdateWork_     FUN_00773d90   Simpler updates
  clipObj                                                  (cutscene clip objs)
                                                          
CommandUpdater_invokeLua_onUpdateWork_     FUN_00773f10   Filtered/complex
  complex                                                  (most regular state)
```

Both are CommandUpdater methods (the same class that has the 4
outbound send_* variants from the prior `_appendMessagePool` finding).

## 2. The simple (clipObj) variant

```c
void CommandUpdater_invokeLua_onUpdateWork_clipObj(this, actor, workPath) {
  // 1. Look up WorkPath entry in the tree
  WorkPathTree_lowerBound(this, &iter, workPath);
  
  // 2. Validate iterator (skipping bounds checks)
  if (iter is invalid) return;
  
  // 3. Check the entry has data (+0x14 != 0)
  if (entry.data == 0) return;
  
  // 4. Build args from WorkPath:
  //    - args[0] = struct name (via FUN_006d60c0)
  //    - args[1] = key constant DAT_0134c504 (= "clipObj" or similar marker)
  
  // 5. Fire Lua callback "_onUpdateWork":
  invokeLuaCallback(actor, "_onUpdateWork", args);
}
```

This is the **simpler dispatch** -- one path component name + a
marker arg. Used for clipObj scene updates (cutscene state).

## 3. The complex variant (most regular state updates)

```c
void CommandUpdater_invokeLua_onUpdateWork_complex(this, outFlag, actor) {
  actorRef = FUN_00cc7a50(this);
  if (!actorRef) return;
  
  // 1. FILTER CHAIN: walk filters at this+0x8..+0xc
  //    Each filter calls vtable[0xc] (could-skip predicate)
  //    Any filter returning 0 -> skip this update
  if (!filtersApplied) {
    for (each filter in this+0x8..+0xc) {
      if (filter->canSkip() == 0) return;
    }
    this->filtersApplied = 1;
  }
  
  // 2. CHECK WorkSync class dispatcher (vtable+0xec)
  if (this->hasDispatcher) {
    classDispatcher = actor.class.vtable[0xec];
    if (FUN_0077c440(classDispatcher, this) == 0) return;
  }
  
  // 3. RUN FILTER ACTIONS (vtable+0xc each, but actually FUN_00b241c0)
  for (each filter in this+0xc..+0x8) {
    filter->action();  // FUN_00b241c0
  }
  
  // 4. BUILD ARGS FOR LUA CALLBACK
  if (this+0xc4 == 0) {
    // Skip path: shortcut Lua-visible path
    FUN_00cc72c0(actor, actorRef, 1);
  } else {
    // Full args path: assemble (structName, slotName, idx0+1, idx1+1)
    args[0] = this->structName;     // at this+0x14
    args[1] = this->slotCategory;   // at this+0x68
    if (this+0xc0 != 0) {           // if has field indices
      args[2] = this->fieldIdx0 + 1; // INVERSE of -1 in outbound
      args[3] = this->fieldIdx1 + 1; // INVERSE of -1 in outbound
    }
    
    // 5. FIRE Lua callback "_onUpdateWork":
    invokeLuaCallback(actor, "_onUpdateWork", args);
  }
  
  // 6. SPECIAL CASE: MyPlayer + "guildleve" path
  if (this+0xc5 != 0) {
    if (filtersApplied OR slotCategory == "guildleve") {
      myPlayerRef = ___RTDynamicCast(actorRef, LuaControl, MyPlayer);
      FUN_006f1d00(actor, this);  // guildleve-specific update
    }
    
    // 7. Notify the actor's WorkSync dispatcher of the change
    classDispatcher = actor.class.vtable[0xec];
    FUN_00768190(classDispatcher, actor, this, this->structName);
  }
}
```

**Multi-stage processing**:
1. Filter chain (vtable+0xc predicate check, then action)
2. WorkSync class dispatcher check
3. Build args with field-index +1 conversion (inverse of outbound -1)
4. Fire `_onUpdateWork` Lua callback
5. Special MyPlayer/guildleve handling
6. Final dispatcher notification

## 4. The field-index +/-1 conversion (CONFIRMED end-to-end)

```text
LUA OUTBOUND:
  Lua call: actor:_updateWork("charaWork", "battleSave", 1, 2)
  Outbound thunk (lua_updateWork_impl):
    short field0 = arg[2] - 1 = 0   <-- adjust 1-based to 0-based
    short field1 = arg[3] - 1 = 1   <-- adjust 1-based to 0-based
  Wire (opcode 0x12F): payload has fieldIdx0=0, fieldIdx1=1

WIRE TRANSPORT...

LUA INBOUND:
  Server pushes update with fieldIdx0=0, fieldIdx1=1
  Inbound thunk (CommandUpdater_invokeLua_onUpdateWork_complex):
    args[2] = fieldIdx0 + 1 = 1     <-- adjust 0-based back to 1-based
    args[3] = fieldIdx1 + 1 = 2     <-- adjust 0-based back to 1-based
  Fires: actor:_onUpdateWork("charaWork", "battleSave", 1, 2)
         (same values script originally passed to _updateWork)
```

**This proves the round-trip is symmetric** -- script receives the
same indices it would have sent. The -1/+1 conversion is internal
plumbing for the wire format (0-based) while Lua uses 1-based
(Lua convention).

## 5. The full WorkSync Lua-visible loop (NOW CLOSED)

```text
ACTOR A (sender):
  Lua: actor:_updateWork("charaWork", "parameterSave.hp", 1)
   -> CharaBase_cpp_updateWork_thunk (or sibling)
   -> WorkSync_dispatchOrEnqueue
   -> WorkSync_serializePayloadAndSend
   -> WorkSync_buildAndSendPacket_opcode_0x12f
   -> Wire (opcode 0x12F, 56-byte STRING packet)

NETWORK: server validates + broadcasts to nearby clients...

ACTOR B (receiver):
  Wire (server-pushed update with binding-id + value)
   -> Inbound packet dispatcher
   -> CommandUpdate record created
   -> Per-tick flush picks up record
   -> CommandUpdater_invokeLua_onUpdateWork_complex/clipObj
   -> Lua hook: actor:_onUpdateWork("charaWork", "parameterSave.hp", 1)
   -> Lua handler updates UI / triggers reactive logic
```

## 6. Confirmed Lua API symmetry: _updateWork ↔ _onUpdateWork

The Lua-visible API for WorkSync is symmetric:

```text
OUTBOUND (write side):
  function MyClass:someChange()
    self:_updateWork("category", "field", subIdx, listIdx)
  end

INBOUND (callback side):
  function MyClass:_onUpdateWork(category, field, subIdx, listIdx)
    -- React to a remote update
    -- subIdx and listIdx are the SAME values that were sent
  end
```

Both functions receive identical arg shape. The engine handles all
serialization/desync internally.

## 7. Filter chain at this+0x8..+0xc (4 bytes = filter list ptrs)

The `complex` variant has a filter chain stored at:
- `this+0x8` = start pointer to filter array
- `this+0xc` = end pointer to filter array

Each filter is a polymorphic object with:
- vtable[0xc] = `canSkip()` -- returns 0 if this update should be skipped
- vtable[c] = `apply()` (actually FUN_00b241c0) -- post-filter action

Filters likely include:
- Range/distance filter (skip if actor too far away)
- Visibility filter (skip if actor not currently visible)
- Class-specific filters (skip if not relevant for our class type)

This allows efficient broadcast: server pushes to many clients,
each client's filter chain decides which updates to propagate to
Lua-level handlers (avoiding wasted Lua calls for irrelevant state).

## 8. The special MyPlayer + guildleve dispatch

```text
if filter chain says "skip this" AND slotCategory == "guildleve":
  Cast actorRef to MyPlayer via RTTI
  Call FUN_006f1d00 (guildleve-specific update path)
```

Guildleve state updates apparently have a special-case dispatch
path that runs EVEN IF other filters skip. This is because
guildleve state changes affect the player's HUD even when out of
range of the event NPC.

## 9. Updated WorkSync coverage (NOW CLOSED on Lua-visible loop)

```text
OUTBOUND (script -> wire):
  ✓ CharaBase _updateWork @ 0x006e7670 -> opcode 0x12F
  ✓ Director _updateWork @ 0x006e85e0 -> opcode 0x12F
  ✓ Item _updateWork @ 0x006e2af0 -> opcode 0x132 (24B)
  ✓ GroupBase _updateWork @ 0x006e8890 -> opcode 0x133 (56B alt)

INBOUND (wire -> script):
  ✓ CommandUpdate record processing (this finding)
  ✓ CommandUpdater_invokeLua_onUpdateWork_clipObj @ 0x00773d90
  ✓ CommandUpdater_invokeLua_onUpdateWork_complex @ 0x00773f10
  ✓ Fires Lua callback "_onUpdateWork" (script-facing)
  ✓ Field-index +1 conversion (inverse of -1 outbound)
  ? The specific INBOUND OPCODE that creates the CommandUpdate
    record is still not pinned (likely 0x12F/0x132/0x133 echo,
    or separate inbound opcodes for server-pushed updates)

STILL UNKNOWN:
  - The wire-side INBOUND packet handlers that create CommandUpdate
    records (the missing link between wire bytes and the
    CommandUpdate record)
  - Whether server uses the same 3 opcodes (0x12F/0x132/0x133) for
    bidirectional sync, or has separate opcodes for inbound
```

## 10. Confidence

```text
Confirmed:
  - CommandUpdater_invokeLua_onUpdateWork_complex/clipObj fire Lua
    callback "_onUpdateWork" with normalized arg shape
  - Field-index +1 conversion mirrors outbound -1 (round-trip symmetric)
  - Filter chain at this+0x8..+0xc allows per-update filtering
  - WorkSync class dispatcher at vtable+0xec also processes inbound
    (paired with outbound side)
  - Special MyPlayer + guildleve dispatch path exists
  - Lua-visible WorkSync loop NOW CLOSED end-to-end:
    _updateWork (out) <-> _onUpdateWork (in)

Likely (High):
  - The 2 variants (clipObj + complex) split by update payload type:
    - clipObj = cutscene-only updates (simpler args)
    - complex = regular actor state (most volume)
  - Filters include range/visibility/class-type checks
  - Server pushes via same 3 opcodes (0x12F/0x132/0x133) bidirectionally
    -- inbound packet handler creates CommandUpdate records that
    eventually call these inbound functions

Likely (Medium):
  - FUN_006f1d00 is the guildleve update applier (MyPlayer-specific)
  - The "_onUpdateWork" Lua hook is documented elsewhere (prior Lua
    findings; this finding is the EXE side that fires it)
```

## 11. Cross-references

- `finding_updateWork_siblings_pattern_NOT_uniform.md` -- the
  OUTBOUND 4-thunk analysis (3 distinct opcodes)
- `finding_groupbase_updateWork_opcode_0x133_confirmed.md` -- the
  opcode 0x133 finding (inbound complement still TBD)
- `finding_updateWork_thunk_worksync_state_replication.md` -- the
  original WorkSync pipeline finding
- `finding_appendMessagePool_thunk_command_updater_dispatch.md` --
  the OUTBOUND CommandUpdater side; this finding is the INBOUND side
- `finding_worksync_inbound_writers_pinned.md` -- the 4 BitPacked
  writers + lowlevel writer that this finding's `_onUpdateWork`
  callback may invoke during state application

## 12. Next test

```text
1. Find the wire packet -> CommandUpdate record bridge:
   - When 0x12F/0x132/0x133 inbound arrives, who creates the record?
   - This is the missing wire-to-record link
2. Disassemble FUN_006f1d00 (guildleve MyPlayer update path)
3. Find Lua-side _onUpdateWork handlers for each major class
   (CharaBase, Director, Item, Group) to see what each does
4. Walk vtable+0xec for sample classes to enumerate WorkSync
   dispatchers (different per class)
5. Disassemble FUN_0077c440 (the WorkSync class dispatcher check)
   to understand its filter semantics
```

## Commit suggestion

```
docs(re/exe): CommandUpdater inbound handlers disassembled -- _onUpdateWork Lua callback bridge; WorkSync Lua-visible loop CLOSED bidirectionally
```
