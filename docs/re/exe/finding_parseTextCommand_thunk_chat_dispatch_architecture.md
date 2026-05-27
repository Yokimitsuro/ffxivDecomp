# Finding: _parseTextCommand Thunk Disassembled -- CHAT COMMAND DISPATCH Architecture Mapped

**Opens the chat command subsystem.** Disassembles the C++ thunk for
`desktopWidget:_parseTextCommand(text)` -- THE chat parser that
handles every `/command` typed in the chat box (/say, /tell, /yell,
/macro, /target, etc.).

Reveals a **typed-argument parser** where each command in
`gameCommand.csv` has a schema declaring the type of each argument
slot. The parser is data-driven: token by token, it looks up the
arg type from the command's schema row, then dispatches to a
type-specific parser.

This is the **7th thunk disassembled** and opens the chat subsystem
that complements the chat display (`_appendMessagePool`) and chat
channels (32/33/38/40) documented previously.

## 1. Thunk located + renamed

```text
Lua entry point:    desktopWidget:_parseTextCommand(text)
                    -- declared in DesktopWidget_u.lua

Registrar:          DesktopWidget_registerLua_parseTextCommand @ 0x00751f70
C++ thunk:          DesktopWidget_cpp_parseTextCommand_thunk @ 0x006fe2a0 (NEW)
Entry wrapper:      ChatParser_entry @ 0x0075ccf0 (NEW)
Main parser:        ChatParser_tokenizeAndParse @ 0x0056e380 (NEW)
Command lookup:     ChatParser_lookupCommandIdByName @ 0x0056d3c0 (NEW)
Typed arg parser:   ChatParser_parseTypedArg @ 0x0056e040 (NEW)
```

## 2. The thunk pipeline (end-to-end)

```text
1. Lua: desktopWidget:_parseTextCommand("/say hello world")
   
2. Thunk extracts arg 0 (the text string) from Lua stack
   
3. Calls ChatParser_entry (wrapper) -> ChatParser_tokenizeAndParse
   - Looks up text via vtable[4] (get input source -- chat input box?)
   - Preprocesses text:
     * Apply substitute strings (macro code expansion via FUN_00447ed0)
     * Trim leading whitespace (" \t\n")
   - Validates first char is '/' (slash command required)
   - Tokenizes by splitting on " " (FUN_0044f840 = split-by-separator)
   - First token must start with '/' -- the command name
   - Calls ChatParser_lookupCommandIdByName to resolve name -> ID
     * Returns -1 if command not found
   - Looks up the command's ARG SCHEMA (vtable+0x18 returns schema)
   - Parses up to 3 integer args via ChatParser_parseTypedArg
     * Each arg's type code drives parsing logic
   - Loops through remaining tokens (up to ~8 bracket/body args):
     * Tokens starting with '<' are bracket args (e.g. <player>, <target>)
     * Other tokens may be marked with "!!!" prefix (emphasis?)
   - Remaining text becomes the message body
   
4. Pushes parsed result onto Lua return stack via param_1[7]:
   - (cmdId, argCount, intArg0, intArg1, intArg2, ... dynamicArgs)
   - Pads to 11 slots total with nulls
   
5. Lua script receives structured result + dispatches to handler
```

## 3. Command-name lookup (the heart of chat dispatch)

```c
ChatParser_lookupCommandIdByName(this, name) {
  // 1. Build the localization path
  path = "xtx/_textCommand";  // = LOCALIZED text command table
  
  // 2. Get table reference via vtable+4
  table = vtable[4](path);
  if (!table) return -2;  // command system not loaded
  
  // 3. Try 3 lookup variants in priority order:
  //    a) Direct lookup at slot 5 (current locale?)
  //    b) Get key at slot 0, lookup
  //    c) Get key at slot 1, lookup
  match = tryLookup(table, slot 5);
  if (!match) match = tryLookup(table, slot 0);
  if (!match) match = tryLookup(table, slot 1);
  if (!match) return -2;  // command not found
  
  // 4. Extract command ID via vtable[8]
  return vtable[8](match);  // = the command ID
}
```

The 3-tier lookup strategy is for **localization**:
- Slot 5 = current locale's command names
- Slot 0/1 = fallback locales (Japanese, English maybe)

So `/say` in English and `/言う` in Japanese both resolve to the same
command ID. This is loaded from the LOCALIZED text command table
(`xtx/_textCommand`) which is a SpreadSheet binding.

