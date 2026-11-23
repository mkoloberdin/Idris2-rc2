#!/usr/bin/env bash
# One-shot verification for tools/idris2-browser's indexer: builds it (plain
# Chez backend, it links idris2api), installs the fixture package with
# --install-with-src into a prefix under build/, indexes it and compares the
# index with the expected files under expected/.
#
# - The fixture is found through IDRIS2_PACKAGE_PATH while --prefix points
#   at an empty prefix, so only the fixture (and a package of another TTC
#   version, `stale-0.1.0`) is indexed, and the environment-variable path is
#   what finds it.
# - Every TTC gets a fixed mtime, so the mtimes in the index are fixed too.
#   Absolute paths, the directory hashes in keys, TTC sizes and the update
#   time are masked before the comparison.
# - Second run: one TTC is touched, so only that module is re-read.
# - Third run: env.json names another indexer version, so every module is
#   re-read.
# - Fourth run: a live process holds the lock, so the run exits with 2.
# - Then the browser (built with rc2) draws screens of that index into text
#   (`--dump`), compared with expected/screens/.
# - Fifth run: a module's TTC is removed, so its file goes and the summary
#   is written again without it.
# - Sixth run: a module file is cut short and the summary is missing, as
#   after a stopped run: the module is read again and the summary rebuilt.
# - Seventh run: a lock whose process is gone is taken over and released.
#
# Usage: ./verify.sh            check
#        ./verify.sh --accept   rewrite expected/ from this run

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$(dirname "$TESTS_DIR")"
REPO_ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
BUILD="$TESTS_DIR/build"
EXPECTED="$TESTS_DIR/expected"
ACCEPT="${1:-}"

fail() { echo "FAIL  $1"; exit 1; }

source "$REPO_ROOT/env.sh"

echo "=== Build idris2-browser-index ==="
(cd "$TOOL_DIR" && idris2 --build index.ipkg)
INDEXER="$TOOL_DIR/build/index/exec/idris2-browser-index"
[[ -x "$INDEXER" ]] || fail "build did not produce $INDEXER"

rm -rf "$BUILD"
mkdir -p "$BUILD/empty" "$BUILD/prefix"
SYSTEM_PKGS="$(idris2 --prefix)/idris2-0.8.0"
PKGS="$BUILD/prefix/idris2-0.8.0"

echo "=== Install the fixture ==="
cp -r "$TESTS_DIR/fixture" "$BUILD/fixture"
(cd "$BUILD/fixture" &&
  IDRIS2_PREFIX="$BUILD/prefix" IDRIS2_PACKAGE_PATH="$SYSTEM_PKGS" \
    idris2 --install-with-src fixture.ipkg >/dev/null)
mkdir -p "$PKGS/stale-0.1.0/2020010100"
find "$PKGS" -name '*.ttc' -exec touch -d '2020-01-01T00:00:00Z' {} +

INDEX="$BUILD/index"
run_indexer() {
  IDRIS2_PACKAGE_PATH="$PKGS" "$INDEXER" --prefix "$BUILD/empty" --index-dir "$INDEX" "$@"
}

mask() {
  sed -E \
    -e "s#$BUILD#@BUILD@#g" \
    -e 's#(-0\.1\.0)-[0-9a-f]{8}#\1-@HASH@#g' \
    -e 's#("(bytes|ttcBytes)": )[0-9]+#\1@N@#g' \
    -e 's#("updated": )"[^"]*"#\1"@TIME@"#g'
}

# Compare one produced text with expected/<name>.
compare() {
  local name="$1" got="$2"
  if [[ "$ACCEPT" == "--accept" ]]; then
    mkdir -p "$(dirname "$EXPECTED/$name")"
    printf '%s\n' "$got" > "$EXPECTED/$name"
    echo "WROTE $name"
    return
  fi
  if ! diff -u "$EXPECTED/$name" <(printf '%s\n' "$got"); then
    fail "$name differs (see diff above)"
  fi
  echo "PASS  $name"
}

