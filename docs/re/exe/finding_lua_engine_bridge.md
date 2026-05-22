# Finding: Lua Engine Bridge (`Component::Lua::GameEngine` + `Application::Lua`)

Document the architecture of the EXE↔Lua bridge as recoverable from the
loaded program. This is needed because the on-disk `.lpb` scripts are
currently undecompilable (`docs/re/lua/finding_lpb_format_blocker.md`), so
the only available evidence about what the Lua side does is what the
**native side exposes to Lua** and **calls back from Lua**.

## Targets / namespaces

```text
Component::Lua::GameEngine                 -- embedded VM wrapper (lib layer)
  LpbLoader                                -- on-disk script loader
    ResourceEvent
    ResumeChecker
  LuaThreadImpl                            -- per-Lua-thread / coroutine
    Resume
    YieldLua
    PushCallStack
    PrepareStackForCallBaseClassFunction_
  Parameter::StackOperatorInterface
    PushReturnsToStack
  Functor                                  -- C++ -> Lua bind dispatcher
    Execute
    GetArguments_
    PushReturns_
  LuaControl
  LuaObject
  LgeBase / LgeCommonMemoryAllocator / LgeBasicMemoryAllocator
  ExecuteScriptListenerInterface
  FunctionEndCallbackInterface
  FunctionEndCallbackFinderInterface
  LuaManyTentativeControlCreator
  LuaThreadEndListenerInterface
  SharedWorkInterface
  SyncWriterLargeDataCheckerInterface
  SyncWriterSetListenerInterface
  LgeCallbackBase / LgeCallbackMemoryAllocator

Application::Lua                           -- per-game bindings
  LuaAppBase                               -- application root
  LuaGCModuleControllerBase / LuaGCModuleController
  InterfaceToSqwt::SetPropertyProcessorInterface
  InterfaceToSqwt::SendStoryboardCommandProcessorInterface
  Script::Client::Control::ActorBase       -- bind: Lua <-> game actor
  Script::Client::Control::CharaBase       -- bind: Lua <-> player character
  Script::Client::Control::NpcBase         -- bind: Lua <-> NPC
  Script::Client::LuaActorImplInterface
  Script::Client::LuaActorImpl
  Script::Client::NullActorImpl
  Script::Client::Group::PacketProcessor   -- bind: Lua <-> packet recv
  Script::Client::Group::PacketRequestBase -- bind: Lua <-> packet send

Component::Lua::GameEngine::LuaControl     -- Lua-side handle for native objects
Application::Main::Element::Window::LuaDebug::LuaDebugLog
Application::Main::Element::Window::LuaDebug::LuaDebugOut
```

## Evidence

### Embedded VM identity

- `011331d8: "Lua 5.1"` — `_VERSION` string of standard Lua 5.1.
- `011329a4: "luaopen_%s"` — the standard `luaopen_<libname>` registration
  format used by Lua 5.1.
- `01132bc0: ".\?.lua;!\lua\?.lua;!\lua\?\init.lua;!\?.lua;!\?\init.lua"`,
  `01132bfc: "LUA_PATH"`, `01132c30: "LUA_CPATH"`,
  `011312f4: "PANIC: unprotected error in call to Lua API (%s)"`,
  `01131a84: "lua_debug> "` — all are unchanged Lua 5.1 reference-impl
  strings; the VM was linked from stock liblua plus an SE wrapper, not
  replaced.

### Replaced `require()` and disabled GC at Lua-side boot

`0110e680` contains the verbatim bootstrap Lua chunk pushed into every
state on init:

```lua
require = nil
function require(filename, listener, errorNotify)
  if _luaGameEngineRequire(filename, listener, errorNotify) == true then
    _luaGameEngineLoad(filename, listener)
  end
  _luaGameEngineRequireEnd()
end
function __lge_isAlive()
  return false
end
function __lge_returnNil()
  return nil
end
collectgarbage = nil
```

Implications:

- The standard `require` (which would read `LUA_PATH`) is replaced by a
  cooperative two-call sequence into the native loader:
  `_luaGameEngineRequire(filename, listener, errorNotify)` followed
  conditionally by `_luaGameEngineLoad(filename, listener)`, then
  `_luaGameEngineRequireEnd()`. This is the only way a `.lpb` ever gets
  pulled in — there is no direct `loadfile`/`dofile` path for scripts.
