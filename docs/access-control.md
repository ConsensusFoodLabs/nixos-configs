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
3. **Rotate secrets they held.** Removing someone as a recipient does not help:
   they already had the plaintext (D1).

   If they held an **administrator age key**, this is the large job, not a
   formality: they could read every machine's recovery key. Remove their public
   key from `.sops.yaml`, run `sops updatekeys` on every file in
   `fleet/secrets/`, rotate each machine's secrets, and re-enrol the affected
   keyslots on machines still in the field (D25). `sops updatekeys` alone
   changes nothing about what they already know.
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
