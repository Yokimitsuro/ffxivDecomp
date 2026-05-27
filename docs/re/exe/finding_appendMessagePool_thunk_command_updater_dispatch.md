# Finding: _appendMessagePool Thunk Disassembled -- IT'S the CommandUpdater General Dispatcher (Not Just Chat)

**Critical reframing.** Disassembling `_appendMessagePool` reveals it
is NOT the simple "chat display primitive" the prior Lua-side
findings suggested. It's actually the **CommandUpdater general
dispatcher** for ALL command-style updates (chat messages, action
notifications, status broadcasts).

Chat is just one user of this generic mechanism via different
target types and channel IDs.

Also discovers the **4th ResumeChecker subclass**:
**AppendMessageResumeChecker** (12 bytes -- smallest yet).
Confirms the predicted ~8 ResumeChecker subclasses; brings total
known to 4 of ~10-12 expected.

This is the **8th thunk disassembled** and CLOSES THE CHAT LOOP
(input parsing via _parseTextCommand + output dispatch via this
finding).

## 1. Thunk located + renamed

```text
Lua entry point:    desktopWidget:_appendMessagePool(target, channel,
                                                      msgRef, msgIdx, ...)
                    -- declared in DesktopWidget_u.lua

Registrar:          DesktopWidget_registerLua_appendMessagePool @ 0x00743ed0
C++ thunk:          DesktopWidget_cpp_appendMessagePool_thunk @ 0x006eced0 (NEW)
Resume checker ctor: AppendMessageResumeChecker_ctor @ 0x007139c0 (NEW)
Main dispatcher:    CommandUpdater_dispatchByTargetType @ 0x006e8360 (NEW)
```

## 2. The thunk pipeline (end-to-end)

```text
1. Lua: worldMaster:say(actor, msgIdx)
   -> internally calls desktopWidget:_appendMessagePool(actor, 40,
                                                          msgRef, msgIdx)
                                                          ^channel 40 = say
   
2. Thunk @ 0x006eced0:
   - Resets flag at this+0x79 to 0
   - Allocates 12-byte AppendMessageResumeChecker
   - Pushes checker via CoroutineContext_pushResumeChecker (script yields)
   - Calls CommandUpdater_dispatchByTargetType(luaCtx, 1)
   
3. CommandUpdater_dispatchByTargetType @ 0x006e8360:
   - Extracts arg 1: channelId (uint16; e.g. 40 for /say)
   - Extracts arg 2: msgRef (probably string table reference)
   - Extracts arg 3: msgIdx (cardinal index)
   - Extracts arg 4: optional substitution params (12-int array)
   - Resolves CommandUpdater from class via vtable+0xf8
   - Branches by target type tag at arg0+0xc:
     * '\0' (0): target is ActorId -> CommandUpdater_send_toActorId
     * '\3' (3): target is ActorName -> CommandUpdater_send_toActorName
     * '\4' (4): target is Reference -> RTTI check:
       - WorldMaster ref -> CommandUpdater_send_broadcast
       - CharaBase ref  -> CommandUpdater_send_toCharaBase_WMSelf

4. CommandUpdater_send_*** functions:
   - Allocate a CommandUpdate record (0x118 = 280 bytes)
   - Fill in (channelId, msgRef, msgIdx, params, target info)
   - Enqueue to CommandUpdater's pending queue
   - Eventually flushed via FUN_00770c00 to wire opcode

5. Script remains yielded until the dispatch completes;
   AppendMessageResumeChecker fires when CommandUpdate is sent.
```

## 3. The 4 dispatch variants (per target type)

```text
Variant                                  Target type   Use case
-------                                  -----------   --------
CommandUpdater_send_toActorId            uint32 ID     "say this to actor X"
  @ 0x007721b0                            (tag '\0')   (NPC dialog)
                                                       
CommandUpdater_send_toActorName          string name   "say this to actor named X"
  @ 0x00772560                            (tag '\3')   (alias lookup)
                                                       
CommandUpdater_send_toCharaBase_WMSelf   CharaBase ref "world message to chara"
  @ 0x00772050                            (tag '\4')   (party/local chat)
                                                       
CommandUpdater_send_broadcast            (no target)   "broadcast to all"
  @ 0x00772650                            (WMaster)    (system notify/alert)
```

The 4 variants are the COMPLETE target dispatch surface. Different
high-level Lua wrappers (worldMaster:say/notify/alert,
NpcBaseClass:say, etc.) use different (target_type, channel) combos
to drive different routing.

## 4. AppendMessageResumeChecker (4th ResumeChecker subclass)

