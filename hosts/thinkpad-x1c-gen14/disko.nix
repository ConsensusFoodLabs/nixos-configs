# Disk layout: GPT, an EFI system partition, and LUKS over everything else.
#
# LUKS rather than the drive's Opal self-encryption, because this declaration
# is the evidence — firmware-level encryption is hard to attest to (D4).
#
# Unlock is passphrase-only; no TPM enrolment. Each machine also carries a
# second keyslot holding an organization-held recovery key (D5).
#
# Both keyslots are declared here rather than enrolled by hand: disko writes
# passwordFile into slot 0 and each additionalKeyFiles entry into a slot of its
# own, testing it before it moves on. Provisioning cannot therefore finish with
# an escrow key that was never enrolled, which is the failure the manual
# procedure invited (D24).
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

            # Written by fleet-install immediately before disko runs, from the
            # encrypted per-machine secrets in fleet/secrets/, and shredded
            # afterwards. /run is a tmpfs in the installer, so nothing here
            # ever reaches a disk in plaintext.
            #
            # These paths exist only during provisioning. Running disko by
            # hand without fleet-install will fail on the missing file, which
            # is the right outcome: the passphrase would otherwise be one
            # nobody has recorded.
            passwordFile = "/run/fleet-provision/passphrase";
            additionalKeyFiles = [ "/run/fleet-provision/recovery.key" ];
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
