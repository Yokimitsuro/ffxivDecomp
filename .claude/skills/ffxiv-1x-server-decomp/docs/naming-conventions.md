# Naming Conventions

## EXE prefixes

- `net_` low-level networking
- `pkt_` packet parsing, building, dispatch
- `login_` login/lobby flow
- `world_` world handoff flow
- `zone_` zone/session flow
- `actor_` actor/entity/object logic
- `char_` character data
- `ui_` UI/loading state
- `state_` state-machine logic
- `serialize_` serialization/deserialization helpers
- `lua_` Lua bridge, native binding, event dispatch
- `crypto_` encryption/decryption/compression when lawful and relevant
- `unk_` unknown

## Lua prefixes in findings

- `lua_ui_`
- `lua_event_`
- `lua_zone_`
- `lua_actor_`
- `lua_char_`
- `lua_native_`
- `lua_loading_`

## Confidence in names

Use uncertainty unless proven:

```text
pkt_maybe_handle_0001
zone_possible_send_player_init
lua_maybe_dispatch_zone_ready
actor_maybe_create_local_player
```

Only use direct names when evidence is strong:

```text
pkt_dispatch_zone_opcode
net_send_packet
lua_dispatch_event
```

## Bad names

Avoid names that imply certainty without evidence:

```text
SendFinalZoneCompletePacket
HandleHeartbeatConfirmed
LoadEverythingCorrectly
```
