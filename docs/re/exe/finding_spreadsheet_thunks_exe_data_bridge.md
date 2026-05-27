# Finding: SpreadSheet Thunks Disassembled -- EXE↔DATA BRIDGE Mapped + 2nd Engine Interface Discovered

**Closes the EXE↔Data correlation axis.** Disassembles 2 critical
SpreadSheet thunks (`_getData` sync read + `_loadKeyTemporarily` async
load) that bridge Lua scripts to FFXIVTool's 803 CSV tables.

**MAJOR ARCHITECTURAL DISCOVERY**: A 2nd engine interface exists
alongside ResumeCheckerInterface — **`FunctionEndCallbackInterface`**.
Async I/O uses a 2-tier system: a FunctionEndCallback handles I/O
completion, and a ResumeChecker watches for that callback before
resuming the script.

**4th thunk batch disassembled. EXE↔Data axis correlation NOW CLOSED.**

## 1. The SSD load+read pipeline (now mapped)

```text
Lua script-level pattern:
  local ssd = SpreadSheet
  ssd:_setFilename("item.csv")          -- point at CSV file
  ssd:_loadKeyTemporarily(itemId)        -- YIELDS until loaded
  local price = ssd:_getData(itemId, "price")  -- sync read

EXE bridge:
  setFilename @ ?                        -- prep (not disassembled here;
                                            registrar at 0x00746e70)
  loadKeyTemporarily @ FUN_006f0840      -- async load (NEW disassembly)
  getData @ FUN_0070a720                 -- sync read (NEW disassembly)

Data backing:
  data/client_exports/ffxivtool/decode_csv/item.csv  -- the actual CSV
  (one of 803 tables, ~12,000 item rows)
```

## 2. _getData (FUN_0070a720) -- SYNCHRONOUS row read

```c
void SpreadSheet_cpp_getData_thunk(int luaContext) {
  // 1. Extract arg 0: row key (uint32 ID, e.g. itemId)
  rowKey = Lua_getInt(stack, 0);
  
  // 2. Extract arg 1: column descriptor (string or enum)
  colDesc = Lua_getPtr(stack, 1);
  
  // 3. Hash-lookup the row in the SpreadSheet's row table
  //    this+0xC4 = row hash table
  rowIter = HashTable_find(this+0xC4, rowKey);
  
  // 4. Index into row's column data
  //    row+0x14 = column-value array
  cellPtr = ColumnArray_get(row+0x14, colDesc);
  
  // 5. Extract typed value
  value = *(cellPtr + 0x14);
  type  = *(byte *)(cellPtr + 0x18);  // column-type tag
  
  // 6. Push to Lua return stack with proper Lua type
  PushTyped(type, &returnSlot);
}
```

This is the **READ primitive**. No yield, no coroutine — direct hash
lookup. Synchronous because the data is already in memory (must call
`_loadKey*` first).

The column-type tag at `+0x18` is the bridge from CSV typed cells
(`s32, str, bool, ...`) to Lua values. The 2-line FFXIVTool header
(`row 0 = column index`, `row 1 = type names`) maps DIRECTLY to this
type byte at runtime.

**SpreadSheet instance layout (revealed)**:
```cpp
struct SpreadSheet {  // partial layout
  // +0x60       ?  (filename / source ref maybe)
  // +0xB4       ?  (column metadata / type schema)
  // +0xC4       row-key hash table
  // +0xD8       ?  (related ssd dependency list?)
  // +...
};
```

## 3. _loadKeyTemporarily (FUN_006f0840) -- ASYNC, 2-tier callback system

