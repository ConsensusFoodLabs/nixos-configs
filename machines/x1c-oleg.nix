# x1c-oleg — configuration for this one machine, not for its model and not
# for its owner's home directory.
#
# The per-machine layer exists because neither of the other two fits a home
# VPN: hosts/thinkpad-x1c-gen14 would put oleg's tunnel on every X1 Carbon
# the company buys, and users/oleg/home.nix is home-manager, which cannot
# bring up a network interface (D40).
{ ... }:

{
  # The tunnel to oleg's home network. How this works — and why the `.conf`
  # is delivered by hand rather than declared or encrypted — is in
  # modules/wireguard-home.nix; the delivery procedure is in
  # docs/operations.md.
  #
  # Only these four facts are specific to this machine. The SSID and the
  # gateway are here rather than in the delivered file because neither is a
  # secret: they name no host and reach nothing.
  fleet.homeTunnel = {
    enable = true;
    interface = "x1c-oleg-h";
    homeSsid = "mingahome";
    homeGateway = "172.26.249.254";

    # Off for now. The units stay defined, so turning this back on is a
    # one-line flip rather than resurrecting deleted code.
    autoconnect = false;
  };
}
