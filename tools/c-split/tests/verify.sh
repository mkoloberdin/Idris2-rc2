#!/usr/bin/env bash
# Builds tools/c-split (plain Chez backend: it only reads and writes text)
# and checks it on hand-written C: sample.c has one of each kind of item the
# tool rewrites (a static prototype and its definition, static constants of a
# named and of an anonymous struct type, a tentative definition, a stray
# `;`, a static inline function, braces and quotes inside literals). Cut
# after every function, every part must compile with -Wall -Werror and the
# linked program print what the unsplit one prints. Each refuse-*.c is outside
# what the tool splits and must make it exit with 1.
#
# Usage: ./verify.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$(dirname "$TESTS_DIR")"
REPO_ROOT="$(cd "$TOOL_DIR/../.." && pwd)"

fail() { echo "FAIL  $1"; exit 1; }

source "$REPO_ROOT/env.sh"

echo "=== Build c-split ==="
(cd "$TOOL_DIR" && idris2 --build c-split.ipkg)

C_SPLIT="$TOOL_DIR/build/exec/c-split"
[[ -x "$C_SPLIT" ]] || fail "build did not produce $C_SPLIT"

OUT="$TOOL_DIR/build/test"
rm -rf "$OUT"
mkdir -p "$OUT/whole" "$OUT/split"

cc -Wall -Werror "$TESTS_DIR/sample.c" -o "$OUT/whole/sample"
want="$("$OUT/whole/sample")"

"$C_SPLIT" --part-bytes 1 "$TESTS_DIR/sample.c" "$OUT/split" > "$OUT/parts.txt" \
    || fail "sample.c was refused"
nparts="$(wc -l < "$OUT/parts.txt")"
[[ "$nparts" -ge 4 ]] || fail "sample.c gave $nparts parts, expected a cut after every function"
objs=()
while read -r p; do
    cc -Wall -Werror -c "$p" -o "${p%.c}.o" || fail "part $p does not compile"
    objs+=("${p%.c}.o")
done < "$OUT/parts.txt"
cc "${objs[@]}" -o "$OUT/split/sample" || fail "the parts do not link"
got="$("$OUT/split/sample")"
[[ "$got" == "$want" ]] || fail "split sample prints '$got', expected '$want'"
echo "PASS  sample.c ($nparts parts)"

# The Makefile from a command file shaped like rc2's (`--directive writecc`):
# relative paths, resolved against `cwd`, and a `$` that make must not expand.
mkdir -p "$OUT/mk/obj"
cp "$TESTS_DIR/sample.c" "$OUT/mk/sample.c"
cat > "$OUT/mk/sample.cmd" <<EOF
cwd $OUT/mk
object obj/sample.o
compile "cc" "-Wall" "-Werror" "-DPRICE=\"\\\$1\"" "-c" "sample.c" "-o" "obj/sample.o"
final "cc" "obj/sample.o" "-o" "obj/sample"
EOF
"$C_SPLIT" --part-bytes 1 --commands "$OUT/mk/sample.cmd" "$OUT/mk/sample.c" "$OUT/mk/split" > /dev/null \
    || fail "no Makefile for sample.c"
make -s -C "$OUT/mk/split" -j4 || fail "the Makefile does not build"
got="$("$OUT/mk/obj/sample")"
[[ "$got" == "$want" ]] || fail "the Makefile's sample prints '$got', expected '$want'"
# What was static is local again in the object the parts make.
nm "$OUT/mk/obj/sample.o" | grep -q ' t helper$' || fail "helper is not local in the merged object"
nm "$OUT/mk/obj/sample.o" | grep -q ' T twice$' || fail "twice is not global in the merged object"
echo "PASS  Makefile ($(grep -c '^[^ ]*\.o:' "$OUT/mk/split/Makefile") parts)"

# `clean` removes what make built, and leaves what c-split wrote.
make -s -C "$OUT/mk/split" clean || fail "make clean failed"
left="$(find "$OUT/mk/obj" "$OUT/mk/split" -name '*.o' -o -name '*.roots' -o -name sample -type f)"
[[ -z "$left" ]] || fail "make clean left: $left"
[[ -f "$OUT/mk/split/sample.h" && -f "$OUT/mk/split/sample-0.c" ]] || fail "make clean removed the parts"
echo "PASS  make clean"

for f in "$TESTS_DIR"/refuse-*.c; do
    name="$(basename "$f")"
    set +e
    "$C_SPLIT" "$f" "$OUT/refused" > /dev/null 2> "$OUT/$name.err"
    code=$?
    set -e
    [[ "$code" -eq 1 ]] || fail "$name: exit code $code, expected 1 ($(cat "$OUT/$name.err"))"
    echo "PASS  $name ($(cat "$OUT/$name.err"))"
done

set +e
"$C_SPLIT" > /dev/null 2>&1
code=$?
set -e
[[ "$code" -eq 2 ]] || fail "no arguments: exit code $code, expected 2"
echo "PASS  usage error"
