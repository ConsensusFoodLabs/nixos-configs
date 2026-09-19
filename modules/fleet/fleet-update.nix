# fleet-update: pull this machine's configuration and switch to it.
#
# Exists so that updating does not require administrator rights. Most people
# holding a laptop are not in wheel (D12), and a fleet where only
# administrators can apply updates is a fleet that does not get updated.
{ config, lib, pkgs, inventory, device, hostname, ... }:

let
  user = device.assignedTo;
  active = inventory.people.${user}.active or false;

  target = "${config.fleet.flakeRef}#${hostname}";

  # The privileged half. Takes no arguments, and ignores any it is given.
  #
  # That is load-bearing, not tidiness: a sudoers rule naming a command with no
  # arguments permits *any* arguments. If this forwarded "$@" to nixos-rebuild,
  # the owner could pass their own --flake and have arbitrary configuration
  # activated as root. The flake reference and the hostname are fixed here, at
  # build time, where the owner cannot reach them.
  doUpdate = pkgs.writeShellApplication {
    name = "fleet-do-update";
    runtimeInputs = [ config.system.build.nixos-rebuild ];
    text = ''
      # --refresh is not optional here. Nix caches the resolution of a
      # git+https flake reference for tarball-ttl, one hour by default, so
      # without it an update run minutes after a merge silently rebuilds the
      # revision it saw last time and reports success. An update command that
      # can apply a stale revision without saying so is worse than no update
      # command.
      exec nixos-rebuild switch --refresh --flake ${lib.escapeShellArg target}
    '';
  };

  fleetUpdate = pkgs.writeShellApplication {
    name = "fleet-update";
    # By path, not via pkgs.sudo on PATH: the store sudo is not setuid and
    # refuses to run, and writeShellApplication would put it ahead of the
    # wrapper that is.
    runtimeInputs = [ ];
    text = ''
      echo "Updating ${hostname} from ${config.fleet.flakeRef}"
      echo
      ${config.security.wrapperDir}/sudo -n ${doUpdate}/bin/fleet-do-update
    '';
  };
in
{
  config = lib.mkIf active {
    environment.systemPackages = [ fleetUpdate ];

    # The owner may run exactly this program as root, and nothing else. What it
    # applies is whatever is on the tracked branch, so the real control over
    # what lands on these machines is review of that branch — which makes
    # branch protection (D23) matter more than it did before this existed.
    security.sudo.extraRules = [{
      users = [ user ];
      commands = [
        { command = "${doUpdate}/bin/fleet-do-update"; options = [ "NOPASSWD" ]; }
      ];
    }];
  };
}
