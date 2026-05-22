#!/usr/bin/env bash
set -euo pipefail

INPUT_DIR="${1:-lua/bytecode}"
OUTPUT_DIR="${2:-lua/decompiled}"
UNLUAC_JAR="${3:-tools/local/unluac.jar}"

if [ ! -f "$UNLUAC_JAR" ]; then
  echo "unluac.jar not found: $UNLUAC_JAR" >&2
  exit 1
fi

if [ ! -d "$INPUT_DIR" ]; then
  echo "Input directory not found: $INPUT_DIR" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

find "$INPUT_DIR" -type f \( -name '*.luac' -o -name '*.lub' \) | while read -r file; do
  rel="${file#$INPUT_DIR/}"
  out="$OUTPUT_DIR/${rel%.*}.lua"
  mkdir -p "$(dirname "$out")"
  echo "Decompiling $file -> $out"
  java -jar "$UNLUAC_JAR" "$file" > "$out"
done
