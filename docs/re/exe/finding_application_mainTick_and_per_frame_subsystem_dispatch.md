# Finding: Application Main Tick + Per-Frame Subsystem Dispatch (Engine Architecture Capstone)

**Architectural capstone.** Pinned the engine's MAIN APPLICATION
LOOP (called from outer Win32 message loop) and the PER-FRAME
SUBSYSTEM TICK that dispatches 15+ subsystem ticks including the
spawn pipeline T0.

This finding closes a major "what's the engine's main loop?"
question that's been implicit in all prior per-tick research
(spawn pump, WorkSync flush, chat send queue, etc.).

## 1. Two-level tick architecture

```text
Win32 message loop (outer)
   ↓
Application_mainTick_perFrame_eventLoopAndSubsystems  @ 0x004da680
   ↓ (when startup gates passed)
PerFrameTick_Subsystems_widgets_zone_spawn_etc        @ 0x00578970
   ↓ (per-subsystem dispatch)
[Widget tick] [Spawn T0] [WorkSync flush] [Chat tick] ... (15+ subsystems)
```

## 2. Application_mainTick body

```text
Application_mainTick_perFrame_eventLoopAndSubsystems(this):
  
  // SHUTDOWN CHECK
  if (this+0x504 != 0): return false  // shutdown flag set
  
  // STARTUP GATES (3 deferred init steps)
  if (this+0x4a8 == 0 AND this+0x17444 != 0 AND this+0x174dc != 0):
    if (this+0x174dd == 1 AND this+0x17445 == 0):
      FUN_004b7160(this+0x17430)     // first-time post-init
    this+0x4a8 = 1                    // mark startup complete
  
  // MAIN LOOP BODY (when ready)
  if (this+0x54b == 0 AND !FUN_00575740(...)):
    iVar5 = FUN_00443e40(...)         // get current engine state
    bVar2 = (2 < iVar5 - 4U)          // ready when state in {5,6,7,...}
    
    if (bVar2):
      // Load fixedPhrase CSV (xtx subsystem)
      FUN_00c9d550("xtx/_fixedPhrase", ...)
      FUN_0056d890(...)                // setup textCommand
    
    FUN_004bbdb0(this+0x928)           // tick + other init
    
    // PROCESS PENDING EVENT QUEUE
    this+0x17820 = 1                   // set tick-in-progress flag
    
    // Walk linked list of event handlers at this+0x17804..this+0x17808
    while (head != tail):
      if (handler[+0x10] != null):
        vtable[+0x18]()                // dispatch event handler
      advance to next
    
    FUN_004cde10(this+0x950, this+0x17804)  // free processed handlers
    this+0x17820 = 0                   // clear tick-in-progress
    
    // PROCESS INPUT EVENT BUFFER
    head = this+0x1782c; tail = this+0x17828
    while (head < tail):
      uVar4 = *head                    // 32-bit packed event
      if ((uVar4 & 0xe0000000) == 0xc0000000):
        subsystem_id = (uVar4 >> 24) & 0xf
        if (subsystem_id < 3):
          FUN_00d35b30(
            &DAT_01336b60 + subsystem_id*24,  // handler table
            uVar4 & 0xffffff                  // payload (24 bits)
          )
      advance
    
    // Cleanup processed input
    _memmove_s(...)
    
    // PER-FRAME SUBSYSTEM TICK (THE BIG ONE)
    if (bVar2):
      PerFrameTick_Subsystems_widgets_zone_spawn_etc(this+0x510)
    
    // Additional subsystem ticks
    FUN_00534010(this)
    FUN_00553be0(this+0x175ac)
  
  return (this+0x504 == 0)
```

### Startup gate fields (3 deferred init steps)

```text
this+0x4a8    Startup complete flag (set after first ready frame)
this+0x504    Shutdown flag (return false when set)
this+0x17444  System ready (set during 1st-stage init)
this+0x17445  Post-startup flag
this+0x174dc  Render ready (set when graphics initialized)
this+0x174dd  Engine "first run" flag (triggers post-init at 1)
this+0x17820  Tick-in-progress flag (set during loop body)
```

### Event-packed encoding

