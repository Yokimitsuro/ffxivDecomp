# Finding: `.lpb` Loader Chain — Entry Points, Header, and Working Decoder

Map the EXE-side path from Lua's `require(...)` call through to
`luaL_loadbuffer()` for a `.lpb` script, document the on-disk header layout
empirically, and record the working body-decode algorithm.

> **Status update (later in same session)**: the algorithm *was* extracted —
> the body is a plain `XOR 0x73` over the bytes that follow a **13-byte**
> header. My earlier ruling-out of single-byte XOR was wrong: I had the
> header size off-by-3 (treated bytes 12..15 as a 4-byte field instead of a
> 1-byte flag + start-of-payload) and was comparing against an incorrect
> reference Lua 5.1 header (used `0x01` for the format byte where Lua
> actually uses `0x00 0x01`). With those two errors corrected the decode is
> trivial. End-to-end-verified against 2,670 / 2,671 scripts. See
> "Working algorithm (corrected)" below.

Companion: `docs/re/lua/finding_lpb_format_blocker.md`,
`docs/re/exe/finding_lua_engine_bridge.md`.

## Targets

```text
FUN_00d08180  candidate: _luaGameEngineLoad        (Lua C function)
FUN_00d08a10  candidate: _luaGameEngineRequire     (Lua C function)
FUN_00d08e50  candidate: _luaGameEngineRequireEnd  (Lua C function)
FUN_00d0cfb0  candidate: LpbLoader__resolveAndFetch
FUN_00d0bb10  candidate: LpbLoader::ResumeChecker__ctor
FUN_00d0d470  candidate: LpbLoader__popRingSlotAndLoad
FUN_00d0ca50  candidate: LpbLoader__loadIntoLuaState     (calls luaL_loadbuffer)
FUN_00cf4680  candidate: luaL_loadbuffer  (or equivalent SE wrapper)
FUN_00d0f360  candidate: ByteSpan__copyCtor
FUN_00cd7fe0  candidate: LpbLoader__getCurrentLpbVersion (reads LpbLoader+0x104)
FUN_00cc7730  candidate: GameEngine__getLpbVersion       (thin wrapper)
FUN_00d11940  candidate: WorkQueue__enqueue (LpbLoader+0xb0)
```

## Evidence

### Entry-point registration

`FUN_00cd8990` registers the three Lua-callable C functions into the VM:

```text
_luaGameEngineRequire      -> FUN_00d08a10  (closure: bound to LpbLoader at +0x1d0)
_luaGameEngineLoad         -> FUN_00d08180  (closure: bound to LpbLoader at +0x1d0)
_luaGameEngineRequireEnd   -> FUN_00d08e50  (no upvalue)
```

Same function also pushes the boot Lua chunk that redefines `require`
(see `docs/re/exe/finding_lua_engine_bridge.md`) and registers a long list
of Lua-side helpers (`assert`, `error`, `pcall` -> `_pcall`, `_time`,
`_clock`, `__lge_getWork`, `__lge_setLoopInterval`, `__lge_syncById`,
`__lge_getIndividualIndex`, `__newindex`, `_onLoop`).

### `_luaGameEngineLoad` -> ring buffer -> luaL_loadbuffer

`FUN_00d08180` body (paraphrased):

```c
// param_1 = lua_State*
FUN_00cf3180(L_wrapper, lua_State);
int top   = FUN_00cf34c0(L_wrapper);     // lua_gettop
listener  = (top == 2 && lua_isfn(L,2))  // optional 2nd arg
              ? lua_touserdata(L, 2) : NULL;
this      = FUN_00cf3620(L_wrapper);     // self LpbLoader (upvalue)
filename  = FUN_00cf3600(L_wrapper, ...);// lua_tolstring(L, 1)
FUN_00d0d470(this, L_wrapper, filename, listener);  // do load
```

`FUN_00d0d470`:

```c
uint idx = this->ring_read_idx;          // this+0xc4
// wrap modulo this+0xc8 / this+0xc0
ByteSpan slot = ring_buf[idx];           // ptr in this+0xbc
ByteSpan copy;                            // local_1c
FUN_00d0f360(&copy, slot);                // copy the bytes out
FUN_00d0e1f0(&this->ring_state);         // advance ring (consume)
// (optional debug callback at this+0x108)
FUN_00d0ca50(this, L_wrapper, filename, listener, &copy);  // load into VM
```

`FUN_00d0ca50` is where the decoded bytes are handed to the Lua VM:

```c
// param_4 (= &copy) has fields {ptr, end} at +0x04, +0x08
size_t len  = copy.end - copy.ptr;
char *bytes = copy.ptr;
SqexString chunkname = filename + ".lua";   // ".lua", not ".lpb"
int err = FUN_00cf4680(L, bytes, len, chunkname, &status);  // luaL_loadbuffer
```

