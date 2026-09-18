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

    # Kernel-assigned name, and applying disko destroys whatever is here.
    # Uniform hardware with a single internal NVMe makes this stable, but it
    # is checked by hand at provisioning time (docs/provisioning.md step 3)
    # rather than trusted. A by-id path would be safer and is unique per
    # physical drive, which would mean putting a hardware identifier in the
    # inventory — deliberately avoided (D13).
    #
    # Nothing downstream depends on this name: disko labels the partitions it
    # creates, and everything mounts by partition label, so no machine-specific
    # device paths or UUIDs reach the configuration.
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
