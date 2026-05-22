Use the ffxiv-1x-server-decomp skill.

The repo is https://github.com/Yokimitsuro/ffxivDecomp.git.
The local game root is E:\Program Files (x86)\SquareEnix\FINAL FANTASY XIV.
unluac.jar is available at tools/local/unluac.jar.
Ghidra MCP is connected and the FFXIV 1.23b client EXE is open in Ghidra.

Goal: decompile/analyze the EXE with Ghidra and analyze/decompile Lua files to understand what the client expects from a compatible MeteorReborn server.

Start by:
1. Reading config/project.local.yml.
2. Verifying repo structure and git branch.
3. Verifying Ghidra MCP has the correct EXE loaded.
4. Locating candidate EXE targets: recv loop, packet header parser, packet dispatcher, send packet builder, Lua bridge.
5. Locating candidate Lua targets: loading, world, zone, actor, character, event, server/session related files.

Every useful finding must be written under docs/ and committed.
Do not dump large proprietary source. Produce summaries, packet notes, structs, xrefs, and server requirements.
