# Decision log

Decisions made for the fleet configuration, with the reasoning behind them.
Recorded so they are not silently re-litigated, and so the reasoning survives
the people who were in the room.

All decisions below were made on 2026-09-18 unless noted. "Status" says whether
the decision is implemented, not whether it is settled.

---

## D1 — Secrets: sops-nix, deferred

**Decided:** sops-nix is the fleet secrets tool. Not wired up yet.

**Why:** agenix and sops-nix are close in capability — both encrypt to recipient
public keys, both can use SSH host keys, both need a rekey when membership
changes. sops-nix wins on two points that matter for a public repository:
partial encryption keeps YAML/JSON keys readable so a pull request shows *which*
secret changed without revealing the value, and `.sops.yaml` creation rules map
path patterns to recipient groups, which composes with the CODEOWNERS split.
It can also move to a cloud KMS backend later without changing consuming
modules.

The maintainer's existing personal NixOS setup uses agenix, but that
infrastructure is entirely separate — personal machines, personal keys, no
shared trust — so familiarity was the only carry-over, and it was not enough to
decide on.

**Deferred because:** there are no fleet secrets yet. Building key groups for a
fleet of one produces structure that will be wrong by the time it is needed.

**Partly adopted by D24.** sops is now used for provisioning secrets:
`.sops.yaml`, age recipients, `fleet/secrets/<host>.yaml`. That is the sops
*file format and CLI*, not the sops-nix NixOS module — nothing is decrypted at
runtime on a laptop, only at install time by an administrator. Runtime secrets
delivered to a running machine remain deferred, and when they arrive they
extend this same `.sops.yaml` rather than introducing a second scheme.

**Consequences:** neither tool solves rekey-on-join/leave. Adding a machine
means re-encrypting to a new recipient, which requires someone with plaintext
access. Offboarding therefore requires *rotating* secrets, not just removing a
recipient — a departing person already had the plaintext.

**Revisit when:** the first real secret needs to ship (likely developer
credentials), at which point the recipient set is known.

---

## D2 — gitleaks from the first commit

**Decided:** a gitleaks pre-commit hook, active immediately.

**Why:** in a public repository a plaintext secret is disclosed on push. This is
the load-bearing control, and it is independent of D1. It matters *most* during
the period when there is no secrets tooling — that is exactly when someone
pastes a credential into a config file "just to test".

**Status:** not yet implemented.

---

## D3 — Per-device flake outputs, generated from the inventory

**Decided:** `flake.nix` maps over `fleet/inventory.nix` and generates one
`nixosConfigurations.<hostname>` per device.

**Why:** three options were considered. Hand-written per-device outputs are
explicit but make `flake.nix` a merge-conflict point and a review bottleneck on
every hire. A single shared profile output scales but has nowhere to put the
PR-gated personal overrides the design calls for. Generating from the inventory
gives the explicitness of the first with the scaling of the second, and makes
the inventory genuinely load-bearing rather than decorative: "who has a laptop"
and "which configurations exist" cannot drift apart, because one derives from
the other.

**Consequences:** slightly more Nix plumbing than literal entries. Adding a
person is an inventory entry plus a `users/<name>/` directory; `flake.nix` does
not change.

---

## D4 — Disk encryption: LUKS via disko, passphrase only

**Decided:** LUKS managed by disko. Unlock by passphrase at every boot. No TPM.

**Why:** LUKS over the drive's Opal self-encryption because LUKS state is
declared in the configuration and readable as evidence, whereas firmware-level
encryption is hard to attest to.

Passphrase over TPM because a fleet of one that is still proving its
provisioning path does not need boot ergonomics optimized, and every TPM
complication is another variable in play when something else fails. TPM
auto-unlock without a PIN was rejected outright: a stolen laptop would boot
straight to a login screen with the disk already decrypted, collapsing
data-at-rest protection into the login password.

**Consequences:** developers type a passphrase at boot and a password at login.

**Revisit when:** daily boot friction becomes a real complaint. TPM+PIN is the
upgrade path, and it is cheap — enrolling a TPM keyslot is a
`systemd-cryptenroll` operation on a running machine, not a reinstall. Note that
PCR values shift on firmware and bootloader updates, so any TPM enrollment needs
a fallback keyslot.

---

## D5 — Recovery keys: per device, offline, non-expiring

**Decided:** every machine gets a second LUKS keyslot holding an
organization-held recovery key, enrolled at provisioning time. One key per
device, not one for the fleet. Stored offline. No rotation policy.

