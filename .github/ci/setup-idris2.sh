#!/usr/bin/env bash
# Builds the Idris 2 that rc2 is built with, from the pinned upstream commit
# (.github/ci/idris2-rev), into <repo>/install. Chez Scheme (`scheme` on PATH)
# is the only thing it needs besides gcc, make and gmp. A second run with the
# same pin does nothing, so a cache of install/ makes it free.
#
#   IDRIS2_SRC_URL  where to clone Idris 2 from (default: upstream on GitHub)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
rev="$(tr -d '[:space:]' < "$here/idris2-rev")"
url="${IDRIS2_SRC_URL:-https://github.com/idris-lang/Idris2.git}"
src="$repo/idris2-src"
prefix="$repo/install"

if [ -x "$prefix/bin/idris2" ] && [ "$(cat "$prefix/.idris2-rev" 2>/dev/null || true)" = "$rev" ]; then
    echo "Idris 2 $rev is already installed in $prefix"
    exit 0
fi

command -v scheme >/dev/null 2>&1 || { echo "error: no 'scheme' (Chez Scheme) on PATH" >&2; exit 1; }

# idris2-src is a plain clone, never edited (see AGENT.md); only the pinned commit is wanted.
if [ ! -d "$src/.git" ]; then
    git init -q "$src"
    git -C "$src" remote add origin "$url"
fi
if ! git -C "$src" fetch -q --depth 1 origin "$rev" 2>/dev/null; then
    # a server that will not hand out a commit that is not a branch tip
    git -C "$src" fetch -q origin
fi
git -C "$src" checkout -q --detach "$rev"
test "$(git -C "$src" rev-parse HEAD)" = "$rev"

make -C "$src" bootstrap SCHEME=scheme PREFIX="$prefix"
make -C "$src" install SCHEME=scheme PREFIX="$prefix"
# install-api runs the `idris2` that was just installed
PATH="$prefix/bin:$PATH" make -C "$src" install-api SCHEME=scheme PREFIX="$prefix"
echo "$rev" > "$prefix/.idris2-rev"
