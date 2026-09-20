# Access control

**Status: draft.** Describes the intended model; the configuration does not
exist yet.

## Identity

Each laptop has one account, named after the person's corporate username —
`oleg`, not a generic `user` (D11). Shared modules refer to it through a
`fleet.user`-style option rather than hardcoding a name.

This means `sudo`, `journald` and auth logs on every machine name a person
directly, without needing a hostname-to-person lookup to interpret them.

## Source of truth

`fleet/inventory.nix` declares people and devices, and everything derives from
it (D13): which accounts exist, who holds administrator rights, which
home-manager configuration is applied, and which `nixosConfigurations` outputs
exist at all (D3).

    people.<name>   = { fullName; email; admin; active; }
    devices.<host>  = { model; assignedTo; profile; }

No hardware serials — those live in the private asset register, joined to this
repository by hostname.

## Privilege

Administrator rights (`wheel`, and therefore `sudo`) are a per-person setting,
but the *assignment* lives in a base-owned file under tight CODEOWNERS review —
never in `users/<name>/` (D12).

The reason is structural: if a developer could grant themselves `wheel` in their
own lightly-reviewed file, the light-review path would become the
highest-privilege path in the repository. Granting root must require the tighter
approver group, and it must be legible in git history, because that history is
the access-control evidence.

### What a non-administrator can do as root

Two things, each a single fixed program reached through a narrow `sudo` rule:
change their own credentials (`fleet-passwd`, `fleet-passphrase`) and apply the
fleet configuration (`fleet-update`). None of them takes arguments from the
caller.

That last one means the tracked branch decides what runs as root on every
laptop, which is the intended model — and the reason review of that branch is
the control that matters, not the `sudo` rule (D23, D30).

### The shared admin account

Every machine ships with an `admin` account in `wheel`, carrying the SSH public
keys of every person in the inventory with `admin = true` and `active = true`
(D32). Being an administrator and being able to SSH into every laptop are
therefore the same fact, expressed once — there is no second list to drift out
of step with the first.

Its password lives in each machine's `fleet/secrets/<host>.yaml`, so it differs
per machine. Unlike the owner's, it is not an initial credential: it stays as
issued.

The account is **not** gated on the owner being active. A machine whose owner
has left is precisely a machine an administrator still needs to reach.

### The administrator age key

Holding an administrator age identity is a distinct and higher privilege from
holding `wheel` on a laptop. It decrypts `fleet/secrets/`, which means it grants
the ability to unlock **every machine in the fleet**, including ones the holder
was never assigned (D25).

It is therefore not implied by `admin = true` in the inventory, and is not
granted by merging anything. Someone holds it because a key was physically given
to them and their public key was added to `.sops.yaml` — a change under tight
review, and the most consequential change anyone can make here.

Keep the list short. Two is the minimum that survives someone losing a key; it
should not casually grow past that.

Each administrator links their identity in at `.admin-key` in the repository
root — gitignored, normally a symlink to removable media, never a file living
on a laptop's disk. See `docs/provisioning.md`.

## Review split

`CODEOWNERS` encodes two tiers:

| Path | Review |
| --- | --- |
| `hosts/`, `profiles/`, `modules/`, `fleet/`, privilege assignments | Tight — restricted approver group |
| `users/<name>/` | Light — peer review |

Nobody merges their own changes to shared configuration.

**Not yet enforced.** Branch protection on `main` is deliberately postponed
until the provisioning flow is proven end to end (D23). Until it is enabled,
GitHub requests review from these teams but does not require it, and direct
pushes to `main` are possible. Treat the tiers as the intended design, not as
an operating control.

Changing `.sops.yaml` or `fleet/secrets/` is tight review, for the reason
above.

## The home-manager boundary

Developers configure their own environment through home-manager at
`users/<name>/home.nix`. The shared baseline uses `lib.mkDefault`, so shared
settings are defaults to override rather than walls to fight (D14).

**Security-relevant settings do not live in home-manager.** Screen locking,
firewall, disk encryption, sudo and `wheel`, audit settings, login policy — all
stay at the NixOS system level, in tightly-reviewed files.

This boundary is what keeps the light-review path from becoming a way to
silently disable controls. It is worth restating when adding anything new,
because the line is not obvious: a screen lock timeout looks like a personal
preference right up until it is a compliance control.

Running standalone home-manager from a personal flake is permitted but
unreviewed, consistent with the software policy.

## Onboarding

1. Pull request adding the person to `fleet/inventory.nix` (`active = true`,
   `admin` as appropriate — note that `admin` needs tight-tier approval).
2. Pull request adding `users/<name>/home.nix`, or start from a minimal
   template.
3. Add their device to `devices` — this is what creates their machine's
   configuration output.
4. Provision the laptop: `docs/provisioning.md`.
5. Record the machine in the asset register and its recovery key offline.

## Offboarding

Configuration changes are the **record** of revocation, not the mechanism. A
laptop only applies a change if it pulls it, and a departing person's machine may
never run `nixos-rebuild` again. Do the real work first:

1. **Recover the device.** Nothing else on this list works without it.
2. **Revoke upstream access** — GitHub, cloud, SSO, anything holding real
   authority. This is what actually ends their access.

   For a departing **administrator**, removing their `sshKeys` from the
   inventory does not take effect until each machine runs `fleet-update`. Until
   then their key still opens the `admin` account on every laptop in the field.
   That is the pull model (D6) showing its cost: there is no push, so
   revocation is a request, not an act. Either reach each machine, or treat
   their access as live until you have confirmed otherwise per machine.
3. **Rotate secrets they held.** Removing someone as a recipient does not help:
   they already had the plaintext (D1).

   If they held an **administrator age key**, this is the large job, not a
   formality: they could read every machine's recovery key. For each machine:
   remove their public key from `.sops.yaml`, `sops updatekeys` every file in
   `fleet/secrets/`, `fleet-mksecrets <host> --rotate`, and then
   `sudo fleet-rotate-recovery` **on the machine itself** (D25).

   The last step is the one that matters and the one that is easy to skip. The
   first three change files; only the last changes a disk. Stopping before it
   leaves every machine still openable with a key that person read, while the
   repository claims otherwise.
4. **Set `active = false`** in the inventory, by pull request. Keep the entry
   rather than deleting it — the inventory is the complete record of who has held
   access, and a deleted entry is indistinguishable from one that never existed.
   `active = false` makes the configuration *assert* the revocation rather than
   merely omit the person.
5. **Wipe or re-provision the returned machine.** Its recovery key unlocks it
   if the passphrase left with them — an administrator reads it from
   `fleet/secrets/<host>.yaml` (D5, D24). This is the case the recovery keyslot
   exists for, and the reason `fleet-passphrase` cannot touch it: a departing
   person cannot lock the organization out of a machine it owns.

### What NixOS actually does with a removed account

Verified against `nixos/modules/config/update-users-groups.pl` (nixos-26.05):
with `users.mutableUsers = false`, an account that is no longer declared **is**
removed from `/etc/passwd`, and `/etc/shadow` is rewritten to match. Login is
genuinely revoked, and previously-used UIDs are tracked so they are not
reissued.

What removal does **not** do: delete the home directory (it remains, owned by an
orphaned UID), terminate live sessions, or remove anything the person left in
their home directory — including SSH keys and tokens. Hence step 5.