**Why:** without escrow, a forgotten passphrase means a wiped laptop and a
returned machine is unreadable — a bad answer to "can you recover company data
from a returned device".

Per-device rather than fleet-wide because a single shared key has a blast radius
of every laptop and can never be rotated without touching every machine — which
"non-expiring" would make permanent. Per-device keys cost nothing extra to
generate (provisioning happens machine by machine anyway) and confine each key's
exposure to one laptop.

Non-expiring is acceptable at current scale: rotation ceremony for one machine
is overhead without benefit.

**Consequences:** if a laptop is lost or someone departs, that machine's key is
the one to rotate — a one-machine problem by construction.

**Amended by D24.** "Stored offline" originally meant a key generated at the
keyboard during installation and written down. It is now generated in advance
and stored in this repository *encrypted*, which is strictly better: escrow
exists before the machine does, cannot be forgotten at the keyboard, and has a
git history saying when it was created. The plaintext key is still nowhere in
this repository, and what is now held offline is the administrator age key that
decrypts it (D25). One key per device, non-expiring, is unchanged.

**Resolved:** the question of whether disko could enrol the second keyslot
declaratively, which blocked this being automatic. It can —
`additionalKeyFiles` adds each key in its own slot and tests it. Neither
keyslot is enrolled by hand any more.

---

## D6 — Laptops track `main` now, a release branch later

**Decided:** laptops build from `main`. A promotion gate comes later.

**Why:** with one merger and one user, a release branch would mean approving
one's own promotions — ceremony without separation.

**Consequences:** anyone who can merge can execute code as root on every
laptop. Pull request review is the only control between a bad commit and the
fleet, and a compromised GitHub account is fleet compromise.

**Revisit when:** the second person gains merge rights. At that point `main`
becomes where pull requests land and laptops track a `release` branch, promoted
by a deliberate fast-forward with its own approvers. Cost is one branch and one
CODEOWNERS line.

Commit signature verification was considered and rejected for now: Nix flake
fetching does not verify signatures, so it would mean building verification into
the update path by hand. The pull model's weak point is not signatures anyway —
`nixos-rebuild switch` runs build code as root by design.

---

## D7 — Flake reference uses `git+https://`, in exactly one place

**Decided:** `git+https://github.com/ConsensusFoodLabs/nixos-configs` rather than
`github:ConsensusFoodLabs/nixos-configs`, and the reference lives in one
documented place.

**Why:** `github:` refs resolve through `api.github.com`, rate-limited to 60
requests/hour *per IP* when unauthenticated. An office behind one NAT, everyone
updating the morning after a merge, hits that — and it fails as a confusing API
error mid-rebuild, not as anything that says "rate limit". `git+https://` uses
the git protocol and is not subject to that limit. The cost is a git fetch
instead of a tarball, which is irrelevant at this repository's size.

Configuring `access-tokens` would also raise the limit, but puts a credential on
every laptop — exactly the distribution problem the public-repository decision
exists to avoid.

Keeping the reference in one place means `github:` → `git+https:` → a release
branch → a self-hosted mirror are all one-line changes, not fleet-wide
retraining.

**Revisit when:** convenient. A self-hosted public mirror would sidestep rate
limits entirely and could double as the D6 promotion gate — at the cost of
owning its availability.

---

## D8 — No CI; images built locally

**Decided:** initial images are built on a maintainer's machine. No build
pipeline.

**Consequences and mitigations:** without CI there is no automatic record of
which commit an image came from, so `system.configurationRevision` is set from
the flake revision (see D9) and images are built only from committed, pushed
revisions. Building from a dirty tree silently breaks the link between a machine
and its source, which is why `dirty` must be visible rather than silent.

Because the flake is structured so that an image is just a derivation of a host
configuration, adding CI later is a workflow file, not a refactor.

---

## D9 — Kernel: stock nixos-26.05, no pinning

**Decided:** the base configuration tracks `nixos-26.05` with its default
`linuxPackages`. No `linuxPackages_latest`, no unstable, no per-host kernel pin.

**Why:** this was an open risk — the Core Ultra 5 325 (Panther Lake) is very new
silicon, and a base image that cannot reach the network cannot provision itself,
with no Ethernet port as a fallback. Resolved empirically: a stock NixOS
26.05 install on the target laptop (kernel 6.18.52) brought up the Intel BE211
Wi-Fi 7 adapter via `iwlwifi` without intervention.

