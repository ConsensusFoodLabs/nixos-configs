# The installer's one command. See scripts/fleet-install for what it does.
{ pkgs, ... }:

{
  environment.systemPackages = [
    (import ./package.nix pkgs)
    (import ./wipe-key.nix pkgs)
  ];

  # The installer boots to a root shell; say what to run rather than making
  # the operator find the documentation on another machine.
  services.getty.helpLine = ''

    Consensus Food Labs fleet installer.

      fleet-install --check --host <hostname>    verify without touching the disk
      fleet-install --host <hostname>            install
      fleet-wipe-key /dev/sdX                    destroy the key partition

    Connect Wi-Fi first with `nmtui`, and plug in the administrator key.
    Full procedure: docs/provisioning.md in the nixos-configs repository.
  '';
}
