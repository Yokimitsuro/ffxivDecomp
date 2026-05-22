# Finding: Client Version Identification

Identify the binary currently loaded in Ghidra and assess whether it is the
FFXIV 1.23b client.

## Context

- Source: Ghidra MCP, currently loaded program
- Method: segment layout, imports, string content, version-related references
- No proprietary code is reproduced here; only short identifying strings,
  symbol names, and section names are quoted

## Evidence

### Binary shape

- PE32 layout, image base `0x00400000` (x86 32-bit)
- Segments: `Headers`, `.text` (`0x00401000`–`0x00f3cfff`, ~11.6 MB code),
  `MSSMIXER` (Miles Sound System mixer section), `.rdata`, `.data`, `.tls`,
  `.rsrc`, `tdb`
- Imports include `kernel32`, `user32`, `gdi32`, `advapi32`, `shell32`,
  `ole32`, `wintrust`, `crypt32`, `version.dll`, `imm32`, `ws2_32`
  (network: `WSAStartup` warning string present)
- Presence of `MSSMIXER` segment is characteristic of FFXIV 1.x using
  Miles Sound System

### FFXIV-specific identifying strings

Short identifying strings observed (not exhaustive):

- `FINAL FANTASY XIV` (`0x00f54c40`)
- `FINAL FANTASY XIV Beta Version` (`0x00f54bcc`)
- `FINAL FANTASY XIV LATEST` (`0x00f54c0c`)
- `FINAL FANTASY XIV Patch Client` (`0x010504f4`)
- `FFXIV Patch` (`0x01050588`)
- `SOFTWARE\SquareEnix\` (registry root)
- `lobby01.ffxiv.com`, `ver01.ffxiv.com` (1.x service endpoints)
- `ffxiv/win32/release/boot`, `ffxiv/win32/release/game`,
  `ffxiv/win32/latest/boot`, `ffxiv/win32/latest/game` (patch repo paths)
- File-name references (as data, not the program's own name):
  `ffxivgame.exe`, `ffxivlogin.exe`, `ffxivboot.exe`, `ffxivupdater.exe`
- Patch-stack identifiers: `SqexPatchSystem v01`, `ZiPatch`, `RTPatch`,
  `VcdPatch`

### Internal engine and component identifiers

C++ RTTI / namespace evidence consistent with FFXIV 1.x client (Crystal Tools
era):

- `CDev.Engine.Lay.*` (numerous Lay/Resrc/Layout/Factory subsystems)
- `CDev.Engine.Lay.Stella : Version 1.0.2.0/0`
- `CutLibrary : Version 1.0.2.0/0`
- `PHI-ENGINE : Version %d.%d.%d`
- `Qix-Engine : Version 1.2.1.6`
- `SQEX::CDev::Engine::Lay::Stella::Resource::_CheckCDevBinaryHeaderVersion`
- Class hierarchy `Patch@Bootup@Menu@Main@Application` and
  `PhasePatchManager@Phase@System@Element@Main@Application` — patch flow
  lives inside the same `Main\Application` object graph as the game

### Build-date evidence

- `CDev.Engine.Dw.RenderInterface : Ver1.0.3.0 / build at Sep  5 2012 06:49:03`
  (`0x00f57b38`)
- No other `build at ...` banner strings were found in the loaded program

The Sep 5 2012 build date sits between the public 1.23a release (Sep 4 2012)
and the 1.23b release (Oct 23 2012), so it is consistent with the 1.23
patch family. It does not by itself disambiguate 1.23a vs 1.23b — the
RenderInterface library may not have been rebuilt for the small 1.23b
content patch.

### Things that confirm "client EXE", not "launcher"

- Section size: ~11.6 MB of code in `.text` — far too large for the
  small `ffxivboot.exe` launcher (which is ~2 MB on disk)
- Presence of full rendering stack (`PHI-ENGINE`, `Qix-Engine`,
  `CDev.Engine.Dw.RenderInterface`, `CDev.Engine.Lay.Stella`),
  Miles Sound System mixer section, and character-creation form paths
  (`\system\bootup\charactercreation\AppearancePhase*.form`)
- The `Patch` subsystem appears as a `Bootup\Menu` phase of `Main\Application`,
  meaning patch+boot+game share one process — matches the 1.x `ffxivgame.exe`
  architecture, where the game client also hosts the in-client patcher UI

### Things not yet directly verified

- `.rsrc` `VS_VERSIONINFO` block was not inspected directly; the imports show
  `GetFileVersionInfoW` / `VerQueryValueW` are used by the binary on
  *other* files (likely peer files during patch verification), so its own
  resource version string was not pulled in this pass
- No literal "1.23", "1.23a", or "1.23b" string was found in the data
  segment

## Assessment

```text
Confirmed:
  - Loaded program is an FFXIV 1.x Crystal Tools-era client EXE
    (engine banners, MSSMIXER section, ffxiv.com endpoints, SqexPatchSystem)
  - Program identity is consistent with `ffxivgame.exe` (the unified
    client), not `ffxivboot.exe`/`ffxivlogin.exe`/`ffxivupdater.exe`

Likely:
  - High: Build belongs to the FFXIV 1.23 patch family (1.23 / 1.23a / 1.23b),
    based on the Sep 5 2012 build date of the bundled
    `CDev.Engine.Dw.RenderInterface` library
  - Medium: Build is specifically 1.23b — the project's stated target is
    1.23b, the Sep 5 2012 date is post-1.23a, and the RenderInterface
    library plausibly was not rebuilt for the small 1.23b content patch.
    Not yet proven from a literal in-binary version string.

Speculative:
  - That the binary embeds an exact "1.23b" string anywhere; none found so
    far in defined string data

Next test:
  - Read the `.rsrc` VS_VERSIONINFO block of the loaded PE
    (`FileVersion` / `ProductVersion` / `ProductName`) directly, either via
    Ghidra's Resource view or by running `(Get-Item <exe>).VersionInfo` on
    the on-disk file; that will yield the canonical SE build number
    (e.g. something of the form `1.23.0.x` or similar) and the original
    product name
  - If `.rsrc` is inconclusive, compare a SHA-256 of the on-disk EXE to a
    known 1.23b reference hash from the user's preserved copy

Commit suggestion:
  docs: identify loaded Ghidra program as FFXIV 1.x client (1.23 family)
```

## Server implication

None directly. This finding only fixes the *target* of all subsequent
EXE reverse-engineering work to the FFXIV 1.x (Crystal Tools / 1.23-family)
unified client — meaning later opcode / packet / Lua bridge findings
should be filed under the assumption that this binary is the in-process
host of boot, patch, login handoff, character creation, and zone
gameplay, not a separate launcher.