**Consequences:** everything stays on `cache.nixos.org`, so no laptop compiles a
kernel and no shared binary cache is needed. This is part of why D8 remains
comfortable.

**Note:** per-host nixpkgs pinning remains available as an escape hatch if a
future model needs newer packages than the fleet tracks.

---

## D10 — Redistributable firmware is mandatory

**Decided:** `hardware.enableRedistributableFirmware = true` in the hardware
module.

**Why:** `iwlwifi` needs firmware that the NixOS installer enables for you and a
hand-written configuration does **not** enable by default. Omitting it produces
a laptop with no Wi-Fi and no Ethernet port — unable to pull its own fix. This
is the single easiest way to brick a provisioning run.

---

## D11 — Identity: corporate usernames, not a generic account

**Decided:** the account name matches the corporate username (`oleg`), exposed
through a `fleet.user`-style option so shared modules never hardcode a name.

**Why:** a uniform `user` account was considered. Its supposed benefit —
generic modules and predictable paths — is available from a single option
instead, so nothing is lost. Its privacy benefit is illusory: per-developer
configuration lives at `users/<name>/` in a public repository, so the name is
present either way.

What a generic account costs is attribution at exactly the layer that matters:
`sudo`, `journald`, and auth logs all record the account name. With `user`
everywhere, every log line on every laptop says the same thing and "who did
this" requires a hostname-to-person lookup in a side table that must be kept
accurate. Self-describing logs are a materially better evidence story.

**Consequences:** reassigning a laptop means a rebuild with a different
configuration rather than handing over an account. Acceptable.

---

## D12 — Administrator privilege is granted outside developer-owned files

**Decided:** admin/`wheel` membership is a per-user setting, but the assignment
lives in a base-owned file under tight CODEOWNERS review. Personal preferences
stay in `users/<name>/` under lighter review.

**Why:** if `wheel` membership were set inside a developer's own file, any
developer could grant themselves root through the lightly-reviewed path. That
would make the loose path the highest-privilege path — the exact separation of
duties failure the split exists to prevent.

**Consequences:** developers freely change their own tooling; changing who holds
root requires the tight approver group, and the change is a legible entry in git
history. That history is the access-control evidence.

---

## D13 — Inventory is the source of truth, and carries no hardware serials

**Decided:** `fleet/inventory.nix` is plain data — people and devices — consumed
by account creation, privilege assignment, home-manager wiring, and host
generation (D3). It records `model`, `assignedTo`, and `profile`. It does **not**
record serial numbers.

**Why:** nothing in the configuration consumes a serial. The hostname is already
a stable machine identity. Serials are warranty and support identifiers usable
for social engineering against the vendor, and they belong to the asset register
— a separate, private artifact — joined back to this repository by hostname.

**Note:** a machine could identify itself from its DMI serial to auto-select a
configuration without a baked-in hostname. That solves a provisioning problem we
do not currently have, and would work with a hash rather than the plaintext.

**Deferred:** referential-integrity assertions (every `assignedTo` resolves to a
real person, every `profile` exists, no duplicate hostnames). Key typos surface
as eval failures anyway; the failures worth catching are the ones that evaluate
to a wrong-but-valid configuration. Worth adding at the first pull request from
someone other than the maintainer — before that they would be untested code
guarding against impossible mistakes, written against a schema that is still
moving.

---

## D14 — home-manager as a NixOS module, with a security boundary

**Decided:** home-manager is wired as a NixOS module (pinned to `release-26.05`,
following nixpkgs). A shared baseline at `modules/home-common.nix` uses
`lib.mkDefault` so developers can override it. Personal configuration lives at
`users/<name>/home.nix` under lighter review.

**The boundary:** security-relevant settings must not live in home-manager.
Screen locking, firewall, disk encryption, sudo and `wheel`, audit settings and
login policy stay at the NixOS system level in tightly-reviewed files.

**Why the boundary:** anything under `users/<name>/` is lightly reviewed, and
home-manager options can be overridden by the file that defines them. Without
this rule the light-review path silently becomes a way to disable controls —
the same hole D12 closes for `wheel`. The boundary is worth stating explicitly
because it is not obvious: "screen lock timeout" looks like a personal
preference right up until it is a compliance control.

**Why a NixOS module rather than standalone:** one command updates everything,
the home configuration is part of the same evaluated system and therefore
covered by the same revision stamp and audit trail, and there is no second tool
with its own state to learn.

