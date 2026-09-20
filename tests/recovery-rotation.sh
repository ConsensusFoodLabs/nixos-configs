#!/usr/bin/env bash
#
# fleet-rotate-recovery must never destroy a key until the replacement has
# been proven to work, and must never touch keyslot 0.
#
# Rotating fleet/secrets/<host>.yaml changes a file; this tool changes the
# disk. Between the two, the repository describes a recovery key that does not
# open the machine — so this is the step that makes a rotation real, and the
# step where a mistake costs a disk nobody can open.

cd "$(dirname "$0")" || exit 1
# shellcheck source=tests/lib.sh
. ./lib.sh
need_root

rotate=$(need_built ../result-rotate/bin/fleet-rotate-recovery \
    "nix build .#fleet-rotate-recovery -o result-rotate") || exit 1

work=$(mktemp -d)
loop=""
cleanup() {
    [[ -n $loop ]] && losetup -d "$loop" 2>/dev/null
    rm -rf "$work"
    true
}
trap cleanup EXIT

OLD_PASS='DEVPASS-AAAA-BBBB-CCCC'
OLD_REC='OLDRECOVERY-KEY-11111'
NEW_REC='NEWRECOVERY-KEY-22222'

fresh_container() {
    [[ -n $loop ]] && losetup -d "$loop" 2>/dev/null
    rm -f "$work/luks.img"
    truncate -s 32M "$work/luks.img"
    loop=$(losetup -f --show "$work/luks.img")
    printf '%s' "$OLD_PASS" >"$work/pass"
    printf '%s' "$OLD_REC" >"$work/oldrec"
    cryptsetup luksFormat --batch-mode --key-file "$work/pass" "$loop"
    cryptsetup luksAddKey "$loop" "$work/oldrec" --key-file "$work/pass"
}

opens() { # key, [slot]
    printf '%s' "$1" >"$work/probe"
    if [[ -n ${2:-} ]]; then
        cryptsetup open --test-passphrase --key-slot "$2" --key-file "$work/probe" "$loop" 2>/dev/null
    else
        cryptsetup open --test-passphrase --key-file "$work/probe" "$loop" 2>/dev/null
    fi
}

step "a happy rotation"
fresh_container
if printf '%s\n%s\n%s\n1\n' "$NEW_REC" "$NEW_REC" "$OLD_PASS" |
    "$rotate" --device "$loop" >"$work/log" 2>&1; then
    pass "completed"
else
    fail "failed"
    tail -5 "$work/log" | sed 's/^/    /'
fi
if opens "$NEW_REC"; then pass "the new recovery key opens the disk"; else fail "the new key does not open the disk"; fi
if opens "$OLD_REC"; then fail "the old recovery key still works"; else pass "the old recovery key is gone"; fi
if opens "$OLD_PASS" 0; then pass "keyslot 0 untouched"; else fail "keyslot 0 was damaged"; fi

step "a wrong authorising key changes nothing"
fresh_container
printf '%s\n%s\n%s\n1\n' "$NEW_REC" "$NEW_REC" "WRONG-KEY-ENTIRELY" |
    "$rotate" --device "$loop" >"$work/log" 2>&1 || true
if opens "$OLD_REC"; then pass "the old recovery key survived"; else fail "the old key was destroyed on a failed run"; fi
if opens "$NEW_REC"; then fail "the new key was enrolled despite bad authorisation"; else pass "nothing was enrolled"; fi

step "mistyped new key is caught before anything happens"
fresh_container
printf '%s\n%s\n%s\n1\n' "$NEW_REC" "TYPO-DIFFERENT-KEY-99" "$OLD_PASS" |
    "$rotate" --device "$loop" >"$work/log" 2>&1 || true
if grep -q "the two entries differ" "$work/log"; then pass "refused on mismatch"; else fail "did not catch the mismatch"; fi
if opens "$OLD_REC"; then pass "the old recovery key survived"; else fail "the old key was destroyed"; fi

step "refuses to remove keyslot 0"
fresh_container
printf '%s\n%s\n%s\n0\n' "$NEW_REC" "$NEW_REC" "$OLD_PASS" |
    "$rotate" --device "$loop" --slot 0 >"$work/log" 2>&1 || true
if grep -q "refusing to remove keyslot 0" "$work/log"; then
    pass "refused"
else
    fail "did not refuse"
    tail -4 "$work/log" | sed 's/^/    /'
fi
if opens "$OLD_PASS" 0; then pass "keyslot 0 still opens the disk"; else fail "keyslot 0 was destroyed"; fi

finish