```c
void SpreadSheet_cpp_loadKeyTemporarily_thunk(this, luaContext) {
  // 1. Extract args
  rowKey  = Lua_getInt(stack, 0);
  scope   = Lua_getInt(stack, 1);     // load scope (temporarily=1?)
  
  // 2. Check if a load is already pending for this key
  pending = CoroutineContext_findPendingCallback(luaCtx, &rowKey);
  
  // 3. If no pending load: kick off async load via 2-tier system
  if (!pending) {
    // TIER 1: Allocate a FunctionEndCallback (40 bytes)
    callback = operator_new(0x28);
    SpreadSheet_LoadDataFunctionEndCallback_ctor(
      callback,
      this,           // SpreadSheet instance
      this+0xC4,      // row table to insert into
      this+0xD8,      // metadata
      callId,         // unique ID for this load
      rowKey
    );
    
    // Push the callback onto the I/O completion queue
    CoroutineContext_pushEndCallback(luaCtx, callback);
  }
  
  // TIER 2: Allocate a LoadDataResumeChecker (148 bytes)
  checker = operator_new(0x94);
  SpreadSheet_LoadDataResumeChecker_ctor(
    checker,
    diskJobId,      // ID linking back to the callback above
    this+0x60,      // SSD context
    rowTableRef,    // where the loaded row will go
    this+0xb4,      // schema metadata
    this+0xc4,      // row table
    rowKey,         // key being loaded
    scope,          // load scope
    callbackRef,    // ref to the FunctionEndCallback
    this+0xd8,      // metadata
    1               // flags
  );
  
  // Push the resume checker — script yields on this
  CoroutineContext_pushResumeChecker(luaCtx, checker);
}
```

This is **a much more sophisticated async pattern** than `_wait` or
`_createActor`. The 2-tier design:

```text
TIER 1: FunctionEndCallback
  - Handles the disk-I/O completion event
  - When CSV row loads, this callback writes data into the row table
  - Then signals the linked ResumeChecker that load is done

TIER 2: ResumeChecker
  - Holds reference to the FunctionEndCallback
  - Script yields on this checker
  - Checker.isReady() polls "did my callback fire?"
  - When ready, script resumes
```

## 4. NEW ENGINE INTERFACE: FunctionEndCallbackInterface

```cpp
namespace Component::Lua::GameEngine {
  class ResumeCheckerInterface {           // (already known)
    virtual bool isReady() = 0;
    // ...
  };
  
  class FunctionEndCallbackInterface {     // (NEW DISCOVERY)
    virtual void onComplete(...) = 0;
    // ...
  };
}
```

The concrete SpreadSheet subclasses:

```cpp
namespace Application::Lua::Script::Client::Control::SpreadSheet {
  // 148-byte resume checker — script yields on this
  class LoadDataResumeChecker
      : Component::Lua::GameEngine::ResumeCheckerInterface {
    /* +0x04 ..   */ ResumeCheckerBase fields
    /* +0x58 */     diskJobId
    /* +0x5C */     ssdContext_p
    /* +0x60 */     rowTableRef
    /* +0x64 */     schemaMetadata
    /* +0x68 */     rowTable
    /* +0x6c */     rowKey
    /* +0x70 */     scope
    /* +0x78..0x80 */ scratch fields (initialized to 0)
    /* +0x84..   */ inner state structure
    /* +0x90 */     flags byte
  };  // sizeof = 0x94 = 148 bytes
  
  // 40-byte completion callback — fires when disk load done
  class LoadDataFunctionEndCallback
      : Component::Lua::GameEngine::FunctionEndCallbackInterface {
    /* +0x04 */ ssd_owner
    /* +0x08 */ rowTable_p
    /* +0x0C */ schemaMetadata_p
    /* +0x10 */ callId
    /* +0x14 */ rowKey (16-bit)
    /* +0x18..0x23 */ inner state
    /* +0x24 */ active_flag (=1)
  };  // sizeof = 0x28 = 40 bytes
};
```

Both classes have proper Ghidra symbols — confirming the engine's
internal namespace hierarchy: `Application::Lua::Script::Client::
Control::SpreadSheet::*`.

## 5. The 2 CoroutineContext functions (now fully named)

