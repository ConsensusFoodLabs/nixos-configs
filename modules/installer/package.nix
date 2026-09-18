# The fleet-install program. Defined apart from the module that installs it so
# the flake can expose it too: `nix flake check` then builds it, and
# writeShellApplication runs shellcheck over it, on every check.
pkgs:

pkgs.writeShellApplication {
  name = "fleet-install";
  runtimeInputs = with pkgs; [
    coreutils
    cryptsetup
    findutils
    gawk
    git
    gnugrep
    jq
    mkpasswd
    mtools
    nix
    nixos-install-tools
    sops
    util-linux
  ];
  text = builtins.readFile ../../scripts/fleet-install;
}
