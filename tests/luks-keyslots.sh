#!/usr/bin/env bash
#
# A developer rotating their disk passphrase must not be able to disturb the
# organization's recovery key (D5, D27).
#
# fleet-passphrase writes keyslot 0 only and refuses unless the passphrase
# given opens keyslot 0. This builds a throwaway LUKS container shaped the way
# disko leaves a real one -- passphrase in slot 0, recovery key in slot 1 --
# runs the same luksChangeKey that tool runs, and checks slot 1 survives.
#
# Run it whenever modules/fleet/fleet-credentials.nix or a disko.nix changes.

cd "$(dirname "$0")" || exit 1
# shellcheck source=tests/lib.sh
. ./lib.sh
need_root

work=$(mktemp -d)
img=$work/luks.img
loop=""
cleanup() {
    [[ -n $loop ]] && cryptsetup close test-fleet 2>/dev/null
    [[ -n $loop ]] && losetup -d "$loop" 2>/dev/null
    rm -rf "$work"
    true
}
trap cleanup EXIT

printf '%s' 'OLDPASS-AAAA-BBBB' >"$work/old"
printf '%s' 'RECOVERY-KEY-ZZZZ' >"$work/rec"
printf '%s' 'NEWPASS-CCCC-DDDD' >"$work/new"

truncate -s 32M "$img"
loop=$(losetup -f --show "$img")

step "a container shaped like a provisioned machine"
cryptsetup luksFormat --batch-mode --key-file "$work/old" "$loop"
cryptsetup luksAddKey "$loop" "$work/rec" --key-file "$work/old"
echo "  slot 0 = developer passphrase, slot 1 = recovery key"

step "baseline"
if cryptsetup open --test-passphrase --key-slot 0 --key-file "$work/old" "$loop" 2>/dev/null; then
    pass "the passphrase opens slot 0"
else
    fail "the passphrase does not open slot 0"
fi
if cryptsetup open --test-passphrase --key-slot 0 --key-file "$work/rec" "$loop" 2>/dev/null; then
    fail "the recovery key opens slot 0 — fleet-passphrase could overwrite it"
else
    pass "the recovery key does not open slot 0"
fi

step "the argument form fleet-passphrase relies on"
# --new-keyfile belongs to luksAddKey. Passing it here fails, and it failing
# is the point of this check: if a future cryptsetup starts accepting it, the
# comment in fleet-credentials.nix explaining why we do not use it is stale.
if cryptsetup luksChangeKey --key-slot 0 --key-file "$work/old" \
    --new-keyfile "$work/new" "$loop" >/dev/null 2>&1; then
    fail "--new-keyfile was accepted; revisit fleet-credentials.nix"
else
    pass "--new-keyfile is rejected, as documented"
fi

step "rotating the passphrase"
if cryptsetup luksChangeKey --key-slot 0 --key-file "$work/old" "$loop" "$work/new" 2>&1 |
    sed 's/^/    /'; then
    :
fi

if cryptsetup open --test-passphrase --key-slot 0 --key-file "$work/new" "$loop" 2>/dev/null; then
    pass "the new passphrase opens slot 0"
else
    fail "the new passphrase does not open slot 0"
fi
if cryptsetup open --test-passphrase --key-file "$work/rec" "$loop" 2>/dev/null; then
    pass "the recovery key still opens the container"
else
    fail "the recovery key was destroyed — escrow is broken"
fi
if cryptsetup open --test-passphrase --key-file "$work/old" "$loop" 2>/dev/null; then
    fail "the old passphrase still works"
else
    pass "the old passphrase no longer works"
fi

finish
