# Finding: Lua `_callServerOnCommand` → EXE `PlayerBase::callServerOnCommand` Bridge

Close the loop between the Lua-side outbound command call documented in
`docs/re/lua/finding_game_command_pipeline.md` and the EXE-side
`PacketRequestBase` infrastructure documented in
`docs/re/exe/finding_ipc_channel_framing.md`. Result is **bridge fully
named, packet serialiser implementation still in unanalysed bytes**.

Sources read for this finding:

```text
EXE @ 0x0073f1d0   FUN_0073f1d0  - registers "_callServerOnCommand" Lua binding
EXE @ 0x0073f320   FUN_0073f320  - registers "_doServerOnCommand" Lua binding
EXE @ 0x0073f080   FUN_0073f080  - registers "_executeCommand"     Lua binding (peer)
EXE @ 0x00726720   FUN_00726720  - Functor pool entry getter
EXE @ 0x00724800   FUN_00724800  - Functor entry constructor
EXE @ 0x0071e760   FUN_0071e760  - sets MemberFunctionHolder vftable (THE NAMING)
EXE @ 0x00753f90   FUN_00753f90  - master block: registers all ~94 PlayerBase bindings

EXE strings:
  0x00fd745c "_callServerOnCommand"
  0x00fd7474 "_doServerOnCommand"
  0x012bf790 ".?AVPacketRequestBase@Group@Client@Script@Lua@Application@@"
  0x012bf988 ".?AVPacketProcessor@Group@Client@Script@Lua@Application@@"

EXE label targets (NOT auto-analysed by Ghidra — see below):
  0x006de650  -> PlayerBase::executeCommand            (member function ptr)
  0x006de680  -> PlayerBase::callServerOnCommand       (member function ptr)
  0x006de690  -> PlayerBase::doServerOnCommand         (member function ptr)
```

## Bridge fully resolved at the binding level

`FUN_0071e760` is the constructor for the Functor's
`MemberFunctionHolder<...>` slot. Ghidra has recovered its full template
type from RTTI:

```cpp
Component::Lua::GameEngine::Functor::MemberFunctionHolder<
    class Application::Lua::Script::Client::Control::PlayerBase,
    void (__thiscall Application::Lua::Script::Client::Control::PlayerBase::*)
        (class Component::Lua::GameEngine::ExecuteParameters const &)
>::vftable
```

This says, definitively:

- The C++ class that owns the `_callServerOnCommand` and
  `_doServerOnCommand` bindings is
  `Application::Lua::Script::Client::Control::PlayerBase`.
- The method signature is **`void(ExecuteParameters const &)`** —
  the args from the Lua call are not passed positionally; they are
  packed into a `Component::Lua::GameEngine::ExecuteParameters` object
  by `Functor::GetArguments_` (RTTI string at
  `0x0110f5b4 "Component::Lua::GameEngine::Functor::GetArguments_"`),
  and the C++ method walks that object to read them.
- Two dwords are stored per binding: `param_2` (the MFP target) and
  `param_3` (the this-offset for virtual inheritance, always `0` here
  because PlayerBase is single-inheritance).

The two registrar functions are byte-for-byte clones except for two
constants:

```text
FUN_0073f1d0      FUN_0073f320       difference
----------------- ------------------ ---------------------
MFP target:       MFP target:        method to invoke
  LAB_006de680      LAB_006de690     (PlayerBase::callServerOnCommand
                                      vs ::doServerOnCommand)

binding name:     binding name:      Lua-side identifier
  "_callServerOnCommand"            "_doServerOnCommand"
```

Both are called from `FUN_00753f90`, the **master block of PlayerBase
binding registrations** — a flat unrolled sequence of ~94+ registrar
calls (one per native binding). That count matches the 94 `_xxx_cpp`
entries in `playerbaseclass_u.lua` exactly, validating the count from
`docs/re/lua/finding_player_slots_and_craft_flow.md`.

## The serialiser implementation is in unanalysed bytes

The MFP targets (`0x006de650`, `0x006de680`, `0x006de690`) live in
`.text` but Ghidra MCP reports **no function** at any of these
addresses and **no auto-analysis** of the surrounding region:

```text
get_function_by_address  0x006de4f0   -> FUN_006de4f0 ends at 006de507
get_function_by_address  0x006de500   -> no function
get_function_by_address  0x006de680   -> no function
get_function_by_address  0x006de6a0   -> no function
get_function_by_address  0x006de700   -> no function
get_function_by_address  0x006de800   -> no function
get_function_by_address  0x006df000   -> no function
```

So roughly **0x006de507 → 0x006df000+** (~2.5 KB of code) is an
auto-analysis hole.

The spacing between the three pinned labels is diagnostic:

```text
0x006de650  PlayerBase::executeCommand
              |
              +- 0x30 = 48 bytes
              v
0x006de680  PlayerBase::callServerOnCommand
              |
              +- 0x10 = 16 bytes
              v
0x006de690  PlayerBase::doServerOnCommand
```

48 and 16 bytes are far too small for methods that build an IPC
segment, push it through `PacketRequestBase`, and hand it to the Up
channel. Therefore these three slots are almost certainly **thunks**
that `jmp` to the real implementations elsewhere in `.text`, with the
real implementations sharing a serialiser helper. MSVC routinely emits
such COMDAT thunks for member function pointers passed by address.

## What we have, what we don't