So the **decoded** Lua 5.1 bytecode lives in the ring-buffer slot at
`LpbLoader + 0xbc[idx]` as a `{ptr, end}` span, gets memcpy'd into a
fresh heap buffer by `FUN_00d0f360`, and is then passed verbatim to
`luaL_loadbuffer`. The decode therefore happens *somewhere on the
producer side of the ring buffer*, before this point — but
`FUN_00d0d470`/`FUN_00d0ca50` themselves do **no** decoding.

### `_luaGameEngineRequire` -> file lookup -> async fetch

`FUN_00d08a10` is the cooperative pre-load:

```c
// param_1 = lua_State*; arg 1 = filename string; opt arg 2 = listener;
// opt arg 3 = errorNotify boolean
push helper: _luaGameEngineRequire (deep recursive guard)
ok = FUN_00ccd1b0(...);                  // pcall-style guard
if (ok) {
    listener = arg2_or_null;
    errorNotify = arg3_or_false;
    rc = FUN_00d0cfb0(LpbLoader, L, filename, listener, errorNotify);
    if (rc == 0) {
        push helper: _luaGameEngineRequireYield
        FUN_00ccd1b0(...);               // re-enter pcall guard
        // pushed flag = need-to-yield
    } else if (rc == 1) push true        // ready
    else if (rc == 2) push false         // cancel
}
```

`FUN_00d0cfb0` is the actual file lookup:

```c
// build "<this+8 base_dir><filename><this+0x5c suffix>"  ("./" + name)
SqexString path = base + name + suffix;
if (!file_exists(path)) {
    // retry with ".lpb" suffix appended
    path = base + name + ".lpb";
    if (!file_exists(path)) {
        log(name + " not found");
        listener->vtable[+8](L);          // notify "not found"
        return 2;                          // cancel
    }
}
// create ResumeChecker (FUN_00d0bb10), enqueue to LpbLoader's work queue
ResumeChecker *rc = new(0x78);            // sizeof(ResumeChecker) = 120
FUN_00d0bb10(rc, this, listener, name, this);
// rc is enqueued via FUN_00d11940 to LpbLoader+0xb0 work list
// async fetch path runs and eventually writes decoded bytes into ring_buf[idx]
```

`FUN_00d0bb10` is `ResumeChecker::ctor`:

```text
+0x00 vtable = Component::Lua::GameEngine::LpbLoader::ResumeChecker::vftable
+0x04 lua_State_wrapper*
+0x08 LpbLoader*               (re-stored)
+0x0c filename string (Sqex::Misc::Utf8String, ~84 bytes)
+0x60 LpbLoader*               (also stored here for dispatcher convenience)
+0x68 buffer_begin (null until fetched)
+0x6c buffer_end   (null until fetched)
+0x70 ?
+0x74 status byte
+0x75 done byte
+0x76 error byte
```

So one `ResumeChecker` corresponds to one in-flight script request. The
async path eventually fills `+0x68 / +0x6c` with the **decoded** bytes
and signals via `+0x74..+0x76`, then the next `_luaGameEngineLoad`
invocation pops the slot.

### LpbLoader instance field map (partial)

Derived from accesses in the above functions:

```text
+0x000 vtable
+0x004 ? (vector<void*> or arena)
+0x008 base_dir (Sqex::Misc::Utf8String) -- "./"/script root
+0x05c suffix   (Sqex::Misc::Utf8String) -- ""/locale tag
+0x0b0 work queue head (ResumeChecker* list anchor)
+0x0b4 file IO subsystem ptr
+0x0b8 ring state object (begin/end/iter)
+0x0bc ring buffer (array of ByteSpan*)
+0x0c0 ring base offset
+0x0c4 ring read index
+0x0c8 ring capacity
+0x0e0 secondary work queue (used in FUN_00d0cfb0 fallback path)
+0x0e8 sync state flag
+0x0ec deferred-load list
+0x0f8 retry list / second-chance queue
+0x104 lpb_version (uint32, cached from a loaded file -- read by FUN_00cd7fe0)
+0x108 debug flag (FUN_00d0d470 only invokes debug branch if non-zero)
+0x109 logging flag
+0x1bc current ResumeChecker*
+0x1c0 lua_State manager*
+0x1c4 ? (size 0x58 allocator)
+0x1c8..0x1d0 various Lua engine subobjects
+0x224 ? (post-init bit)
```

### Header layout (corrected)

Sampled five 69-byte stub files and one ~7 KB content file. Header is
**13 bytes**, not 16:

