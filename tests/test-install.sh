#!/usr/bin/env bash
# Behavioral tests for install-user.sh.
# Run from anywhere: ./tests/test-install.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/install-user.sh"
TMP_ROOT="$(mktemp -d)"
RUN_NUMBER=0
LAST_STDOUT=''
LAST_STDERR=''

# The single revision that shipped agents/implementer.md and
# agents/test-engineer.md unchanged across v1.2.0 through v1.2.2.
LEGACY_REVISION='1137714'

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "  ok - $*"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

assert_file() {
  [[ -f "$1" && ! -L "$1" ]] || fail "expected regular file: $1"
}

assert_absent() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "expected absent path: $1"
}

assert_contains() {
  grep -qF -- "$2" "$1" || fail "expected $1 to contain: $2"
}

assert_not_contains() {
  grep -qF -- "$2" "$1" && fail "expected $1 NOT to contain: $2"
  return 0
}

assert_same_file() {
  cmp -s "$1" "$2" || fail "expected identical files: $1 vs $2"
}

assert_differs() {
  cmp -s "$1" "$2" && fail "expected different files: $1 vs $2"
  return 0
}

backup_count() {
  find "$1" -maxdepth 1 -name '*.bak.*' | wc -l | tr -d ' '
}

run_install() {
  local home="$1"
  local label="$2"
  shift 2
  RUN_NUMBER=$((RUN_NUMBER + 1))
  LAST_STDOUT="$TMP_ROOT/$RUN_NUMBER-$label.stdout"
  LAST_STDERR="$TMP_ROOT/$RUN_NUMBER-$label.stderr"
  if ! CLAUDE_CONFIG_DIR="$home" "$INSTALLER" "$@" >"$LAST_STDOUT" 2>"$LAST_STDERR"; then
    echo "--- stdout ---"; cat "$LAST_STDOUT"
    echo "--- stderr ---"; cat "$LAST_STDERR"
    fail "installer failed: $label"
  fi
}

run_install_expect_failure() {
  local home="$1"
  local label="$2"
  shift 2
  RUN_NUMBER=$((RUN_NUMBER + 1))
  LAST_STDOUT="$TMP_ROOT/$RUN_NUMBER-$label.stdout"
  LAST_STDERR="$TMP_ROOT/$RUN_NUMBER-$label.stderr"
  if CLAUDE_CONFIG_DIR="$home" "$INSTALLER" "$@" >"$LAST_STDOUT" 2>"$LAST_STDERR"; then
    fail "installer unexpectedly succeeded: $label"
  fi
}

write_legacy_fixture() {
  local legacy="$1"
  local destination="$2"
  git -C "$ROOT_DIR" show "$LEGACY_REVISION:agents/$legacy" > "$destination" \
    || fail "cannot load legacy fixture agents/$legacy from repository history"
}

CANONICAL_ROLES=(architect debugger explorer git-operator reviewer tester worker)
BEGIN_MARKER='<!-- BEGIN CLAUDE ENGINEERING TEAM -->'
END_MARKER='<!-- END CLAUDE ENGINEERING TEAM -->'

echo "Checking syntax, role contracts, and bounded legacy names..."

bash -n "$INSTALLER" || fail "install-user.sh has a syntax error"

# The package ships exactly the seven canonical roles, and every file's
# frontmatter name matches its filename (Claude Code resolves agents by name).
shipped="$(cd "$ROOT_DIR/agents" && ls *.md | sed 's/\.md$//' | sort | tr '\n' ' ')"
[[ "$shipped" == "${CANONICAL_ROLES[*]} " ]] \
  || fail "shipped roles [$shipped] != canonical [${CANONICAL_ROLES[*]}]"

for role in "${CANONICAL_ROLES[@]}"; do
  declared="$(awk -F': *' '/^name: /{print $2; exit}' "$ROOT_DIR/agents/$role.md")"
  [[ "$declared" == "$role" ]] || fail "agents/$role.md declares name: $declared"
done

# No retired role name may survive anywhere in the shipped contract.
if grep -rniE '\bimplementer\b|\btest[-_]engineer\b' \
    "$ROOT_DIR/agents" "$ROOT_DIR/global" "$ROOT_DIR/sample-prompts.md" >/dev/null; then
  fail "retired role names still present in shipped contract files"
fi

