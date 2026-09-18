# Per-machine provisioning secrets

One file per machine, named after its hostname, holding the credentials that
machine is installed with:

| key | what it is |
| --- | --- |
| `luks_passphrase` | the disk passphrase the machine ships with; the developer replaces it with `fleet-passphrase` |
| `luks_recovery_key` | the organization's standing access to the disk. Not initial, does not expire (D5) |
| `user_initial_password` | the login password the machine ships with; the developer replaces it with `fleet-passwd` |

These are encrypted with [sops](https://github.com/getsops/sops) to the age
recipients listed in `.sops.yaml` at the repository root, and are safe in this
public repository *for exactly as long as that stays true*. A pre-commit hook
refuses any `.yaml` here that is not encrypted.

## Creating them

On an administrator workstation, in a checkout of this repository:

    nix run .#fleet-mksecrets -- <hostname>

The host must already exist in `fleet/inventory.nix`. Commit the result and
open a PR like any other change — the git history is the audit trail for when
each machine's key material was created or rotated (D24).

## Reading them

    sops decrypt fleet/secrets/<hostname>.yaml

Requires an administrator age identity. `fleet-install` does this itself
during provisioning; you should rarely need to.

## Rotating them

    nix run .#fleet-mksecrets -- <hostname> --rotate

Rotation changes what the *next* install uses. It does nothing to a machine
already in the field: that machine keeps the keyslots it was built with, and
removing the old ones is a physical task. See `docs/provisioning.md`.

## What is not here

The private age identities that decrypt these files. Those are held by fleet
administrators on removable media and exist nowhere in this repository or in
the installer image — which is what makes both of those non-sensitive (D25).
