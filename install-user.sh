#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET_AGENTS="$CLAUDE_DIR/agents"
TARGET_GLOBAL="$CLAUDE_DIR/CLAUDE.md"
SOURCE_GLOBAL="$SCRIPT_DIR/global/CLAUDE.md"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
INSTALL_GLOBAL=true
BEGIN_MARKER='<!-- BEGIN CLAUDE ENGINEERING TEAM -->'
END_MARKER='<!-- END CLAUDE ENGINEERING TEAM -->'

usage() {
  cat <<'USAGE'
Usage: ./install-user.sh [--no-global]

  --no-global  Install the custom agent files without modifying the global
               ~/.claude/CLAUDE.md operating agreement.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --no-global) INSTALL_GLOBAL=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

backup_path() {
  local path="$1"
  cp "$path" "$path.bak.$STAMP"
  echo "Backed up: $path -> $path.bak.$STAMP"
}

install_file() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [[ -e "$dst" ]] && cmp -s "$src" "$dst"; then
    echo "Unchanged: $label"
    return
  fi

  if [[ -e "$dst" ]]; then
    backup_path "$dst"
  fi
  cp "$src" "$dst"
  echo "Installed: $label"
}

mkdir -p "$TARGET_AGENTS"

for src in "$SCRIPT_DIR"/agents/*.md; do
  name="$(basename "$src")"
  install_file "$src" "$TARGET_AGENTS/$name" "agent $name"
done

if [[ "$INSTALL_GLOBAL" == true ]]; then
  tmp="$(mktemp "$CLAUDE_DIR/.CLAUDE.md.tmp.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT

  begin_count=0
  end_count=0
  if [[ -f "$TARGET_GLOBAL" ]]; then
    begin_count="$(grep -Fxc "$BEGIN_MARKER" "$TARGET_GLOBAL" || true)"
    end_count="$(grep -Fxc "$END_MARKER" "$TARGET_GLOBAL" || true)"
  fi

  if ! { [[ "$begin_count" == "0" && "$end_count" == "0" ]] || [[ "$begin_count" == "1" && "$end_count" == "1" ]]; }; then
    echo "Error: $TARGET_GLOBAL contains unmatched or duplicate engineering-team markers." >&2
    echo "No global instructions were changed. Repair the markers or use --no-global." >&2
    exit 1
  fi

  if [[ -f "$TARGET_GLOBAL" ]]; then
    # Remove the previous managed block, preserve all unrelated content, and
    # normalize only trailing blank lines so repeated installs are idempotent.
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
      $0 == begin { skip = 1; next }
      $0 == end   { skip = 0; next }
      !skip {
        if ($0 ~ /^[[:space:]]*$/) { blanks++; next }
        while (blanks > 0) { print ""; blanks-- }
        print
      }
    ' "$TARGET_GLOBAL" > "$tmp"
  fi

  if [[ -s "$tmp" ]]; then
    printf '\n' >> "$tmp"
  fi

  {
    printf '%s\n' "$BEGIN_MARKER"
    cat "$SOURCE_GLOBAL"
    printf '%s\n' "$END_MARKER"
  } >> "$tmp"

  if [[ -e "$TARGET_GLOBAL" ]] && cmp -s "$tmp" "$TARGET_GLOBAL"; then
    echo "Unchanged: global team agreement"
  else
    if [[ -e "$TARGET_GLOBAL" ]]; then
      backup_path "$TARGET_GLOBAL"
      # Keep the existing file's permissions rather than the temp file's.
      chmod --reference="$TARGET_GLOBAL" "$tmp" 2>/dev/null \
        || chmod "$(stat -f '%Lp' "$TARGET_GLOBAL")" "$tmp"
    fi
    mv "$tmp" "$TARGET_GLOBAL"
    trap - EXIT
    echo "Installed/updated: $TARGET_GLOBAL"
  fi
fi

echo
echo "Claude home: $CLAUDE_DIR"
echo "Agents:      $TARGET_AGENTS"
if [[ "$INSTALL_GLOBAL" == true ]]; then
  echo "Global:      $TARGET_GLOBAL"
fi
echo "Project:     copy $SCRIPT_DIR/project/CLAUDE.md.template into each repo as CLAUDE.md and fill in real project facts."
echo "Start a new Claude Code session so the agents and global instructions load."