# Legacy migration must target an explicit, bounded set of filenames so a future
# edit cannot turn it into a generic delete.
migrated="$(grep -oE '^migrate_legacy_agent "[^"]+"' "$INSTALLER" \
  | sed 's/.*"\(.*\)"/\1/' | sort | tr '\n' ' ')"
[[ "$migrated" == "implementer.md test-engineer.md " ]] \
  || fail "unexpected legacy migration targets: [$migrated]"

# The allowlisted digests must match what the repository actually shipped.
for pair in "implementer.md" "test-engineer.md"; do
  fixture="$TMP_ROOT/fixture-$pair"
  write_legacy_fixture "$pair" "$fixture"
  digest="$(sha256_file "$fixture")"
  grep -qF "$digest" "$INSTALLER" \
    || fail "installer allowlist is missing the shipped digest for $pair"
done

pass "seven canonical roles, matching frontmatter names, bounded legacy targets, correct digests"

echo "Checking fresh install..."

HOME1="$TMP_ROOT/home1"
mkdir -p "$HOME1"
run_install "$HOME1" fresh

for role in "${CANONICAL_ROLES[@]}"; do
  assert_file "$HOME1/agents/$role.md"
  assert_same_file "$ROOT_DIR/agents/$role.md" "$HOME1/agents/$role.md"
done
installed_count="$(find "$HOME1/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
[[ "$installed_count" == "7" ]] || fail "expected 7 agent files, found $installed_count"
assert_file "$HOME1/CLAUDE.md"
assert_contains "$HOME1/CLAUDE.md" "$BEGIN_MARKER"
assert_contains "$HOME1/CLAUDE.md" "$END_MARKER"
[[ "$(grep -Fxc "$BEGIN_MARKER" "$HOME1/CLAUDE.md")" == "1" ]] || fail "expected exactly one BEGIN marker"
[[ "$(backup_count "$HOME1")" == "0" ]] || fail "fresh install should not create backups"

pass "fresh install creates exactly seven roles and one managed block"

echo "Checking reinstall idempotence..."

cp "$HOME1/CLAUDE.md" "$TMP_ROOT/home1-global.snapshot"
run_install "$HOME1" reinstall
assert_same_file "$TMP_ROOT/home1-global.snapshot" "$HOME1/CLAUDE.md"
assert_contains "$LAST_STDOUT" "Unchanged: global team agreement"
[[ "$(backup_count "$HOME1")" == "0" ]] || fail "idempotent reinstall should not create backups"

pass "reinstall is byte-identical and creates no backups"

echo "Checking in-place block replacement preserves surrounding content..."

HOME2="$TMP_ROOT/home2"
mkdir -p "$HOME2"
# Prefix, an outdated managed block, and a suffix with no trailing newline.
{
  printf '# My global preferences\n'
  printf 'Always answer in Chinese.\n'
  printf '\n'
  printf '%s\n' "$BEGIN_MARKER"
  printf 'stale managed content\n'
  printf '%s\n' "$END_MARKER"
  printf '\n'
  printf '# Notes I keep after the contract\n'
  printf 'This must stay put.'
} > "$HOME2/CLAUDE.md"

head -n 3 "$HOME2/CLAUDE.md" > "$TMP_ROOT/expected-prefix"
tail -n +7 "$HOME2/CLAUDE.md" > "$TMP_ROOT/expected-suffix"

run_install "$HOME2" inplace

begin_line="$(grep -Fxn "$BEGIN_MARKER" "$HOME2/CLAUDE.md" | cut -d: -f1)"
end_line="$(grep -Fxn "$END_MARKER" "$HOME2/CLAUDE.md" | cut -d: -f1)"
head -n "$((begin_line - 1))" "$HOME2/CLAUDE.md" > "$TMP_ROOT/actual-prefix"
tail -n "+$((end_line + 1))" "$HOME2/CLAUDE.md" > "$TMP_ROOT/actual-suffix"

assert_same_file "$TMP_ROOT/expected-prefix" "$TMP_ROOT/actual-prefix"
assert_same_file "$TMP_ROOT/expected-suffix" "$TMP_ROOT/actual-suffix"
assert_not_contains "$HOME2/CLAUDE.md" 'stale managed content'
# The suffix must remain after the block, not be hoisted above it.
[[ "$(grep -Fxn 'This must stay put.' "$HOME2/CLAUDE.md" | cut -d: -f1)" -gt "$end_line" ]] \
  || fail "suffix content was moved above the managed block"

cp "$HOME2/CLAUDE.md" "$TMP_ROOT/home2.snapshot"
run_install "$HOME2" inplace-again
assert_same_file "$TMP_ROOT/home2.snapshot" "$HOME2/CLAUDE.md"

pass "managed block is replaced in place; prefix and suffix bytes survive, including a suffix with no final newline"

echo "Checking malformed marker layouts fail closed..."

malformed_case() {
  local label="$1"
  local body="$2"
  local home="$TMP_ROOT/bad-$label"
  mkdir -p "$home"
  printf '%s' "$body" > "$home/CLAUDE.md"
  cp "$home/CLAUDE.md" "$TMP_ROOT/bad-$label.snapshot"
  run_install_expect_failure "$home" "$label"
  assert_same_file "$TMP_ROOT/bad-$label.snapshot" "$home/CLAUDE.md"
  assert_contains "$LAST_STDERR" 'No global instructions were changed.'
  # Agents still install; only the global step refuses.
  assert_file "$home/agents/worker.md"
}

malformed_case "reversed" "$END_MARKER
$BEGIN_MARKER
# Important notes that must not vanish.
"
malformed_case "duplicate-begin" "$BEGIN_MARKER
a
$BEGIN_MARKER
b
$END_MARKER
"
malformed_case "unterminated" "$BEGIN_MARKER
a
"
malformed_case "orphan-end" "text
$END_MARKER
more text
"

for label in reversed duplicate-begin unterminated orphan-end; do
  pass "malformed layout '$label' fails closed and preserves the file"
done
assert_contains "$TMP_ROOT/bad-reversed/CLAUDE.md" 'Important notes that must not vanish.'
pass "user content survives the reversed-marker case"

echo "Checking --no-global boundary..."

HOME3="$TMP_ROOT/home3"
mkdir -p "$HOME3"
printf 'untouched global\n' > "$HOME3/CLAUDE.md"
run_install "$HOME3" no-global --no-global
assert_file "$HOME3/agents/tester.md"
[[ "$(cat "$HOME3/CLAUDE.md")" == "untouched global" ]] || fail "--no-global modified CLAUDE.md"
assert_not_contains "$HOME3/CLAUDE.md" "$BEGIN_MARKER"

pass "--no-global installs agents and leaves the global file untouched"

echo "Checking legacy migration of package-owned files..."

HOME4="$TMP_ROOT/home4"
mkdir -p "$HOME4/agents"
write_legacy_fixture "implementer.md" "$HOME4/agents/implementer.md"
write_legacy_fixture "test-engineer.md" "$HOME4/agents/test-engineer.md"
printf -- '---\nname: my-own\ndescription: mine\n---\nkeep me\n' > "$HOME4/agents/my-own.md"
cp "$HOME4/agents/my-own.md" "$TMP_ROOT/my-own.snapshot"

run_install "$HOME4" migrate

assert_absent "$HOME4/agents/implementer.md"
assert_absent "$HOME4/agents/test-engineer.md"
assert_file "$HOME4/agents/worker.md"
assert_file "$HOME4/agents/tester.md"
assert_same_file "$TMP_ROOT/my-own.snapshot" "$HOME4/agents/my-own.md"
[[ "$(find "$HOME4/agents" -maxdepth 1 -name 'implementer.md.bak.*' | wc -l | tr -d ' ')" == "1" ]] \
  || fail "expected a backup of the migrated implementer.md"
[[ "$(find "$HOME4/agents" -maxdepth 1 -name 'test-engineer.md.bak.*' | wc -l | tr -d ' ')" == "1" ]] \
  || fail "expected a backup of the migrated test-engineer.md"
assert_contains "$LAST_STDOUT" 'Deactivated legacy package agent'

# Re-running must be a no-op, not a second migration.
run_install "$HOME4" migrate-again
assert_not_contains "$LAST_STDOUT" 'Deactivated legacy package agent'

pass "exact package-owned legacy files are backed up, deactivated, and unrelated agents are untouched"

echo "Checking modified and nonregular legacy files are preserved..."

HOME5="$TMP_ROOT/home5"
mkdir -p "$HOME5/agents"
write_legacy_fixture "implementer.md" "$HOME5/agents/implementer.md"
printf '\nMy own extra rule.\n' >> "$HOME5/agents/implementer.md"
cp "$HOME5/agents/implementer.md" "$TMP_ROOT/modified-legacy.snapshot"
printf 'elsewhere\n' > "$TMP_ROOT/link-target.md"
ln -s "$TMP_ROOT/link-target.md" "$HOME5/agents/test-engineer.md"

run_install "$HOME5" preserve

assert_same_file "$TMP_ROOT/modified-legacy.snapshot" "$HOME5/agents/implementer.md"
assert_contains "$LAST_STDERR" 'differ from known package revisions'
[[ -L "$HOME5/agents/test-engineer.md" ]] || fail "symlinked legacy file should be preserved as-is"
assert_contains "$LAST_STDERR" 'not a regular package file'
[[ "$(cat "$TMP_ROOT/link-target.md")" == "elsewhere" ]] || fail "symlink target was written through"

pass "modified and nonregular legacy files are preserved with warnings"

echo "Checking migration waits for a verified canonical replacement..."

HOME6="$TMP_ROOT/home6"
mkdir -p "$HOME6/agents"
write_legacy_fixture "implementer.md" "$HOME6/agents/implementer.md"
printf 'not the canonical worker\n' > "$TMP_ROOT/worker-decoy.md"
ln -s "$TMP_ROOT/worker-decoy.md" "$HOME6/agents/worker.md"

run_install "$HOME6" canonical-unavailable

assert_file "$HOME6/agents/implementer.md"
assert_contains "$LAST_STDERR" 'verified canonical replacement for worker is unavailable'
assert_contains "$LAST_STDERR" 'not a regular file. Skipping agent worker.md'
[[ "$(cat "$TMP_ROOT/worker-decoy.md")" == "not the canonical worker" ]] \
  || fail "nonregular canonical destination was written through"

pass "legacy file survives when the canonical replacement could not be installed"

echo
echo "All installer tests passed."
