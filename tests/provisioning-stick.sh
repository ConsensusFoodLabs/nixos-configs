#!/usr/bin/env bash
#
# fleet-mkstick must produce a bootable stick and must never write inside the
# installer image.
#
# Two failures destroyed real sticks during the first provisioning run, and
# both are checked here:
#
#   - Writing a second, larger image over a stick that already had a key
#     partition. dd does not make the kernel re-read the partition table, so
#     the stale partition was formatted inside the new image.
#   - Identifying the appended partition by diffing the partition list, which
#     named partition 1 -- the image itself.

cd "$(dirname "$0")" || exit 1
# shellcheck source=tests/lib.sh
. ./lib.sh
need_root

mkstick=$(need_built ../result-mkstick/bin/fleet-mkstick "nix build .#fleet-mkstick -o result-mkstick") || exit 1
wipekey=$(need_built ../result-wk/bin/fleet-wipe-key "nix build .#fleet-wipe-key -o result-wk") || exit 1
shopt -s nullglob
isos=(../result/iso/*.iso)
shopt -u nullglob
((${#isos[@]} == 1)) || {
    echo "expected exactly one image in ./result/iso/" >&2
    echo "build it first:  nix build .#installer-iso" >&2
    exit 1
}
iso=${isos[0]}
key=../.admin-key
[[ -e $key ]] || { echo "no .admin-key; link your identity in first" >&2; exit 1; }

iso_sectors=$(($(stat -c%s "$iso") / 512))
work=$(mktemp -d)
img=$work/stick.img
loop=""
cleanup() {
    umount "$work/mnt" 2>/dev/null
    [[ -n $loop ]] && losetup -d "$loop" 2>/dev/null
    rm -rf "$work"
    true
}
trap cleanup EXIT
mkdir -p "$work/mnt"

truncate -s $(($(stat -c%s "$iso") + 512 * 1024 * 1024)) "$img"
loop=$(losetup -fP --show "$img")

key_partition() {
    lsblk -rno PATH,LABEL "$loop" | awk '$2 == "FLEETKEY" { print $1 }' | head -n1
}
start_of() { cat "/sys/class/block/$(basename "$(readlink -f "$1")")/start"; }

step "writing a stick"
echo "$loop" | "$mkstick" "$loop" --iso "$iso" >/dev/null 2>&1 || fail "fleet-mkstick failed"
p=$(key_partition)
if [[ -n $p ]]; then pass "a FLEETKEY partition exists ($p)"; else fail "no FLEETKEY partition"; fi

step "the key partition is outside the image"
if [[ -n $p ]] && (($(start_of "$p") >= iso_sectors)); then
    pass "starts at sector $(start_of "$p"), image ends at $iso_sectors"
else
    fail "key partition overlaps the image"
fi
if [[ $p != "${loop}p1" ]]; then
    pass "partition 1 was not chosen as the key partition"
else
    fail "partition 1 was chosen — this is what destroyed a stick"
fi

step "the key reads back"
if mount -o ro "$p" "$work/mnt" 2>/dev/null; then
    same_file "$key" "$work/mnt/fleet-admin-key.txt" "matches .admin-key"
    umount "$work/mnt" 2>/dev/null
else
    fail "could not mount the key partition"
fi

step "the image is intact and still looks bootable"
if file -s "$loop" | grep -qiE "ISO 9660|DOS/MBR"; then
    pass "boot signature survived adding the partition"
else
    fail "boot signature gone: $(file -s "$loop")"
fi

step "writing the same stick a second time"
# The case that corrupted a stick: the second write is a different size, and
# the stale key partition from the first run is still in the kernel's table.
out=$(echo "$loop" | "$mkstick" "$loop" --iso "$iso" 2>&1)
if grep -q "image on the stick matches" <<<"$out"; then
    pass "image verifies after a second write"
else
    fail "image did not verify after a second write"
    tail -3 <<<"$out" | sed 's/^/    /'
fi
p=$(key_partition)
if [[ -n $p ]] && (($(start_of "$p") >= iso_sectors)); then
    pass "key partition still outside the image"
else
    fail "second write put the key partition inside the image"
fi

step "wiping the key"
echo "$p" | "$wipekey" "$loop" >/dev/null 2>&1
if mount -o ro "$p" "$work/mnt" 2>/dev/null; then
    if [[ -e $work/mnt/fleet-admin-key.txt ]]; then
        fail "key survived the wipe"
    else
        pass "key gone"
    fi
    umount "$work/mnt" 2>/dev/null
else
    fail "could not mount the wiped partition"
fi

step "re-arming with --key-only"
echo "$loop" | "$mkstick" "$loop" --key-only >/dev/null 2>&1
if mount -o ro "$(key_partition)" "$work/mnt" 2>/dev/null; then
    same_file "$key" "$work/mnt/fleet-admin-key.txt" "key restored without rewriting the image"
    umount "$work/mnt" 2>/dev/null
else
    fail "could not mount the re-armed partition"
fi

finish
