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
`profiles/base.nix`, rather than `allowUnfree = true`. Currently four
entries: `claude-code`, `google-chrome`, `slack` and `vscode`.

**Amended:** `google-chrome`, `slack` and `vscode` are in the shared baseline
in `profiles/engineering.nix` — every engineering machine gets them, Chrome
alongside Firefox. These are the first unfree packages we ship fleet-wide
rather than to one person, which is exactly the question this allowlist exists
to make answerable: "what proprietary software runs on these machines" is
answered by four lines in one tightly-reviewed file.

`vscode` rather than `vscodium`, which is MIT and would need no entry here:
the marketplace is the reason people want it, and the open-vsx one codium uses
does not carry the same extensions. That is a deliberate trade of a licensing
entry for the thing people actually asked for, not an oversight. The allowlist entry and the baseline entry have to
move together — removing one without the other either breaks the build or
leaves a stale permission behind.

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

**Amended (D33):** GNOME is now the *default* rather than the only option.
`fleet/inventory.nix` picks a session per device and `profiles/engineering.nix`
branches on it; `x1c-oleg` runs i3. The thing this decision said to preserve
was preserved — see D33 for how i3's locking is declared, and why the choice
is a fleet attribute rather than a home-manager one.

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

## D33 — The desktop session is a fleet attribute, because screen locking rides on it

`fleet/inventory.nix` gained a `desktop` attribute per device, read by
`profiles/engineering.nix` through the `fleet.desktop` option. `x1c-oleg` is
`i3`; anything that does not say otherwise is `gnome`.

The obvious place for "which window manager do I use" is the owner's own
home-manager file, under light review (D14). It does not go there, and the
reason is narrow: **a desktop environment carries a screen lock, and screen
locking is a security control.** GNOME ships one. i3 does not — it ships
nothing at all, and a session with no locker configured is an unlocked laptop
the moment its owner walks away. If choosing i3 were a home-manager change,
then removing the fleet's only screen lock would be a lightly-reviewed one.

So the choice lives at the system level, and each branch of the conditional is
responsible for declaring locking for its own session. For i3 that is two
pieces, and both are required:

- `programs.xss-lock` handles the event-driven cases — suspend, lid close, and
  `loginctl lock-session`. It deliberately does not pass `--ignore-sleep`, so
  the screen is locked *before* the machine suspends rather than after it
  wakes.
- `services.xserver.xautolock` handles the idle case, at five minutes, matching
  the GNOME branch's `idle-delay=300`. It invokes `loginctl lock-session`
  rather than `i3lock` directly, so the lock goes through xss-lock and logind
  agrees the session is locked.

`fleet.desktop` is an `enum`, not a `str`, for the same reason: a typo must
fail the build rather than quietly select a branch that declares no locking.
**Adding a third desktop means declaring locking for it in the same commit.**

The owner's i3 config binds `$mod+Shift+x` to `loginctl lock-session`. That
binding is a convenience; it is not the control. Deleting it changes nothing
about whether the machine locks itself.

### What did not come across from the reference configuration

The i3 setup was ported from a personal repository. Three things were left
behind deliberately:

- **Credentials.** The upstream `i3blocks` blocks carried a Gmail password, an
  OpenWeatherMap API key, and an admin URL with a password embedded in it, all
  in cleartext. This repository is public (D1). The blocks were rewritten
  against what the machine actually runs — PipeWire, NetworkManager, sysfs —
  and none of them takes a secret. A status bar block that needs a credential
  does not belong here.
- **A vendored theme tree.** The rofi configuration referenced some 200 files
  of third-party themes, scripts and wallpapers. That is a large amount of
  unreviewed third-party content to carry in a company repository for a
  launcher. The styling that was actually in use — adi1090x/rofi (MIT),
  `launchers/type-1/style-4` and `powermenu/type-1/style-1` with the onedark
  palette — is inlined across four small files under `users/oleg/etc/rofi`
  instead, with attribution. The other fourteen colour schemes, six launcher
  types and sixteen wallpapers are not carried.

  Those files import `colors.rasi` by absolute path rather than relatively.
  Each is a separate symlink into the Nix store, so a relative `@import`
  resolves inside the store directory of whichever file did the importing and
  finds nothing there.
