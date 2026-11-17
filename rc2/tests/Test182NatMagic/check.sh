#!/usr/bin/env bash
# Post-compile check run by verify.sh (see its "Per-test checks"
# comment); by hand: ./TestN/check.sh build TestN
# Compiler.RC2.NatMagic: Data.Nat.isLTE and lte no longer call themselves, and the program
# built with --directive nonatmagic (upstream's recursive definitions) prints the same.
set -u
TMP="$1"
name="$2"
pass() { echo "PASS  $name ($1)"; }
fail() { echo "FAIL  $name ($1)"; }

here="$(cd "$(dirname "$0")" && pwd)"
rc2="$here/../../build/exec/idris2-rc2"
tests="$here/.."
off="$TMP/${name}_nonatmagic"
ir="$TMP/${name}_rc2.rcexpr"

[ -f "$ir" ] || { fail "no IR dump $ir"; exit 0; }
rec="$(awk '/^def Data\.Nat\.(isLTE|lte) /{d=1; next} /^def /{d=0} d && /call Data\.Nat\.(isLTE|lte) /' "$ir" | wc -l)"
if [ "$rec" = "0" ]; then pass "isLTE and lte call no one"; else fail "$rec recursive calls left in isLTE/lte in $ir"; fi
if ! ( cd "$tests" && "$rc2" --cg rc2 --directive nonatmagic "$name/$name.idr" -o "$off" ) > "$off.log" 2>&1; then
    fail "nonatmagic build failed, see $off.log"
    exit 0
fi
if "$off" | cmp -s - "$here/$name.expected"; then
    pass "nonatmagic (upstream's definitions) -- same output"
else
    fail "nonatmagic -- the output differs from $name.expected"
fi