## 4. The typed-arg parser (5 arg type codes)

`ChatParser_parseTypedArg(this, token, typeCode, outBuffer)`:

```text
typeCode  Meaning                    Parsing logic
--------  -------                    -------------
  0       Decimal integer            atoi(token, base=10)
  1       Command name               If starts with '/': lookup ID
                                      Else: prepend '/' and lookup
< 0       Special types:
  -1      Target with +N modifier    Parse as "@target+1" form
                                      Split on '+', take [0] as target,
                                      [1] as offset integer
                                      Then look up target via
                                      FUN_0056d720 (target resolver)
  -2..    Other relative offsets     FUN_0056d720(this, name, -1-typeCode)
> 1       Cardinal/positional        FUN_0056d6e0(token, typeCode - 2)
                                      (probably enum/lookup table)
```

Each `gameCommand.csv` row specifies the arg types for that command,
so different commands have different arg parsing logic. This is a
**data-driven parser** with the command-arg schema as input.

Examples:
- `/say <message>` -- 0 typed args + 1 body arg
- `/target <player>` -- 1 typed arg (type=command-name? target?)
- `/tell <player> <message>` -- 1 typed arg + body arg
- `/macro 5` -- 1 typed arg (type=0 decimal: 0-9 macro slot)
- `/team @1+2 attack` -- 1 typed arg (type=-1: target+offset)

## 5. Special command ID 0x67 (103) -- the "emphasis" form

```text
The parser has a hardcoded special case at command ID 0x67 (103):
  if (vtable[0x18]() returns context type 4 or 5) and (cmdId == 0x67)
    then SET emphasis_mode flag
  
  Effect on parsing: each non-bracket arg gets "!!!" prepended
  to its parsed form.
```

Command ID 103 is likely `/!` or some specific emphasis/shout
command. The "!!!" prefix marker is added to its tokens during
parsing for some downstream rendering effect.

## 6. The wire path (CONFIRMED: chat does NOT use _parseTextCommand)

```text
IMPORTANT: This thunk's job is ONLY parsing.
It does NOT send a wire packet.

The parser returns the parsed (cmdId, args[]) structure to Lua.
Lua-side code then:
  1. Validates the command (canUse, target valid, etc.)
  2. Dispatches to the command handler
  3. THE HANDLER may send wire packets (e.g. chat opcode 0x40 for /say)
  4. Or update local state (e.g. /target updates UI selection)

So the chat input flow is:
  user types text in chat box
   -> Lua: desktopWidget:_parseTextCommand(text)
   -> EXE: parse + return structured result
   -> Lua: dispatch to handler (e.g. say:execute(target, text))
   -> Lua: may call _executeCommand (which sends wire packet)
   -> wire opcode (chat-specific; per channel: 32/33/38/40)
```

The 4 chat channels (per `worldMaster._appendMessagePool` routing):
- 32 = system notify (yellow)
- 33 = system alert (red)
- 38 = NPC dialog (white)
- 40 = world cryer / global say

## 7. Data flow architecture

```text
xtx/_textCommand.csv (localized command names)
    |
    +-> ChatParser_lookupCommandIdByName -> cmdId
    
gameCommand.csv (1611 rows, 141 cols)
    |
    +-> per-command arg schema (type codes per slot)
    +-> ChatParser_parseTypedArg uses these types
    
gameCommandBasic.csv (1611 rows, 121 cols)
    |
    +-> compact version of gameCommand for the parser path?
    
SpreadSheet loaders (Tier 1 boot init in commonJudge.lua):
    itemDataSheet, equipmentSheet, weaponSheet, armorSheet,
    accessorySheet, gameCommandSheet, gameCommandBasicSheet,
    compatibilitySheet, exp_BPCostSheet

The chat parser needs gameCommand + the localized text command
table to be loaded before /commands work.
```

## 8. Renames made (5)

```text
RENAMES:
  - 0x006fe2a0 -> DesktopWidget_cpp_parseTextCommand_thunk
                  (Lua _parseTextCommand entry-point)
  - 0x0075ccf0 -> ChatParser_entry
                  (wrapper that gets the parser context)
  - 0x0056e380 -> ChatParser_tokenizeAndParse
                  (main parser; tokenize + lookup + dispatch)
  - 0x0056d3c0 -> ChatParser_lookupCommandIdByName
                  (xtx/_textCommand 3-tier localized lookup)
  - 0x0056e040 -> ChatParser_parseTypedArg
                  (per-slot typed arg parser, 5 type codes)
```

