#!/usr/bin/env bash
# Render an .ansi file to .png using vhs
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: $0 <file.ansi> [file2.ansi ...]"
  exit 1
fi

for input in "$@"; do
  if [ ! -f "$input" ]; then
    echo "File not found: $input"
    exit 1
  fi

  abs_input="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
  abs_output="${abs_input%.ansi}.png"
  tape=$(mktemp /tmp/groschen-render.XXXXXXXX.tape)

  cat > "$tape" <<EOF
Set Shell "bash"
Set Width 80
Set Height 40
Set FontSize 16
Set Padding 0
Set TypingSpeed 0
Type "cat '${abs_input}'; sleep 1"
Enter
Sleep 2s
Screenshot "${abs_output}"
EOF

  echo "Rendering $(basename "$input") -> $(basename "$abs_output")"
  vhs "$tape"
  rm -f "$tape"
done
