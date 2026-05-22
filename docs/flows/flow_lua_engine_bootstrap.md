# Flow: Lua Engine Bootstrap and `.lpb` Loading

End-to-end sequence the client follows to bring its Lua engine online and
to load a single `.lpb` script. This is a *behavioural* flow note, not a
protocol packet — Lua engine bootstrap happens entirely client-side.

Sources:
- `docs/re/exe/finding_lua_engine_bridge.md`
- `docs/re/lua/finding_lpb_format_blocker.md`

## High-level sequence

```text
[boot]
   |
   v
1. Component::Lua::GameEngine init
     - allocate VM via LgeCommonMemoryAllocator
     - link stock Lua 5.1 ("Lua 5.1" _VERSION confirmed)
     - install LgeBase / LgeCallbackBase plumbing
   |
   v
2. Push boot-Lua chunk (literal at .rdata 0x0110e680):
        require = nil
        function require(filename, listener, errorNotify)
          if _luaGameEngineRequire(filename, listener, errorNotify) == true then
            _luaGameEngineLoad(filename, listener)
          end
          _luaGameEngineRequireEnd()
        end
        function __lge_isAlive() return false end
        function __lge_returnNil() return nil end
        collectgarbage = nil
   - Lua-side `require` is rerouted to native loader
   - Lua-side GC control disabled (native owns GC)
   |
   v
3. Register native bindings via Functor::Execute
     - Actor / Chara / Npc control
     - PacketProcessor (incoming packet hook)
     - PacketRequestBase  (outgoing packet builder)
     - InterfaceToSqwt::* (UI bridge)
     - per-game functions (TBD, enumerated by walking Functor::Execute xrefs)
   |
   v
4. Application::Lua::LuaAppBase initialises and starts a root coroutine
   |
   v
5. Root script `require`s next script:
        require("<obfuscated_name>", listener, errorNotify)
        |
        |--(coroutine yield)--
        |
        v
        native _luaGameEngineRequire(filename, listener, errorNotify):
          - asks LpbLoader to fetch <filename>.lpb from
            client/script/<obfuscated_dir>/
          - LpbLoader::ResumeChecker polls the I/O state
          - when bytes are ready, LuaThreadImpl::Resume wakes the coroutine
        |
        v
        native _luaGameEngineLoad(filename, listener):
          - read 8-byte header: "rle\x0C" + 0x0000C51F
          - reject if version dword != client's compiled lpbversion
            (logs "client lpb version: <n>" / "!!!error!!! client lpb version:")
          - decode body (RLE/transform layer — exact algorithm TBD)
          - luaL_loadbuffer(decoded standard Lua 5.1 chunk) into VM
          - call the loaded chunk under a guarded pcall
        |
        v
        native _luaGameEngineRequireEnd():
          - book-keeping; return control to the requesting coroutine
   |
   v
6. Loaded script registers UI handlers (UILuaCommands.*), actor callbacks,
   or packet observers (PacketProcessor)
   |
   v
[ready: VM is now driving UI/event/packet hooks]
```

## What gates "Lua is alive enough to drive a screen"

Behavioural prerequisites observed:

1. Engine init complete (step 1–3 above).
2. The application root `.lpb` (the "first script" — not yet identified by
   name due to obfuscation) is loaded and running its coroutine.
3. At least one UI form is loaded and a corresponding UI Lua script
   has registered handlers for the relevant `UILuaCommands.*` verbs.

If step 3 has not happened for a given screen, the client's C++ side will
load the `.form` but no Lua reaction will occur on user input. The
"cut lua actor is not exist" error strings (`00fa3268`, `00fa3318`,
`00fa33dc`) are precisely this failure mode for scenes.

## Failure modes worth recognising

- **Version mismatch**: file header dword at +0x04 != EXE `lpbversion`.
  Logs "client lpb version: " + "!!!error!!! client lpb version:".
  Script does not load; downstream features silently fail.
- **Missing script**: `_luaGameEngineRequire` returns `false`. The Lua
  `require` chain proceeds to `_luaGameEngineRequireEnd()` without a
  load, and the caller sees no error other than the helper function
  staying undefined.
- **Dead actor handle**: `__lge_isAlive()` returns `false` (default).
  Bound methods on stale actors no-op; this matches the `LuaActorImpl`
  / `NullActorImpl` split in the bindings.

## Server implication

- Lua bootstrap is **strictly client-local** and does not depend on the
  server.
- However, **after** bootstrap the server starts mattering: the
  `PacketProcessor` registered by some `.lpb` will receive a copy of every
  IPC payload (segment-type-3) the server sends — see
  `docs/re/exe/finding_ipc_channel_framing.md` for the secondary-processor
  position at `PacketBufferBase + 0x78`.
- Practical consequence for protocol bring-up: if the server delivers a
  recognised IPC packet and the C++ side reacts but UI/animation does
  not progress, the missing reaction is on the Lua side, not the wire.
- No server-side message is needed to advance Lua bootstrap.