- **Arch-isms that failed silently.** The reference power menu probed
  `/usr/bin/betterlockscreen` and `/usr/bin/i3lock` — neither exists on NixOS,
  so its "lock" entry did nothing whatsoever. This is the failure mode the
  system-level declaration exists to prevent: a lock that looks configured and
  is not.

## D34 — A kernel pin on the X1 Carbon Gen 14, for audio

**Decided:** `boot.kernelPackages = pkgs.linuxPackages_latest` in
`hosts/thinkpad-x1c-gen14/hardware.nix`, overriding the nixos-26.05 default of
6.18.52. Scoped to this model, not the fleet.

This is an exception to D9, which said not to pin kernels. D9 stands as a
default: pin when the hardware does not work otherwise, not when a newer
kernel would be nice to have.

**Why:** the machine has no speakers and no microphone on 6.18.52, and cannot
have them. Its SoundWire codecs are a Cirrus CS42L45 jack/mic codec (part
`0x4245`) on link 3 and two CS35L63 speaker amps (part `0x3563`) on link 2.
6.18.52 contains no CS42L45 support of any kind — `sound/soc/sdw_utils/` has
helpers for the CS42L42 and CS42L43 and nothing for the 45. SOF finds no
machine driver for the ACPI-reported configuration, falls back to
`skl_hda_dsp_generic`, and loads `sof-hda-generic-idisp.tplg` — an
HDMI/DisplayPort-only topology. The only PCMs created are HDMI, which is
exactly what the machine shows: a Dummy Output and no sources.

7.2.x adds `soc_sdw_cs42l45.c`, the generic SDCA path for this codec.

**Confirmed working, 2026-09-20.** The machine was updated to 7.2.6 and
rebooted, and audio came up. The open question below — whether the generic
SDCA path binds without a quirk table entry — is answered: it does.

The rest of this entry is kept as written, because it is the reasoning that
picked the kernel and it is what the next person needs if this regresses. In
particular, upstream reports described the microphone working on 7.1.8 and
regressing on 7.2.x. That did not reproduce here, but it is the specific thing
to check first if capture goes silent after a kernel bump.

**What this decision claimed before it was tested.** Two things were
established by reading the sources, and one was not:

- **Established:** 6.18.52 cannot work — the codec support does not exist.
- **Established:** the SoundWire address quirk table
  (`soc-acpi-intel-ptl-match.c`) has no entry for this board in 6.18.52,
  7.2.6, **or** 7.3-rc3. The nearest entries are CS42L43 (`0x4243`) plus
  CS35L56 (`0x3556`) — different silicon. `sof-firmware` 2025.12.2 likewise
  ships no `cs42l45`/`cs35l63` topology. So the quirk route is not available
  on any released kernel.
- **Not established at the time, since confirmed:** whether the generic SDCA
  path in 7.2.x binds this machine without a quirk entry. It does.

**Consequences:** this model now tracks a kernel that moves faster than the
release channel, which is a real cost. 6.18.x is the version Wi-Fi was
confirmed on; Wi-Fi is working on 7.2.6 too, but it is no longer the tested
combination, and a kernel that moves on its own schedule is a standing risk to
a machine whose only network is wireless (D10). The rollback is the previous
generation in the boot menu, which is why D18 keeps it.

Revisit when `soc-acpi-intel-ptl-match.c` gains a `0x4245`/`0x3563` entry and
`sof-firmware` ships the matching topology; at that point this can go back to
the channel default.

## D35 — nix-ld, so prebuilt binaries run

**Decided:** `programs.nix-ld.enable = true` in `profiles/engineering.nix`.

**Why:** NixOS has no `/lib64/ld-linux-x86-64.so.2`. A binary built for any
other Linux therefore fails to start with `No such file or directory`, naming
the binary rather than the loader it actually could not find — one of the more
confusing errors a developer can meet on their first week. nix-ld installs a
loader at that path which finds libraries under `NIX_LD_LIBRARY_PATH`.

This is not theoretical. VS Code's Remote-SSH server downloads a prebuilt
node, many extensions ship prebuilt language servers, and several toolchains
fetch their own binaries. We now ship VS Code fleet-wide (D20), so we would be
shipping that failure fleet-wide with it.