- `collectgarbage = nil` removes Lua-side GC control: garbage collection
  is driven from C++ (via `LuaGCModuleController`).
- `__lge_isAlive` returns `false` by default — it is overwritten per
  bound object so script code can check "is this native handle still
  valid?" without holding strong references.
- There is also `_luaGameEngineRequireYield` (`0110f0a8`) — implies the
  loader yields the Lua coroutine while it asynchronously fetches the
  next .lpb from disk/archive, then resumes when bytes are ready. This
  matches the presence of `LpbLoader::ResumeChecker` and
  `LuaThreadImpl::Resume`.

### Callback dispatch shape

`Component::Lua::GameEngine::Functor::{Execute, GetArguments_,
PushReturns_}` plus `Parameter::StackOperatorInterface::PushReturnsToStack`
follow the classic SE/Crystal Tools binding pattern:

- A native binding is a `Functor` object whose `Execute` is called from
  Lua.
- `Functor::GetArguments_` reads positional args off the Lua stack via
  `Parameter::StackOperatorInterface`.
- `Functor::PushReturns_` / `PushReturnsToStack` pushes return values
  back.
- `LuaThreadImpl::PushCallStack` records the Lua call site for error
  reporting.

This is the path **every** native call from a `.lpb` script goes through.
There is no `lua_pushcfunction`-with-an-arbitrary-C-function in the
hot path — all bindings are routed through `Functor::Execute`, which
keeps the bind list discoverable by xref-walking `Execute` callers.

### Application bindings (what Lua scripts can do)

Concrete bindings exposed to script (from RTTI):

```text
Script::Client::Control::ActorBase     -> manipulate any Actor
Script::Client::Control::CharaBase     -> manipulate a player Character
Script::Client::Control::NpcBase       -> manipulate NPCs
Script::Client::LuaActorImpl           -> the Lua-side handle backing an Actor
Script::Client::NullActorImpl          -> safe no-op handle for unbound Actor
Script::Client::Group::PacketProcessor -> route incoming server packets to Lua
Script::Client::Group::PacketRequestBase -> build outbound packets from Lua
InterfaceToSqwt::SetPropertyProcessorInterface       -> set UI properties
InterfaceToSqwt::SendStoryboardCommandProcessorInterface -> issue Sqwt cmds
```

Key correlations to other findings:

- **`PacketProcessor` is the secondary processor at `PacketBufferBase
  + 0x78`** (see `docs/re/exe/finding_ipc_channel_framing.md`). In the
  segment parser (`docs/packets/packet_frame_and_segment_header.md`),
  type-3 IPC dispatch path calls `*(*+0x1c)` of the secondary processor
  — i.e. it forwards every received IPC payload to Lua scripts in
  addition to the primary C++ dispatch. This explains how Lua scripts
  can observe and react to server traffic without owning the socket.
- **`PacketRequestBase` is the outbound path** — scripts can request a
  packet send and the native side constructs the actual segment-3 IPC
  via the per-channel `ClientPacketBuilder` documented in the channel
  finding.

### UI-event names visible to Lua

`UILuaCommands.*` and `UIOperatorCommands.*` strings indicate the set of
verbs Lua scripts dispatch into the UI layer:

```text
UILuaCommands.Operate                 UIOperatorCommands.BeforeLuaInit
UILuaCommands.Cancel                  UIOperatorCommands.AfterLuaInit
UILuaCommands.WidgetClose             UIOperatorCommands.BeforeLuaShow
UILuaCommands.Selection               UIOperatorCommands.AfterLuaShow
UILuaCommands.SelectionChanged
UILuaCommands.SelectionChangedOnce
UILuaCommands.MainMenu
UILuaCommands.Function1
UILuaCommands.PressEnter
HCUILuaCommands.Cancel                (HC = HardCoded?)
```

These names appear directly in script-bound code paths; a `.lpb` that
implements one of them will reference these literal strings.

### Debug-console verbs

`FUN_0057a190` registers debug-console commands. The set includes:

```text
"lpbversion"    -> FUN_00578ab0    (prints loaded lpb version)
"lpb"           -> FUN_00578ab0    (alias)
"zone"          -> FUN_005776b0    (zone command — TBD)
"gettutorialmode" -> FUN_00578ba0
"list"          -> FUN_00577780
"gmevent"       -> FUN_00579000    (GM/test event trigger)
"achievement"   -> FUN_005794c0
"acv"           -> FUN_005794c0    (alias for achievement)
```