**Also decided:** a developer running standalone home-manager from a personal
flake is permitted but unreviewed. Consistent with D15; blocking it would not
work anyway.

---

## D15 — Software: change-controlled baseline, not enforcement

**Decided:** the declared software set is change-controlled through pull
requests. Local installation by developers is permitted. No technical
enforcement is attempted. See `docs/software-policy.md` for the framing to use
in compliance contexts.

**Why:** enforcement is not achievable on a developer laptop without breaking
the laptop. `nix shell`, `nix profile install`, language package managers,
containers and downloaded binaries all remain available; the Nix daemon can be
restricted but packages cannot be whitelisted, and anything strict enough to
matter would stop engineers working. The people being restricted are the people
best equipped to route around it.

**The important part is not overclaiming.** "Only approved software can be
installed" is false and collapses under the first auditor question. The true
statement — centrally defined and change-controlled baseline, developers retain
local installation, deviations detected by periodic inventory — is a stronger
position precisely because it survives scrutiny.

---

## D16 — Break-glass is a written policy, not machinery

**Decided:** out-of-band local changes are permitted when needed and reconciled
back into the repository afterwards via pull request. One paragraph of policy,
no tooling, no approval flow. See `docs/operations.md`.

**Why:** the original scope for break-glass covered urgent software installs
(dissolved by D15 — nothing to break glass for), laptop lockout (solved by D5),
and urgent configuration changes. Only the last has substance, and at current
scale the requester, approver and logger would be the same person, which is
theatre. Any process designed today would be designed against imagined incidents
rather than real ones.

**Consequences:** a machine running an out-of-band configuration is by
definition no longer described by this repository — which is what the whole
compliance story rests on. That is the argument for reconciling promptly, and
why drift detection (D17) is what eventually makes this real.

---

## D17 — Drift detection: the primitive now, collection later

**Decided:** set `system.configurationRevision` from the flake revision (falling
back to `dirty`), and ship a `fleet-status` script in the base configuration
that reports revision, lag behind `main`, and user profile contents. No timers,
no reporting endpoint, no central collection.

**Why:** the expensive part is collection; the cheap part is the primitive that
makes collection possible later, and it cannot be recovered retroactively — a
machine without a revision stamp can never tell you what it was built from. The
`dirty` fallback is as important as the revision: it makes D8's "build only from
pushed revisions" rule visible instead of silent.

**The honest caveat:** a script a developer runs by hand is a debugging aid, not
a detective control, and must not appear in a compliance narrative as
monitoring. It becomes a control when something collects centrally and a person
reviews the results.

**Revisit when:** there are enough machines that reading your own report stops
being the whole of it.

---

## D18 — Generation retention has a floor

**Decided:** garbage collection and generation pruning are configured from day
one, but retention is set by time with a minimum floor (target: 30 days) rather
than by disk pressure.

**Why:** the previous generation in the boot menu is the primary recovery
mechanism for a bad update — including one that breaks networking on a machine
with no Ethernet port. On a 256 GB disk it is tempting to prune aggressively,
which would delete the recovery mechanism to save space. The floor is a safety
control, not a housekeeping preference, and should carry a comment saying so.

---

## D19 — One USB-C Ethernet adapter, for the office

**Decided:** buy one adapter as a shared recovery aid. Nothing depends on it.

**Why:** Wi-Fi works out of the box (D9), so this is not a provisioning
requirement. It covers the case where a configuration change breaks networking
*and* generation rollback (D18) is unavailable or insufficient. Roughly the
difference between "drive over with a dongle" and "reinstall".

---

## D20 — Unfree packages allowed by name, not blanket-enabled

**Decided:** `nixpkgs.config.allowUnfreePredicate` with an explicit allowlist in
`profiles/base.nix`, rather than `allowUnfree = true`. Currently one entry:
`claude-code`.

**Why:** this is a *licensing* control, not a security one. It makes the set of
proprietary software shipped fleet-wide reviewable in one place and answers
"what non-free software runs on these machines" from the repository. It is not
an attempt to restrict what developers run — that would contradict D15, and
anyone can still `nix shell` anything.

**Consequences:** a developer who wants an unfree package in their own
`users/<name>/home.nix` needs an entry added to a tightly-reviewed file. That is
real friction, and it is the argument for flipping this to `allowUnfree = true`
if it becomes annoying — a one-line change.

