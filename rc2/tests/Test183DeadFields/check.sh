#!/usr/bin/env bash
# Post-compile check run by verify.sh (see its "Per-test checks"
# comment); by hand: ./TestN/check.sh build TestN
# DeadFields (on here by `%cg rc2 deadfields`): a copy of myLTE makes Yes/No of erased fields and
# calls itself in a tail position, and the program built without it prints the same (the side
# effect included).
set -u
TMP="$1"
name="$2"
pass() { echo "PASS  $name ($1)"; }
fail() { echo "FAIL  $name ($1)"; }

here="$(cd "$(dirname "$0")" && pwd)"
rc2="$here/../../build/exec/idris2-rc2"
tests="$here/.."
on="$TMP/${name}_named"
off="$TMP/${name}_off"

if ! ( cd "$tests" && "$rc2" --cg rc2 --directive dumpnamed "$name/$name.idr" -o "$on" ) > "$on.log" 2>&1 || [ ! -f "$on.named" ]; then
    fail "dumpnamed build failed, see $on.log"
    exit 0
fi
loops="$(awk '/^\{rc2_dropf_[0-9]+:0\} = / { n=$1; if (index($0, "Prelude.Types.Yes Just 0 [___]") && index(substr($0, length(n) + 1), n " [")) c++ } END { print c+0 }' "$on.named")"
if [ "$loops" -ge 1 ]; then pass "a copy of myLTE makes no proof and calls itself"; else fail "no copy of myLTE without its proof in $on.named"; fi
# the same program without the directive (the pass is off by default)
src="$TMP/${name}_off_src"
rm -rf "$src"; mkdir -p "$src"
grep -v '^%cg rc2 deadfields$' "$here/$name.idr" > "$src/$name.idr"
if ! ( cd "$src" && "$rc2" --cg rc2 "$name.idr" -o "$off" ) > "$off.log" 2>&1; then
    fail "build without deadfields failed, see $off.log"
    exit 0
fi
if "$off" | cmp -s - "$here/$name.expected"; then
    pass "without deadfields -- same output, the side effect included"
else
    fail "without deadfields -- the output differs from $name.expected"
fi
