# Hardware support for the X1 Carbon Gen 14.
#
# Filesystems are not declared here — they come from disko.nix, which is the
# single declaration of the disk layout (D4).
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  # MANDATORY. iwlwifi needs firmware that the NixOS installer enables for you
  # and a hand-written configuration does not. Without this the machine has no
  # Wi-Fi — and no Ethernet port — so it cannot pull its own fix (D10).
  hardware.enableRedistributableFirmware = true;

  hardware.cpu.intel.updateMicrocode = true;

  # Panther Lake is new silicon; firmware updates are worth having.
  services.fwupd.enable = true;
  services.thermald.enable = true;

  # Stock nixos-26.05 kernel (6.18.x) brings up the BE211 via iwlwifi with no
  # special handling — confirmed on the target hardware. No kernel pin (D9).

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}
