# Finding: Network Event Loop and Socket Class

Identify the client's network event loop, its socket state machine, and the
shape of the per-socket object that wraps a Winsock `SOCKET`.

## Targets

```text
FUN_00d514f0  candidate: NetIo_PollStep
FUN_00d511c0  candidate: NetIo_HandleReadySockets
FUN_00d44ae0  candidate: Socket_StateMachine_Tick
FUN_00d447e0  candidate: Socket_DoRecv_TCP    (state 4)
FUN_00d44950  candidate: Socket_DoRecvfrom    (state 5)
FUN_00d44610  candidate: Socket_DoSend_TCP    (vtable slot)
FUN_00d44690  candidate: Socket_DoRecv_inner  (vtable slot)
FUN_00d43140  candidate: Socket_recv_thin     (calls recv())
FUN_00d430d0  candidate: Socket_send_thin     (calls send())
FUN_00d57530  candidate: NetIo_SelectWait     (calls select())
FUN_00d4dc60  candidate: NetIo_PollStep_outer (calls FUN_00d514f0)
```

## Evidence

### Winsock import resolution

The binary statically links Winsock; the imports of interest were located by
xrefs to the `EXTERNAL` slots from `list_imports`:

```text
recv        EXTERNAL:00000151 -> thunk inside FUN_00d43140
send        EXTERNAL:00000152 -> thunk inside FUN_00d430d0
select      EXTERNAL:00000142 -> thunk inside FUN_00d57530
socket      EXTERNAL:00000157 -> thunk inside FUN_00d42d90
connect     EXTERNAL:00000153 -> thunk inside FUN_00d43060
WSAStartup  EXTERNAL:00000140 -> thunk inside FUN_00d432a0
```

`FUN_00d43140` and `FUN_00d430d0` are tiny shims: they pull a `SOCKET` from
`*(SOCKET*)(this + 4)`, call `recv` / `send`, and translate `WSAEWOULDBLOCK`
(`0x2733` = 10035) into `-2` / `0` respectively. On other errors they log
`"Error: recv(),"` / `"Error: send(),"` to a stream object at
`DAT_0137b2f0`.

### Socket vtable confirmed at 0x01113340

`FUN_00d44690` (Socket recv inner) and `FUN_00d44610` (Socket send inner)
are referenced only from data words at `0x0111334c` and `0x01113350`. Two
adjacent vtable slots referencing the recv/send inner functions, with no
code xrefs, are diagnostic of a C++ vtable for a Socket class. Calls into
the recv/send vtable slots use `(**(code **)(*this + 0xc))(…)` style — i.e.
a virtual `OnError`/`OnClose` is at vtable slot `+0x0c`.

### Socket struct layout (High confidence on annotated offsets)

Derived from `FUN_00d447e0`, `FUN_00d44950`, `FUN_00d44690`, `FUN_00d44610`,
`FUN_00d43140`, `FUN_00d430d0`. Offsets are byte offsets within the Socket
object pointed to by `this`:

```text
+0x00  vtable                              (slot +0x0c = on_error/on_close)
+0x04  SOCKET handle                       (passed to recv/send/recvfrom)
+0x08  blocking?/flag                      (read as param_1[2] in 0d447e0)
+0x38  on_recv_tcp(ctx, buf, len)          (param_1[0x0e])
+0x3c  on_recvfrom_udp(ctx, buf, len, sa*) (param_1[0x0f])
+0x58  recv_call_count                     (param_1[0x16])
+0x5c  send_call_count                     (param_1[0x17])
+0x60  bytes_recv_total                    (param_1[0x18])
+0x64  bytes_send_total                    (this+100)
+0x68  bytes_send_rolling                  (this+0x68)
+0x6c  bytes_recv_rolling                  (param_1[0x1b])
+0x70  last_send_size                      (this+0x70)
+0x74  last_recv_size                      (param_1[0x1d])
+0x80  last_recv_time_t64                  (param_1[0x20])
+0x88  last_send_time_t64                  (this+0x88)
+0x90  on_recv_ctx                         (param_1[0x24])
+0x98  state                               (atomic, InterlockedExchangeAdd)
+0x9c  recv_buffer_size                    (param_1[0x27], passed to recv())
```

State values seen in `FUN_00d44ae0` and `FUN_00d511c0`:

```text
2  LISTENING_OR_ACCEPTING (state 2 + readable -> FUN_00d44370 accept-path)
3  CONNECTING              (state 3 + writable/exception -> FUN_00d438e0)
4  CONNECTED_TCP           (state 4 + readable -> FUN_00d447e0 TCP recv)
5  CONNECTED_UDP           (state 5 + readable -> FUN_00d44950 recvfrom)
```

