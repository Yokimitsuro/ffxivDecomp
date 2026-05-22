# Packet Research Notes

When documenting packets, always include:

```text
Opcode / command id:
Direction:
Payload length:
Header fields:
Source id:
Target id:
Session id:
Actor id:
Endian assumptions:
Read offsets:
Write offsets:
Receive path:
Send path:
Lua event/callback triggered:
State changes:
Server-side implication:
Confidence:
```

## Packet Finding Template

```md
# Packet Finding: <opcode/name>

## Summary

## Direction

Client -> Server / Server -> Client / Both

## Evidence

- 

## Layout

```c
// Confidence: Low/Medium/High/Confirmed
struct PacketXXXXMaybe {
    // fields
};
```

## EXE Behavior

## Lua Behavior / Events

## Server Requirement

## Unknowns

## Next Test
```
