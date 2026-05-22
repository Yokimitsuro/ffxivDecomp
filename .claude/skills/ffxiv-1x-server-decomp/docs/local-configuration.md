# Local Configuration

This skill uses a local configuration file so the assistant can find the game installation, the research repository, Ghidra exports, Lua files, and `unluac.jar` without hardcoding machine-specific paths in `SKILL.md`.

## Required file

Create:

```text
config/project.local.yml
```

Use this template:

```text
config/project.local.example.yml
```

## Example for this project

```yaml
repo:
  url: "https://github.com/Yokimitsuro/ffxivDecomp.git"
  local_path: "."

game:
  root: 'E:\Program Files (x86)\SquareEnix\FINAL FANTASY XIV'

tools:
  unluac_jar: "tools/local/unluac.jar"
```

## Rules

- Do not commit `config/project.local.yml`.
- Do not commit `tools/local/unluac.jar`.
- Do not commit game binaries, assets, or large extracted proprietary dumps.
- Keep findings in `docs/`.
- Keep temporary decompilation output in `lua/decompiled/` or another gitignored/local path unless intentionally summarized into findings.

## unluac.jar

Recommended local layout:

```text
tools/local/unluac.jar
```

PowerShell:

```powershell
mkdir tools\local -Force
copy C:\path\to\unluac.jar tools\local\unluac.jar
```

Bash:

```bash
mkdir -p tools/local
cp /path/to/unluac.jar tools/local/unluac.jar
```

Then set:

```yaml
tools:
  unluac_jar: "tools/local/unluac.jar"
```
