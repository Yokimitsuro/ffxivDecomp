# Finding: `.lpb` Script Format — Custom SE Wrapper, Obfuscated Names, Standard Decompilers Reject

Characterise the FFXIV 1.x on-disk Lua script container and explain why
straightforward Lua decompilation is **not currently possible** with the
tools listed in `config/project.local.yml`.

## Source / scope

- Game root from `config/project.local.yml` -> `game.root`
  (`E:\Program Files (x86)\SquareEnix\FINAL FANTASY XIV`)
- File pattern: `*.lpb` (the configured `lua_search_patterns` also lists
  `*.lua` and `*.luac`, but **zero** loose `.lua` / `.luac` files exist
  under the game root)
- Search was constrained to the game install directory; SqPack-backed
  archives under `data/` were not opened (no extractor available in
  `tools/local/`)
- Tool tried: `tools/local/unluac.jar` (~777 KB, Java 24 host)

## Evidence

### Inventory

```text
.lpb file count under client/   : 2,671
size range                      : 69 B  ..  213,487 B
average size                    : ~2,076 B
```

Top-level distribution under `client/script/` (directory names are
obfuscated — see below):

```text
client/script/729s9       1,052 files
client/script/tp5rq         629
client/script/61s57qvs      299
client/script/n1635q        202
client/script/7vxx9w6       160
client/script/rq9qpr        158
client/script/9s59           60
client/script/1q5x           26
client/script/3svpu          26
client/script/0p635          23
client/script/rlrq5x         10
client/script/nvsy6           7
client/script/39x569q9        6
client/script/658p3           5
client/script/7vxx9w6...      5
... and a long tail of smaller bins
```

There are also peer top-level directories (`chara`, `cut`, `sqwt`, `vfx`)
under `client/`, but the .lpb files cluster in `client/script/`.

### File-name obfuscation

Both **directory** and **file** names under `client/script/` are
substitution-cipher-obfuscated. Sample file names:

```text
3yv89y_p.le.lpb
64qrsq.le.lpb
658p36pxxl.le.lpb
7vwq5wq3svpu89r57y9rr.le.lpb
7svn689r57y9rr.le.lpb
ny6jpd.le.lpb
tp5rq61s57qvs9s7gjdji.le.lpb
xvs8vywvsx9y.le.lpb
```

Observations:

- Common token `89r57y9rr` recurs in many names — looks like a frequent
  suffix word (e.g. "function", "controller", "instance", "interface" —
  not yet decoded).
- Suffixes `_p`, `_pq`, `_xxx` recur — likely variant markers.
- The character alphabet used (`0-9`, plus lowercase `b-y` excluding `a`,
  `c`, `e`, `f`, `i`, `m`, `o`, `z`) is consistent with a fixed
  substitution table whose plaintext-vs-ciphertext mapping is not
  derivable without correlating with another source (the `Lpb`
  index inside the EXE, or a known plaintext/ciphertext pair from a
  community 1.x dump).
- The full extension is `.le.lpb`. Interpretation: **`.le`** = build/locale
  marker (e.g. little-endian or English-EU); **`.lpb`** = "Lua precompiled
  binary" (matches the in-EXE term — see below).

This name obfuscation is **separate from** any obfuscation of the
bytecode payload — see next section.

### File-header magic (constant across all .lpb files inspected)

First 8 bytes of every sample:

```text
72 6C 65 0C 1F C5 00 00       "rle\x0C\x1F\xC5\x00\x00"
```

This is **not** the standard Lua bytecode magic `1B 4C 75 61` ("`\x1bLua`").
The dword at offset +0x04 (`0x0000C51F` = 50,463 decimal) is identical in
every sampled file regardless of script size — strongly suggesting a
**format/version constant** embedded by the SE loader, not a per-file
field.

Bytes 8..15 vary per file:

```text
B5 0D 00 00 FF 68 3F 06   (one sample)
12 22 73 72 77 77 77 7B   (continuation in same file)
73 73 73 73 73 73 73 73   (8 repeated 0x73s at offset 0x18 in same file)
```

The 8-byte run of `0x73` at offset 0x18 (and other repeating-byte runs in
other files) is consistent with **run-length-encoded zeros** under a
fixed-byte translation. The mnemonic `rle` in the magic supports this:
the format is plausibly **a custom RLE/transform layer wrapping vanilla
Lua 5.1 bytecode**, not a fundamentally different VM.

### Standard `unluac` rejects every sample

Running:

```text
java -jar tools/local/unluac.jar <sample>.lpb
```

produces:

```text
Exception in thread "main" java.lang.IllegalStateException:
  The input file does not have the signature of a valid Lua file.
        at unluac.parse.BHeader.<init>(BHeader.java:84)
```

i.e. unluac's strict-magic check (`\x1bLua`) fires at byte 0 and aborts.
No further work is attempted by unluac. This is expected because the file
has the SE-specific `rle\x0C` magic rather than the Lua-standard magic.

### Cross-corroboration from the EXE

The loaded EXE confirms the format name and the Lua dialect:

