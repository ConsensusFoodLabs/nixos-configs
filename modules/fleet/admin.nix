# The shared `admin` account, on every machine.
#
# Every laptop ships with it, in wheel, reachable over SSH with the public keys
# of every active administrator in the inventory (D32). It is how an
# administrator gets into a machine they are not the owner of: to fix something
# remotely, or to recover one whose owner is unavailable.
#
# Its password is a provisioned secret like the others — generated ahead of
# time, encrypted in fleet/secrets/<host>.yaml, written to disk at install
# (D24). It is needed for sudo and for console login; SSH itself is key-only.
#
# Unlike the owner's account this is not gated on `active`: a machine whose
# owner has left is exactly a machine an administrator still needs to reach.
{ config, lib, inventory, hostname, ... }:

let
  admins = lib.filterAttrs (_: p: p.admin && p.active) inventory.people;

  # Public keys only, from the inventory, which is the source of truth for who
  # is an administrator (D3, D13). Granting SSH access to every machine is
  # therefore the same tightly-reviewed change as granting `admin` itself — it
  # is not a separate list that can drift out of step with it (D12).
  adminKeys = lib.concatMap (p: p.sshKeys or [ ]) (lib.attrValues admins);
in
{
  assertions = [
    {
      assertion = adminKeys != [ ];
      message = ''
        fleet/inventory.nix: no active administrator has an sshKeys entry, so
        '${hostname}' would ship with an admin account nobody can log into.

        Add the public key of at least one administrator, or this machine is
        unreachable the moment its owner cannot help.
      '';
    }
  ];

  users.users.admin = {
    isNormalUser = true;
    description = "Fleet administrator";
    extraGroups = [ "wheel" ];

    # Not in this repository: the hash is derived on the machine at
    # provisioning time from the encrypted password (D21, D24).
    hashedPasswordFile = "/var/lib/fleet/admin.passwd";

    openssh.authorizedKeys.keys = adminKeys;
  };

  # These laptops travel, so this is a listening service on untrusted networks.
  # Keys only, no root, no keyboard-interactive — a password prompt reachable
  # from a cafe network is exactly what must not exist here (D32).
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
