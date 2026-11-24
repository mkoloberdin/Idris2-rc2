#!/usr/bin/env bash
# Post-compile check run by verify.sh (see its "Per-test checks"
# comment); by hand: ./TestN/check.sh build TestN
set -u
TMP="$1"
name="$2"
pass() { echo "PASS  $name ($1)"; }
fail() { echo "FAIL  $name ($1)"; }

dump="$TMP/${name}_rc2.rcexpr"

# SpecIterate: iteration of the specialization passes to a fixpoint
# (doc/speculative-closure-specialization.md, "Iteration"). The closure
# key `applyAll incr` only appears inside the clone the constant-
# constructor half builds for `run`, i.e. it needs a second round. Asserts
# the `run` clone uses a closure clone of `applyAll` and no longer the
# generic one, so a cap of one round, `--directive nospecclosure` and
# `--directive nospecconstcon` all make it FAIL by design. The clone is
# either called or, being `applyAll`'s TRMC twin with `run` as its one
# caller, spliced into `run` by LateInline: then `incr`'s `+ 3` is in the
# loop itself (doc/trmc.md, "Entries").
it="Test106TransitiveSpec_SpecIterate"
inRun() { PAT="$1" awk -v r="rc2_specConst_${it}_run" '/^def /{ins = index($0, r) > 0} ins && $0 ~ ENVIRON["PAT"]' "$dump" | wc -l; }
viaClone="$(inRun 'call .*rc2_specClosure_Test106TransitiveSpec_SpecIterate_applyAll')"
spliced="$(inRun 'op \+Int \[v[0-9]+, #3\]')"
generic="$(inRun 'call (Test106TransitiveSpec\.SpecIterate\.applyAll|\{rc2_trmc_Test106TransitiveSpec_SpecIterate_applyAll)')"
if [ $((viaClone + spliced)) -ge 1 ] && [ "$generic" = "0" ]; then
    pass "second-round closure clone of applyAll: the run clone calls one ($viaClone site(s)) or has it spliced ($spliced), no generic call left"
else
    fail "expected the run clone to call an applyAll closure clone ($viaClone) or have it spliced ($spliced), and not the generic one ($generic) in $dump"
fi

# MultiApplySpec: closure specialisation of callees that apply the
# closure parameter more than once (doc/speculative-closure-
# specialization.md, "Multiple apply chains"): callees applying the
# closure parameter 2-3 times get closure clones with no generic apply
# left (`twice`, `thrice`: 2-3 chains and `map f` forwarding;
# `fwd`: two chains and a self passthrough); `medium` and `big` (above
# SpecClosure.multiApplyMaxSize) get none, and neither does `twice` with
# a capturing closure (multi-apply is for constant closures only).
ma="Test106TransitiveSpec_MultiApplySpec"
for fn in twice thrice fwd; do
    clones="$(grep -cE "^def .*rc2_specClosure_${ma}_$fn" "$dump" || true)"
    generic="$(awk -v f="rc2_specClosure_${ma}_$fn" '/^def /{ins = index($0, f) > 0} ins && (/^ *apply|[^_]apply /)' "$dump" | wc -l)"
    if [ "$clones" -ge 1 ] && [ "$generic" = "0" ]; then
        pass "$fn: $clones closure clone(s), no generic apply inside"
    else
        fail "$fn: expected >=1 closure clone ($clones) without apply ($generic) in $dump"
    fi
done
bigClones="$(grep -cE "^def .*rc2_specClosure_${ma}_(big|medium)" "$dump" || true)"
if [ "$bigClones" = "0" ]; then
    pass "big, medium: over the size threshold, no closure clone"
else
    fail "big, medium: $bigClones closure clone(s), expected 0 in $dump"
fi

# LazyFuncSpec: `Prelude.Types.maybe`/`either` take their function
# arguments as `Lazy`, so the body reaches them through a `force`
# (doc/speculative-closure-specialization.md, "Forcing a closure
# parameter"). With the clones (and the inlining they enable) no call to
# either remains; `--directive nospecclosure` makes this FAIL by design.
lazyCalls="$(grep -cE "call Prelude\.Types\.(maybe|either) " "$dump" || true)"
if [ "$lazyCalls" = "0" ]; then
    pass "LazyFuncSpec: no call to maybe/either left"
else
    fail "LazyFuncSpec: $lazyCalls call(s) to maybe/either left in $dump"
fi
