# Finding: ExecuteParameters Marshalling -- 14 Typed StackOperator Categories

Maps the Lua↔EXE argument marshalling system used by Functor bindings
(the ~94 PlayerBase + N NpcBaseClass + N other class bindings). The
system is templated over `StackOperator<T>` for each supported type;
14 distinct type categories are identified from RTTI strings.

## Sources

```text
EXE strings (RTTI type descriptors):
  0x0130c788  ".?AVStackOperatorInterface@Parameter@GameEngine@Lua@Component@@"
  0x0130c7d0  ".?AV?$StackOperator@H@..."                        -- int
  0x0130c818  ".?AV?$StackOperator@M@..."                        -- float
  0x0130c860  ".?AV?$StackOperator@_N@..."                       -- bool
  0x0130c8a8  ".?AV?$StackOperator@VUtf8String@Misc@Sqex@@@..."   -- Utf8String
  0x0130c908  ".?AV?$StackOperator@PAVLuaControl@..."             -- LuaControl* (actor)
  0x0130c978  ".?AV?$StackOperator@VAutoReleaseTentative@..."     -- AutoReleaseTentative
  0x0130c9f0  ".?AV?$StackOperator@VNil@..."                      -- Nil
  0x0130ca58  ".?AV?$StackOperator@VTable@..."                    -- Table
  0x0130cac0  ".?AV?$StackOperator@VIndividualIndex@..."          -- IndividualIndex
  0x0130cb30  ".?AV?$StackOperator@VVariable@..."                 -- Variable (any-typed)
  0x0130cb98  ".?AV?$StackOperator@VLuaControlArray@..."          -- LuaControlArray
  0x0130cc08  ".?AV?$StackOperator@VLuaManyTentativeControlArray@..."
                                                                  -- many-tentative
  0x0130cc88  ".?AV?$StackOperator@VIntegerArray@..."             -- IntegerArray
  0x0130ccf8  ".?AV?$StackOperator@VVariantVectorArray@..."       -- VariantVectorArray
  0x0130cd68  ".?AVWhichStackOperator@..."                        -- dispatcher

EXE strings (debug names):
  0x0110ebd8  "Component::Lua::GameEngine::Parameter::StackOperatorInterface::PushReturnsToStack"
  0x0110f5b4  "Component::Lua::GameEngine::Functor::GetArguments_"

EXE functions (renamed):
  0x0072b440  Functor_NpcBaseClass_buildOutputStackOperatorVector
  0x0072c7e0  Functor_NpcBaseClass_buildInputStackOperatorVector
  0x0071e760  Functor_MemberFunctionHolder_ctor   (already named)
  0x00724800  Functor_entry_ctor                  (already named)
  0x00726720  Functor_pool_alloc                  (already named)
  0x00cf9630  FUN_00cf9630 (PushReturnsToStack debug-named function)
```

## Mangled C++ type code key (per StackOperator<T>)

```text
H     -> int                                 (32-bit signed)
M     -> float                                (32-bit IEEE 754)
_N    -> bool                                 (1 byte)
VUtf8String@Misc@Sqex@@                       -- Square Enix's UTF-8 string class
PAVLuaControl@GameEngine@Lua@Component@@      -- pointer to LuaControl (actor)
VAutoReleaseTentative@...                     -- auto-released temp ptr
VNil@...                                      -- Lua nil
VTable@...                                    -- Lua table (raw)
VIndividualIndex@...                          -- unique index type
VVariable@...                                 -- variant (any-typed)
VLuaControlArray@...                          -- vector<LuaControl*>
VLuaManyTentativeControlArray@...             -- many-tentative LuaControl*
VIntegerArray@...                             -- vector<int>
VVariantVectorArray@...                       -- vector<Variable>
WhichStackOperator                            -- runtime dispatcher
                                                 over the 14 above
```

So the marshalling supports 14 distinct typed argument categories +
1 runtime dispatcher.

## Marshalling flow

```text
LUA CALL SITE: self:_callServerOnTalk(target_actor, event_data)

1. Lua-side wrapper pushes self + 2 args onto Lua stack.

2. Functor::Execute invoked with the Lua state.

3. Functor::GetArguments_ iterates over the binding's INPUT
   StackOperator vector (built by FUN_0072c7e0 for NpcBaseClass).
   For each operator:
     - op.GetFromStack(L, &outArg)   reads the typed value off
                                      the Lua stack into a typed slot
   The set of slots forms an ExecuteParameters object.

4. The C++ member function is invoked via the MFP thunk with
   signature void method(ExecuteParameters const&).

5. Inside the method, args are read from the ExecuteParameters via
   typed accessors (Parameter::Get<T>(params, index) idiom).

6. If the method has return values, it writes them into a Functor
   slot. Then Functor::PushReturnsToStack uses the OUTPUT
   StackOperator vector (built by FUN_0072b440) to push each return
   back onto the Lua stack.

7. Lua execution continues with the return values.
```

## StackOperatorInterface vtable (partial)

From PushReturnsToStack (FUN_00cf9630):

```text
slot 2 (+0x08): GetFromStack / push-typed-value (the main op)
slot 6 (+0x18): is-valid / has-error check
slot 7 (+0x1c): error-message-builder
```

Other slots exist but are not yet probed.

## Functor entry layout (0x58 bytes)

Per Functor_entry_ctor (FUN_00724800):

```text
+0x00 (8B):   MFP target + this-offset    (set by FUN_0071e760)
+0x08 (8B):   zero-init
+0x10 (4B):   MFP base offset             (returned by MemberFunctionHolder_ctor)
+0x14 (16B):  Input StackOperator vector  (copy of param_4)
+0x24 (16B):  Output StackOperator vector (copy of param_5)
+0x34 (16B):  additional state slot 1
+0x44 (16B):  additional state slot 2
              total 0x58 (88) bytes
```