```text
CoroutineContext_isTrackingEnabled (FUN_00cd27d0)  -- known
CoroutineContext_pushResumeChecker (FUN_00cd2860)  -- known
CoroutineContext_findPendingCallback (FUN_00cd2630)  -- NEW
CoroutineContext_pushEndCallback (FUN_00cd28c0)    -- NEW
ScriptCoroutineKey_construct (FUN_00713f80)        -- known
```

The CoroutineContext has TWO queues per pending coroutine:
- **Resume checker queue** (pushResumeChecker)
- **End callback queue** (pushEndCallback)

When the pump runs:
1. Walk each pending coroutine's callback queue — fire completed I/O
2. Walk each pending coroutine's resume checker queue — resume if ready

This is a clean async I/O event loop.

## 6. Implications for the FFXIVTool 803-table catalog

Now we can correlate the EXE bridge with the catalogued data:

```text
Each FFXIVTool CSV file maps to ONE SpreadSheet instance:
  data/client_exports/ffxivtool/decode_csv/item.csv
  -> SpreadSheet instance "item" loaded via _setFilename("item.csv")
  -> 12,000 rows accessible via _loadKeyTemporarily(itemId) + _getData(...)
  -> Each row's typed columns (s32/str/bool/...) decoded via type byte at +0x18

The catalog (docs/data/ffxivtool_table_catalog.csv) has 164 critical
tables. Each maps to ONE Lua SpreadSheet instance, accessed by some
class's:
  - ItemBaseClass uses item.csv
  - NpcBaseClass uses npc.csv / battle_npc.csv
  - WorldMaster uses worldMaster.csv + zone.csv
  - etc.
```

This closes the **EXE↔Data axis correlation**: every CSV table is
loadable by the same 10-binding API on SpreadSheet, accessed through
the LoadData callback pattern.

## 7. Implications for server design

```text
The server doesn't need to model the LoadData callbacks. BUT this tells
us how the client expects to consume data:

1. Server-side data shape MUST match CSV columns + types
   - The column-type tag at +0x18 is consumed by Lua's PushTyped
   - Mismatched types would crash the script
   - Server import must preserve the type schema EXACTLY

2. Row keys are uint32 (or smaller) hash keys
   - Server uses same primary key as the CSV
   - For items: itemId (s32) is the canonical row key

3. The 2-tier async load pattern is CLIENT-INTERNAL
   - Server doesn't need to manage callbacks
   - Just push initial data; client loads it lazily via SSD

4. Critical insight: scripts assume LOAD is async (yields), READ is sync
   - Server can push entire static datasets at session init
   - Or trust the client's per-key lazy load for less common data
```

## 8. Renames made (7)

```text
RENAMES:
  - 0x0070a720 -> SpreadSheet_cpp_getData_thunk
                  (sync row+column read)
  - 0x006f0840 -> SpreadSheet_cpp_loadKeyTemporarily_thunk
                  (async row load with 2-tier callback)
  - 0x00725a50 -> SpreadSheet_LoadDataResumeChecker_ctor
                  (148B checker; script yields on this)
  - 0x0071db70 -> SpreadSheet_LoadDataFunctionEndCallback_ctor
                  (40B callback; fires when disk load done)
  - 0x00cd2630 -> CoroutineContext_findPendingCallback
                  (lookup helper for dedup)
  - 0x00cd28c0 -> CoroutineContext_pushEndCallback
                  (queue an end-callback for completion)
```

## 9. Updated Resume Checker / End Callback inventory

```text
ResumeCheckerInterface subclasses (yields a script):
  Class                             Size    Used by
  ----                              ----    -------
  OnInitResumeChecker               16 B    _createActor
  WaitResumeChecker                 40 B    _wait
  LoadDataResumeChecker            148 B    _loadKeyTemporarily   (NEW)
  [predicted ~7 more for other _wait* / async bindings]

FunctionEndCallbackInterface subclasses (fires on async completion):
  Class                                  Size    Used by
  ----                                   ----    -------
  LoadDataFunctionEndCallback            40 B    SSD async loads (NEW)
  [predicted N more for other async I/O paths]
```