**Security position:** this grants no privilege and removes no control. It
changes what is *convenient*, not what is *possible* — anyone could already
run a downloaded binary via `nix shell`, a FHS environment, a container, or
`patchelf`. D15 states plainly that we do not attempt to prevent developers
installing and running software, and that any restriction strict enough to
matter would stop them working. Making the ordinary case work follows from
that decision rather than weakening it.

What it does do is make "download a binary and run it" a frictionless path.
That friction was never a control — it was an accident of the distribution,
it stopped nobody determined, and it cost time from everybody else. Do not
describe its removal to an auditor as a loosening of a control, because it was
not one; see docs/software-policy.md for how to describe this area accurately.

**Consequences:** the default library set comes from systemd and nix
dependencies. A binary needing something outside it still fails, with a
missing-library error that at least names what is missing. The fix is an entry
in `programs.nix-ld.libraries`, which is a pull request against a
tightly-reviewed file — acceptable friction, since it is rare and the error
message says what to add.

## D36 — Fingerprint authentication, and a new screen locker to make it usable

**Decided:** `services.fprintd.enable = true` on engineering machines, with
the screen locker changed from i3lock to xsecurelock on i3 machines.

The reader is a Synaptics match-on-chip sensor, `06cb:019f`, supported by the
`synaptics` driver in libfprint 1.94.10 — the version in our pin. Enrolment
and matching happen on the device; what lands in `/var/lib/fprint` is a
handle, inside the LUKS volume, machine-local, and never in this repository.

### What it is used for

`sudo`, polkit prompts, GDM login, and the screen lock. GDM needs nothing from
us: the gdm module adds a `gdm-fingerprint` PAM service when fprintd is on.

### Why the locker changed

i3lock's PAM conversation is password-shaped. With `pam_fprintd` in the stack
it appears to hang until you press Enter, which is not a configuration
problem — it is what the program does. xsecurelock drives PAM properly and
surfaces the "place your finger" prompt.

This replaced a security control, so two things were checked rather than
assumed:

- `XSECURELOCK_PAM_SERVICE` defaults to `login`. NixOS's fallback PAM service
  `other` is `pam_deny` in **every** phase, so pointing the locker at a
  service that does not exist does not degrade gracefully — it produces a lock
  screen that rejects every correct password. The service name is therefore
  set explicitly and `security.pam.services.xsecurelock` is defined alongside
  it. The rendered stack was read back to confirm `pam_unix` is present, so
  the login password still works if the reader does not.
- The locker settings are exported inside the locker command rather than left
  to the session environment, because xss-lock runs it from a systemd user
  service which inherits no login shell.

**If the lock screen ever does reject a correct password**, the way back in is
SSH as `admin` and `pkill xsecurelock` (D32). That is a reason to keep the
admin account working, not a reason to be relaxed about the locker.

### What enabling fprintd actually does

`security.pam.services.*.fprintAuth` **defaults to
`services.fprintd.enable`**. One line therefore puts `pam_fprintd` into the
auth stack of every PAM service on the machine. That is mostly harmless —
`pam_fprintd` authenticates the *target* user, so `su oleg` still needs
oleg's finger, and tools like `useradd` run as root and do not authenticate
at all — but it is invisible from the config, and it was not what the line
appeared to say. Two exceptions are set explicitly:

- **`sshd`: off.** `pam_fprintd` prompts the reader attached to *this*
  machine. If sshd's auth stack were reachable, someone innocently touching
  the sensor could complete a stranger's remote login — the person
  authenticating would not be the person being authenticated. It is not
  reachable today, because `modules/fleet/admin.nix` disables both
  `PasswordAuthentication` and `KbdInteractiveAuthentication`. An assertion
  ties those two files together so that re-enabling ssh password auth fails
  the build instead of quietly creating the hazard.
- **`passwd` and `chpasswd`: off.** The fingerprint is meant to be a
  convenience alternative to the login password. If it can also rotate that
  password, it is no longer an alternative — it is strictly more powerful
  than the credential it stands in for, and the fallback becomes resettable
  by the convenience. This is a structural preference and is recorded as one:
  there is no specific attack behind it, since an opportunist at an
  unattended unlocked laptop does not have your finger either.

