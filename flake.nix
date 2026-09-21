{
  description = "Consensus Food Labs — engineering laptop fleet";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, disko, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      inventory = import ./fleet/inventory.nix;

      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # One nixosConfiguration per device in the inventory (D3). Adding a
      # machine is an inventory entry; this file does not change.
      mkDevice = hostname: device:
        lib.nixosSystem {
          system = "x86_64-linux";

          specialArgs = inputs // { inherit inventory hostname device; };

          modules = [
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager

            ./modules/fleet
            ./profiles/base.nix
            ./hosts/${device.model}
            ./profiles/${device.profile}.nix
          ]
          # One optional file per machine, for the things that belong to a
          # single laptop rather than to its model, its profile or its owner
          # (D40). Most machines have none, and then this adds nothing.
          ++ lib.optional
            (builtins.pathExists (./machines + "/${hostname}.nix"))
            (./machines + "/${hostname}.nix")
          ++ [

            {
              networking.hostName = hostname;

              # What this machine was built from. "dirty" means it was built
              # from an uncommitted tree and cannot be traced to a source
              # state — that is the signal, not a curiosity (D8, D17).
              system.configurationRevision =
                self.rev or self.dirtyRev or "dirty";
            }
          ];
        };
    in
    {
      nixosConfigurations = lib.mapAttrs mkDevice inventory.devices // {
        # One generic installer for the whole fleet: the machine's real
        # configuration is fetched during nixos-install, so nothing
        # host-specific is baked into the image.
        installer = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs;
          modules = [ ./hosts/installer.nix ];
        };
      };

      packages.x86_64-linux = {
        # Built locally; there is no CI (D8). One image for the whole fleet.
        installer-iso =
          self.nixosConfigurations.installer.config.system.build.isoImage;

        # Run on an administrator workstation to create a machine's encrypted
        # provisioning secrets: nix run .#fleet-mksecrets -- <hostname>
        fleet-mksecrets = pkgs.writeShellApplication {
          name = "fleet-mksecrets";
          runtimeInputs = with pkgs; [ coreutils git gnugrep jq nix sops ];
          text = builtins.readFile ./scripts/fleet-mksecrets;
        };

        # Lives on the installer image, not on a workstation. Exposed so that
        # `nix flake check` builds it and shellcheck sees it.
        fleet-install = import ./modules/installer/package.nix pkgs;

        # Writes the installer image and an administrator key to one stick.
        fleet-mkstick = pkgs.writeShellApplication {
          name = "fleet-mkstick";
          runtimeInputs = with pkgs; [
            coreutils
            dosfstools
            git
            gnugrep
            util-linux
          ];
          text = builtins.readFile ./scripts/fleet-mkstick;
        };

        # Destroys the key partition afterwards. Manual, never automatic (D29).
        fleet-wipe-key = import ./modules/installer/wipe-key.nix pkgs;

        # Installed on every machine; exposed here without a device baked in
        # so it is shellchecked and can be tested against a loop container.
        fleet-rotate-recovery = import ./modules/fleet/recovery-package.nix pkgs null;
      };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
    };
}