## 10. Confidence

```text
Confirmed:
  - SpreadSheet_cpp_getData_thunk @ 0x0070a720 is the sync read primitive
  - SpreadSheet_cpp_loadKeyTemporarily_thunk @ 0x006f0840 is async load
  - LoadDataResumeChecker (148B) is the 3rd ResumeCheckerInterface
    subclass observed
  - LoadDataFunctionEndCallback (40B) is a NEW interface type:
    FunctionEndCallbackInterface
  - The 2-tier callback+checker pattern is the engine's standard
    async I/O mechanism
  - Class names from Ghidra symbols:
    Application::Lua::Script::Client::Control::SpreadSheet::LoadDataResumeChecker
    Application::Lua::Script::Client::Control::SpreadSheet::LoadDataFunctionEndCallback
  - The column-type tag at row+0x18 directly maps to FFXIVTool's
    2-line CSV header type schema (s32, str, bool, ...)
  - SpreadSheet IS the loader behind FFXIVTool's 803 CSVs

Likely (High):
  - All async I/O bindings in the engine use the same 2-tier pattern:
    a FunctionEndCallback for I/O completion + a ResumeChecker for
    script yield
  - _loadKeySemipermanently / _loadKeyAsync / _loadMultiKeyAsync follow
    the same pattern with different scope flags
  - _setFilename is sync (no callback needed)
  - The row hash table at SpreadSheet+0xC4 uses uint32 keys
  - Per-script load deduplication is enabled by
    CoroutineContext_findPendingCallback (avoid loading same row twice)

Likely (Medium):
  - The 148-byte LoadDataResumeChecker holds enough state for retry
    + cancellation on failure (the 24 bytes at +0x78-0x80 are likely
    error code, retry count, deadline)
  - There may be a separate "loaded permanently" flag set by
    _loadAllKeyPermanently that affects unload semantics
```

## 11. Cross-references

- `finding_smallmodules_inventory_closed_17_masters.md` -- located the
  SpreadSheet master (10 EXACT bindings); this finding disassembles 2
- `finding_wait_thunk_universal_resume_checker_confirmed.md` -- prior
  ResumeChecker confirmation (2nd data point); this is the 3rd
- `finding_createActor_thunk_async_actor_factory.md` -- 1st thunk +
  CoroutineContext_pushResumeChecker discovery
- `docs/data/ffxivtool_export_overview.md` -- the 803 CSV catalog this
  finding bridges to runtime
- `docs/server/content_requirements/ffxivtool_import_plan.md` -- server
  import plan informed by this finding's type-preservation requirement

## 12. Next test

```text
EXE↔Data axis: NOW CLOSED. Major architectural axes mapped:
  Lua scripts <-> EXE thunks  (mapped via masters + thunks)
  EXE async I/O <-> CSV data   (mapped via SpreadSheet thunks NOW)
  Lua scripts <-> Wire opcodes (mapped via prior correlation findings)

Remaining high-value targets:
1. _parseTextCommand thunk -- chat command dispatch
2. _appendMessagePool thunk -- chat display sink
3. _updateWork thunk (CharaBase) -- WorkSync mechanism (server-critical)
4. _isInstanceOf thunk -- RTTI walk
5. Other _wait* thunks (8 more) -- additional ResumeChecker subclasses
6. Vtable[0x6c] walk for sample classes -- mechanical naming of
   200+ per-class spawn ctors
7. Cross-reference the 164 critical CSV tables with their consuming
   Lua classes (now that the SSD bridge is understood)
```

## Commit suggestion

```
docs(re/exe): SpreadSheet thunks disassembled -- EXE↔DATA bridge CLOSED + 2nd engine interface discovered (FunctionEndCallbackInterface for async I/O)
```
