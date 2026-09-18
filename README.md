# nixos-configs

Centralized NixOS configuration for Consensus Food Labs engineering laptops.

**Status: early.** The first machine (a ThinkPad X1 Carbon Gen 14) is being
provisioned. Most of what is described in `docs/` is decided but not yet
implemented — see the status markers in each document.

## This repository is public

Anyone can read it. Nothing secret goes in, in any form, ever — not in a
config, not in a comment, not in a commit that is later reverted. A secret
pushed here is disclosed the moment it lands, and rewriting history does not
undo that.

Secrets will eventually ship via sops-nix (see `docs/decisions.md`, D1). Until
that exists, the answer to "where do I put this credential" is: not in this
repo, ask first.

The repository is public deliberately: laptops pull their configuration
directly from it, so there are no deploy keys or tokens to distribute to
devices.

## Layout

    fleet/inventory.nix     people and devices — source of truth
    hosts/<model>/          hardware: kernel, firmware, disk layout
    profiles/              shared system config (security baseline, engineering)
    modules/               reusable system modules, home-manager baseline
    users/<name>/          per-developer config (home-manager)
    docs/                  decisions and operating procedures

## Common commands

Update a laptop to the current fleet configuration:

    sudo nixos-rebuild switch --flake git+https://github.com/ConsensusFoodLabs/nixos-configs#$(hostname)

See `docs/operations.md` for rollback, drift checks, and the break-glass
procedure.

## Working on this repository

- Changes land via pull request. Nobody merges their own changes to shared
  configuration.
- `CODEOWNERS` splits review: shared configuration (`hosts/`, `profiles/`,
  `modules/`, `fleet/`) needs approval from the tighter group; per-developer
  configuration (`users/<name>/`) needs lighter review.
- Install the gitleaks pre-commit hook before your first commit. It is the
  control that actually protects a public repository.
- Build only from revisions that are committed and pushed. A system built from
  a dirty working tree reports its revision as `dirty` and cannot be traced
  back to anything.

## Documents

| Document | What it covers |
| --- | --- |
| [decisions.md](docs/decisions.md) | Every significant decision, with reasoning and revisit triggers |
| [provisioning.md](docs/provisioning.md) | Building an image and installing a new laptop |
| [operations.md](docs/operations.md) | Updating, rollback, drift, break-glass |
| [access-control.md](docs/access-control.md) | Identity, privilege, onboarding, offboarding |
| [software-policy.md](docs/software-policy.md) | What the software baseline does and does not control |