`FUN_00d511c0` also routes state-change callbacks via `FUN_00d57460`
(connect/disconnect notification with codes 0/1/2).

### Event loop shape

`FUN_00d514f0`:

```c
iVar1 = FUN_00d57530(this);          // select()
if (iVar1 == 0)        { FUN_00d51400(this); ... }   // timeout
else if (iVar1 < 0)    { /* WSAGetLastError check */ FUN_00d51310(this); }
else                   { FUN_00d511c0(this); }       // sockets ready
```

`FUN_00d511c0` walks a contiguous vector of "ready" descriptors. Each entry
is 12 bytes:

```text
+0  socket_index/non-null marker
+4  readable flag (char)
+5  writable flag (char)
+6  exceptional flag (char)
+7  skip flag (char)
+8  Socket*
```

For each non-skipped entry, it loads `state` (`Socket+0x98`), reads the
readable/writable/exceptional flags, and calls
`FUN_00d44ae0(socket, r, w, x)` — the per-socket state-machine tick — then
dispatches state-transition callbacks via `FUN_00d57460` on connect/disconnect
boundaries.

### Where the buffer payload first appears

In `FUN_00d447e0` (the TCP recv state-4 worker):

```text
1. allocate buffer of size (recv_buffer_size + 1) via FUN_00d40b90
2. recv() into it via FUN_00d43140
3. update stats and last_recv_time
4. if on_recv_ctx (+0x90) != null and on_recv_tcp (+0x38) != null:
       (*on_recv_tcp)(on_recv_ctx, buf, len)
5. free buffer
```

So the entry point into client packet *parsing* is whatever function pointer
gets installed at `Socket+0x38`. The buffer at this point is raw TCP bytes
of length `len`; the parser is responsible for framing.

`FUN_00d44950` (state-5 UDP variant) is identical in shape but uses
`recvfrom`-style (`FUN_00d42b80`, takes a `sockaddr*`) and dispatches via
the `+0x3c` callback that also receives the `sockaddr`.

## Assessment

```text
Confirmed:
  - Client links Winsock and implements its own select()-driven I/O loop
    around a Socket wrapper class with a vtable.
  - Distinct TCP and UDP recv paths exist on the same Socket class (state 4
    vs state 5).
  - Bytes arrive to user code via a per-socket callback at offset +0x38;
    parsing happens beyond that callback, not inside the recv worker.
  - WSAEWOULDBLOCK is normalised to "no data" rather than treated as error.

Likely (High):
  - FUN_00d514f0 is one tick of the I/O thread loop; FUN_00d4dc60 is the
    thin outer wrapper that null-checks the manager pointer.
  - FUN_00d44ae0 is the per-socket state machine and the canonical place to
    map state-id -> behaviour.
  - vtable at 0x01113340-0x0111335x is the concrete Socket class vtable;
    on_error/on_close lives at vtable slot +0x0c.

Likely (Medium):
  - State 2 = listening (accept-side), state 3 = connecting (outbound
    pending), state 4 = connected TCP, state 5 = connected UDP. Strong
    structural fit but not yet cross-checked against constructor/string
    evidence.

Speculative:
  - That FUN_00d57530 is the only select() callsite the client uses; only
    one indirect-call xref was seen so far.

Next test:
  - Identify what installs the function pointer at Socket+0x38. The
    setter exposes the packet parser entry point and the per-connection
    user context, which in turn lets us name the lobby vs game/zone
    parsers.
  - Decompile FUN_00d44370 (state-2 accept) and FUN_00d438e0 (state-3
    connect-complete) to verify the state semantics above.
  - Walk callers of FUN_00d4dc60 upward to locate the I/O thread entry.

Commit suggestion:
  docs(re/exe): document client network event loop and Socket class
```

## Server implication

- A compatible server must accept ordinary blocking-style TCP/UDP from the
  client; the client is a non-blocking `select()` driver and treats
  `WSAEWOULDBLOCK` as "nothing to read".
- The client invokes its parser on **raw TCP byte chunks of arbitrary
  length** equal to whatever `recv()` returns (capped at
  `Socket+0x9c`). The parser, not the recv worker, is what enforces packet
  framing — so a compatible server should not assume that every `send()`
  on its side maps 1:1 to a parser invocation on the client side. Frames
  may arrive split or coalesced.
- Disconnect handling on the client is driven by `recv() <= 0` plus
  vtable slot `+0x0c`; the server should be able to close the socket
  cleanly and expect the client to release state without ceremony.
- No evidence yet of TLS or a custom transport handshake at this layer —
  the bytes the client hands to its parser appear to be the actual game
  protocol frames.