---

## D21 — Password hashes live on the machine, not in the repository

**Decided:** accounts use `hashedPasswordFile = "/var/lib/fleet/<user>.passwd"`,
created during provisioning with `mkpasswd`. Combined with
`users.mutableUsers = false`.

**Why:** `mutableUsers = false` gives the guarantee that no undeclared local
account exists, and makes a removed account actually disappear from
`/etc/passwd`. But it requires a declared password, and a password hash in a
public repository is a crackable credential published to the world. Until
secrets tooling exists (D1), the hash is per-machine local state created at
install time.

**Consequences:** provisioning has a step that, if skipped or misnamed, produces
a machine nobody can log in to. That step is no longer manual: `fleet-install`
derives the hash from the encrypted initial password and writes it under the
right name (D24), so the failure mode is gone rather than documented around.

**Still true after D24:** the repository holds the initial *password*,
encrypted — never the hash, and never in plaintext. The hash is derived on the
machine and stays there. The developer replaces it on first login with
`fleet-passwd`, which is what makes a change survive `nixos-rebuild` under
`mutableUsers = false` (D27).

---

## D22 — GNOME as the desktop environment

**Decided:** GNOME with GDM, declared in `profiles/engineering.nix`.

**Why:** a laptop needs a desktop, and GNOME has working defaults on current
hardware. More importantly it provides screen locking, which is a security
control — so the lock settings are declared at the system level where light
review cannot reach them (D14), not left to each developer's home
configuration.

**Consequences:** this was chosen without much deliberation and is easy to
change. If the team prefers something else, the thing to preserve is that
screen locking stays a system-level declaration rather than a personal
preference.

---

## D23 — Branch protection postponed

**Decided:** `CODEOWNERS` and the two GitHub teams exist and have write access,
but branch protection on `main` is **not** enabled yet. Deferred until the
provisioning flow has been proven end to end.

**Why:** the flow has never been run — disko, keyslot enrolment, the password
hash file and the first `nixos-install` are all unexercised. Iterating on that
is faster without a review gate, and a gate approved only by the person who
wrote the change would not be separating anything yet.

**What this means in the meantime — read this part:** until branch protection
is on, `CODEOWNERS` is advisory. GitHub will request review from the right team
but will not require it, and nothing prevents a direct push to `main`. The
separation of duties described in `docs/access-control.md` is therefore
*structurally in place but not enforced*. Do not describe it as an operating
control until this is done.

**Revisit when:** the first laptop is provisioned and updating from the repo
works. At that point enable, on `main`: require a pull request, require review
from Code Owners, dismiss stale approvals on new commits, and no bypass for
administrators. Note that `engineering` already has a second member, so
review by someone other than the author becomes possible — and meaningful —
immediately.

---

## D24 — Per-machine secrets are generated ahead of time, encrypted, and committed here

Each machine's disk passphrase, recovery key and initial login password are
generated by `fleet-mksecrets` on an administrator workstation, encrypted with
sops to the age recipients in `.sops.yaml`, and committed to this public
repository as `fleet/secrets/<host>.yaml`.

**Why:** provisioning was nine manual steps, several of which produced a secret
that existed only in the operator's head or on a scrap of paper until they
remembered to record it. The recovery key in particular was generated at the
keyboard and escrowed by discipline. Generating it in advance, encrypted,
means the escrow exists *before* the machine does and cannot be forgotten.

Committing it to the public repository, rather than a secret store we do not
have, buys: a git audit trail for when each machine's key material was created
and rotated; durability and backup we do not have to operate; and a
reinstallable machine years later. The secrets are useless without an
administrator key.

**What was considered instead:** baking per-device secrets into a per-device
installer image. Rejected — for the image to install unattended it must carry
its own decryption key, so the encryption protects nothing against whoever
holds the stick, and every laptop needs its own 1.5 GB build.

**This supersedes** the parts of D1 and D21 that said no secrets tooling
exists. Password *hashes* are still not in the repository: `fleet-install`
derives the hash on the machine from the encrypted plaintext password (D21
stands).

---

## D25 — The administrator age key is the only artifact held outside the repository

The private age identities that decrypt `fleet/secrets/` are held by fleet
administrators on removable media. They are not in this repository, not in the
installer image, and not on any laptop.

**Why:** it is the thing that makes everything else non-sensitive. The repo can
be public, the installer image can be built once and left in a drawer, and
neither discloses anything. All of the fleet's confidentiality is concentrated
in one small artifact that is easy to store properly.

