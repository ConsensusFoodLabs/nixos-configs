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
    nix build .#nixosConfigurations.<host>.config.system.build.isoImage

Build only from a committed, pushed revision. A system built from a dirty tree
reports its revision as `dirty` and cannot be traced to a source state.

Write it to the stick with `dd` or equivalent.

## 2. Firmware settings

- Secure Boot: **off** for now. NixOS Secure Boot support requires additional
  tooling (lanzaboote) that is not part of this configuration.
- Boot from the USB stick.

## 3. Partition and encrypt

Disk layout, including LUKS, is declared with disko and applied from the
installer:

    sudo nix run github:nix-community/disko -- --mode disko \
        --flake git+https://github.com/ConsensusFoodLabs/nixos-configs#<host>

This will prompt for the LUKS passphrase, which becomes the developer's boot
passphrase. Unlock is passphrase-only; no TPM enrollment (D4).

**[verify]** How much of keyslot setup disko manages declaratively versus what
must be done by hand — in particular whether the escrow keyslot in step 4 can be
declared or must be added manually after installation.

## 4. Enrol the recovery key

Every machine gets a second LUKS keyslot holding an organization-held recovery
key, unique to that machine (D5).

    # generate a strong random key and add it to a second keyslot
    cryptsetup luksAddKey /dev/<device>

Record it offline, against this machine's hostname. It does not go in this
repository, a password-sharing channel, or a ticket. It does not expire.

Verify the slot works before leaving the installer — an escrow key that was
never tested is not escrow:

    cryptsetup luksOpen --test-passphrase /dev/<device>

## 5. Install

    sudo nixos-install --flake git+https://github.com/ConsensusFoodLabs/nixos-configs#<host>

Set the initial user password when prompted, reboot, remove the stick.

## 6. Verify before handing the machine over

    nixos-version --json          # configurationRevision must be a real commit, not "dirty"
    ip link                       # wlan interface present
    dmesg | grep -i iwlwifi       # firmware loaded, no errors
    systemctl --failed
    lsblk                         # confirm the LUKS layout matches the declaration

Then reboot once more and confirm the machine unlocks with the developer
passphrase, and separately that it unlocks with the recovery key.

Wi-Fi is the one that matters most: these machines have no Ethernet port, and a
laptop that cannot reach the network cannot pull its own fix (D10). If `iwlwifi`
has not loaded firmware, stop and fix it before the machine leaves.

## 7. Record it

- Asset register (private, not this repository): hostname, serial, purchase and
  warranty details, who holds it.
- Offline recovery key store: hostname and its key.

The asset register and this repository join on hostname (D13).

## Afterwards

The machine updates itself from `main`; see `docs/operations.md`.
