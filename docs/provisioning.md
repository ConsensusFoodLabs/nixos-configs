# Provisioning a laptop

**Status: not yet executed end to end.** No machine has been installed with
this procedure. Expect it to need corrections after the first run; correct it
rather than working around it.

What *has* been verified, on a loop device rather than hardware:
`fleet-mkstick` adds the key partition to the image without breaking its boot
signature, the key reads back byte-identical, `fleet-wipe-key` removes it, and
`--key-only` re-arms the stick. What has not: whether this laptop's firmware
boots a stick whose partition table has been appended to, and everything from
step 4 onwards.

Target hardware for the first machines: ThinkPad X1 Carbon Gen 14 (Core Ultra 5
325 / Panther Lake, 32 GB LPDDR5X, 256 GB SSD, Intel BE211 Wi-Fi 7, Synaptics
fingerprint reader).

## How this works

One generic installer image provisions every machine in the fleet (D26). It
carries no secrets and nothing host-specific: the machine's configuration
*and* its credentials are fetched from this repository at install time.

Per-machine credentials live encrypted in `fleet/secrets/`, in this public
repository (D24). They are decrypted during installation with an administrator
age key held on removable media — the one artifact that is neither in the
image nor in the repository, and without which an installer stick can do
nothing (D25).

`fleet-mkstick` puts both on one stick — the image in the usual place, the key
in a partition of its own. Two separate sticks work equally well, and are the
fallback if a stick or a firmware dislikes the appended partition.

## Before you start

- The machine's entry exists in `fleet/inventory.nix`, merged to `main`. The
  configuration is generated from the inventory (D3); a device that is not in
  it has nothing to build.
- Its secrets exist in `fleet/secrets/<host>.yaml`, merged to `main`:

      nix run .#fleet-mksecrets -- <host>

- A provisioning stick: the installer image *and* your administrator key, made
  with `fleet-mkstick` (step 1). Two separate sticks also work — `fleet-install`
  searches removable media for `fleet-admin-key.txt` or `.admin-key`, and
  `--identity` names one explicitly.

### One-time: create an administrator key

If `.sops.yaml` still contains the placeholder recipient, no administrator key
exists yet. Generate one onto removable media — not onto a laptop's disk:

    age-keygen -o /run/media/$USER/<stick>/fleet-admin-key.txt

Put the printed public key in `.sops.yaml`, and back the identity up offline in
more than one place.

Then link it in, once, on each workstation you use:

    ln -s /run/media/$USER/<stick>/fleet-admin-key.txt .admin-key
    direnv allow        # if you use direnv

`.admin-key` at the repository root is how everything here refers to your
identity: `fleet-mksecrets` uses it, and `.envrc` points `sops` at it so plain
`sops decrypt` works anywhere in the repository. It is gitignored, it is
normally a symlink, and each administrator decides what is behind it — the
repository never learns where anyone keeps their key. The pre-commit hook
refuses it by path, because as a symlink git would store only the link target
and the secret scanner would see nothing wrong.

Without it, `sops` falls back to its own default (`~/.config/sops/age/keys.txt`)
and behaviour differs between machines for no reason.

Losing every administrator identity means losing every machine's recovery key,
with no way to regenerate it from anything in this repository. That is the
trade for the installer image and this repository both being non-sensitive.

## 1. Build the provisioning stick

Images are built locally; there is no CI (D8).

    git -C nixos-configs status          # must be clean
    git -C nixos-configs push            # the revision must exist upstream
    nix build .#installer-iso
    nix build .#fleet-mkstick -o result-mkstick
    sudo ./result-mkstick/bin/fleet-mkstick /dev/sdX

Build only from a committed, pushed revision. A system built from a dirty tree
reports its revision as `dirty` and cannot be traced to a source state.

`fleet-mkstick` writes the image, then appends a partition holding your
administrator key, with the filesystem label `FLEETKEY`. It asks you to type
the device path before it writes anything.

Expect it to land as the *third* partition. The image is an isohybrid: a
DOS/MBR table whose first partition spans the whole image, with the EFI
partition nested inside it, so the key partition is appended after both (D29).

If it cannot append one — no free space, or a stick that objects — carry the
key on a second stick instead. Nothing else changes: `fleet-install` searches
every removable partition for `fleet-admin-key.txt` or `.admin-key`.

The key goes on the **stick**, never into the **image**. The image lives in the
nix store, which is world-readable and may be copied to a binary cache; a
private key put there could not be unpublished. Keeping them apart is what lets
the image be built once, reused for every machine, and shared freely (D29).

You only need the image step again when the image itself changes. To re-arm a
stick whose key partition was wiped:

    sudo ./result-mkstick/bin/fleet-mkstick /dev/sdX --key-only

### The stick is now sensitive

It holds an identity that decrypts every machine's recovery key. Carry it as
you would the key itself.

## 2. Firmware settings

- Secure Boot: **off** for now. NixOS Secure Boot support requires additional
  tooling (lanzaboote) that is not part of this configuration.
