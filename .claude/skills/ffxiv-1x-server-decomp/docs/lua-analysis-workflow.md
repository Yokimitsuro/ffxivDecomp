# Lua Analysis / Lua Decompilation Workflow

Use this workflow for FFXIV 1.x Lua source files, Lua bytecode files, UI scripts, event scripts, and client-side state scripts.

## Inputs

Read `config/project.local.yml` first.

Relevant fields:

```yaml
game:
  root: 'E:\Program Files (x86)\SquareEnix\FINAL FANTASY XIV'
  lua_search_patterns:
    - "*.lua"
    - "*.luac"
    - "*.lub"
  extracted_lua_input:
    - "lua/source"
    - "lua/bytecode"
  decompiled_lua_output: "lua/decompiled"

tools:
  unluac_jar: "tools/local/unluac.jar"
```

## Rules

- Preserve original Lua/bytecode files.
- Do not commit large decompiled source dumps.
- Use decompiled Lua as evidence, then write concise findings in `docs/re/lua/`.
- Treat decompiler output as approximate unless manually verified.
- Extract server requirements when Lua waits for events, flags, actors, zone state, or native callbacks.

## Bytecode decompilation

PowerShell:

```powershell
.\.claude\skills\ffxiv-1x-server-decomp\scripts\decompile_lua_folder.ps1 -InputDir lua\bytecode -OutputDir lua\decompiled -UnluacJar tools\local\unluac.jar
```

Bash:

```bash
bash .claude/skills/ffxiv-1x-server-decomp/scripts/decompile_lua_folder.sh lua/bytecode lua/decompiled tools/local/unluac.jar
```

## What to document

For each Lua target:

```text
File:
Lua type: source / bytecode / decompiled
Purpose:
Entry points:
Functions:
Events handled:
Native/engine calls:
State variables:
Network/server assumptions:
Strings useful for EXE xrefs:
Server-side implication:
Confidence:
```
