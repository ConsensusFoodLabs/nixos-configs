# Engineering laptop profile: desktop environment and shared developer tools.
#
# Changes here reach every engineering machine, so they go through tight
# review. Personal tooling belongs in users/<name>/home.nix instead (D14).
#
# Beyond the module list, this file also carries the one thing genuinely
# specific to engineering laptops, and only to them: the firewall override
# below. What a profile *is* is otherwise the choice of which modules apply
# to a class of machine; the modules themselves are shared, because the
# second profile will want most of the same ones (D41).
{ lib, ... }:

{
  imports = [
    ../modules/desktop
    ../modules/hardware/fingerprint.nix
    ../modules/dev-toolchain.nix
  ];

  # profiles/base.nix turns the firewall on fleet-wide and says why: laptops
  # roam onto networks we don't control, and nothing should be reaching in
  # by default. Engineering overrides that here, wide open on all incoming
  # ports, because developers routinely run local servers, webhook
  # receivers, and LAN-reachable services that need to be reachable from
  # other machines — on the office network and otherwise.
  #
  # This is a real exposure on untrusted networks (conference wifi, hotel
  # wifi): anything a developer runs that listens on a socket is reachable
  # by every other device on that network, not just the office LAN.
  # Requested and confirmed with that tradeoff explicit, engineering-only.
  networking.firewall.enable = lib.mkForce false;
}
