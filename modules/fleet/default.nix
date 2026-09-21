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
  imports = [ ./fleet-status.nix ./fleet-credentials.nix ./fleet-update.nix ./fleet-recovery.nix ./admin.nix ];

  options.fleet = {
    user = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        Account name of the person this machine is assigned to. Shared modules
        refer to this rather than hardcoding a name (D11).
      '';
    };

    repoUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        Where machines fetch their configuration. Defined once so that moving
        to a release branch or a self-hosted mirror is a one-line change (D7).
      '';
    };

    flakeRef = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        repoUrl as a flake reference. git+https rather than github: because the
        latter goes through api.github.com, which rate-limits unauthenticated
        requests per IP — an office full of laptops shares one (D7).
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

    desktop = lib.mkOption {
      type = lib.types.enum [ "gnome" "i3" ];
      readOnly = true;
      description = ''
        Which desktop session this machine boots into. Set per device in
        fleet/inventory.nix, read by profiles/engineering.nix.

        An enum rather than a free string: a typo must fail the build, not
        silently land on a session with no screen locking (D14).
      '';
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        System timezone. Set per device in fleet/inventory.nix; defaults to
        UK time when a device doesn't set one. Read by profiles/base.nix.
      '';
    };
  };

  config = lib.mkMerge [
    {
      fleet.user = owner;
      fleet.admin = person.admin;
      fleet.desktop = device.desktop or "gnome";
      fleet.timezone = device.timezone or "Europe/London";
      fleet.repoUrl = "https://github.com/ConsensusFoodLabs/nixos-configs";
      fleet.flakeRef = "git+" + config.fleet.repoUrl;

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
        # video: brightness control writes /sys/class/backlight, which
        # acpilight's udev rules make group-writable (profiles/engineering.nix).
        extraGroups = [ "networkmanager" "video" ]
          ++ lib.optional person.admin "wheel";

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

        # The layers, and the order that makes overriding work: shared
        # defaults first, the personal file last. Which layers apply is
        # decided by the machine's inventory entry, not by the personal file
        # — a developer cannot opt out of the i3 defaults by editing their
        # own config, they change the machine's desktop (D38).
        users.${owner}.imports = [
          ../../modules/home-common.nix
        ]
        ++ lib.optional (config.fleet.desktop == "i3") ../../modules/home-i3
        ++ [ ../../users/${owner}/home.nix ];
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
