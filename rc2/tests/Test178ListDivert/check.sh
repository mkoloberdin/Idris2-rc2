#!/usr/bin/env bash
# Post-compile check run by verify.sh (see its "Per-test checks"
# comment); by hand: ./TestN/check.sh build TestN
# Compiler.RC2.ListDivert (rc2/doc/list-divert.md) is opt-in: the default build keeps
# upstream's two-pass list helpers; built with --directive listdivert none is left in
# the IR, the loops TRMC made of the naive definitions fill their holes, and the output
# is the same.
set -u
TMP="$1"
name="$2"
pass() { echo "PASS  $name ($1)"; }
fail() { echo "FAIL  $name ($1)"; }

here="$(cd "$(dirname "$0")" && pwd)"
rc2="$here/../../build/exec/idris2-rc2"
tests="$here/.."
off="$TMP/${name}_rc2.rcexpr"
on="$TMP/${name}_listdivert"

[ -f "$off" ] || { fail "no IR dump $off"; exit 0; }
kept="$(grep -cE 'Prelude\.Types\.List\.(reverseOnto|mapAppend|filterAppend|mapMaybeAppend)' "$off" || true)"
if [ "$kept" -ge 1 ]; then
    pass "off by default: $kept references to the upstream helpers"
elif [ "$(grep -c '^ *fill ' "$off" || true)" -ge 4 ]; then
    # verify.sh --directive listdivert: the default build is the diverted one
    pass "built with listdivert: no upstream helper, the loops fill their holes"
else
    fail "default build has no upstream helper in $off"
fi
if ! ( cd "$tests" && "$rc2" --cg rc2 --directive dumprcexpr --directive listdivert "$name/$name.idr" -o "$on" ) \
        > "$on.log" 2>&1 || [ ! -f "$on.rcexpr" ]; then
    fail "listdivert build failed, see $on.log"
    exit 0
fi
left="$(grep -cE 'Prelude\.Types\.List\.(reverseOnto|mapAppend|filterAppend|mapMaybeAppend|tailRecAppend)' "$on.rcexpr" || true)"
fills="$(grep -c '^ *fill ' "$on.rcexpr" || true)"
if [ "$left" = "0" ] && [ "$fills" -ge 4 ]; then
    pass "listdivert: no upstream two-pass helper left, $fills filled holes"
else
    fail "listdivert: $left reference(s) to an upstream helper (want 0), $fills fills (want >= 4) in $on.rcexpr"
fi
if "$on" | cmp -s - "$here/$name.expected"; then
    pass "listdivert -- same output"
else
    fail "listdivert -- the output differs from $name.expected"
fi