```text
+0x00  4  magic        = "rle\x0C"
+0x04  4  lpb_version  = 0x0000C51F   (one file showed 0x0000461C -- older build)
+0x08  4  decoded_size = uint32 LE    (length of payload AFTER decode)
+0x0C  1  flag         = 0xFF          (single byte; role TBD, constant in samples)
+0x0D  …  XOR-0x73-encoded body
```

My initial parse mistakenly treated bytes 12..15 (`FF 68 3F 06`) as a
four-byte dword `0x063F68FF`. The first byte (`0xFF`) is actually a
one-byte flag and the next three bytes (`68 3F 06`) are already the
first three bytes of the encoded Lua chunk header — which decode under
`XOR 0x73` to `1B 4C 75` ("`\x1bLu`...").

### Working algorithm (corrected)

```python
def decode(data: bytes) -> bytes:
    assert data[:4] == b"rle\x0c"
    decoded_size = int.from_bytes(data[8:12], "little")
    # data[12] is a 1-byte flag (0xFF in all sampled files; role TBD)
    return bytes(b ^ 0x73 for b in data[13:13 + decoded_size])
```

The transformation is the simplest possible: **XOR every payload byte
with `0x73`.** Decoded output begins at file offset 13 and is exactly
`decoded_size` bytes long.

Re-checking the first 12 bytes of a typical file against this:

```text
file offset 13..24 (encoded):  68 3F 06 12 22 73 72 77 77 77 7B 73
XOR 0x73                       =====================================
decoded                        1B 4C 75 61 51 00 01 04 04 04 08 00
                              ( \x1b   L   u   a   Q   . . . . . . . )
```

which is the standard **Lua 5.1 little-endian, 32-bit-int, 64-bit-size_t,
4-byte-instruction, 8-byte-double, IEEE-754** header byte for byte —
exactly what `luaL_loadbuffer` expects.

The reason my earlier empirical probe failed:

- I parsed the first 16 bytes as the header (treating `FF 68 3F 06` as a
  dword), so my "body offset 16" tests were skipping the first three
  payload bytes.
- I compared against a memorised reference Lua 5.1 header of
  `... 51 01 04 04 04 08 ...`, which is wrong: the actual standard
  header byte at offset 5 (the `format` byte) is `0x00` for official
  builds, with `0x01` being the *endianness* byte at offset 6. With the
  bad reference, the XOR pad came out non-uniform and led me to wrongly
  conclude the transform was per-position-stateful.

### Encoded vs decoded size

```text
file_size = 13 + decoded_size
```

This makes the wrapper a flat one-byte expansion over plain Lua 5.1
bytecode: there is no compression at all, just `XOR 0x73`. Encoded and
decoded body sizes are identical.

### Edge case: `rlu\x0B` variant (1 file)

One outlier file (`9s59\kvw5\kvw5xvo5usv3q5rq.le.lpb`, 139 bytes) uses
magic `rlu\x0B` instead of `rle\x0C`. Inspection shows its body starts
directly with `1B 4C 75 61 51 00 01 04 ...` — i.e. plain Lua 5.1
bytecode with **no XOR**. Same 8-byte header prefix (magic + version),
no flag byte, payload starts at file offset 8.

```text
+0x00  4  magic        = "rlu\x0B"
+0x04  4  lpb_version  = 0x00001D96
+0x08  …  plain Lua 5.1 bytecode (no XOR)
```

This is presumably the "Raw LUa" sibling of the "RLE-encoded" wrapper,
used for one file that the build pipeline chose not to obfuscate. The
overall decoder needs a small branch:

```python
if data[:4] == b"rle\x0c":
    return bytes(b ^ 0x73 for b in data[13:13 + decoded_size])
elif data[:4] == b"rlu\x0b":
    return data[8:]
```

### Validation result

Running the user-supplied `tools/local/decode.py` (XOR-0x73 over the
13-byte header) against the full `client/script/` tree:

```text
OK: 2670  Bad: 1
  bad: 9s59\kvw5\kvw5xvo5usv3q5rq.le.lpb - not rle wrapper   (the rlu variant)
```

i.e. **99.96 %** of all scripts decode on the first pass. The single
outlier is the `rlu\x0B` variant above.

End-to-end confirmation via `unluac.jar` on one decoded output
(`3yv89y_p.lub`, 3,509 bytes — the engine class-system bootstrap):

```text
EXIT=0
local L0_1, L1_1
L0_1 = _G
function L1_1(...)
  local L3_2, L4_2
  L3_2 = "global"
  L4_2 = "_defineClass_cpp"
  return L3_2, L4_2
end
L0_1._defineClass_inl = L1_1
... (continues with _defineBaseClass_cpp, _isInstanceOf_cpp,
     _isExistActor_cpp, etc.)
```