Everything else keeps the default. An earlier draft of this change carried a
long deny-list covering `su`, `chsh`, `chfn`, `useradd` and others; it was
dropped because none of those cases survived examination, and a deny-list
that implies an unwritten threat model is worse than no deny-list.

### What this does not touch

**The disk.** fprintd is a userspace D-Bus daemon and initrd has neither, and
`systemd-cryptenroll` has no fingerprint backend. LUKS keyslot 0, the
recovery keyslot, the escrow in `fleet/secrets/` and `fleet-rotate-recovery`
are all exactly as they were (D5, D31).

### The tradeoff being accepted

A fingerprint is not a secret. It is on every surface you touch, including
the laptop, and unlike the recovery key — for which this repository has a
rotation tool — it cannot be reissued. `sufficient` means it *replaces* the
password rather than adding to it, so for a user in `wheel` a fingerprint
grants root.

The judgement is that this is worth it at prompts where the alternative
credential is a login password typed many times a day in a public place,
where shoulder-surfing is the more realistic threat. It would not be worth it
for disk encryption, which is why that is untouched.

## D37 — Putting back what GNOME was quietly providing

**Decided:** four additions to `profiles/engineering.nix`, all of them things
the GNOME session supplied and the i3 session did not.

Moving a machine to i3 (D33) was treated as a change of window manager. It was
not. A desktop environment is a bundle of services, and dropping it drops all
of them at once — silently, because nothing fails. Screen locking was caught
at the time because it was obviously a security control. These were not.

- **A secret store.** `services.gnome.gnome-keyring.enable`, with
  `security.pam.services.login.enableGnomeKeyring` so it unlocks at login.
  This is the one that mattered. With no Secret Service on the bus, Chrome
  does not warn or refuse — it silently falls back to its `basic` password
  store, which is **plaintext in the profile directory**. Every saved password
  on the machine had been downgraded by a change about window management.

  Chrome also picks its store by sniffing the desktop environment and
  recognises nothing under i3, so `--password-store=gnome-libsecret` is passed
  explicitly. Enabling the daemon alone would not have been enough, and would
  have looked like it was.

  Fingerprint login interacts with this: `pam_gnome_keyring` normally unlocks
  the keyring with the password you just typed, and with a fingerprint there
  is no such password. GDM handles it via `pam_gdm`, which retrieves the
  stored credential; the rendered `gdm-fingerprint` stack was read back to
  confirm `pam_gdm` sits between `pam_fprintd` and `pam_gnome_keyring`.

- **Bluetooth.** `hardware.bluetooth.enable`, plus `services.blueman.enable`
  on i3 for a tray applet. `powerOnBoot` is left off: the radio comes up when
  asked for, not on every boot. PipeWire already handles the audio side.

- **Service discovery.** `services.avahi`, browse-only —
  `publish.enable` stays false, so the machine asks who is on the network and
  never announces itself, which is the right posture for a laptop that joins
  cafe and hotel networks. `openFirewall` does open UDP 5353 to receive
  responses; that is the cost of discovery working at all, and it is a
  deliberate hole rather than an incidental one.

- **Screenshots.** No PrintScreen binding existed at all. `maim` driven by a
  small script, bound to Print, Shift+Print and $mod+Print. Chosen over
  flameshot because it needs no tray icon and no daemon. Every mode copies to
  the clipboard *and* writes a dated file, so a screenshot is not lost to
  whatever lands in the clipboard next.

**The general lesson, which is the point of this entry:** the cost of leaving
a desktop environment is not the window manager, it is the list of things it
was doing that nobody had written down. When another machine changes
`desktop` in the inventory, this list is the starting checklist — and it
should still be assumed incomplete.

### Second pass

The list above was written assuming it was incomplete, and it was. A
follow-up audit of the remaining suspects found two more real gaps:

