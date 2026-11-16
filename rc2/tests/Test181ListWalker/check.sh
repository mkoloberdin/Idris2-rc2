#!/usr/bin/env bash
# Post-compile check run by verify.sh (see its "Per-test checks"
# comment); by hand: ./TestN/check.sh build TestN
# --directive listfuse: the walkers sumSq, pairs and weigh get a copy that a chain feeds
# (rc2_thru_*), twiceRest (which reads the rest twice) does not, and the output is the same.
set -u
TMP="$1"
name="$2"
pass() { echo "PASS  $name ($1)"; }
fail() { echo "FAIL  $name ($1)"; }

here="$(cd "$(dirname "$0")" && pwd)"
rc2="$here/../../build/exec/idris2-rc2"
tests="$here/.."
on="$TMP/${name}_listfuse"

if ! ( cd "$tests" && "$rc2" --cg rc2 --directive dumpnamed --directive listfuse "$name/$name.idr" -o "$on" ) \
        > "$on.log" 2>&1 || [ ! -f "$on.named" ]; then
    fail "listfuse build failed, see $on.log"
    exit 0
fi
for w in sumSq pairs weigh; do
    if grep -q "rc2_thru_Main.${w}_" "$on.named"; then pass "listfuse: $w is fed by a chain"; else fail "listfuse: no copy of $w in $on.named"; fi
done
if grep -q "rc2_thru_Main.twiceRest" "$on.named"; then
    fail "listfuse: twiceRest reads the rest twice and was copied anyway"
else
    pass "listfuse: twiceRest, which reads the rest twice, is left alone"
fi
if "$on" | cmp -s - "$here/$name.expected"; then
    pass "listfuse -- same output"
else
    fail "listfuse -- the output differs from $name.expected"
fi
