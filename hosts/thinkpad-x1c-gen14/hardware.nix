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

  # Kernel: newer than the 26.05 default, for audio. See D34.
  #
  # Wi-Fi works on the stock 6.18.x via iwlwifi with no special handling,
  # confirmed on the hardware. Audio does not, and cannot: this machine's
  # SoundWire codecs are a CS42L45 jack/mic codec (part 0x4245) and two
  # CS35L63 speaker amps (part 0x3563), and 6.18.52 has no CS42L45 support at
  # all — sound/soc/sdw_utils/ has helpers for the CS42L42 and CS42L43 and
  # nothing for the 45. SOF therefore finds no machine driver, falls back to
  # skl_hda_dsp_generic with the HDMI-only topology, and the machine comes up
  # with no speakers and no microphone.
  #
  # 7.2.x adds soc_sdw_cs42l45.c, which is the generic SDCA path for this
  # codec. This is a hardware-support pin, not a preference, and it is scoped
  # to this model rather than the fleet.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
}
