# Finding: `.le.lpb` Filename Cipher — Cracked (involution `a..j<->9..0`, `k..z<->z..k`)

The obfuscation that SE applies to `.le.lpb` filenames and to every path
component under `client/script/` is a **single fixed character-level
substitution**, applied case-insensitively to alphanumerics only. It is
its own inverse — applying it twice returns the original string.

This is the final blocker on Lua-side analysis of the 1.x client.
Combined with the working `.lpb` decoder (`finding_lpb_loader_chain.md`)
and the bulk `unluac.jar` pass, the full corpus of 2,671 scripts is now
readable and namable.

## The cipher

```text
a <-> 9      k <-> z
b <-> 8      l <-> y
c <-> 7      m <-> x
d <-> 6      n <-> w
e <-> 5      o <-> v
f <-> 4      p <-> u
g <-> 3      q <-> t
h <-> 2      r <-> s
i <-> 1
j <-> 0
```

- Underscore `_`, dot `.`, slash `/`, hyphen `-`, and other non-alnum
  characters pass through unchanged.
- Uppercase passes through the case-folded rule and re-capitalises (i.e.
  `A` → `9` on encode; `9` → `a` on decode; if the host code uses
  PascalCase, decode then re-capitalise as needed).
- The transform is an **involution**: `decipher(decipher(s)) == s`.

## How the cipher was found

The single class-definition pattern at the top of
`97qvs89r57y9rr_p.lua` (which Lua actually contains as
`L0_1 = ActorBaseClass`) is enough to fix the map by inspection:

```text
on-disk basename : 97qvs89r57y9rr_p
class in source  : ActorBaseClass

97qvs  <-> actor        => 9=a, 7=c, q=t, v=o, s=r
89r57y9rr <-> baseclass => 8=b, 9=a (dup), r=s, 5=e, 7=c (dup),
                           y=l, 9=a (dup), r=s (dup), r=s (dup)
_p     <-> _u           => p=u  (underscore unchanged)
```

Reading off the pairs and noticing the two halves are each
order-reversing:

- `a, b, c, ..., j` (positions 1..10) line up with `9, 8, 7, ..., 0`.
- `k, l, m, ..., z` (positions 11..26) line up with `z, y, x, ..., k`.

Confirmation: running the rule across all on-disk paths and visually
spot-checking the result yields 100 % readable English (`actor`,
`chara`, `baseclass`, `master`, `worldmaster`, `zonemaster`,
`director`, `widget`, `command`, `quest`, `gamedata`, `system`,
`debug`, `group`, `partygroup`, `relationgroup`, `instanceraid`,
`guildleve`, `chocobo`, `tutorial`, `harvest`, `craft`, `synthesis`,
`battle`, `attack`, `process`, `judge`, etc.).

## Top-level deciphered directories under `client/script/`

```text
on-disk     plain         count of .le.lpb
0p635       judge            23
1q5x        item             26
3svpu       group            26
39x569q9    gamedata          6
61s57qvs    director        299
658p3       debug             5
7vxx9w6     command         160
729s9       chara          1052     (the giant one)
9s59        area             60
n1635q      widget          202
nvsy6       world             7
rlrq5x      system           10
rq9qpr      status          158
tp5rq       quest           629
```

Plus one bare path (`3yv89y_p.le.lpb` -> `global_u`) at the root that
contains the top-level boot definitions
(`_defineClass_inl`, `_isInstanceOf_inl`, ...) seen in the EXE bindings.

## What `_p` / `_u` means

Every base script has a `_p` companion on disk:

```text
9s59/kvw5/kvw589r57y9rr.lua       -> area/zone/zonebaseclass         (real definition)
9s59/kvw5/kvw589r57y9rr_p.lua     -> area/zone/zonebaseclass_u       (override stub)
```

Many `_u` files are 18-byte stubs (empty Lua chunks); a smaller number
are full overrides with real bodies (e.g. `world/worldmaster_u.lua`
4,333 B vs the base `world/worldmaster.lua` 2,614 B).