```text
The input event buffer at this+0x1782c stores PACKED 32-bit events:

  Bit pattern    Meaning
  -----------    -------
  0xe0000000     Top 3 bits = event tag
    = 0xc0       → routed event (subsystem dispatch)
  0x0e000000     Subsystem ID (4 bits, 0-15; only 0-2 used currently)
                  → maps to DAT_01336b60 + subsystem_id * 24
  0x00ffffff     Payload (24 bits)

So each input event is a 32-bit value: 3 bits tag + 4 bits subsystem
+ 24 bits payload. Compact, fast to dispatch.

The 3 known subsystem handlers at DAT_01336b60+{0,24,48} need
follow-up to identify (likely: 0=input, 1=network, 2=gameplay).
```

## 3. PerFrameTick body

```text
PerFrameTick_Subsystems_widgets_zone_spawn_etc(this):
  
  if (this+0x3b != 0): return            // disabled flag
  
  if (FUN_00cc9890(*this) == 0):         // engine state check
    FUN_00d353f0(&local_24)              // init local context
    FUN_00cc9500(*this, &local_30)       // init context state
    
    Widget_perFrameTick_externalEntryPoint(*this, &local_2c)
    FUN_00766f00(this[2])                // widget container tick #1
    FUN_0076f6f0(this[3], &local_30)     // widget container tick #2
    FUN_007700b0(this[4])                // widget container tick #3
    FUN_0076a9c0(this[5])                // widget container tick #4
    SpawnPipeline_perFrameWrapper_dispatchesT0(this[6])  ← SPAWN PUMP
    FUN_00583440(this[7], &local_30)     // subsystem tick
    FUN_005836d0(this[8], &local_30)     // subsystem tick
    thunk_FUN_007694d0(this[9], &local_30)  // widget tick
    FUN_00770c00(this[10])               // network tick (?)
    FUN_0076dab0(this[11], &local_30)
    FUN_00765340(this[12], &local_30)
    FUN_0075d120(this[1]+0x110, &local_30)
    FUN_00764fd0(this[1]+0x114)
    vtable[+8](this[0xd])                // final pluggable tick
    
    FUN_00cc77f0(&local_30)              // cleanup context state
```

## 4. Why spawn-rate is 2-per-tick (revisited)

```text
Prior spawn finding noted: "2-per-tick" rate for spawn pipeline T1.

This finding EXPLAINS that rate:
  - SpawnPipeline T1 reads 2 entries per call from ring buffer
  - SpawnPipeline_perFrameWrapper_dispatchesT0 calls T1 ONCE per
    invocation
  - perFrameWrapper is called ONCE per frame from PerFrameTick
  - PerFrameTick is called ONCE per frame from Application_mainTick
  - Application_mainTick is called ONCE per frame from Win32 loop
  
TOTAL: 2 actor spawns per frame max.

At 60 Hz target:
  - 120 spawn/second max
  - 50-actor zone = ~25 frames = ~417ms ramp-up

At 30 Hz (low-end PC):
  - 60 spawn/second max
  - 50-actor zone = ~833ms ramp-up

THE 'FADE-IN' visible at zone enter in 1.x is this ramp.
```

## 5. Subsystem slot identification (this+N where this = subsystem container)

```text
Slot              Subsystem                                Confidence
----              ---------                                ----------
this[0]           Engine state container                   Confirmed
this[1]           Secondary state container (with +0x110)  Confirmed
this[2]           Widget tick #1 (FUN_00766f00)            Likely UI
this[3]           Widget tick #2 (FUN_0076f6f0)            Likely UI
this[4]           Widget tick #3 (FUN_007700b0)            Likely UI
this[5]           Widget tick #4 (FUN_0076a9c0)            Likely UI
this[6]           SPAWN PIPELINE (perFrameWrapper)         CONFIRMED
this[7]           Subsystem #1 (FUN_00583440)              Unknown
this[8]           Subsystem #2 (FUN_005836d0)              Unknown
this[9]           Widget thunk (thunk_FUN_007694d0)        Likely UI
this[10]          Network/zone (FUN_00770c00)              Likely
this[11]          Subsystem (FUN_0076dab0)                 Unknown
this[12]          Subsystem (FUN_00765340)                 Unknown
this[1]+0x110     Subsystem (FUN_0075d120)                 Unknown
this[1]+0x114     Subsystem (FUN_00764fd0)                 Unknown
this[0xd]         Pluggable subsystem (vtable[+8])         Polymorphic
```

