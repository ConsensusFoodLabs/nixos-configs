# Turns an inventory entry into a machine: the account, its privileges, and
# its home-manager configuration (docs/decisions.md D3, D11, D12, D14).
{ config, lib, pkgs, inventory, hostname, device, ... }:

let
  owner = device.assignedTo;

  person = inventory.people.${owner} or
    (throw "inventory: device '${hostname}' is assigned to '${owner}', who is not in people");

  inherit (person) active;
in
{
  imports = [ ./fleet-status.nix ];

  options.fleet = {
    user = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        Account name of the person this machine is assigned to. Shared modules
        refer to this rather than hardcoding a name (D11).
      '';
    };

    admin = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      description = ''
        Whether the owner holds administrator rights. Assigned in
        fleet/inventory.nix under tight review — never in a developer's own
        file (D12).
      '';
    };
  };

  config = lib.mkMerge [
    {
      fleet.user = owner;
      fleet.admin = person.admin;

      # Referential integrity. Nix is lazy, so a device pointing at a person
      # who does not exist can evaluate fine and only fail somewhere
      # unhelpful later — the wrong-but-evaluable case that matters (D13).
      assertions = [
        {
          assertion = inventory.people ? ${owner};
          message = ''
            fleet/inventory.nix: device '${hostname}' is assigned to
            '${owner}', who is not listed in people.
          '';
        }
      ];

      # No undeclared local accounts. An account that stops being declared is
      # removed from /etc/passwd and /etc/shadow; the home directory is left
      # behind, which is why offboarding also wipes the machine
      # (docs/access-control.md).
      users.mutableUsers = false;
    }

    (lib.mkIf active {
      users.users.${owner} = {
        isNormalUser = true;
        description = person.fullName;
        extraGroups = [ "networkmanager" ] ++ lib.optional person.admin "wheel";

        # Not in this repository: the hash is created on the machine at
        # provisioning time. A public repo is no place for a password hash,
        # and secrets tooling does not exist yet (D1).
        hashedPasswordFile = "/var/lib/fleet/${owner}.passwd";
      };

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "backup";
        extraSpecialArgs = { inherit inventory person; };
        users.${owner} = import ../../users/${owner}/home.nix;
      };
    })

    # active = false is an assertion that the account is gone, not merely an
    # omission. Revocation still depends on recovering the device and revoking
    # upstream access — see docs/access-control.md.
    (lib.mkIf (!active) {
      warnings = [
        "fleet: ${owner} is marked inactive; no account is created on ${hostname}"
      ];
    })
  ];
}
