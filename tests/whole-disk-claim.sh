#!/usr/bin/env bash
#
# fleet-install must be able to read the administrator key off the stick it
# booted from.
#
# An isohybrid's first partition starts at sector 0, so the iso9660 filesystem
# is visible on the whole-disk device as well as on partition 1 -- and the
# installer boots with /dev/sda mounted at /iso, not /dev/sda1. A mounted whole
# disk is claimed exclusively, so no partition on it can be mounted at all.
#
# That is why fleet-install reads the key with mtools rather than by mounting.
# It cannot be caught by building a stick and reading it back: it only appears
# when running *from* the stick.

cd "$(dirname "$0")" || exit 1
# shellcheck source=tests/lib.sh
. ./lib.sh
need_root

mkstick=$(need_built ../result-mkstick/bin/fleet-mkstick "nix build .#fleet-mkstick -o result-mkstick") || exit 1
mcopy=$(need_built ../result-mtools/bin/mcopy "nix build nixpkgs#mtools -o result-mtools") || exit 1
shopt -s nullglob
isos=(../result/iso/*.iso)
shopt -u nullglob
((${#isos[@]} == 1)) || { echo "build the image first: nix build .#installer-iso" >&2; exit 1; }
iso=${isos[0]}
key=../.admin-key
[[ -e $key ]] || { echo "no .admin-key; link your identity in first" >&2; exit 1; }

work=$(mktemp -d)
loop=""
cleanup() {
    umount "$work/iso" 2>/dev/null
    [[ -n $loop ]] && losetup -d "$loop" 2>/dev/null
    rm -rf "$work"
    true
}
trap cleanup EXIT
mkdir -p "$work/iso" "$work/mnt"

truncate -s $(($(stat -c%s "$iso") + 512 * 1024 * 1024)) "$work/stick.img"
loop=$(losetup -fP --show "$work/stick.img")
echo "$loop" | "$mkstick" "$loop" --iso "$iso" --no-verify >/dev/null 2>&1
part=$(lsblk -rno PATH,LABEL "$loop" | awk '$2 == "FLEETKEY" { print $1 }' | head -n1)
[[ -n $part ]] || { echo "no key partition; run provisioning-stick.sh first" >&2; exit 1; }

step "mount the whole disk, as the installer does"
if mount -o ro "$loop" "$work/iso" 2>/dev/null; then
    pass "$loop mounted — the whole disk is now claimed exclusively"
else
    fail "could not mount the whole disk; the rest of this test is meaningless"
    finish
fi

step "mounting the key partition must now fail"
if mount -o ro "$part" "$work/mnt" 2>/dev/null; then
    fail "the partition mounted — this kernel does not reproduce the condition,
        so this test proves nothing today. fleet-install still uses mtools."
    umount "$work/mnt" 2>/dev/null
else
    pass "refused, as on the laptop (\"can't open blockdev\")"
fi

step "mtools reads it anyway"
if MTOOLS_SKIP_CHECK=1 "$mcopy" -n -i "$part" ::fleet-admin-key.txt "$work/out" 2>/dev/null &&
    [[ -s $work/out ]]; then
    same_file "$work/out" "$key" "key read byte-identical to .admin-key"
else
    fail "mtools could not read the key — fleet-install would fail on a real stick"
fi

finish
