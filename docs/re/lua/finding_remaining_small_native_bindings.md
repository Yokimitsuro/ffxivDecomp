# Finding: Remaining Small _u.lua Files — Debug/Table/SpreadSheet/CutScene (28 Bindings)

Cleans up the last small `_u.lua` files. Covers Debug, Table,
SpreadSheet, and CutScene system bindings.

## 1. System Debug (8 bindings)

```text
_getInstanceName()          actor instance name
_getClassName()             actor class name
_getAllCharacter()           list all characters in world
_commandDebug(cmd)           debug command (dev tool)
_setOthersWork(actor, key, val)   set work field on OTHER actor
_getOthersWork(actor, key)        get work field from OTHER actor
_getOthersWorkLength(actor, key)  array length of other's work
_getAllItem()                 list all items in world
```

**Key insight**: `_setOthersWork` / `_getOthersWork` are DEBUG
bindings — they allow scripts to MUTATE/INSPECT other actors' work
fields directly. In retail builds these are probably disabled or
locked to GM-only.

## 2. System Table (5 bindings)

```text
_concat(table, sep)         join array elements
_insert(table, [pos], val)  insert element
_maxn(table)                max numeric key
_remove(table, [pos])       remove element
_sort(table, comparator)    sort table
```

Direct Lua-stdlib `table` library replacements. Same shape as
standard Lua but native C++ implementation.

## 3. GameData SpreadSheet (10 bindings)

```text
_setFilename(filename)              sheet file to load
_getData(key, columnIdx)            read cell at (key, column)
_isExistKey(key)                    is this key present?
_getAllKey()                        enumerate all keys

_loadKeyTemporarily(key, scope)     load key for short term
_loadKeySemipermanently(key, scope) load key with longer lifetime
_unloadKey(key, scope)              unload to free memory

_loadAllKeyPermanently()             load entire sheet (caching)
_loadKeyAsync(key, callback)         async load + callback
_loadMultiKeyAsync(keys, callback)   async load multiple keys
```

The spreadsheet system is the **sheet data layer** -- every
gameplay table (items, commands, achievements, NPCs) is a sheet.
Three loading lifetimes: Temporarily, Semipermanently, Permanently.
Plus async loading for non-blocking IO.

## 4. GameData CutScene (5 bindings)

```text
_setFilename(filename)      cutscene file
_loadCutScene()             load it
_play()                     play normally
_replay()                   replay (e.g. cutscene replay system)
_skip()                     skip to end
```

## Total API Surface Update

```text
Previously documented:    ~437 bindings
This finding (4 files):    +28 bindings
TOTAL DOCUMENTED:         ~465 bindings

Plus likely a few more in stub _u files (5-10 bindings)
ESTIMATED FINAL: ~470-475 native bindings across the 1.x Lua API
```

This effectively CLOSES the native binding enumeration. The last
~10 bindings in tiny stub files don't materially change the
picture.

## Server Implementation Notes

```text
DEBUG BINDINGS:
  _setOthersWork etc. are SERVER-VALIDATED only (player can't
  modify other players' state directly from client). For a test
  server, can be locked to admin GM rank.

SHEET LOADING:
  Lifetime-based memory management. Server can leverage this
  pattern for its own data: load infrequently-used sheets
  temporarily, cache hot sheets permanently.

CUTSCENE:
  Server sends "play cutscene X" via _onReceiveDataPacket(3) etc.;
  client calls _loadCutScene + _play locally. Server doesn't
  stream the cutscene -- just sends the trigger.
```
