param(
  [string]$RepoUrl = "https://github.com/Yokimitsuro/ffxivDecomp.git",
  [string]$GameRoot = "E:\Program Files (x86)\SquareEnix\FINAL FANTASY XIV",
  [string]$UnluacJar = "tools/local/unluac.jar",
  [string]$OutFile = "config/project.local.yml"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile -Parent) | Out-Null

@"
repo:
  url: "$RepoUrl"
  local_path: "."
  expected_branch: "main"

game:
  root: '$GameRoot'
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
  unluac_jar: "$UnluacJar"
  java_command: "java"

output:
  exe_findings: "docs/re/exe"
  lua_findings: "docs/re/lua"
  correlation_findings: "docs/re/correlation"
  packet_docs: "docs/packets"
  struct_docs: "docs/structs"
  flow_docs: "docs/flows"
  server_requirements: "docs/server"
"@ | Set-Content -Encoding UTF8 $OutFile

Write-Host "Created $OutFile"
Write-Host "Do not commit this file."