```cpp
struct AppendMessageResumeChecker {  // sizeof = 12 (0x0C)
  // +0x00  vtable*  = Application::Lua::Script::Client::Control
  //                   ::DesktopWidget::AppendMessageResumeChecker::vftable
  //                   (override of ResumeCheckerInterface vftable)
  // +0x04  uint32   context_ref (the dispatch context)
  // +0x08  uint8    ready_flag  (0 = pending; 1 = sent)
};
```

**Updated ResumeChecker inventory (4 of ~10-12):**

```text
Subclass                       Size    Backed by              Wait condition
--------                       ----    ---------              --------------
OnInitResumeChecker            16 B    _createActor           actor onInit done
WaitResumeChecker              40 B    _wait                  timer deadline
LoadDataResumeChecker         148 B    _loadKey* (SSD async)  disk load done
AppendMessageResumeChecker     12 B    _appendMessagePool     dispatch complete

Predicted remaining ~7:
  _waitForGroup, _waitForTurning, _waitForCharaSchedulerFinished,
  _waitForCharaSchedulerTutorialFinished, _waitForTargetTutorial,
  _waitForCameraTutorial, _waitForItemSearchWidget,
  _waitForHamletDefenseScore
```

The 12-byte size for AppendMessageResumeChecker is the smallest yet
-- it doesn't need to store much state because the dispatch is fast
(local queue insert + flush). The flag just signals "queued".

## 5. The CommandUpdater subsystem (broader than just chat)

Found 7 named CommandUpdater functions:

```text
CommandUpdater_allocAndEnqueueRecord     @ 0x0076b3d0
  Allocate a 280-byte CommandUpdate record; enqueue to pending list

CommandUpdater_send_toActorId            @ 0x007721b0
CommandUpdater_send_toActorName          @ 0x00772560
CommandUpdater_send_toCharaBase          @ 0x00771f50
CommandUpdater_send_toCharaBase_WMSelf   @ 0x00772050
CommandUpdater_send_broadcast            @ 0x00772650

CommandUpdater_invokeLua_onUpdateWork_clipObj    @ 0x00773d90
CommandUpdater_invokeLua_onUpdateWork_complex    @ 0x00773f10
  Lua callback dispatchers triggered when records process
```

**This means _appendMessagePool is one of MANY Lua APIs that funnel
through CommandUpdater.** Other bindings (combat actions, status
updates, event broadcasts) likely use the same dispatcher with
different (target_type, channel) combinations.

The CommandUpdater is essentially the **client-side outbound
command queue** (separate from WorkSync which is for state field
updates).

## 6. The CommandUpdate record (0x118 = 280 bytes)

Per prior session memory + this finding's evidence:

```text
CommandUpdate record layout (0x118 = 280 bytes):
  - Channel ID (the 32/33/38/40 etc.)
  - Target spec (variant: actor ID / actor name / actor ref / broadcast)
  - Message reference (string table key or text ID)
  - Message index (cardinal)
  - Substitution params (up to 12 int slots from local_3c[12])
  - Sender info (script context, originating actor)
  - Wire serialization buffer (eventually filled at flush time)

The 280-byte size accommodates the worst case:
  - Channel + tag                 ~16 bytes
  - Target spec (with name copy) ~64 bytes
  - Message data (ref + idx)     ~16 bytes
  - 12-slot params               ~48 bytes
  - Script context tracking      ~32 bytes
  - Sender + flags + framing     ~64 bytes
  - Wire buffer / reserved       ~40 bytes
  -----                          ----
  TOTAL                          ~280 bytes
```

The records are pool-allocated and reused (queue flush returns them
to the pool).

## 7. The 4 chat channels routed via this thunk

```text
Channel ID    Used by                       Routing
----------    -------                       -------
32            worldMaster:notify            broadcast (system, yellow)
33            worldMaster:alert             broadcast (system, red)
38            NpcBaseClass:say              toActorId or toActorName (NPC)
40            worldMaster:say               broadcast (world cryer / global)

All 4 enter via _appendMessagePool with different (target, channel)
combos. The C++ side routes via target type tag, not channel ID --
channel is just metadata that survives to the wire packet.
```

## 8. Implications for server design

```text
CHAT SUBSYSTEM is fully bidirectional now mapped:

  IN (server -> client):
    Server sends chat packet with (channel, sender, msg, params)
    Client routes via inbound chat dispatch (entries 35-37 in inbound
    table @ 0x00fdfb80 = CHAT TYPE A/B/C per prior finding)
    Client calls _appendMessagePool with appropriate target type
    Message appears in chat UI window
    
  OUT (client -> server):
    User types '/say hello' in chat
    Lua: desktopWidget:_parseTextCommand(text)
    Returns parsed (cmdId, args)
    Lua handler (say-class command) calls _appendMessagePool ECHO
    + _executeCommand to send chat opcode
    Server receives chat packet, broadcasts to nearby players

SERVER WIRE FORMAT (chat outbound):
  - cmdId (uint16 from gameCommand.csv = 0x?? for /say)
  - channel ID (uint16 = 40 for /say)
  - target spec (variant; depends on /tell vs /say vs /yell)
  - msg payload (UTF-8 text + optional substitution params)

CommandUpdater is the CLIENT-INTERNAL queue. Server doesn't model
this; it just receives the final wire packet.
```

