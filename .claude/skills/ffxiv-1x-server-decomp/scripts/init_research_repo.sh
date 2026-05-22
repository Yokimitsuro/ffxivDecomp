#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  config \
  docs/re/exe \
  docs/re/lua \
  docs/re/correlation \
  docs/packets \
  docs/structs \
  docs/flows \
  docs/server \
  ghidra/exports \
  ghidra/notes \
  lua/source \
  lua/bytecode \
  lua/decompiled \
  captures \
  tools/local

if [ ! -f config/project.local.yml ]; then
  if [ -f .claude/skills/ffxiv-1x-server-decomp/config/project.local.example.yml ]; then
    cp .claude/skills/ffxiv-1x-server-decomp/config/project.local.example.yml config/project.local.yml
  elif [ -f .claude/skills/ffxiv-1x-server-decomp-skill-v0.3/config/project.local.example.yml ]; then
    cp .claude/skills/ffxiv-1x-server-decomp-skill-v0.3/config/project.local.example.yml config/project.local.yml
  fi
fi

if [ ! -f .gitignore ]; then
  touch .gitignore
fi

append_ignore() {
  local line="$1"
  grep -qxF "$line" .gitignore || echo "$line" >> .gitignore
}

append_ignore "config/project.local.yml"
append_ignore "tools/local/"
append_ignore "lua/decompiled/"
append_ignore "captures/raw/"
append_ignore "game/"
append_ignore "*.exe"
append_ignore "*.dll"
append_ignore "*.dat"
append_ignore "*.index"
append_ignore "*.sqpack"

if [ ! -f progress.yml ]; then
  cat > progress.yml <<'PROGRESS'
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
PROGRESS
fi

echo "Research repo initialized."
echo "Next: place unluac.jar at tools/local/unluac.jar or update config/project.local.yml."