# Every file of the index, masked, under a name without the key hash.
compare_index() {
  local suffix="$1" f rel
  for f in "$INDEX/env.json" "$INDEX/packages.json" "$INDEX"/pkg/*/summary.json "$INDEX"/pkg/*/mod/*.json; do
    rel="$(printf '%s' "${f#"$INDEX"/}" | mask)"
    compare "index$suffix/$rel" "$(mask < "$f")"
  done
}

echo "=== First run ==="
compare "print-index-dir.txt" "$(XDG_CACHE_HOME=/cache "$INDEXER" --print-index-dir)"
compare "run1.events" "$(run_indexer --update --json --pretty 2>/dev/null | mask)"
compare_index ""

echo "=== Second run: one TTC touched ==="
touch -d '2030-01-01T00:00:00Z' "$PKGS"/fixture-0.1.0/*/Fixture/Shapes.ttc
compare "run2.events" "$(run_indexer --update --json --pretty 2>/dev/null | mask)"
# The summary was rebuilt from the re-read module and the parsed module file
# of the other one, so it must equal the first run's.
compare "index/pkg/fixture-0.1.0-@HASH@/summary.json" \
  "$(mask < "$(ls "$INDEX"/pkg/fixture-0.1.0-*/summary.json)")"

echo "=== Third run: env.json from another indexer version ==="
sed -i 's/"version": "[^"]*"/"version": "0.0.0"/' "$INDEX/env.json"
compare "run3.events" "$(run_indexer --update --json --pretty 2>/dev/null | mask)"

echo "=== Fourth run: the lock is held ==="
mkdir -p "$INDEX/.lock"
echo "$$" > "$INDEX/.lock/pid"
code=0
run_indexer --update 2>/dev/null || code=$?
[[ "$code" == 2 ]] || fail "lock held: exit code $code, expected 2"
rm -rf "$INDEX/.lock"
echo "PASS  lock held: exit code 2"

echo "=== Build idris2-browser (rc2) ==="
IDRIS2RC2="$REPO_ROOT/rc2/build/exec/idris2-rc2"
[[ -x "$IDRIS2RC2" ]] || fail "rc2/build/exec/idris2-rc2 not found -- build it first (see rc2/tests/verify.sh)"
(cd "$TOOL_DIR" && "$IDRIS2RC2" --cg rc2 --build browser.ipkg)
BROWSER="$TOOL_DIR/build/browser/exec/idris2-browser"
[[ -x "$BROWSER" ]] || fail "build did not produce $BROWSER"

# The screens draw from a copy of the index whose paths are a fixed /fixture:
# a path is wrapped where it reaches the edge, so masking it after drawing
# would still leave the line breaks of this checkout's path.
SCREEN_INDEX="$BUILD/screen-index"
cp -r "$INDEX" "$SCREEN_INDEX"
find "$SCREEN_INDEX" -name '*.json' -exec sed -i "s#$BUILD#/fixture#g" {} +

# The screen at 100x30 after the actions of `--dump`
# (IdrisBrowser.Main.actionMsg).
screen() {
  local name="$1"; shift
  compare "screens/$name.txt" "$("$BROWSER" --index-dir "$SCREEN_INDEX" --dump 100 30 "$@")"
}

echo "=== Screens ==="
screen start
screen next-module mod-down
screen next-definition mod-down def-down def-down
screen all-definitions mod-down filter
screen undocumented mod-down filter filter
screen type mod-down def-down tab:1
screen stats tab:2
screen package tab:3
screen unreadable pkg-down tab:3
screen search search type:point
screen jump search type:hidden jump

echo "=== Fifth run: a module removed ==="
rm "$PKGS"/fixture-0.1.0/*/Fixture/Shapes.ttc
compare "run5.events" "$(run_indexer --update --json --pretty 2>/dev/null | mask)"
compare "summary-after-removal.json" "$(mask < "$(ls "$INDEX"/pkg/fixture-0.1.0-*/summary.json)")"

echo "=== Sixth run: a corrupt module file, no summary (a run stopped) ==="
printf '{"formatVersion":1,' > "$(ls "$INDEX"/pkg/fixture-0.1.0-*/mod/Fixture.json)"
rm "$INDEX"/pkg/fixture-0.1.0-*/summary.json
compare "run6.events" "$(run_indexer --update --json --pretty 2>/dev/null | mask)"
compare "summary-after-removal.json" "$(mask < "$(ls "$INDEX"/pkg/fixture-0.1.0-*/summary.json)")"

echo "=== Seventh run: a lock whose process is gone ==="
sh -c 'exit 0' & dead=$!
wait "$dead"
mkdir -p "$INDEX/.lock"
echo "$dead" > "$INDEX/.lock/pid"
code=0
run_indexer --update 2>/dev/null || code=$?
[[ "$code" == 0 ]] || fail "stale lock: exit code $code, expected 0"
[[ ! -e "$INDEX/.lock" ]] || fail "stale lock: the lock was not released"
echo "PASS  stale lock taken over and released"

echo "=== All idris2-browser checks passed ==="