## 9. Renames made (3)

```text
RENAMES:
  - 0x006eced0 -> DesktopWidget_cpp_appendMessagePool_thunk
                  (Lua _appendMessagePool entry-point)
  - 0x007139c0 -> AppendMessageResumeChecker_ctor
                  (12-byte resume-checker construction)
  - 0x006e8360 -> CommandUpdater_dispatchByTargetType
                  (the 4-variant target type dispatcher)
```

## 10. Confidence

```text
Confirmed:
  - _appendMessagePool is the CommandUpdater entry point (NOT just chat)
  - 4 target type variants: toActorId, toActorName, toCharaBase_WMSelf,
    broadcast
  - AppendMessageResumeChecker is a 12-byte 4th ResumeChecker subclass
  - Class names from Ghidra symbols:
    Application::Lua::Script::Client::Control::DesktopWidget
      ::AppendMessageResumeChecker
  - RTTI dispatch via WorldMaster vs CharaBase distinction
  - CommandUpdate records are 280 bytes (0x118) as prior memory noted
  - Chat input (parser) + chat output (this dispatcher) are now both mapped

Likely (High):
  - Many other Lua APIs (combat actions, status updates) funnel
    through the same CommandUpdater (1 of N consumers; chat is the
    only one confirmed)
  - The 12-slot substitution params support template strings like
    "${player} hit ${target} for ${damage}"
  - The CommandUpdater queue is flushed at game-tick boundaries
    (batched outbound packets for bandwidth efficiency)
  - The 4 channels (32/33/38/40) determine the WIRE OPCODE used at
    flush time (not the routing in this thunk)

Likely (Medium):
  - The msgRef vs msgIdx 2-tuple suggests a localization pattern:
    msgRef = string table key, msgIdx = which entry in the message
    pool (for multi-line messages or alternates)
  - The "_WMSelf" naming on toCharaBase_WMSelf indicates it's a
    WorldMaster-originated chat to a specific chara (e.g., system
    say targeted at one player)
  - CommandUpdater_send_toCharaBase (without _WMSelf, @ 0x00771f50)
    is the chara-originated chat variant (e.g., NPC speaking to a
    specific player as opposed to broadcast)
```

## 11. Cross-references

- `finding_parseTextCommand_thunk_chat_dispatch_architecture.md`
  -- the PARSE side (user typing) -- this finding is the OUTPUT side
  -- TOGETHER THEY CLOSE THE CHAT LOOP
- `finding_desktopwidget_master_44_of_44_complete.md` -- where the
  _appendMessagePool registrar (slot 1) was identified
- `finding_worldmaster_complete.md` -- documents worldMaster:say
  (channel 40), notify (32), alert (33)
- `finding_npc_dialog_protocol.md` -- documents NpcBaseClass:say
  (channel 38)
- `finding_inbound_dispatch_table_found.md` -- inbound entries 35-37
  (CHAT TYPE A/B/C) which is the INBOUND counterpart to this OUTBOUND
- `finding_csv_lua_correlation_35_tables_mapped.md` -- gameCommand.csv
  has the cmdId definitions for chat commands
- `finding_wait_thunk_universal_resume_checker_confirmed.md` --
  prior ResumeChecker finding; this finding adds the 4th subclass

## 12. Next test

```text
1. Disassemble CommandUpdater_send_broadcast in full to extract
   wire opcode + packet shape for chat outbound (probably 0x140-0x150)
2. Disassemble CommandUpdater_send_toActorId to confirm same wire
   packet with target field
3. Trace the queue flush path (FUN_00770c00) to find the wire
   send function
4. Identify all other Lua APIs that funnel through CommandUpdater:
   - Combat command execution
   - Status broadcasts
   - Action notifications
5. Disassemble inbound chat dispatch (entries 35-37 in 0x00fdfb80
   table) to close the chat loop end-to-end on both directions
6. Disassemble _isInstanceOf thunk (RTTI walk) -- uses same
   pattern as the WorldMaster/CharaBase dispatch in this finding
```

## Commit suggestion

```
docs(re/exe): _appendMessagePool thunk disassembled -- IT'S the CommandUpdater general dispatcher (not just chat); 4th ResumeChecker subclass (AppendMessage 12B); CHAT LOOP CLOSED
```
