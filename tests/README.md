# Tests

Scripts written because each one caught a real bug, or guards a step that runs
with nobody watching. They are run by hand — there is no CI (D8) — and each one
takes about a minute.

They touch no hardware: everything happens inside loop devices backed by files
in `/tmp`. They do need root, for `losetup`, `mount` and `cryptsetup`.

## Running them

Build what they exercise first, so that nothing has to run `nix` as root:

    nix build .#installer-iso
    nix build .#fleet-mkstick -o result-mkstick
    nix build .#fleet-wipe-key -o result-wk
    nix build nixpkgs#mtools -o result-mtools
    nix build nixpkgs#dosfstools -o result-dosfstools

Then:

    sudo ./tests/luks-keyslots.sh
    sudo ./tests/provisioning-stick.sh
    sudo ./tests/whole-disk-claim.sh
    sudo ./tests/recovery-rotation.sh
    sudo ./tests/key-wipe.sh

Every check prints `PASS` or `FAIL`; the exit status is non-zero if anything
failed.

## What each one is for

### `luks-keyslots.sh`

That a developer rotating their disk passphrase cannot disturb the
organization's recovery key (D5, D27).

`fleet-passphrase` writes keyslot 0 only and refuses unless the passphrase
given opens keyslot 0. This builds a throwaway LUKS container with a
passphrase in slot 0 and a recovery key in slot 1, performs the same
`luksChangeKey` that tool performs, and checks the recovery key still works
afterwards.

Run this whenever `fleet-credentials.nix` or `disko.nix` changes. It is the
only check of that property, and the property is the reason the organization
can still open a returned laptop.

It also pins the argument form. `cryptsetup luksChangeKey` takes the new key
as a *positional argument*; `--new-keyfile` belongs to `luksAddKey` and fails
here. That cost a round trip on real hardware.

### `provisioning-stick.sh`

That `fleet-mkstick` produces a bootable stick and never writes inside the
image.

Covers the full lifecycle — write, read the key back, wipe with
`fleet-wipe-key`, re-arm with `--key-only` — plus the two failures that
destroyed sticks:

  - Writing a second, larger image over a stick that already had a key
    partition. The kernel does not re-read the partition table after `dd`, so
    the stale partition could be formatted inside the new image.
  - Identifying the appended partition by diffing the partition list, which
    could name partition 1 — the image itself.

### `whole-disk-claim.sh`

That `fleet-install` can read the administrator key off the stick it booted
from.

An isohybrid's first partition starts at sector 0, so the installer mounts
`/dev/sda` rather than `/dev/sda1`, and a mounted whole disk is claimed
exclusively — no partition on it can be mounted. This reproduces that state
and checks `mtools` reads the key anyway.

This one cannot be caught by building a stick and reading it back; it only
appears when running *from* the stick.

### `key-wipe.sh`

`fleet-install` wipes the administrator key after a successful install (D39),
so `fleet-wipe-key` now runs with `--yes` and nobody at the keyboard. The typed
confirmation used to be the last thing between a mistake and a destroyed
partition; these checks cover what is left.

The one that matters is the second: a FAT partition that is neither labelled
`FLEETKEY` nor holds a key file must be refused **even with `--yes`**, and the
files on it must still be there afterwards. `--yes` is allowed to skip the
question, not to widen what the tool will destroy.