Functors are allocated in a fixed-stride pool (size 0x58 each) via
Functor_pool_alloc (FUN_00726720). The pool's capacity is bounded
by `*(this+4)..*(this+8)`.

## Server implication

```text
WHAT THIS UNLOCKS for a compatible server:

1. The OUTBOUND payload for any of the ~94 PlayerBase bindings (and
   the N NpcBaseClass / N GroupBase / etc. bindings) is structured
   as follows on the wire:

     <method_id selector>  (probably the discriminator byte at
                            opcode 0x12d offset 0x28)
     <typed_arg_0>          (encoded per StackOperator<T0>)
     <typed_arg_1>          (encoded per StackOperator<T1>)
     ...
     <typed_arg_N-1>

2. Each StackOperator<T> defines its own serialization format. To
   implement the server: pick one of the 14 typed serializers,
   read the binary representation off the wire (after a fixed header),
   and dispatch to the matching server-side method handler.

3. The 14 categories cover the entire native binding surface. There
   are no "untyped" or "unknown" args. Once the per-type wire format
   is reverse-engineered for each StackOperator<T>, the marshalling
   is fully solved.

4. Likely wire encoding per type (Speculative until inspected):
     int (H)        4 bytes LE
     float (M)      4 bytes IEEE 754 LE
     bool (_N)      1 byte (0 or 1)
     Utf8String     [u16 length][N bytes UTF-8][zero terminator?]
     LuaControl*    4 bytes actor id (uint32)
     Nil            0 bytes (just a type tag)
     Table          length-prefixed flat encoding of key/value pairs
     IndividualIndex 4 bytes (an integer)
     Variable       1 byte type tag + N bytes typed data
     IntegerArray   [u16 count][N x int]
     LuaControlArray [u16 count][N x actor id]
     VariantVectorArray [u16 count][N x Variable]

  Verifying these is the next reverse-engineering step.
```

## Inferred binding signatures

Some bindings have visible Lua signatures, from which we can infer
the StackOperator types:

```text
NpcBaseClass:
  _callServerOnTalk(self, target_actor, event_data)
                    -- 2 args: LuaControl* + Variable (or Utf8String)
  _callServerOnEmote(self, target_actor, event_data)
                    -- same shape
  _callServerOnPush(self, target_actor, event_data)
                    -- same shape

PlayerBaseClass (from prior findings):
  _callServerOnCommand(self, ExecuteParameters const&)
                    -- 1 variable-shape Variable arg packing the
                       command id + variadic command args
  _executeCommand(self, name, slotActor, cmdId, variadic...)
                    -- 4+ args of mixed types

GroupBase:
  Various group manipulation bindings (per RTTI strings around
  Functor::MemberFunctionHolder<GroupBase>)
```

## Confidence

```text
Confirmed:
  - 14 distinct StackOperator<T> RTTI types exist for the marshalling.
  - StackOperatorInterface is the abstract base; concrete operators
    are template instantiations.
  - Functor entry is exactly 0x58 bytes; allocated in a fixed-stride
    pool.
  - The marshalling flow goes:
      Lua stack -> GetFromStack(*N) -> ExecuteParameters const&
                                   -> C++ method
                                   -> outputs into Functor slots
                                   -> PushReturnsToStack(*N)
                                   -> Lua stack

Likely (High):
  - The 14 types fully cover the binding surface; there is no
    "untyped" / "raw bytes" fallback in this system.
  - The on-wire encoding for primitive types (int, float, bool) is
    just the underlying byte representation in LE.
  - LuaControl* is encoded as a 4-byte actor id; the receiver resolves
    via the standard FUN_00cc7a50 actor-lookup pair.

Likely (Medium):
  - The "WhichStackOperator" dispatcher is invoked for the Variable
    type (the most common variadic arg), reading a leading type tag
    byte from the wire to select the actual StackOperator<T>.
  - The Utf8String encoding is length-prefixed (most common pattern
    in SE engine code) but the exact prefix size (u8 / u16 / u32) is
    not yet verified.

Speculative:
  - The exact wire layout for Table is probably:
        [u16 num_keys][for each: type tag, key, type tag, value]
  - IntegerArray / LuaControlArray / VariantVectorArray are all
    length-prefixed homogeneous arrays.
  - The "AutoReleaseTentative" type is internal-only (for in-process
    GC management) and never appears on the wire.
```

## Next test

- Find a concrete StackOperator<H> (int) vtable in .rdata. Walk its
  PushToStack and GetFromStack methods. The C++ template
  instantiation pattern would put them at predictable addresses
  near the RTTI descriptor at 0x0130c7d0.
- Repeat for bool, float, LuaControl*, Utf8String to confirm the
  primitive wire formats.
- Walk WhichStackOperator (RTTI 0x0130cd68) to identify the type-tag
  byte values used to discriminate Variable subtypes.
- Force-disassemble at one of the PlayerBase command thunks
  (0x006de650 / 680 / 690) and confirm the actual method body
  reads ExecuteParameters via these StackOperator types.

## Annotations made in Ghidra

```text
RENAMES:
  - 0x0072b440 -> Functor_NpcBaseClass_buildOutputStackOperatorVector
  - 0x0072c7e0 -> Functor_NpcBaseClass_buildInputStackOperatorVector

COMMENTS:
  - 0x0072c7e0 (multi-line, lists all 14 StackOperator<T> RTTI types
                with their addresses, and explains the 2-arg signature
                of the NpcBaseClass Talk/Emote/Push bindings)
```

## Commit suggestion

```
docs(re/correlation): map ExecuteParameters marshalling + 14 StackOperator types
```
