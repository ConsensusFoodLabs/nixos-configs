# Software policy

**Status: current policy.** Short by design.

## What we do

The software that ships on every laptop is defined in this repository. Changing
it is a pull request, reviewed and approved by someone other than the author,
and the git history is the record of what changed, when, and who approved it.

Developers may install additional software on their own machines as needed.

## What we do not do

We do not technically prevent developers from installing software. This is a
deliberate decision (D15), not a gap we intend to close.

It is not achievable on a developer laptop without breaking the laptop:
`nix shell`, `nix profile install`, language package managers, containers and
downloaded binaries all remain available. The Nix daemon can be restricted, but
packages cannot be whitelisted, and any restriction strict enough to matter
would prevent engineers from working. The people being restricted are also the
people best equipped to route around the restriction.

## How to describe this accurately

For questionnaires, audits, and customer security reviews, the accurate
statement is:

> Standard software on engineering workstations is centrally defined in a
> version-controlled configuration and change-controlled through peer-reviewed
> pull requests. Developers retain the ability to install additional software
> locally. Deviations from the declared baseline are detectable through
> inventory of installed packages.

Do **not** claim that only approved software can be installed. It is false, and
the first follow-up question ("what stops a developer running `nix shell`?")
produces an answer that undermines every other claim made alongside it. The
accurate statement is the stronger position because it survives scrutiny.

Note that the inventory sentence describes a capability, not a running control.
Periodic collection and review do not exist yet (D17). Do not describe them as
though they do.