- `00fa6a7c: "lpbversion"` — debug-console command (see `FUN_0057a190`
  which registers it together with other debug verbs like `zone`,
  `gmevent`, `achievement`, `list`).
- `00fa6ac4: "client lpb version: "` — printed by the `lpbversion` handler
  `FUN_00578ab0`, which reads a single uint via `FUN_00cc7730` and
  prints it. That uint is the in-binary `lpbversion` constant; the
  expected match against the on-disk dword `0x0000C51F` at file +0x04
  remains to be confirmed but is a **High-confidence prediction**.
- `00fdf550: " lpb version: "` and `00fd89a8: "!!!error!!! client lpb
  version: "` — version-mismatch error path; the client refuses scripts
  whose dword at +0x04 differs from its compiled-in `lpbversion`.
- `0130d534: ".?AVResourceEvent@LpbLoader@GameEngine@Lua@Component@@"`
  and `0130d574: ".?AVResumeChecker@LpbLoader@GameEngine@Lua@Component@@"`
  — confirm the loader's full namespace path:
  `Component::Lua::GameEngine::LpbLoader`.
- `011331d8: "Lua 5.1"` — the embedded Lua VM is **Lua 5.1** (the
  `_VERSION` string baked into liblua).
- `010c5740: " | %s binary version error. rid(%s)"` and the surrounding
  `binary control version error`, `version error. (your version=%d).
  (now version=%d)` strings — generic SE resource versioning that the
  same loader uses; same family of mismatch errors applies to `.lpb`.

So the format is precisely:

```text
SE-wrapped Lua 5.1 precompiled bytecode
  magic    : "rle\x0C"   (4 bytes)
  version  : 0x0000C51F  (uint32 LE) -- must match EXE's `lpbversion`
  body     : either obfuscated/RLE-encoded vanilla Lua 5.1 chunk,
             or plain Lua 5.1 chunk with a non-standard header. Not yet
             demonstrated which.
```

## Assessment

```text
Confirmed:
  - Embedded Lua VM is Lua 5.1.
  - .lpb files share an identical 8-byte header: "rle\x0C" + 0x0000C51F.
  - tools/local/unluac.jar cannot read .lpb files because of the magic
    mismatch.
  - File names (and directory names) under client/script/ are
    cipher-obfuscated; the cipher is a fixed substitution but not yet
    decoded.

Likely (High):
  - The dword at .lpb +0x04 (0xC51F) is the client's `lpbversion`
    constant; the EXE rejects scripts whose value differs.
  - The format is a thin SE wrapper around standard Lua 5.1 bytecode
    (the "rle" tag, repeating-byte runs in the payload, and the standard
    Lua 5.1 VM together fit a RLE-of-vanilla-bytecode hypothesis better
    than a custom VM hypothesis).

Likely (Medium):
  - Once the wrapper is stripped (header removed + RLE/transform
    reversed), unluac can decompile the resulting standard Lua 5.1
    bytecode.

Speculative:
  - The .lpb body is encrypted (not just compressed/obfuscated). No
    evidence of a key-schedule or block cipher has been found in the
    samples or in the loader strings yet.
  - .le.lpb means "little-endian build". Could equally be "EU/English
    locale".

Next test (in priority order):
  1. Decompile FUN_00cc7730 in Ghidra to retrieve the literal
     `lpbversion` constant the EXE compares against. If it matches
     0x0000C51F, the format guess is confirmed.
  2. Identify the .lpb loader entry point in the EXE by xref-ing one of
     "client lpb version: " / "lpbversion" / the RTTI strings for
     LpbLoader::ResourceEvent / LpbLoader::ResumeChecker. Then decompile
     the load path to extract the exact decode algorithm (likely:
     skip 8-byte header -> RLE-expand -> hand to luaL_loadbuffer).
  3. Once the decode is reproduced as a small Python/Java utility, run
     each .lpb through it and feed the result to unluac.jar.
  4. After decompilation works, deobfuscate names by correlating the
     first decompiled file's `require("...")` arguments with the
     ciphered filenames they resolve to. Each correlation yields one
     plaintext-vs-ciphertext pair; a handful is sufficient to recover
     the substitution table.

Commit suggestion:
  docs(re/lua): document .lpb wrapper format, name obfuscation, and
                why unluac currently rejects 1.x scripts
```

## Server implication

- For an MVP server bring-up, **Lua script behaviour is not on the
  critical path**. The server only needs to satisfy whatever network
  protocol the EXE drives; the EXE's network code runs in C++, not
  inside Lua (see `docs/re/exe/finding_packet_dispatch_by_id.md`).
- Lua scripts are however the only place where certain UI- and event-
  driven flows live (see `docs/re/exe/finding_lua_engine_bridge.md`).
  Until `.lpb` decompilation is unblocked, those flows must be inferred
  from EXE-side bindings only, which is partial.
- Practical short-term workaround: ignore Lua entirely and validate
  server behaviour against EXE response only. Long-term: reverse the
  `.lpb` decode (one-time task) so the 2,671 scripts become readable.