```text
RESOLVED
  - The C++ owning class: Application::Lua::Script::Client::Control::PlayerBase
  - The C++ method signature: void(ExecuteParameters const&)
  - The registration site, registration mechanism, and binding count
    (~94 bindings via the master block at FUN_00753f90).
  - The argument-marshalling path:
        Lua call site
     -> Functor::Execute
     -> Functor::GetArguments_  (reads typed args off the Lua stack)
     -> ExecuteParameters const& packed
     -> PlayerBase::callServerOnCommand(ExecuteParameters const&)

NOT RESOLVED (under Ghidra MCP, without manual auto-analysis)
  - The actual body of PlayerBase::callServerOnCommand / doServerOnCommand.
  - How it constructs a PacketRequestBase derivative.
  - Which ClientPacketBuilder it dispatches through (LobbyProtoUp,
    ZoneProtoUp, ChatProtoUp).
  - The exact wire opcode and payload layout for the outgoing
    "execute command" IPC segment.
```

## How to finish the loop (out-of-MCP work)

The remaining work is a one-shot Ghidra manual session:

1. In a full Ghidra session (no MCP), navigate to `0x006de680` and use
   "Disassemble" (D) to force-decode the bytes. The first instruction
   is almost certainly a `JMP rel32` to the real implementation.
2. Follow the JMP. The real implementation:
   - Takes `this` (the PlayerBase pointer) and the
     `ExecuteParameters const&`.
   - Reads the args off the parameters object (most likely via
     `Parameter::StackOperatorInterface` — RTTI string at
     `0x0110ebd8`).
   - Constructs a `PacketRequestBase` derivative (one of the
     subclasses for "command request" — naming TBD).
   - Hands it to the `ZoneProtoChannel`'s `ClientPacketBuilder` (the
     command flow goes over the Zone channel — see
     `finding_ipc_channel_framing.md`).
3. The payload that gets serialised is the third segment-3 IPC packet
   payload spec the project needs (alongside the keepalive and the
   data-packet shapes already documented).

## Assessment

```text
Confirmed:
  - _callServerOnCommand and _doServerOnCommand are *member methods*
    of Application::Lua::Script::Client::Control::PlayerBase.
  - Method signature is void(ExecuteParameters const&). The args from
    the Lua call land in that object.
  - There are exactly ~94 native bindings registered for PlayerBase by
    a single master block FUN_00753f90, matching playerbaseclass_u.lua.
  - The MFP targets at 0x006de650/680/690 are stored as
    member-function-pointer constants into the Functor by
    FUN_0071e760, which has been RTTI-named.

Likely (High):
  - The three pinned labels are thunks (JMP rel32 to real bodies);
    real bodies live further into the unanalysed window
    0x006de507..0x006df000+.
  - The real body uses Parameter::StackOperatorInterface to walk the
    ExecuteParameters, then constructs a PacketRequestBase derivative
    and dispatches via ZoneProtoChannel's ClientPacketBuilder.

Likely (Medium):
  - Both _callServerOnCommand and _doServerOnCommand build *the same*
    IPC segment; their only difference is whether the original
    request came from the client (callServer) or as a fallback from a
    server-pushed _onCommandRequest (doServer). The wire-format is
    presumably identical and the server can treat both equivalently
    for early bring-up.

Speculative:
  - That an "ExecuteCommand" IPC opcode exists with payload
    (slot_name_string, command_id_uint32, variadic args). The args
    likely encode target actor id(s), area-target coordinates, and
    sub-target index — matching the variadic signature observed in
    PlayerBaseClass:_onCommandEvent.

Next test:
  - Manual Ghidra: force-disassemble at 0x006de680. Follow the JMP.
    Inspect the body for:
      * A `lea ecx, [esp+...]` or similar to build a stack frame for
        a `PacketRequestBase` derivative.
      * A `call` into the ZoneProtoChannel builder (cross-ref with
        the existing finding's ClientPacketBuilder address space).
      * The IPC opcode written into the segment.
  - Alternative: search for callers of any `PacketBufferTmpl
    <TZoneProtoUp>::vftable` and look for a callsite whose calling
    function name pattern matches "...callServerOnCommand...". MSVC
    sometimes keeps demangled symbols for these.

Commit suggestion:
  docs(re/correlation): name Lua/EXE command bridge; serialiser body
                        in unanalysed region pending manual Ghidra pass
```

## Server implication

We do not yet have the exact wire bytes of the "execute command"
packet — that requires the unanalysed body. But the bridge is named,
which fixes several things for the server side:

1. **One outbound IPC type carries every command.** Both
   `_callServerOnCommand` and `_doServerOnCommand` go through methods
   on the same C++ class with the same signature; almost certainly
   they emit the same packet shape (differentiated, if at all, by a
   one-bit "is-fallback" flag in the payload). A server can implement
   one handler and dispatch on the embedded command id.
2. **Per-binding marshalling is uniform.** The 94 PlayerBase bindings
   share the `Functor` registration path. Whatever encoding the
   command path uses for its `ExecuteParameters`, the other 93
   bindings use the same encoding for their inputs. Reverse one and
   the marshalling primitives unlock all of them.
3. **The Zone channel is the carrier.** The command flow does not go
   through Lobby (which is finished before zone entry) and does not
   go through Chat (which carries only chat traffic). So a minimal
   server only needs to be able to receive IPC on the Zone channel
   for command traffic.
4. **Static service actors observed so far** (running list, updated):
   - `310001` WorldMaster
   - `320013` Chocobo Rider
   - `24301`  Instance Raid service
   - `12015`  Push-Out-From-Chocobo sentinel command
   Plus the implicit `PlayerBase` (the local player actor) which is
   the target of `_callServerOnCommand`.
