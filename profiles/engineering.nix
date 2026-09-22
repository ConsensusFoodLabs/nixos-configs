# Engineering laptop profile: desktop environment and shared developer tools.
#
# Changes here reach every engineering machine, so they go through tight
# review. Personal tooling belongs in users/<name>/home.nix instead (D14).
#
# This file is deliberately a list and nothing else. What a profile *is* is
# the choice of which modules apply to a class of machine; the modules
# themselves are shared, because the second profile will want most of the
# same ones (D41). Anything genuinely specific to engineering laptops, and
# only to them, would be declared here — today nothing is.
{ ... }:

{
  imports = [
    ../modules/desktop
    ../modules/hardware/fingerprint.nix
    ../modules/dev-toolchain.nix
  ];
}
