#!/usr/bin/env bash
# What this defends: fleet-install now wipes the administrator key after a
# successful install (D39), which means a destructive operation runs with no
# human at the keyboard. The typed confirmation used to be the last line of
# defence; --yes removes it. These check that the *other* guards — the ones
# that decide whether something is key media at all — still hold, because
# they are now the only thing standing between a slip and a wiped disk.
#
#   sudo tests/key-wipe.sh
#
cd "$(dirname "$0")" || exit 1
# shellcheck source=tests/lib.sh
. ./lib.sh
need_root

wipe=$(need_built ../result-wk/bin/fleet-wipe-key "nix build .#fleet-wipe-key -o result-wk") || exit 1
# mkfs.vfat is not part of a NixOS installer's or a workstation's base system,
# and these run under sudo where nix is often not on PATH — so it comes from a
# built path like everything else here.
dosfs=$(need_built ../result-dosfstools/bin/mkfs.vfat \
    "nix build nixpkgs#dosfstools -o result-dosfstools") || exit 1
PATH=$(dirname "$dosfs"):$PATH
export PATH

tmp=$(mktemp -d)
loop=""
cleanup() {
    [[ -n $loop ]] && losetup -d "$loop" 2>/dev/null
    rm -rf "$tmp"
}
trap cleanup EXIT

# A stick shaped like one fleet-mkstick makes: one FAT partition, labelled
# FLEETKEY, holding a key file.
img=$tmp/stick.img
truncate -s 64M "$img"
printf 'label: dos\n,,b\n' | sfdisk -q "$img" >/dev/null
loop=$(losetup -fP --show "$img")
mkfs.vfat -n FLEETKEY "${loop}p1" >/dev/null 2>&1
mnt=$tmp/mnt
mkdir -p "$mnt"
mount "${loop}p1" "$mnt"
echo "AGE-SECRET-KEY-NOTAREALKEYJUSTATESTFIXTURE" > "$mnt/fleet-admin-key.txt"
umount "$mnt"

step "--yes wipes key media without a prompt"
# stdin from /dev/null: if --yes were ignored and it asked, read would get EOF
# and the wipe would abort — so a pass here really means it did not ask.
if "$wipe" --yes "$loop" </dev/null >"$tmp/out" 2>&1; then
    pass "exited 0"
else
    fail "exited non-zero: $(tail -2 "$tmp/out")"
fi

mount "${loop}p1" "$mnt" 2>/dev/null || true
if [[ -e $mnt/fleet-admin-key.txt ]]; then
    fail "the key file is STILL THERE after a wipe"
else
    pass "key file is gone"
fi
if [[ $(lsblk -rno LABEL "${loop}p1" | head -n1) == FLEETKEY ]]; then
    pass "partition left usable and still labelled FLEETKEY"
else
    fail "partition was not reformatted as FLEETKEY"
fi
umount "$mnt" 2>/dev/null || true

step "--yes still refuses media that is not a key partition"
# The guard that matters most: --yes must not turn this into "wipe anything".
other=$tmp/other.img
truncate -s 64M "$other"
printf 'label: dos\n,,b\n' | sfdisk -q "$other" >/dev/null
loop2=$(losetup -fP --show "$other")
mkfs.vfat -n DATA "${loop2}p1" >/dev/null 2>&1
mount "${loop2}p1" "$mnt"
echo "someone's holiday photos" > "$mnt/IMG_0001.txt"
umount "$mnt"

if "$wipe" --yes "$loop2" </dev/null >"$tmp/out2" 2>&1; then
    fail "wiped a partition that is neither labelled FLEETKEY nor holds a key"
else
    pass "refused"
fi
mount "${loop2}p1" "$mnt" 2>/dev/null || true
if [[ -e $mnt/IMG_0001.txt ]]; then
    pass "the unrelated data survived"
else
    fail "THE UNRELATED DATA WAS DESTROYED"
fi
umount "$mnt" 2>/dev/null || true
losetup -d "$loop2" 2>/dev/null

step "an empty non-key partition is refused even though it is FAT"
# After the wipe above, the partition is labelled FLEETKEY again, so it is
# still recognised — that is deliberate, and it is what lets fleet-mkstick
# re-arm the same stick. Check the other direction instead: unlabelled, empty
# FAT must not be mistaken for key media.
mkfs.vfat "${loop}p1" >/dev/null 2>&1
if "$wipe" --yes "${loop}p1" </dev/null >/dev/null 2>&1; then
    fail "wiped unlabelled, empty FAT with no key on it"
else
    pass "refused unlabelled, empty FAT"
fi

printf '\n%s\n' "----------------------------------------"
if ((fails)); then
    printf 'FAILED: %d check(s)\n' "$fails"
    exit 1
fi
printf 'All checks passed.\n'
