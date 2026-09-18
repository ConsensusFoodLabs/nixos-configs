# Installer image, used to provision new machines (docs/provisioning.md).
#
# Deliberately generic: one image installs any machine in the fleet, because
# the machine's actual configuration is fetched from this repository during
# `nixos-install`. Nothing host-specific is baked in.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # The installer must be able to fetch this flake.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # These laptops have no Ethernet port, so the installer needs working Wi-Fi
  # or provisioning cannot start at all (D10).
  hardware.enableRedistributableFirmware = true;
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    git
    cryptsetup # enrolling the recovery keyslot (D5)
    mkpasswd # creating the account password hash
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
