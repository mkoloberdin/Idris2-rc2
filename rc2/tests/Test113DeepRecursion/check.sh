#!/usr/bin/env bash
# Post-compile check run by verify.sh (see its "Per-test checks"
# comment); by hand: ./TestN/check.sh build TestN
set -u
TMP="$1"
name="$2"
pass() { echo "PASS  $name ($1)"; }
fail() { echo "FAIL  $name ($1)"; }

# TrmcHoles and TrmcMutual (rc2/doc/trmc.md, "Several hole indexes"):
# `alternate` fills field 1 of `A` and field 0 of `B`, so it fills
# `last . hk`, an index read at run time, not one constant index per
# branch of a `case` on `hk`. Inlining moves `alternate`'s loop into
# `main`, so this counts over the whole dump.
dump="$TMP/${name}_rc2.rcexpr"
varFills="$(grep -cE '^ *fill v[0-9]+ \. v[0-9]+ =' "$dump" || true)"
if [ "$varFills" -ge 1 ]; then
    pass "TrmcHoles: $varFills fill(s) at a run-time index"
else
    fail "TrmcHoles: no fill at a run-time index (want >= 1) in $dump"
fi
