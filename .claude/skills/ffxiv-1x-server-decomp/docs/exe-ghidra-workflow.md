# EXE Ghidra MCP Workflow

Use this workflow for native EXE analysis.

## Inputs

Read `config/project.local.yml` first:

```yaml
game:
  root: 'E:\Program Files (x86)\SquareEnix\FINAL FANTASY XIV'
  exe_search_patterns:
    - "*.exe"

ghidra:
  exports_dir: "ghidra/exports"
```

The EXE should be opened in Ghidra by the user. Claude should verify the currently loaded Ghidra program through MCP before assuming it is the correct binary.

## Evidence checklist

For each native function:

1. Function metadata
2. Signature and parameters
3. Decompiled output summary
4. Disassembly if needed
5. Callers
6. Callees
7. Referenced strings
8. Constants
9. Data xrefs
10. Switch/dispatch tables
11. Network import xrefs
12. Lua API / script bridge xrefs
13. Server implication

## Server-focused questions

```text
Does this parse a server packet?
Does this build a client packet?
Does this dispatch by opcode?
Does this call Lua?
Does this set a loading/ready flag?
Does this create or update actor/session/character state?
What would the server need to send for this path to continue?
```

## Output

Write concise findings under:

```text
docs/re/exe/
docs/packets/
docs/server/
```