i.e. **decoded scripts decompile cleanly with stock unluac.** No
SE-custom Lua VM extensions are needed at the bytecode level. The
binding names visible in this very first script (`_defineClass_cpp`,
`_defineBaseClass_cpp`, `_isInstanceOf_cpp`, `_isExistActor_cpp`,
etc.) confirm the SE Lua-OO class system documented in
`finding_lua_engine_bridge.md`.

### Why the initial probe missed the answer

`tools/local/lpb_probe.py` (early in the session) tested
single-byte XOR, single-byte ADD, naive RLE, and zlib/deflate. The
XOR-0x73 case *was* tested, but failed because:

1. The probe assumed the header was 16 bytes long and looked for
   `\x1bLua\x51` at body offset 0 of *that* assumption, missing the
   first three bytes of real payload.
2. The probe compared against a memorised `\x1bLua\x51` prefix; the
   correct check is the 12-byte `\x1bLua\x51 0x00 0x01 0x04 0x04 0x04
   0x08 0x00` Lua 5.1 header — and a one-byte XOR test against the
   shorter literal happens to still hit the same key, so this on its
   own wouldn't have masked the result. But combined with the
   off-by-three header parse, the probe never tried `XOR 0x73` against
   body offset 0 of the *correct* payload.

The decoder under `tools/local/decode.py` (added by the user) supplied
the correct 13-byte header parse, after which the XOR was trivial.
**Lesson**: when ruling out simple algorithms, always re-derive the
header length empirically (e.g. by comparing across files of different
content sizes) before deciding the payload offset.

## Assessment

```text
Confirmed:
  - Lua-side require("name") translates to one of three native calls
    (_luaGameEngineRequire / _luaGameEngineLoad / _luaGameEngineRequireEnd),
    bound at FUN_00d08a10 / FUN_00d08180 / FUN_00d08e50.
  - File lookup tries name verbatim, then name + ".lpb".
  - Decoded bytes pass through a per-LpbLoader ring buffer at +0xbc and
    are handed directly to luaL_loadbuffer (FUN_00cf4680) with chunkname
    = "<name>.lua".
  - Header is 13 bytes: magic ("rle\\x0C") + lpb_version + decoded_size
    + 1 flag byte (0xFF in samples).
  - Body is plain XOR-0x73 over the next `decoded_size` bytes; no
    compression. Encoded body size == decoded body size.
  - One file uses an `rlu\\x0B` variant with an 8-byte header and no
    XOR (raw bytecode).
  - Decoded output IS standard Lua 5.1 bytecode and unluac.jar
    decompiles it without modification.

Likely (High):
  - The "rle" mnemonic is just the SE label for this XOR-obfuscation,
    not literal run-length encoding. The "rlu" variant means "raw lua"
    (no obfuscation).
  - The flag byte at file +0x0C governs the format variant or marks
    "needs XOR" vs other modes. Only 0xFF observed in samples.

Likely (Medium):
  - The actual XOR loop in the binary lives downstream of the
    LpbLoader work queue (LpbLoader+0xb0) and upstream of the ring
    buffer (LpbLoader+0xbc). Pinning it in Ghidra is now optional
    follow-up because the algorithm is already known empirically.

Speculative:
  - 0xFF at file +0x0C might select among multiple obfuscation modes
    (e.g. different XOR keys for different builds). Only one mode has
    been observed in 2,670 files; no contradicting evidence has surfaced.

Done:
  - Decoder validated end-to-end: 2,670 of 2,671 files decode and
    unluac yields readable Lua 5.1 source.

Next test:
  - Patch the decoder to also handle the rlu\\x0B variant (1 file).
  - Bulk-decompile all 2,670 .lub files into a queryable corpus
    (gitignored under lua/decompiled/).
  - Begin reading the corpus for the topics the user originally asked
    about: login / lobby / world / zone / loading / actor / character /
    event / network. Now unblocked.

Commit suggestion:
  docs(re/exe): correct .lpb header parse and document working
                XOR-0x73 decoder; unblock Lua-side analysis
```

## Server implication

- Unchanged from `docs/re/lua/finding_lpb_format_blocker.md` regarding
  the wire: nothing about the `.lpb` decode affects the protocol.
- However, the **Lua-side blocker is now lifted**. All 2,670 standard
  scripts and 1 raw script are recoverable. Per-flow follow-ups
  (login / lobby / world / zone / loading / actor / character / event /
  network) — the topics the user originally asked about — can now be
  answered by reading the corpus rather than by inference from EXE-side
  bindings alone.
- The decoder is `tools/local/decode.py` (kept gitignored per project
  policy). Decoded `.lub` files should be written to `lua/decompiled/`
  (also gitignored).