15+ subsystems tick per frame. Spawn is one of many. Each subsystem
has its own per-tick rate limit.

## 6. Implications for spawn wire-side trace

```text
The spawn pipeline T0/T1 is the DRAIN side of a producer-consumer
ring buffer. Per this finding, T0 is called per-frame.

The PRODUCER (who pushes Group::PacketRequestBase entries to the
ring) is ASYNCHRONOUS from the per-frame tick:
  - Network I/O thread (or fiber) deserializes wire packets
  - Pushes PacketRequestBase instances to spawn queue
  - Per-frame tick drains them at 2/frame

This explains why the wire opcode wasn't found via the per-frame
trace. Need to trace from the WIRE INBOUND side:
  - Find Zone channel packet dispatcher (likely main inbound entry)
  - Find handler for "tagged container" opcode 0x12d
  - Find PacketRequestBase deserializer (likely uses RTTI for
    polymorphic construction)
```

## 7. Renames + comments applied

```text
0x004da680  FUN_004da680  → Application_mainTick_perFrame_eventLoopAndSubsystems
0x00578970  FUN_00578970  → PerFrameTick_Subsystems_widgets_zone_spawn_etc
0x006cdf20  FUN_006cdf20  → SpawnPipeline_perFrameWrapper_dispatchesT0
0x006c5f40  FUN_006c5f40  → SpawnPipeline_outerRing_packetTypeDispatcher_with2711tag
0x006ced30  FUN_006ced30  → GenericQueue_peekHead_sharedHelper
```

Plus decompiler comments at 0x004da680 and 0x00578970 documenting
the full body + subsystem slot layout.

## 8. Cross-references

- `finding_spawn_pipeline_typed_packet_ring_buffer_6_stage_architecture.md`
  -- the spawn pipeline this drives (now linked to per-frame tick)
- `finding_appendMessagePool_thunk_command_updater_dispatch.md`
  -- chat output (also called from per-frame ticks)
- `finding_worksync_pipeline.md` -- WorkSync flush (per-tick consumer)

## 9. Confidence

```text
Confirmed:
  - Application_mainTick is the per-frame entry point (1 caller from
    Win32 message loop)
  - PerFrameTick is called once per frame from Application_mainTick
  - PerFrameTick dispatches 15+ subsystems including spawn pipeline
  - Spawn pipeline at slot this[6] of subsystem container
  - 32-bit packed event encoding at this+0x17828 input buffer
  - Subsystem ID encoded in bits 0x0e000000 of each event
  - 3 startup gates control loop body (+0x4a8, +0x17444, +0x174dc)

Likely (High):
  - The 60 Hz target framerate translates to 120 spawn/sec max
  - The 15+ subsystem slots in PerFrameTick are static (defined at
    engine init via subsystem registration)
  - Network I/O happens off the main thread (otherwise wire
    deserialization would be in the trace here)

Likely (Medium):
  - The 3 input subsystem handlers (DAT_01336b60+{0,24,48}) are
    likely: 0=input/keyboard, 1=window events, 2=gameplay
  - this[10] (FUN_00770c00) IS the per-frame network tick (need to
    verify)
```

## 10. Next test

```text
1. Decompile FUN_00770c00 (subsystem [10]) -- if it's network tick,
   it might drain incoming packets and dispatch to type handlers
   (including PacketRequestBase)
2. Trace from ZoneClient_dispatchOutbound's INBOUND counterpart to
   find where wire packets become PacketRequestBase instances
3. Identify the 3 DAT_01336b60 subsystem event handlers
4. Walk subsystem slots this[2]-this[12] to name each one
   (15+ subsystems is a major engine architecture map)
```

## Commit suggestion

```
docs(re/exe): Application main tick + per-frame subsystem dispatch -- 2-level loop architecture; spawn at slot[6]; explains 2/frame spawn rate
```
