# Installer image, used to provision new machines (docs/provisioning.md).
#
# Deliberately generic: one image installs any machine in the fleet, because
# the machine's actual configuration is fetched from this repository during
# `nixos-install`. Nothing host-specific is baked in — and, just as
# deliberately, no secrets are either.
#
# Per-machine key material lives encrypted in fleet/secrets/ in the public
# repository, and is decrypted at install time with an administrator key held
# on removable media. So this image is not sensitive, is built once, and
# installs every machine in the fleet (D24, D25, D26).
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../modules/installer/fleet-install.nix
  ];

  # The installer must be able to fetch this flake.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # These laptops have no Ethernet port, so the installer needs working Wi-Fi
  # or provisioning cannot start at all (D10).
  hardware.enableRedistributableFirmware = true;
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  # fleet-install carries its own dependencies; these are for the operator
  # when something goes wrong and the scripted path is not enough.
  environment.systemPackages = with pkgs; [
    git
    cryptsetup
    mkpasswd
    sops
    age
    jq
    gptfdisk
    pciutils
    usbutils
  ];

  # The built filename comes from image.baseName: iso-image.nix passes
  # "${config.image.baseName}.iso" to the image builder and ignores
  # image.fileName, despite isoImage.isoName having been renamed to it.
  # Setting fileName alone silently does nothing.
  image.baseName = lib.mkForce "consensusfoods-installer";

  # New default from 26.11; set explicitly to reduce data-loss risk and to
  # keep the installer build quiet.
  boot.zfs.forceImportRoot = false;
}
