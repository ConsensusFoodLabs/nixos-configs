# Operating a laptop

**Status: draft.** Describes intended procedure; the configuration and the
`fleet-status` script do not exist yet.

## Updating

    sudo nixos-rebuild switch --flake git+https://github.com/ConsensusFoodLabs/nixos-configs#$(hostname)

Laptops currently track `main`, so an update picks up whatever has been merged
(D6). There is no automatic update timer — updates are something a person runs.

The flake reference is deliberately kept in one place so that switching to a
release branch or a self-hosted mirror later is a one-line change (D7).

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
2. If the LUKS passphrase is the problem, the machine's recovery key unlocks it
   (D5) — held offline, per machine.
3. If networking is broken in every generation, the office has a USB-C Ethernet
   adapter (D19).
4. Reinstall from `docs/provisioning.md`. The machine's configuration is in the
   repository, so this loses local state, not configuration.
