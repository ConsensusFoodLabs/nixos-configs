# Disk layout: GPT, an EFI system partition, and LUKS over everything else.
#
# LUKS rather than the drive's Opal self-encryption, because this declaration
# is the evidence — firmware-level encryption is hard to attest to (D4).
#
# Unlock is passphrase-only; no TPM enrolment. Each machine also carries a
# second keyslot holding an organization-held recovery key, enrolled by hand at
# provisioning time and stored offline (D5, docs/provisioning.md).
{ ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