**The cost, stated plainly:** lose every administrator identity and you lose
every machine's recovery key, with nothing in this repository able to
regenerate it. Back it up offline, in more than one place, before provisioning
anything.

**Two identities exist**, both currently held by one person: a working key and
an offline backup on separate media. That is *durability*, not separation of
duties — it removes the single-disk failure mode, and nothing else. Two copies
of the same authority is not two approvers, and this must not be described as
one. A second *administrator*, with their own key, remains outstanding.

Adding a recipient to `.sops.yaml` does not re-encrypt anything. Existing files
must be resynced, or the new identity decrypts nothing that already exists:

    sops updatekeys fleet/secrets/<host>.yaml

**How it is referenced:** everything reaches the identity through `.admin-key`
at the repository root — gitignored, and normally a symlink to removable media.
The repository names one path; each administrator decides what is behind it and
the repository never learns where anyone keeps their key. `.envrc` exports
`SOPS_AGE_KEY_FILE` from it *for direnv users only* — direnv is not a
dependency of this repository and was not in fact installed on the first
administrator's workstation, so documented `sops` commands pass the variable
explicitly rather than assuming it. `fleet-mksecrets` sets it itself.

Without a single agreed path, `sops` silently falls back to its own default
(`~/.config/sops/age/keys.txt`) and every workstation behaves differently for
no reason. The pre-commit hook refuses `.admin-key` *by path*: as a symlink,
git stores only the link target, which passes a secret scan cleanly while still
publishing where an administrator keeps their key (D28).

**`fleet-mksecrets` verifies the round trip** before replacing anything.
Encrypting needs only public keys, so it can happily produce a file its author
cannot read; with `--rotate` that would destroy the previous secrets and
replace them with ones nobody can open. It now decrypts what it built, and only
then moves it into place.

**Revoking an administrator** requires more than removing their key from
`.sops.yaml`: run `sops updatekeys` on every file *and* rotate the secrets
themselves, because they could already read the old ones.

---

## D26 — One generic installer image; the machine is chosen at install time

`fleet-install --host <host>` on a single fleet-wide image, rather than a
per-machine image.

**Why:** one artifact to build, verify and keep current, instead of one per
laptop. Nothing host-specific has to be decided at build time, because the
configuration and the secrets are both fetched from a pinned revision during
the run — which also means the installed system and the tool that installed it
come from the same commit.

**The disk confirmation stays manual.** An image that installs on boot is an
image that destroys whatever machine it is left plugged into. The single typed
confirmation is worth more than the seconds it costs.

---

## D27 — What ships on the machine is *initial* credentials

Machines are installed with a generated disk passphrase and login password.
Developers replace both on first login with `fleet-passwd` and
`fleet-passphrase`. The recovery key is not initial and is untouched by either.

**Why:** a 25-character random passphrase typed at every boot will be written
on a sticky note within the week. The organization does not need to know the
developer's chosen passphrase, because it holds the recovery keyslot — so
there is no reason to insist on one it knows.

`fleet-passphrase` writes keyslot 0 only, and refuses unless the passphrase
given opens keyslot 0. Confirmed on the first provisioned machine
(2026-09-19): the developer passphrase opens slot 0 and the recovery key does
not, so the refusal is doing what it claims. Otherwise a developer holding the recovery key could
move it into slot 0 and quietly interfere with escrow. `fleet-passwd` persists
the hash `passwd` produced into `/var/lib/fleet/<user>.passwd`, which is what
makes the change survive the next `nixos-rebuild` under
`users.mutableUsers = false`.

Both are reachable by non-administrators through two narrow `sudo` rules, so
changing your own credentials does not require `wheel` (D12).

---

## D28 — The pre-commit hook verifies that `fleet/secrets/` is encrypted

Separately from gitleaks, and before it.

**Why:** gitleaks does not flag these values. They are random strings with no
provider fingerprint; a plaintext `fleet/secrets/<host>.yaml` scans clean, as
tested. The secret scanner is therefore not the control that protects this
directory — this check is. It requires both a `sops:` block and an
`ENC[AES256_GCM` marker in every staged `.yaml` under `fleet/secrets/`.

---

## D29 — The administrator key ships on the stick, never in the image; wiping it is manual

`fleet-mkstick` writes the installer image to a USB stick and then adds a
separate `FLEETKEY` partition holding the administrator age identity.
`fleet-wipe-key` destroys that partition, and is run by hand.

