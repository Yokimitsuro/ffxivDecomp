# EXE-Lua Correlation Workflow

Use this when Lua findings and Ghidra findings may describe the same behavior.

## Correlation targets

```text
Lua event name -> EXE string xref
Lua native call -> EXE binding/wrapper
Lua state variable -> EXE struct field candidate
Lua loading flag -> EXE loading state transition
Lua packet/command name -> EXE opcode handler
Lua actor/zone event -> EXE packet handler or state machine
```

## Evidence levels

### Low

String appears in both Lua and EXE, but no call chain yet.

### Medium

String/function appears in Lua and has EXE xrefs near scripting/event dispatch.

### High

EXE call chain clearly invokes Lua function/event or Lua native call maps to EXE wrapper.

### Confirmed

Both directions are understood: Lua caller/callee and EXE bridge are mapped with clear evidence.

## Output format

```text
Lua evidence:
EXE evidence:
Bridge hypothesis:
Confidence:
Server implication:
Next test:
```

Commit to:

```text
docs/re/correlation/
```
