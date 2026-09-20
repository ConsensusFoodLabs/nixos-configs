# shellcheck shell=bash
# Shared preamble for the tests. See tests/README.md.
set -uo pipefail

fails=0
pass() { printf '  PASS: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*"; fails=$((fails + 1)); }
step() { printf '\n=== %s ===\n' "$*"; }

# cmp, but reported. Written out because `A && B || C` runs C when A succeeds
# and B fails, which would turn a real mismatch into a silent pass.
same_file() {
    if cmp -s "$1" "$2"; then pass "$3"; else fail "$3"; fi
}

need_root() {
    ((EUID == 0)) || { echo "must run as root (sudo $0)" >&2; exit 1; }
}

# Resolve a built artifact, or say exactly what to build. Deliberately does
# not run nix itself: these run under sudo, where nix is often not on PATH.
need_built() {
    local path=$1 build=$2
    [[ -e $path ]] || {
        echo "missing $path" >&2
        echo "build it first:  $build" >&2
        exit 1
    }
    printf '%s' "$path"
}

finish() {
    echo
    if ((fails)); then
        echo "$fails check(s) FAILED"
        exit 1
    fi
    echo "all checks passed"
}
