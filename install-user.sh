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

sha256_file() {
  local path="$1"
  local digest_line

  if command -v shasum >/dev/null 2>&1; then
    digest_line="$(shasum -a 256 "$path")" || return 2
  elif command -v sha256sum >/dev/null 2>&1; then
    digest_line="$(sha256sum "$path")" || return 2
  else
    return 2
  fi

  printf '%s\n' "${digest_line%% *}"
}

legacy_matches_known_package() {
  local path="$1"
  shift
  local actual
  local expected

  actual="$(sha256_file "$path")" || return $?
  for expected in "$@"; do
    if [[ "$actual" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

# Deactivate a package-owned legacy agent file only when its content matches a
# known shipped revision. A user-modified file is never deleted or overwritten.
migrate_legacy_agent() {
  local legacy_name="$1"
  local canonical_name="$2"
  shift 2
  local legacy_path="$TARGET_AGENTS/$legacy_name"
  local canonical_path="$TARGET_AGENTS/$canonical_name.md"
  local canonical_source="$SCRIPT_DIR/agents/$canonical_name.md"
  local match_status

  if [[ ! -e "$legacy_path" && ! -L "$legacy_path" ]]; then
    return
  fi

  # Never retire a legacy role before its replacement is verifiably in place.
  if [[ ! -f "$canonical_source" || -L "$canonical_source" || ! -f "$canonical_path" || -L "$canonical_path" ]] || ! cmp -s "$canonical_source" "$canonical_path"; then
    echo "WARNING: preserved legacy agent $legacy_path; migration skipped because a verified canonical replacement for $canonical_name is unavailable." >&2
    return
  fi

  if [[ ! -f "$legacy_path" || -L "$legacy_path" ]]; then
    echo "WARNING: preserved legacy agent $legacy_path; it is not a regular package file. Verified canonical $canonical_name is available, so no migration was performed." >&2
    return
  fi

  if legacy_matches_known_package "$legacy_path" "$@"; then
    backup_path "$legacy_path"
    rm "$legacy_path"
    echo "Deactivated legacy package agent: $legacy_path (backup retained; canonical $canonical_name installed)."
    return
  else
    match_status=$?
  fi

  if [[ "$match_status" == "2" ]]; then
    echo "WARNING: preserved legacy agent $legacy_path because package ownership could not be verified. Canonical $canonical_name was installed separately; review the legacy file manually." >&2
  else
    echo "WARNING: preserved legacy agent $legacy_path because its contents differ from known package revisions. Canonical $canonical_name was installed separately; review the legacy file manually." >&2
  fi
}

install_file() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ ! -f "$dst" || -L "$dst" ]]; then
      echo "WARNING: preserved canonical agent destination $dst; it is not a regular file. Skipping $label." >&2
      return
    fi

    if cmp -s "$src" "$dst"; then
      echo "Unchanged: $label"
      return
    fi

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

# SHA-256 allowlist for package-owned legacy files shipped in v1.2.0 through
# v1.2.2; unknown content stays user-owned and active.
migrate_legacy_agent "implementer.md" "worker" \
  "4b52a1984e91f3398bec7cc70e777542536e0dbcbea6aee809f2e88a6ebda93a"
migrate_legacy_agent "test-engineer.md" "tester" \
  "7939ad3fb7b627d14ff2c6557e9badb96cc1e86cfcaa38ccfa940559e26f955d"

if [[ "$INSTALL_GLOBAL" == true ]]; then
  if [[ -e "$TARGET_GLOBAL" || -L "$TARGET_GLOBAL" ]]; then
    if [[ ! -f "$TARGET_GLOBAL" || -L "$TARGET_GLOBAL" ]]; then
      echo "Error: $TARGET_GLOBAL is not a regular file. No global instructions were changed." >&2
      echo "Repair the path or use --no-global." >&2
      exit 1
    fi
  fi

  tmp="$(mktemp "$CLAUDE_DIR/.CLAUDE.md.tmp.XXXXXX")"
  prefix_tmp=''
  suffix_tmp=''
  cleanup_tmp() {
    if [[ -n "$tmp" ]]; then
      rm -f "$tmp"
    fi
    if [[ -n "$prefix_tmp" ]]; then
      rm -f "$prefix_tmp"
    fi
    if [[ -n "$suffix_tmp" ]]; then
      rm -f "$suffix_tmp"
    fi
  }
  trap cleanup_tmp EXIT

  # Require either no markers at all, or exactly one ordered, non-nested block.
  # Counting occurrences is not enough: END before BEGIN also counts 1:1.
  marker_info='NONE'
  if [[ -f "$TARGET_GLOBAL" ]]; then
    marker_status=0
    marker_info="$(awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
      BEGIN { state = 0; invalid = 0 }
      $0 == begin {
        if (state != 0) { invalid = 1; exit 2 }
        state = 1
        begin_line = NR
        next
      }
      $0 == end {
        if (state != 1) { invalid = 1; exit 2 }
        state = 2
        end_line = NR
        next
      }
      END {
        if (invalid || state == 1) { exit 2 }
        if (state == 0) {
          print "NONE"
        } else {
          printf "BLOCK %d %d\n", begin_line, end_line
        }
      }
    ' "$TARGET_GLOBAL")" || marker_status=$?

    if [[ "$marker_status" != "0" ]]; then
      echo "Error: $TARGET_GLOBAL contains unmatched, duplicate, or out-of-order engineering-team markers." >&2
      echo "Expected one ordered, non-nested BEGIN...END block, or no markers at all." >&2
      echo "No global instructions were changed. Repair the markers or use --no-global." >&2
      exit 1
    fi
  fi

  marker_kind="${marker_info%% *}"
  if [[ "$marker_kind" == "NONE" ]]; then
    if [[ -f "$TARGET_GLOBAL" ]]; then
      # With no markers, retain user content and normalize only trailing blank
      # lines before appending the managed block.
      awk '
        {
          if ($0 ~ /^[[:space:]]*$/) { blanks++; next }
          while (blanks > 0) { print ""; blanks-- }
          print
        }
      ' "$TARGET_GLOBAL" > "$tmp"
    fi
    if [[ -s "$tmp" ]]; then
      printf '\n' >> "$tmp"
    fi
  elif [[ "$marker_kind" == "BLOCK" ]]; then
    # Replace the managed block in place so surrounding user content keeps its
    # original position and bytes.
    marker_lines="${marker_info#BLOCK }"
    read -r begin_line end_line <<< "$marker_lines"
    prefix_tmp="$(mktemp "$CLAUDE_DIR/.CLAUDE.md.prefix.XXXXXX")"
    suffix_tmp="$(mktemp "$CLAUDE_DIR/.CLAUDE.md.suffix.XXXXXX")"
    if (( begin_line > 1 )); then
      head -n "$((begin_line - 1))" "$TARGET_GLOBAL" > "$prefix_tmp"
    else
      : > "$prefix_tmp"
    fi
    tail -n "+$((end_line + 1))" "$TARGET_GLOBAL" > "$suffix_tmp"
    cat "$prefix_tmp" > "$tmp"
  else
    echo "Error: could not classify marker state for $TARGET_GLOBAL. No global instructions were changed." >&2
    exit 1
  fi

  {
    printf '%s\n' "$BEGIN_MARKER"
    cat "$SOURCE_GLOBAL"
    printf '%s\n' "$END_MARKER"
  } >> "$tmp"

  if [[ "$marker_kind" == "BLOCK" ]]; then
    cat "$suffix_tmp" >> "$tmp"
  fi

  if [[ -f "$TARGET_GLOBAL" ]] && cmp -s "$tmp" "$TARGET_GLOBAL"; then
    echo "Unchanged: global team agreement"
  else
    if [[ -f "$TARGET_GLOBAL" ]]; then
      backup_path "$TARGET_GLOBAL"
      # Keep the existing file's permissions rather than the temp file's.
      chmod --reference="$TARGET_GLOBAL" "$tmp" 2>/dev/null \
        || chmod "$(stat -f '%Lp' "$TARGET_GLOBAL")" "$tmp"
    fi
    mv "$tmp" "$TARGET_GLOBAL"
    tmp=''
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