Working interpretation (Medium confidence): `_u` = "update" — SE
ships an override slot next to every script so that content patches can
add behaviour to a script without rebuilding the base file. The empty
18-byte stubs are the default no-op overrides; the larger `_u` files
are real patched logic.

## What is *not* in the corpus

The user's original brief mentioned login / lobby / world / zone /
loading / actor / character / event / network as topics of interest.
The catalogue (`docs/re/lua/catalog.md`) shows their presence as
deciphered paths. Notable absences:

- **No `lobby/` directory.** Lobby flow lives entirely in C++
  (`Application::Network::LobbyProtoChannel`); no scripted lobby code.
- **No `network/` or `packet/` directory.** Network framing is
  C++; the only Lua-side packet contact is the `PacketProcessor`
  binding (secondary processor at `PacketBufferBase + 0x78`), and that
  is registered from C++, not declared in a Lua file.
- **Only one `login`-named script** (`command/system/logineventcommand`,
  4.6 KB) — a single event-handler tying login UI commands into the
  EXE-driven session start.
- **No top-level `loading` directory.** Loading-screen behaviour is
  driven from the EXE state machine and surfaces as Lua UI events
  inside `widget/` scripts, not as standalone scripts.

These absences are consistent with the EXE-side findings: 1.x keeps the
network and session lifecycle out of Lua. Lua handles UI, scenes,
quests, actor behaviour, and gameplay event reactions.

## Assessment

```text
Confirmed:
  - The on-disk filename cipher is a single involution defined above.
  - 100% of obfuscated path components in client/script/ are valid
    plaintext after decipher (English, well-known FFXIV 1.x terms).
  - 2,671 scripts decompile to readable Lua 5.1 source via the
    XOR-0x73 wrapper decoder + stock unluac.jar.
  - The `_p` -> `_u` decipher pattern is a consistent override-slot
    convention across the whole tree.

Likely (High):
  - The cipher is applied character-by-character at filename
    generation time during the SE build pipeline. There is no
    file-content-derived element in the obfuscation.
  - Inside a decompiled script, calls to `require("X")` use
    PLAINTEXT script names — i.e. the cipher is applied at write time
    only, and the Lua VM at runtime sees the plaintext name and the
    native `_luaGameEngineRequire` is responsible for re-applying the
    cipher when it goes to disk. (Direct check: any `require("...")`
    string inside the .lub files contains readable English, never
    cipher.)

Likely (Medium):
  - `_u` = "update" override slot. 18-byte `_u` stubs are the empty
    default; non-empty `_u` files override the base.

Speculative:
  - That all SE build pipelines of the Crystal Tools / 1.x era used
    this same cipher table (we only have evidence for the FFXIV 1.23b
    build).

Next test:
  - Walk every `require("...")` inside the decompiled .lua corpus and
    confirm those names match deciphered on-disk paths 1:1. That fully
    validates the cipher direction.
  - Use the catalogue (docs/re/lua/catalog.md) to dive into specific
    flows of interest for the server — recommended starting points are
    `world/worldmaster.lua` + `_event.lua` + `_u.lua` (overall world
    handoff) and `area/zone/zonebaseclass.lua` (per-zone init).

Commit suggestion:
  docs(re/lua): crack the .le.lpb filename cipher; add corpus catalogue
```

## Server implication

- No direct protocol implication — the cipher is on-disk only.
- Practical implication: the **Lua corpus is now fully searchable**.
  When a feature on the wire does not produce the expected client
  behaviour, you can `grep` the deciphered source for relevant strings
  (e.g. `worldmaster_event`, `zonemaster*`, `instanceraid*`,
  `partygroup`, `widget/...`) and read the actual logic. This was the
  blocker for everything Lua-side and it is now gone.
- The tooling chain (kept under `tools/local/`, gitignored per project
  policy) is:
  ```text
  decode_all.py          XOR-0x73 + rlu\x0B handling, .lpb -> .lub
  decompile_all.py       parallel unluac.jar, .lub -> .lua
  decipher_names.py      involution table, --validate / --decipher / --dump-table
  catalog_scripts.py     emits docs/re/lua/catalog.md
  ```
