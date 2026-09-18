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

      # Built locally; there is no CI (D8).
      packages.x86_64-linux.installer-iso =
        self.nixosConfigurations.installer.config.system.build.isoImage;

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
    };
}
