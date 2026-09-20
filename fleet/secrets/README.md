# Per-machine provisioning secrets

One file per machine, named after its hostname, holding the credentials that
machine is installed with:

| key | what it is |
| --- | --- |
| `luks_passphrase` | the disk passphrase the machine ships with; the developer replaces it with `fleet-passphrase` |
| `luks_recovery_key` | the organization's standing access to the disk. Not initial, does not expire (D5) |
| `admin_password` | password for the shared `admin` account — sudo and console. Not initial: it stays as issued (D32) |
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

    SOPS_AGE_KEY_FILE=$PWD/.admin-key sops decrypt fleet/secrets/<hostname>.yaml

Or one value at a time, which is usually what you want — there is no reason to
put the whole file on your screen to read one recovery key:

    SOPS_AGE_KEY_FILE=$PWD/.admin-key \
      sops decrypt --extract '["luks_recovery_key"]' fleet/secrets/<hostname>.yaml

Set `SOPS_AGE_KEY_FILE` explicitly, or `sops` searches its own default
locations (`~/.config/sops/age/keys.txt`, your SSH keys) and fails with a long
list of places it looked, none of which is `.admin-key`. If you use direnv,
`.envrc` exports it for you and you can drop the prefix — but direnv is not a
dependency of this repository, so the commands here spell it out.

`fleet-install` handles this itself during provisioning; you should rarely need
to read these by hand.

## Adding a field to an existing machine

When a new secret is introduced, a machine provisioned before it exists has a
file without that field:

    nix run .#fleet-mksecrets -- <hostname> --add-missing

Every value already present is carried across byte for byte; only absent ones
are generated. It prints which it kept and which it added.

Use this, never `--rotate`, for a machine already in service. `--rotate` would
replace `luks_recovery_key` too, and that key is enrolled on a real disk (D31).

## Rotating them

    nix run .#fleet-mksecrets -- <hostname> --rotate

This changes the file only. For a machine already in service it leaves the
repository holding a recovery key that **does not open that disk** — escrow you
believe you have and do not.

Finish the job on the machine:

    sudo fleet-rotate-recovery

which enrols the new key, tests it, and only then removes the old one. Full
procedure, and when rotating is worth doing at all, in
`docs/provisioning.md`.

## What is not here

The private age identities that decrypt these files. Those are held by fleet
administrators on removable media and exist nowhere in this repository or in
the installer image — which is what makes both of those non-sensitive (D25).
