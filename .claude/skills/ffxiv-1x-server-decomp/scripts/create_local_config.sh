#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-https://github.com/Yokimitsuro/ffxivDecomp.git}"
GAME_ROOT="${2:-E:\\Program Files (x86)\\SquareEnix\\FINAL FANTASY XIV}"
UNLUAC_JAR="${3:-tools/local/unluac.jar}"
OUT_FILE="${4:-config/project.local.yml}"

mkdir -p "$(dirname "$OUT_FILE")"
cat > "$OUT_FILE" <<YAML
repo:
  url: "$REPO_URL"
  local_path: "."
  expected_branch: "main"

game:
  root: '$GAME_ROOT'
  exe_search_patterns:
    - "*.exe"
  lua_search_patterns:
    - "*.lua"
    - "*.luac"
    - "*.lub"
  extracted_lua_input:
    - "lua/source"
    - "lua/bytecode"
  decompiled_lua_output: "lua/decompiled"

ghidra:
  expected_program_name: null
  expected_architecture: null
  exports_dir: "ghidra/exports"

tools:
  unluac_jar: "$UNLUAC_JAR"
  java_command: "java"

output:
  exe_findings: "docs/re/exe"
  lua_findings: "docs/re/lua"
  correlation_findings: "docs/re/correlation"
  packet_docs: "docs/packets"
  struct_docs: "docs/structs"
  flow_docs: "docs/flows"
  server_requirements: "docs/server"
YAML

echo "Created $OUT_FILE"
echo "Do not commit this file."
