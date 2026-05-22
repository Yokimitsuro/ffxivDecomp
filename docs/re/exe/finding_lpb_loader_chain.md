# Finding: `.lpb` Loader Chain — Entry Points, Header, Ring Buffer, and Decode Status

Map the EXE-side path from Lua's `require(...)` call through to
`luaL_loadbuffer()` for a `.lpb` script, document the on-disk header layout
empirically, and report the *current* status of the body-decode algorithm
(reachable but not yet fully extracted).

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

### Header layout observed across many .lpb files

Sampled five 69-byte stub files (different obfuscated names) and one
~7 KB content file. Header (16 bytes) is consistent:

```text
+0x00  4  magic        = "rle\x0C"
+0x04  4  lpb_version  = 0x0000C51F   (one file showed 0x0000461C -- older build)
+0x08  4  decoded_size = uint32 LE    (matches expected uncompressed size)
+0x0C  4  format_const = 0x063F68FF   (CONSTANT across all sampled files)
+0x10  …  encoded body
```

Cross-file comparison nails the field at `+0x0C` as a **fixed encoder
constant or RLE seed/IV**, **not** a per-file checksum (it does not
change between files of differing content). The dword value
`0x063F68FF` itself is not a known CRC32 magic; its semantic role is
TBD.

### Body shape (empirical)

- Encoded vs decoded sizes are within a few bytes of each other
  (e.g. stub: 53 enc -> 56 dec; mid-size file: 7010 enc -> 7013 dec). This
  rules out LZ-class compression — the format is *near-1:1*.
- The **first 16 bytes** of every encoded body are constant across all
  inspected .lpb files (stubs and content files alike):
  ```text
  12 22 73 72  77 77 77 7B  73 73 73 73 73 73 73 73
  ```
  This corresponds to the **standard Lua 5.1 header** in the decoded
  stream (which is always identical for a given Lua build):
  ```text
  1B 4C 75 61  51 01 04 04  04 08 00 00 00 00 00 00
  ```
  i.e. `\x1bLua\x51\x01\x04\x04\x04\x08` (magic + version + format +
  endianness + sizeof(int)=4 + sizeof(size_t)=8) plus six zero bytes.
- The mapping from encoded bytes to decoded bytes is **not** a single-byte
  XOR / ADD / substitution: the same encoded byte 0x77 (in positions 4
  and 5 of the body) decodes to two different bytes (0x51 then 0x01).
  The pad/transform therefore has per-position state.
- Encoded `0x73` does *not* always represent a literal `0x00` either —
  it does so at positions 8..15 (where decoded bytes are all 0x00), but
  at position 2 the encoded byte `0x73` decodes to `0x75` ('u' in
  `\x1bLua`).

The most consistent hypothesis is **a stateful stream transform** (small
PRNG / rolling key) seeded from `format_const` (`0x063F68FF`), possibly
combined with a special-case for zero-byte runs (justifying the `"rle"`
mnemonic in the magic).

### Validation: `lpb_probe.py` (kept under `tools/local/`)

A small probe was added at `tools/local/lpb_probe.py` (gitignored by
`tools/local/`). It currently tries:

- raw zlib / deflate / gzip with various `wbits`
- single-byte XOR keying onto `\x1bLua\x51`
- single-byte ADD keying onto `\x1bLua\x51`
- naive RLE with markers 0x73, 0x77, 0x00, 0x12

**None** of these candidates produces `\x1bLua` output on any of the
sampled files. This is consistent with the per-position-state hypothesis
above and is the experimental evidence ruling out the simpler schemes.

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
  - Header is 16 bytes: magic ("rle\\x0C"), lpb_version, decoded_size,
    and a fixed encoder constant 0x063F68FF.
  - Body length is essentially equal to decoded length (1:1, not LZ).
  - The first 16 body bytes are constant across all files and correspond
    to the constant Lua 5.1 chunk-header in the decoded stream.

Likely (High):
  - The body is encoded by a **stateful** stream transform (single-byte
    XOR / ADD / substitution all ruled out empirically).
  - The transform's state seed is the dword at file +0x0C
    (`0x063F68FF`), which is identical across files and therefore makes
    *every file* decode from the same initial state.
  - A producer function on the file-IO side (downstream of the work
    queue at LpbLoader+0xb0, upstream of the ring buffer at +0xbc)
    contains the decoder. Its address has not been pinned in this pass.

Likely (Medium):
  - The "rle" mnemonic refers to a special-case path for zero-byte
    runs inside the stream (justifying the constant 0x73 mapping at
    body offsets 8..15) — i.e. the transform is mostly a stream cipher
    but emits a different code when many zeros are present.

Speculative:
  - 0x063F68FF is an LCG / PRNG seed. Common 32-bit constants such as
    0x9E3779B9 / 0xC6EF3720 are not visible here, so if it's a PRNG it
    is a SE-custom one.

Next test (in priority order):
  1. Find the ResumeChecker vtable in .rdata (xref the RTTI string at
     0x0130d574). Inspect the "process" / "run" slot — that is what the
     work-queue worker invokes. It is the canonical entry to the
     decode + ring-buffer-push code.
  2. Walk from that entry forward until either a memcpy with a small
     loop over input bytes is found, or until a separate "decode" helper
     is called. Decompile that helper; its inputs are `(encoded_ptr,
     encoded_len, decoded_buf, decoded_cap, seed=0x063F68FF)`.
  3. Once the algorithm is extracted, port it to `tools/local/lpb_probe.py`
     (or a new `tools/local/lpb_decode.py`) and confirm the output of
     decoding a stub .lpb begins with `\\x1bLua\\x51\\x01\\x04\\x04\\x04\\x08`.
  4. Then run unluac.jar on the decoded chunk to recover Lua 5.1 source.

Commit suggestion:
  docs(re/exe): map .lpb loader chain and header; algorithm extraction
                stalled at per-position transform
```

## Server implication

- Unchanged from `docs/re/lua/finding_lpb_format_blocker.md`: the server
  bring-up does not depend on `.lpb` decompilation working.
- This finding *narrows* the remaining work to a single-function reverse
  on the file-IO completion path (driven from the LpbLoader's work
  queue). Once that one function is decompiled, all 2,671 scripts become
  readable in batch — which then enables reading what the client *expects*
  to happen on the server side at the UI / scene / actor level.
- No tooling change is required on the server side. Whether `.lpb`
  decompilation has happened or not is invisible to the wire.
