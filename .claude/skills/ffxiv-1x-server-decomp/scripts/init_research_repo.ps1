$ErrorActionPreference = "Stop"

$dirs = @(
  "config",
  "docs/re/exe",
  "docs/re/lua",
  "docs/re/correlation",
  "docs/packets",
  "docs/structs",
  "docs/flows",
  "docs/server",
  "ghidra/exports",
  "ghidra/notes",
  "lua/source",
  "lua/bytecode",
  "lua/decompiled",
  "captures",
  "tools/local"
)

foreach ($d in $dirs) {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}

if (-not (Test-Path "config/project.local.yml")) {
  $skillExample1 = ".claude/skills/ffxiv-1x-server-decomp/config/project.local.example.yml"
  $skillExample2 = ".claude/skills/ffxiv-1x-server-decomp-skill-v0.3/config/project.local.example.yml"
  if (Test-Path $skillExample1) {
    Copy-Item $skillExample1 "config/project.local.yml"
  } elseif (Test-Path $skillExample2) {
    Copy-Item $skillExample2 "config/project.local.yml"
  }
}

if (-not (Test-Path ".gitignore")) {
  New-Item -ItemType File -Path ".gitignore" | Out-Null
}

function Add-GitIgnoreLine($line) {
  $content = Get-Content ".gitignore" -ErrorAction SilentlyContinue
  if ($content -notcontains $line) {
    Add-Content ".gitignore" $line
  }
}

Add-GitIgnoreLine "config/project.local.yml"
Add-GitIgnoreLine "tools/local/"
Add-GitIgnoreLine "lua/decompiled/"
Add-GitIgnoreLine "captures/raw/"
Add-GitIgnoreLine "game/"
Add-GitIgnoreLine "*.exe"
Add-GitIgnoreLine "*.dll"
Add-GitIgnoreLine "*.dat"
Add-GitIgnoreLine "*.index"
Add-GitIgnoreLine "*.sqpack"

if (-not (Test-Path "progress.yml")) {
@"
project: Meteor Reborn / FFXIV 1.x Server Research
repo_url: https://github.com/Yokimitsuro/ffxivDecomp.git
areas:
  exe:
    functions_identified: 0
    functions_documented: 0
  lua:
    files_identified: 0
    files_documented: 0
  correlation:
    links_documented: 0
  packets:
    observed: 0
    named: 0
    confirmed: 0
  server_requirements:
    documented: 0
"@ | Set-Content "progress.yml"
}

Write-Host "Research repo initialized."
Write-Host "Next: place unluac.jar at tools/local/unluac.jar or update config/project.local.yml."