- **Automounting.** `services.udisks2` is on by default, so it looked
  covered. It was not: udisks2 only mounts when something asks it to, and
  GNOME's Files was the thing asking. Inserting a USB stick produced no
  mount, no icon and no error — the most expensive kind of missing, because
  there is nothing to notice. `udiskie` as a user service does the asking.
  `services.gvfs` comes with it, for trash and for phones over MTP.
- **Battery warnings.** Nothing warned before the battery ran out. logind
  acts at the very end, but there is no notice before that, so the first
  signal was the machine going away with unsaved work. `poweralertd` is a
  user service now. The bar's battery block turning red at 15% is not a
  substitute: it only works if you happen to be looking at the bar.

And two that turned out not to be problems, recorded so they are not
re-investigated:

- **Screen sharing did not need portals.** Chrome and Slack capture through
  X11 directly on an X session; the portal path matters on Wayland. Portals
  are enabled anyway, with `xdg-desktop-portal-gtk` and an explicit
  `config.common.default`, because file choosers do ask for them and a
  portal with no declared default can leave a request waiting for a backend
  to volunteer. That is insurance, not a fix.
- **gnome-settings-daemon's remaining jobs were already covered.** GTK
  settings reach applications through the files written in D33's cursor work
  rather than through an XSettings daemon; media keys are bound in the i3
  config; lid and power-button handling is logind's. No `xsettingsd` needed.

**Printer drivers were deliberately not added.** Modern network printers are
driverless IPP, which CUPS plus the Avahi added above already handles. Adding
`gutenprint` and `hplip` speculatively would grow every machine's closure to
support printers we have not met. When a specific printer fails, add the
driver it needs and say which printer in the commit.

## D38 — Three layers of home configuration, chosen by the machine

**Decided:** a user's home-manager configuration is composed from layers in
`modules/fleet/default.nix`, in this order:

```
modules/home-common.nix   every developer
modules/home-i3           every user of a machine whose desktop = "i3"
users/<name>/home.nix     that person
```

**Why:** everything the i3 session needed had been written into
`users/oleg/home.nix`, because oleg's machine was the first and only one to
run i3. None of it was personal. A second person switching to i3 would have
found an empty desktop and no clue what was missing, and the obvious fix —
copying oleg's file — is how two configurations start drifting on the day
they are created.

The split is by **whose decision it is**, not by what the setting touches:

- **System** (`profiles/engineering.nix`): things the session needs in order
  to be safe or to function regardless of anyone's preference. Screen
  locking, the polkit agent, the notification daemon, the network applet,
  automounting, battery warnings, the touchscreen mapping. A personal file
  must not be able to remove these — without a polkit agent an authorisation
  request fails with no prompt at all, and without a notification daemon the
  battery warning goes nowhere.
- **`modules/home-i3`**: the session's tools and defaults. Compositor,
  launcher, bar, screenshots, cursor theme, terminal, dotfiles. Shared so
  nobody rebuilds them, but every option is `lib.mkDefault` and every file is
  overridable, so a personal file overrides by simply setting the same option
  — no `mkForce`, no fighting.
- **`users/<name>/home.nix`**: that person's own tooling. For oleg this is
  now jujutsu, claude-code, telegram, yazi, sox and the two rclone Drive
  mounts, and nothing else.

Which layers apply is decided by the **machine's inventory entry**, not by
the personal file. A developer cannot opt out of the i3 defaults by editing
their own config; they change the machine's `desktop`. This is the same
principle as D33 — the desktop is a fleet attribute because things hang off
it — extended to the home configuration that goes with it.

**On the i3 config being shared.** The workspace scheme and keybindings in
`modules/home-i3/etc/i3/config` are one person's habits, and that is fine for
a default. It is a starting point, not a house style. The terminal binding
was changed back to `i3-sensible-terminal` to make this concrete: it honours
`$TERMINAL`, which the layer sets with `mkDefault`, so changing your terminal
is one line in your own file rather than a fork of the shared config.

**Verified as a refactor, not a rewrite.** The pre-refactor home-manager
generation was built from the previous commit and diffed against the new one.
The only differences were the three units that moved to the system level, the
terminal binding, and the store path embedded in the fontconfig file. The diff
also caught a real regression: moving the nm-applet *unit* to the system level
without its *package* took `nm-connection-editor` off PATH, which the bar's
network block opens on click.
