# FFXIV 1.x Server Decomp Skill v0.3

Claude/Claude Code skill for researching Final Fantasy XIV 1.0 / 1.23b client behavior in order to implement a compatible MeteorReborn-style server.

It supports two research tracks:

1. Native EXE analysis through Ghidra MCP
2. Lua source / Lua bytecode analysis with optional `unluac.jar`

The skill is designed around a strict workflow:

```text
Claim -> Inspect -> Document Evidence -> Stop Before Spinning -> Commit Findings
```

## Repository target

Recommended private repository:

```text
https://github.com/Yokimitsuro/ffxivDecomp.git
```

Use a private/local repository for notes, findings, packet docs, structs, flow docs, and server requirements.

Do not commit proprietary game binaries, assets, large extracted dumps, full decompiled source dumps, or `unluac.jar`.

## Recommended install

Clone your research repo:

```bash
git clone https://github.com/Yokimitsuro/ffxivDecomp.git
cd ffxivDecomp
```

Install the skill in the repo:

```text
.claude/skills/ffxiv-1x-server-decomp/
```

Run the initializer:

PowerShell:

```powershell
.\.claude\skills\ffxiv-1x-server-decomp\scripts\init_research_repo.ps1
```

Bash:

```bash
bash .claude/skills/ffxiv-1x-server-decomp/scripts/init_research_repo.sh
```

## Local configuration

The initializer creates or expects:

```text
config/project.local.yml
```

This file is local-only and gitignored.

Example:

```yaml
repo:
  url: "https://github.com/Yokimitsuro/ffxivDecomp.git"
  local_path: "."

game:
  root: 'E:\Program Files (x86)\SquareEnix\FINAL FANTASY XIV'

tools:
  unluac_jar: "tools/local/unluac.jar"
```

## unluac.jar

Place it here:

```text
tools/local/unluac.jar
```

PowerShell:

```powershell
mkdir tools\local -Force
copy C:\path\to\unluac.jar tools\local\unluac.jar
```

Then Lua bytecode can be decompiled with:

```powershell
.\.claude\skills\ffxiv-1x-server-decomp\scripts\decompile_lua_folder.ps1 -InputDir lua\bytecode -OutputDir lua\decompiled -UnluacJar tools\local\unluac.jar
```

## First Claude prompt

```text
Use the ffxiv-1x-server-decomp skill.

The repo is https://github.com/Yokimitsuro/ffxivDecomp.git.
The local game root is E:\Program Files (x86)\SquareEnix\FINAL FANTASY XIV.
unluac.jar is available at tools/local/unluac.jar.
Ghidra MCP is connected and the FFXIV 1.23b client EXE is open in Ghidra.

Goal: decompile/analyze the EXE with Ghidra and analyze/decompile Lua files to understand what the client expects from a compatible MeteorReborn server.

Start by reading config/project.local.yml, verifying the repo structure, and identifying the first server-critical targets: packet receive/dispatch, Lua event bridge, character select, world handoff, zone entry, player init, and actor spawn.

Every useful finding must be written under docs/ and committed.
```

## Safety / project hygiene

Allowed:

- packet documentation
- EXE function summaries
- Lua behavior summaries
- structs and offsets
- EXE-Lua correlations
- server requirements
- pseudocode summaries

Avoid committing:

- original game EXEs/DLLs/assets
- large decompiled source dumps
- `unluac.jar`
- local machine paths except in `config/project.local.yml`
- credentials/tokens