**Why not put the key in the image:** the image is a nix store path. The store
is world-readable by design (`drwxrwxr-t`, and the ISO itself `-r--r--r--`), so
every user on the build machine could read the key, and anything pushed to a
binary cache or copied with `nix copy` would take it along — unpublishable
after the fact. The image is also the long-lived, shareable artifact: built
once, reused for every laptop, handed to whoever is provisioning. The key is
the opposite — per-administrator, rotated, revoked. Binding them would mean
rebuilding and redistributing the image whenever an administrator changed, and
would recreate the secret-bearing-image design rejected in D24, except
fleet-wide rather than per-machine.

**Why one stick rather than two:** "burn the image, then remember to copy the
key" is a step that gets skipped, and it gets skipped standing in front of the
laptop. One command produces a stick that works.

**Why the wipe is manual:** the procedure has not yet been run end to end and
will take several attempts. An install that wiped its own key would have to be
re-armed before every retry, which turns a proving exercise into a chore and
invites people to disable the wipe permanently. It is step 7 of
`docs/provisioning.md` instead.

**What the wipe actually achieves — do not overstate this.** On flash media,
overwriting does not guarantee erasure: wear levelling means the controller may
retain copies in blocks no command can address. `fleet-wipe-key` issues a
discard for the whole range, which is the best available answer, and falls back
to zeroing. A stick that has held a key should be treated as having held it. Do
not describe this as secure erasure in a questionnaire; describe it as a
hygiene step. The controls that actually bound the exposure are a dedicated
stick, and the ability to rotate the administrator key (D25).

