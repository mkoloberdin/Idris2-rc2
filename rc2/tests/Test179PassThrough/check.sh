#!/usr/bin/env bash
# Post-compile check run by verify.sh (see its "Per-test checks"
# comment); by hand: ./TestN/check.sh build TestN
# No worker of `errno` is left (every call spliced), and an inlined %foreign
# wrapper nothing calls has no prototype or body, while its header is still included.
set -u
TMP="$1"
name="$2"
pass() { echo "PASS  $name ($1)"; }
fail() { echo "FAIL  $name ($1)"; }
c="$TMP/${name}_rc2.c"
[ -f "$c" ] || { fail "no C file $c"; exit 0; }
w="$(grep -c 'worker_System_Posix_Errno_errno' "$c" || true)"
if [ "$w" = "0" ]; then pass "errno worker spliced at every call"; else fail "$w mentions of the errno worker in $c"; fi
s="$(grep -c 'prim__SIGCONT' "$c" || true)"
if [ "$s" = "0" ]; then pass "unused prim__SIGCONT wrapper not emitted"; else fail "$s mentions of prim__SIGCONT in $c"; fi
if grep -q '#include <signal.h>' "$c"; then pass "its header is still included"; else fail "signal.h not included in $c"; fi
# the spliced wrapper leaves no `let v = (let w = <call>; w)`: no line of just a local follows the inlined errno call
ir="$TMP/${name}_rc2.rcexpr"
if [ -f "$ir" ]; then
    twice="$(awk '/callFFIInline.*errno/ { getline nxt; if (nxt ~ /^ *v[0-9]+$/) n++ } END { print n+0 }' "$ir")"
    if [ "$twice" = "0" ]; then pass "no let that only returns the inlined call"; else fail "$twice inlined errno calls followed by a bare local in $ir"; fi
else
    fail "no IR dump $ir"
fi