`gmevent`, `zone`, and `achievement` are the most useful for protocol
research — once the dispatcher is reachable (via the `\debug\LuaDebugOut.form`
window), they let the operator inject behaviour without going through a
real server.

## Assessment

```text
Confirmed:
  - Embedded VM is stock Lua 5.1 wrapped by SE's GameEngine layer.
  - require() is forcibly replaced with a native-driven two-call sequence;
    standard Lua module resolution is not used.
  - Garbage collection is removed from Lua-side control.
  - All native bindings go through Functor::Execute, making the bind
    surface discoverable by Functor::Execute xref-walking.
  - Lua scripts have first-class bindings to Actor / Character / NPC
    manipulation, to outbound packet construction, and to UI commands.
  - PacketProcessor is the secondary processor on PacketBufferBase,
    receiving a copy of every incoming IPC packet for script-side reaction.

Likely (High):
  - The .lpb loader is cooperative-coroutine driven (Resume / Yield /
    ResumeChecker). Loading a script can block the Lua side without
    blocking the client.
  - Every UI Lua command in the UILuaCommands.* set corresponds to a
    well-known script entry point that a server can rely on existing.

Likely (Medium):
  - The PacketRequestBase outbound binding gates which IPC packet ids a
    Lua script can construct. This may be smaller than the full set the
    EXE's C++ side can build.

Speculative:
  - That the GameEngine boot chunk at 0x0110e680 is the only Lua source
    embedded as a literal string. (Other small literals like "work.lua"
    and "dummy.lua" suggest at least sentinel script names exist as data.)
  - That LuaActorImpl / NullActorImpl swap dynamically based on whether
    a target actor is still alive; this is consistent with
    __lge_isAlive returning false-by-default.

Next test:
  - Xref Functor::Execute (RTTI string at .rdata) and walk the
    registration table to enumerate every Lua-callable native function
    by name. This is the canonical "what can scripts do" inventory.
  - Locate the .lpb loader entry by xref-ing the string "client lpb
    version: " (already known at 0x00fa6ac4) -> FUN_00578ab0 ->
    FUN_00cc7730; the parent of FUN_00cc7730 is likely the LpbLoader
    instance, from which `_luaGameEngineRequire` can be reached.
  - Inspect FUN_005776b0 ("zone" debug verb) and FUN_00579000 ("gmevent")
    — these are the easiest in-EXE entry points for forcing client
    state from a development perspective and will help the server side
    by exposing what the client treats as a "zone change" or "GM event".

Commit suggestion:
  docs(re/exe): document Lua 5.1 bridge (Component::Lua::GameEngine,
                Application::Lua) and confirm PacketProcessor as
                PacketBufferBase secondary processor
```

## Server implication

- **A compatible server does not need to ship Lua to bring the client
  online.** The EXE-side C++ path handles all network framing, segment
  parsing, and primary packet dispatch. Lua scripts are downstream
  *observers* of incoming packets and *requesters* for outgoing packets.
- However, **certain client behaviours are gated on a `.lpb` reacting**
  — examples include UI screen transitions (`UILuaCommands.MainMenu`,
  `Selection`, `WidgetClose`) and cut-scene / scene-change handling
  (the `cut lua actor is not exist` error strings show that scenes
  expect a live Lua actor). For those flows, a server can drive the
  client only if the corresponding script is still loaded; if a script
  is missing, the client logs and continues, but the user-visible
  behaviour may not occur.
- **For "is the server's IPC packet being received?" testing**, sending
  an IPC packet to the client will exercise both the C++ dispatch AND
  the `PacketProcessor` Lua hook. If only the C++ side reacts and Lua
  remains silent, that diagnoses a script-side gap rather than a
  protocol gap.
- **`_luaGameEngineRequire` is the only legitimate way to load a `.lpb`**.
  Any private/network-fed script-injection path would have to forge the
  same call sequence; the server-server interface has no exposure to
  this from the network.
- **Test-server practical recipe**: implement the C++ packet dispatch
  with no expectation that Lua-side packet processors will ever ACK
  anything; only require ACK from primary dispatch for protocol
  progression. This avoids being blocked on `.lpb` decompilation
  (see `docs/re/lua/finding_lpb_format_blocker.md`).
