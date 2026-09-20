# Rotating the organization's recovery key on a machine already in the field.
#
# Deliberately root-only, with no sudo rule: replacing escrow is an
# administrator action, not something the machine's owner does. Administrators
# have wheel (D12), so plain `sudo fleet-rotate-recovery` is the whole story.
#
# It is installed on every machine because the machine is where it has to run —
# the alternative is an administrator typing cryptsetup luksKillSlot at a
# terminal, one mistake away from a disk nobody can open.
{ config, lib, pkgs, inventory, device, ... }:

let
  user = device.assignedTo;
  active = inventory.people.${user}.active or false;

  luksDevice =
    config.disko.devices.disk.main.content.partitions.luks.content.device;
in
{
  config = lib.mkIf active {
    environment.systemPackages = [
      (import ./recovery-package.nix pkgs luksDevice)
    ];
  };
}
