#!/usr/bin/env bash
# Builds and installs the rc2 compiler and its runtime, then installs libs/rc2base
# (README.md, "Building and installing rc2" and "Installing the support library") and
# libs/control-async, which the ThreadSanitizer tests (rc2/tests/tsan.sh) need.
# Needs the Idris 2 of setup-idris2.sh in install/.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo"
./gen-env.sh
# shellcheck source=/dev/null
source env.sh

(cd rc2 && idris2 --build rc2.ipkg && idris2 --install rc2.ipkg)
(cd libs/rc2base && idris2 --install rc2base.ipkg)
(cd libs/control-async && idris2 --install control-async.ipkg)
