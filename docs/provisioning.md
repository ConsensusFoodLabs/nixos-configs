# Provisioning a laptop

**Status: draft.** The configuration this describes does not exist yet. Steps
marked **[verify]** have not been executed end to end and should be confirmed
against current disko documentation before being relied on.

Target hardware for the first machines: ThinkPad X1 Carbon Gen 14 (Core Ultra 5
325 / Panther Lake, 32 GB LPDDR5X, 256 GB SSD, Intel BE211 Wi-Fi 7, Synaptics
fingerprint reader).

## Before you start

- A USB stick for the installer image.
- Somewhere offline to record this machine's recovery key (D5). Have it ready
  *before* you install — the key is generated during installation and there is
  no second chance to capture it.
- The machine's entry must already exist in `fleet/inventory.nix`, merged to
  `main`. The configuration is generated from the inventory (D3), so a device
  that is not in it has nothing to build.

## 1. Build the installer image

Images are built locally; there is no CI (D8).

    git -C nixos-configs status          # must be clean
    git -C nixos-configs push            # the revision must exist upstream
    nix build .#installer-iso

One image installs any machine in the fleet — nothing host-specific is baked
in, because the machine's real configuration is fetched from this repository
during installation. The image carries `cryptsetup`, `mkpasswd`, git and
NetworkManager, which is everything the steps below need.

Build only from a committed, pushed revision. A system built from a dirty tree
reports its revision as `dirty` and cannot be traced to a source state.

Write it to the stick with `dd` or equivalent, then connect it to Wi-Fi once
booted (`nmtui`).

## 2. Firmware settings

- Secure Boot: **off** for now. NixOS Secure Boot support requires additional
  tooling (lanzaboote) that is not part of this configuration.
- Boot from the USB stick.

## 3. Confirm the target disk

`hosts/<model>/disko.nix` names the disk as `/dev/nvme0n1`. That is a
kernel-assigned name, and the next step **destroys whatever is at it**. Confirm
it is the machine's internal drive and that nothing else could be claiming the
name:

    lsblk -o NAME,SIZE,TYPE,MODEL,TRAN

Expect exactly one internal NVMe device, of the expected size, plus the USB
installer. If there is more than one NVMe, or the internal drive is not
`nvme0n1`, stop: fix the declaration rather than improvising, because the
mismatch will be silent and destructive.

After this step device names stop mattering — disko labels the partitions it
creates and everything mounts by partition label, so no machine-specific UUIDs
or device paths end up in the configuration.

## 4. Partition and encrypt

Disk layout, including LUKS, is declared with disko and applied from the
installer:

    sudo nix run github:nix-community/disko -- --mode disko \
        --flake git+https://github.com/ConsensusFoodLabs/nixos-configs#<host>

This will prompt for the LUKS passphrase, which becomes the developer's boot
passphrase. Unlock is passphrase-only; no TPM enrollment (D4).

**[verify]** How much of keyslot setup disko manages declaratively versus what
must be done by hand — in particular whether the escrow keyslot in step 4 can be
declared or must be added manually after installation.

## 5. Enrol the recovery key

Every machine gets a second LUKS keyslot holding an organization-held recovery
key, unique to that machine (D5).

    # generate a strong random key and add it to a second keyslot
    cryptsetup luksAddKey /dev/<device>

Record it offline, against this machine's hostname. It does not go in this
repository, a password-sharing channel, or a ticket. It does not expire.

Verify the slot works before leaving the installer — an escrow key that was
never tested is not escrow:

    cryptsetup luksOpen --test-passphrase /dev/<device>

## 6. Set the account password hash

Accounts are declared with `users.mutableUsers = false`, so the password comes
from a file on the machine rather than from the repository — a public repo is
no place for a password hash, and secrets tooling does not exist yet (D1, D21).

Create it **before** installing, or the machine boots with no way to log in:

    mkdir -p /mnt/var/lib/fleet
    mkpasswd -m yescrypt > /mnt/var/lib/fleet/<user>.passwd
    chmod 0600 /mnt/var/lib/fleet/<user>.passwd

The filename must match the account name exactly (the account is named after
the person's corporate username — D11).

## 7. Install

    sudo nixos-install --no-root-passwd \
        --flake git+https://github.com/ConsensusFoodLabs/nixos-configs#<host>

Root has no password by design; administrators use `sudo` via `wheel`, which is
granted in the inventory (D12). Reboot and remove the stick.

## 8. Verify before handing the machine over

    fleet-status                  # revision, upstream lag, profile contents
    nixos-version --json          # configurationRevision must be a real commit, not "dirty"
    ip link                       # wlan interface present
    dmesg | grep -i iwlwifi       # firmware loaded, no errors
    systemctl --failed
    lsblk                         # confirm the LUKS layout matches the declaration

Log in as the account before handing the machine over. A missing or
wrongly-named password hash file (step 6) produces an account that cannot log
in, and it is much easier to fix from the installer than afterwards.

Then reboot once more and confirm the machine unlocks with the developer
passphrase, and separately that it unlocks with the recovery key.

Wi-Fi is the one that matters most: these machines have no Ethernet port, and a
laptop that cannot reach the network cannot pull its own fix (D10). If `iwlwifi`
has not loaded firmware, stop and fix it before the machine leaves.

## 9. Record it

- Asset register (private, not this repository): hostname, serial, purchase and
  warranty details, who holds it.
- Offline recovery key store: hostname and its key.

The asset register and this repository join on hostname (D13).

## Afterwards

The machine updates itself from `main`; see `docs/operations.md`.