**Implementation note, learned the hard way.** The installer image is an
*isohybrid*: a DOS/MBR table whose first partition starts at sector 0 and spans
the whole image, with the EFI partition nested inside it. That boots, and it is
not a valid GPT — `sgdisk` rejects it outright ("MBR partitions 1 and 2
overlap"). The key partition is therefore appended with `sfdisk` in MBR terms,
and identified by its *filesystem* label, because MBR has no partition labels.
Verified on a loop device: partition appears, key reads back byte-identical,
the boot signature survives, and wipe then `--key-only` re-arm leaves the image
intact.

**Revisit when:** provisioning has been run successfully several times. At that
point, wiping automatically at the end of a successful install becomes the
right default, with a flag to keep the key for back-to-back provisioning.

---

## D30 — Updating does not require administrator rights

`fleet-update` applies the fleet configuration without `sudo`, through a narrow
`sudo` rule granting the machine's owner one fixed program.

**Why:** administrator rights are assigned per person and most people holding a
laptop will not have them (D12). If updating needed `wheel`, either everyone
gets `wheel` — making D12 meaningless — or machines stop being updated. Neither
is acceptable, and the second is the likelier.

**The argument detail, which is the whole security of it:** a sudoers rule
naming a command with no arguments permits *any* arguments. So the privileged
half takes none and ignores any it is given; the flake reference and hostname
are fixed at build time, in the nix store, where the caller cannot reach them.
Had it forwarded `"$@"` to `nixos-rebuild`, the owner could have passed their
own `--flake` and had arbitrary configuration activated as root.

**`--refresh`, which is not a detail:** Nix caches the resolution of a
`git+https` flake reference for `tarball-ttl` — one hour by default — so an
update run shortly after a merge will otherwise rebuild the revision it
resolved last time and report success. This was found the hard way: a laptop
reported `configurationRevision` two commits behind `main` immediately after a
rebuild that appeared to work. `fleet-update` always passes `--refresh`, and
the by-hand command in `docs/operations.md` shows it.

**What it does grant:** the ability to activate, as root, whatever is on the
tracked branch, at a time of the owner's choosing. That is the pull model
working as designed (D6) — but it does mean the branch, not the `sudo` rule, is
the thing that decides what runs as root on every laptop. Branch protection
(D23) matters more now than it did before this existed.

---

## D31 — Rotating a recovery key is two steps, and the second one is a tool

`fleet-mksecrets <host> --rotate` changes the file. `fleet-rotate-recovery`,
run on the machine as an administrator, changes the disk.

**Why a tool rather than a documented `cryptsetup` sequence:** between the two
steps, `fleet/secrets/<host>.yaml` holds a recovery key that does not open that
machine. The repository describes escrow that does not exist, and nothing
detects it — the failure surfaces when someone tries to open a returned laptop.
That makes the second step the one that must not be skipped or fumbled, and
`cryptsetup luksKillSlot` will remove the last key that opens a disk without
complaint.

The tool enforces the only order that is safe: enrol, test, then remove —
authorising the removal with the *new* key, so cryptsetup must accept it for
real before anything is destroyed. It refuses to touch keyslot 0, which is the
developer's passphrase and the basis of `fleet-passphrase`'s guarantee (D27).

**Root-only, with no sudo rule.** Replacing escrow is an administrator action,
unlike changing your own credentials. Administrators have `wheel` (D12), so
plain `sudo` is the whole mechanism.

**A consequence to expect:** the new key lands in a free slot rather than the
one it replaces, so a rotated machine may hold its recovery key in slot 2 while
`disko.nix` describes slot 1. That comment describes a freshly installed
machine. The invariant that must hold is keyslot 0.

**Not automated further, on purpose.** There is no fleet-wide rotation, because
there is no fleet-wide anything: no push, no agent, no inventory of live
machines (D6, D17). Rotating after an administrator departs means visiting each
machine, and `docs/access-control.md` says so rather than implying a button
exists.

---

## D32 — Every machine ships with a shared `admin` account, reachable over SSH

In `wheel`, carrying the SSH public keys of every person in the inventory with
`admin = true` and `active = true`. Its password is a provisioned secret,
per machine (D24). Not gated on the owner being active.

**Why:** a fleet where the only way into a laptop is its owner is a fleet with
no answer to "the owner is on leave and their machine is wedged", or "someone
left and the machine is still in the field". Administrator rights already exist
per person (D12); this makes them mean something on a machine the administrator
does not own.

Keys come from the inventory rather than a separate list, so granting `admin`
and granting SSH to every machine are one tightly-reviewed change and cannot
drift apart. An assertion fails the build if no active administrator has a key,
because a machine shipping with an admin account nobody can log into is worse
than shipping without one — it looks like access that is not there.

**This reverses `services.openssh.enable = false`** in `profiles/base.nix`,
whose note read "laptops are not servers, nothing should be reaching in". That
was right until administrators needed to reach a machine whose owner cannot
help. Stated here so the reversal is a decision rather than a drift.

**What it costs, plainly.** These laptops travel, so this is a listening
service on untrusted networks — hotel wifi, conference wifi, cafes. Mitigated
by: key-only authentication, no keyboard-interactive, no root login, so there
is no password prompt to attack. Not mitigated: the presence of the service
itself, port 22 reachable from the local network wherever the machine is, and
any future vulnerability in sshd. The honest description is that the exposure
is a real increase, bounded by there being nothing to guess.

**`sudo` without a password, for `admin` only.** The point of the account is
reaching a machine remotely, and a password prompt is what a non-interactive
`ssh host sudo ...` cannot answer. The owner's account is unaffected:
`wheelNeedsPassword` stays true, so the developer is still prompted.

This moves the whole weight onto the SSH key. Before it, a stolen key bought a
shell and root still needed `admin_password`; now the key alone is root on
every machine in the fleet. Two things follow, and neither is optional if this
is to stay defensible:

  - **Administrator SSH keys should carry a passphrase.** They are now
    root-equivalent, fleet-wide, in a single file. `ssh-keygen -p -f <key>`
    adds one to an existing key without changing the public half, so nothing
    in the inventory changes.
  - `admin_password` is now only for console login and is no longer a second
    factor for root. It is still worth having — a machine with a broken
    network is reached at the keyboard — but do not count it as one.

**Revisit when:** there is a VPN or an overlay network (Tailscale, WireGuard).
Binding sshd to that interface instead of every interface removes most of this,
and is the obvious next step once such a thing exists.

**A consequence that is easy to miss:** removing a departing administrator's
`sshKeys` from the inventory does not revoke anything until each machine runs
`fleet-update`. There is no push (D6). Their key opens the `admin` account on
every laptop in the field until that machine pulls. `docs/access-control.md`
says so in the offboarding checklist; do not describe SSH revocation as
immediate.

---

## Open, non-blocking

- **Fingerprint reader.** The sensor is Synaptics `06cb:019f` (not Goodix as
  originally assumed). Many Synaptics sensors work only through a closed-source
  TOD driver rather than plain libfprint, so support may be full, blob-dependent,
  or absent. Cheap to test with `fprintd-enroll` on the running machine. Not a
  blocker either way.
