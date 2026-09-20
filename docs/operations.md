# Operating a laptop

**Status: draft.** Describes intended procedure. No machine has been
provisioned yet, so none of it has been exercised on real hardware.

## Updating

    fleet-update

No `sudo`, and no arguments to remember or mistype. Laptops currently track
`main`, so an update picks up whatever has been merged (D6). There is no
automatic update timer — updates are something a person runs.

It needs no administrator rights: most people holding a laptop are not in
`wheel` (D12), and a fleet only administrators can update is a fleet that does
not get updated. The owner is allowed to run one fixed program as root, which
takes no arguments — see D30 for why that detail matters.

The equivalent by hand, if you are an administrator and want to see it —
note `--refresh`:

    sudo nixos-rebuild switch --refresh \
      --flake git+https://github.com/ConsensusFoodLabs/nixos-configs#$(hostname)

**Without `--refresh` you may quietly rebuild an old revision.** Nix caches the
resolution of a `git+https` flake reference for `tarball-ttl`, one hour by
default, so a rebuild shortly after a merge can reuse what it resolved last
time and report success having changed nothing. `fleet-update` always passes
it. If a rebuild appears to have done nothing, check `fleet-status`: it
compares the running revision against `git ls-remote`, which is not cached.

The flake reference lives in one place — `fleet.repoUrl` in
`modules/fleet/default.nix` — so switching to a release branch or a
self-hosted mirror later is a one-line change (D7).

## Changing your credentials

Your laptop shipped with a generated disk passphrase and login password. They
are *initial* credentials — the ones from `fleet/secrets/<host>.yaml` — and you
should replace both on your first day (D27):

    fleet-passwd        # login password
    fleet-passphrase    # disk passphrase

Use these rather than `passwd` and `cryptsetup` directly. `passwd` alone works
until the next `nixos-rebuild`, which then silently restores the old password:
accounts are declared with `users.mutableUsers = false`, so the file on disk is
the source of truth and `fleet-passwd` is what updates it.

Neither tool needs administrator rights, and neither can alter the recovery
keyslot. The organization keeps its access to the disk whatever you choose, so
nobody needs to know your passphrase.

## Rollback

A bad update is recoverable without network access, which matters on machines
with no Ethernet port:

- Reboot and pick the previous generation from the boot menu, **or**
- `sudo nixos-rebuild switch --rollback`

Generations are pruned on a schedule, but retention has a deliberate floor so
that a known-good generation is always available (D18). If you are tuning
garbage collection to reclaim disk space, do not lower that floor — it is the
recovery mechanism, not housekeeping.

## Checking what a machine is running

    nixos-version --json     # includes configurationRevision
    fleet-status             # revision, lag behind main, user profile contents

`configurationRevision` is the git revision the running system was built from
(D17). A value of `dirty` means the system was built from an uncommitted working
tree and cannot be traced to a source state — treat that as something to fix,
not a curiosity.

`fleet-status` is a debugging aid, not monitoring. Nothing collects it centrally
and nobody reviews it on a schedule, so it must not be described as a detective
control. It becomes one when central collection exists.

## Administrator access to a machine

Every machine carries a shared `admin` account, in `wheel`, with the SSH public
keys of every active administrator (D32):

    ssh -i ~/.ssh/fleet-admin-<name> admin@<machine>

Key-only — password and keyboard-interactive authentication are off, and root
login is refused. The `admin` password, in `fleet/secrets/<host>.yaml`, is for
`sudo` and console login.

This exists so a machine can be reached when its owner cannot help: someone on
leave, a laptop that boots but has a broken desktop, a departure. It is not a
substitute for asking the owner.

### If sudo rejects the admin password

On a machine provisioned before the admin account existed,
`/var/lib/fleet/admin.passwd` was never written. NixOS warns once at activation
and leaves the account locked, so SSH keys still work and `sudo` rejects a
password that is definitely correct.

    fleet-status                       # shows which accounts are missing one
    sudo fleet-set-password admin      # prompts, writes the file, applies it

It takes effect immediately — no rebuild needed. The same applies to any
account added to a fleet that already exists.

**It is a listening service on a laptop that travels.** Port 22 is open on
whatever network the machine is on, including untrusted ones. Key-only
authentication is what makes that acceptable rather than reckless; see D32 for
what is and is not mitigated.

## Installing software

Install what you need, when you need it. The declared baseline is what every
machine gets by default; it is not a restriction on what you may run. See
`docs/software-policy.md`.

If something is broadly useful, add it to the shared configuration by pull
request so everyone gets it rather than each person rediscovering it.

## Break-glass: urgent out-of-band changes

Sometimes you need a change on your machine now, and waiting for review is not
viable — a broken toolchain in the middle of an incident, say.

**The policy, in full:** make the change locally. Reconcile it back into this
repository by pull request afterwards, promptly — same week, not eventually. If
the change should apply only to your machine, it belongs in `users/<name>/`; if
it should apply to everyone, it belongs in the shared configuration and needs
the tighter review.

There is no approval form and no ticket to file (D16).

**Why reconciling matters:** a machine running an out-of-band configuration is
no longer described by this repository, and "the repository describes the
fleet" is the claim everything else rests on. An unreconciled local change is
not a rule violation so much as a quiet hole in that claim.

Security-relevant settings are the exception: do not disable disk encryption,
firewall, screen locking or audit settings locally. If one of those is blocking
you, that is a conversation, not a local edit.

## When a machine will not boot

1. Previous generation from the boot menu (above).
2. If the LUKS passphrase is the problem, the machine's recovery key unlocks
   it. Ask an administrator: it is in `fleet/secrets/<host>.yaml`, encrypted,
   and an administrator reads it, from a checkout of this repository, with

       SOPS_AGE_KEY_FILE=$PWD/.admin-key \
         sops decrypt --extract '["luks_recovery_key"]' fleet/secrets/<host>.yaml

   (D5, D24). One key per machine, and it is unaffected by anything you did
   with `fleet-passphrase`.
3. If networking is broken in every generation, the office has a USB-C Ethernet
   adapter (D19).
4. Reinstall from `docs/provisioning.md`. The machine's configuration is in the
   repository, so this loses local state, not configuration.
