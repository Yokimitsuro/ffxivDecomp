# Server Interoperability Workflow

Use this workflow when converting client findings into MeteorReborn/server behavior.

## 1. Identify client expectation

For each EXE or Lua finding, extract:

- what the client expects to receive
- what order packets/events appear to arrive in
- what client state changes after each packet/event
- what values are read from packet payloads
- what values are stored in client/Lua structures
- what Lua event or native callback is triggered

## 2. Convert to server requirement

Use this format:

```text
Client-side observation:
Server-side implication:
Minimum server behavior:
Required packet/event order:
Fields required:
Fields unknown:
Validation test:
```

## 3. Keep implementation separate from evidence

Use:

```text
docs/re/exe/           EXE findings
docs/re/lua/           Lua findings
docs/re/correlation/   EXE-Lua bridge findings
docs/packets/          packet layouts
docs/server/           server requirements
src/                   only tested server changes
```

## 4. Minimum useful finding

A useful finding can be small:

- one opcode identified
- one Lua event named
- one native binding located
- one payload field documented
- one function renamed cautiously
- one send/receive path located
- one state flag identified
- one required packet/event order discovered

Record and commit it.