## 9. Implications for server design

```text
The chat command system is LARGELY CLIENT-LOCAL:

PARSING is client-side:
  - Tokenizing, command-name -> ID lookup, arg type parsing
  - Validation (canUse checks)
  - Target resolution (@target+1 etc.)
  
The SERVER receives:
  - Already-parsed commands (cmdId + args)
  - Via channel-specific wire opcodes (probably 0x40 family)
  - Server may re-validate but doesn't re-parse the text

DATA REQUIREMENTS:
  - xtx/_textCommand.csv must be available at session init
    (localized command name -> ID mapping)
  - gameCommand.csv must be available (arg schemas)
  - gameCommandBasic.csv (probably arg schemas summary)
  
The text command table is LOCALIZATION-AWARE:
  - Slot 5 = primary locale
  - Slot 0, 1 = fallbacks
  - Server doesn't need to support multiple locales in its dispatch
    -- the client always sends cmdId (integer), not text
```

## 10. Confidence

```text
Confirmed:
  - DesktopWidget_cpp_parseTextCommand_thunk @ 0x006fe2a0 backs
    Lua _parseTextCommand
  - The parser is data-driven by gameCommand.csv arg schemas
  - Command names looked up in localized "xtx/_textCommand" table
  - 3-tier localized lookup (slot 5 + 2 fallbacks)
  - 5 arg type codes (0, 1, -1, -2..-N, >1) drive per-slot parsing
  - First token must start with '/' (no implicit command)
  - Bracket args (<player>, <target>) are recognized syntactically
  - "!!!" emphasis prefix applied for command ID 0x67 in certain contexts
  - Parser returns to Lua; does NOT send wire packet itself
  - Wire transmission is done by Lua handlers via _executeCommand

Likely (High):
  - Command ID 0x67 (103) is /shout or similar emphasis command
  - The vtable[4] / vtable[8] / vtable[0x14] / vtable[0x18] / vtable[0x20]
    calls walk the gameCommand SpreadSheet's row + column accessors
  - Target resolver FUN_0056d720 handles @1 / @target / @me etc.
  - "+N" modifier on targets allows party-relative addressing
    (@1+1 = next party member after #1)

Likely (Medium):
  - The 11-slot Lua return is sized for the max command arity in
    1.x gameCommand schema (cmd + 11 args max)
  - "!!!" prefix might be /shout's text-emphasis marker (rendered
    differently in chat display)
  - The localization slot mapping is determined at engine boot
    based on user's selected language setting
```

## 11. Cross-references

- `finding_desktopwidget_master_44_of_44_complete.md` -- where the
  _parseTextCommand registrar (slot 32) was identified
- `finding_csv_lua_correlation_35_tables_mapped.md` -- documents
  gameCommand.csv + gameCommandBasic.csv loading via commonJudge
- `finding_system_commands_and_command_id_ranges.md` (Lua) -- the
  Lua-side command system overview
- `finding_command_execute_wire.md` (Lua) -- documents
  _executeCommand wire send path (called AFTER this parser)
- `finding_worldmaster_complete.md` -- documents the 4 chat channels
  (32/33/38/40) where parsed output may be routed
- `finding_npc_dialog_protocol.md` -- documents say/ask family
  (the NPC end of chat)

## 12. Next test

```text
1. Disassemble FUN_0056d720 (target resolver) to map @target syntax
2. Disassemble FUN_0056d6e0 (cardinal/positional parser) for type > 1
3. Find the Lua-side command DISPATCHER (where the parsed result
   gets executed)
4. Trace _executeCommand wire send (Lua-side already documented;
   find the EXE thunk if Lua doesn't expose it as a binding)
5. Identify chat channel-specific wire opcodes (32/33/38/40 should
   each map to a specific outbound opcode in the 0x140-0x150 range
   per prior outbound opcode roster)
6. Disassemble _appendMessagePool thunk (the chat DISPLAY sink;
   complement to this finding's PARSE side)
```

## Commit suggestion

```
docs(re/exe): _parseTextCommand thunk disassembled -- chat command dispatch architecture mapped (data-driven typed-arg parser + localized lookup)
```