- Boot from the USB stick.

## 3. Network

    nmtui

These laptops have no Ethernet port, and every remaining step needs the
network.

## 4. Check, then install

The key is already on the stick you booted from. If you are using two sticks,
plug the key one in now. Then:

    fleet-install --check --host <host>

This fetches the repository, resolves the configuration, finds your key and
decrypts the machine's secrets — and stops before touching the disk. Do it
first; every way this can fail cheaply, it fails here.

Then:

    fleet-install --host <host>

It will show you `lsblk` and ask you to type the target device path. This is
the only prompt, and the only irreversible step. Confirm it is the internal
drive and not the installer stick. If more than one NVMe is listed, stop and
fix the declaration rather than improvising (D13 keeps hardware identifiers
out of the inventory, so the device name is checked by hand rather than
trusted).

From there it runs unattended: partition, encrypt, enrol both keyslots, verify
both keyslots, write the account password hash, and install NixOS from the
same pinned revision it started with.

Omit `--host` and it will list the machines in the inventory and let you pick.

### What it does about keys

Both LUKS keyslots are declared in `hosts/<model>/disko.nix` and written by
disko: the developer passphrase from `passwordFile`, the organization's
recovery key from `additionalKeyFiles`. Both are tested before the install
proceeds, and the run aborts if either fails — an escrow key that was never
tested is not escrow.

**Confirm on the first install** that the developer passphrase landed in
keyslot 0 and the recovery key did not. `luksDump` will not tell you — it shows
both slots identically — so test the slot directly, on the running machine:

    # succeeds with the developer passphrase
    sudo cryptsetup open --test-passphrase --key-slot 0 /dev/disk/by-partlabel/disk-main-luks

    # must FAIL with the recovery key
    sudo cryptsetup open --test-passphrase --key-slot 0 /dev/disk/by-partlabel/disk-main-luks

`fleet-passphrase` refuses to write any slot but 0, and that is what stops a
developer from overwriting the organization's recovery key. The protection
assumes this ordering. If it is reversed, fix it before the machine ships.

The key material is written to a tmpfs under `/run/fleet-provision` for the
length of the run and shredded on exit, success or failure. It never reaches a
disk in plaintext.

## 5. Verify before handing the machine over

    fleet-status                  # revision, upstream lag, profile contents
    nixos-version --json          # configurationRevision must be a real commit, not "dirty"
    ip link                       # wlan interface present
    dmesg | grep -i iwlwifi       # firmware loaded, no errors
    systemctl --failed
    lsblk                         # the LUKS layout matches the declaration

Log in as the account, then reboot once more and confirm the machine unlocks
with the passphrase `fleet-install` printed — and separately that it unlocks
with the recovery key. `fleet-install` tested both keyslots with `cryptsetup`,
which is not the same as proving the machine boots from them.

Wi-Fi is the one that matters most: these machines have no Ethernet port, and a
laptop that cannot reach the network cannot pull its own fix (D10). If
`iwlwifi` has not loaded firmware, stop and fix it before the machine leaves.

## 6. Hand over

Give the developer the passphrase and password `fleet-install` printed, and
tell them to change both on first login:

    fleet-passwd        # login password
    fleet-passphrase    # disk passphrase

Both are initial credentials (D27). Neither tool can touch the recovery
keyslot, so the organization keeps its access whatever the developer chooses.

## 7. Wipe the key partition

**Manual, and deliberately not automatic (D29).** Provisioning is still being
proven, and a run that wiped its own key would have to be re-armed before every
retry.

When you are finished with the stick — not between attempts, but before it goes
back in a drawer:

    sudo fleet-wipe-key /dev/sdX                      # from the installer
    sudo ./result-wk/bin/fleet-wipe-key /dev/sdX      # from a workstation,
                                                      # after: nix build .#fleet-wipe-key -o result-wk

It refuses anything that is not recognisably key media, and leaves an empty
`FLEETKEY` partition behind so the stick stays usable.

What this does and does not achieve: on flash, overwriting does not guarantee
erasure. Wear levelling means the controller may retain copies in blocks no
command can address. `fleet-wipe-key` asks the controller to discard the range,
which is the best available answer, but treat a stick that has held a key as
having held it. The durable controls are a dedicated stick and the ability to
rotate the key (D25).

## 8. Record it

- Asset register (private, not this repository): hostname, serial, purchase and
  warranty details, who holds it.

The asset register and this repository join on hostname (D13). The recovery key
does not need recording anywhere: it is in `fleet/secrets/<host>.yaml`, and the
git history says when it was created.

## Rotating a machine's secrets

    nix run .#fleet-mksecrets -- <host> --rotate

This changes what the *next* install uses. A machine already in the field keeps
the keyslots it was built with — rotation is not revocation. To make it real on
an existing machine you must reinstall it, or remove the old keyslots by hand
with `cryptsetup luksKillSlot`, having first enrolled the new ones.

## Afterwards

The machine updates itself from `main`; see `docs/operations.md`.
