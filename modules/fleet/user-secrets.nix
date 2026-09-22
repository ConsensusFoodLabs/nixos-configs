# A declared place for material that is delivered by hand.
#
# Some things cannot live in this repository and are not fleet secrets
# either: they are not provisioning credentials the installer needs (D27), so
# fleet/secrets/ is the wrong home for them, and the repository is public, so
# no file in it is. What is left is "copy it onto the machine yourself" — the
# rclone OAuth tokens, a personal VPN configuration (D40), an API key for
# something with no better story.
#
# Left to itself that becomes a different path on every machine and a
# permissions mistake waiting to happen. One directory, created with the
# right mode before anything needs it, makes delivering such a file a copy
# and nothing else — and gives modules somewhere to point a `configFile` at
# without each of them inventing a path.
#
# What this is NOT: a secrets mechanism. Nothing here is encrypted, rotated
# or backed up. The protection is the disk encryption (D4) and the mode.
{ config, lib, ... }:

{
  options.fleet.userSecretsDir = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      Directory on this machine for hand-delivered files belonging to the
      owner. Created 0700 and owned by them; contents are never in this
      repository.
    '';
  };

  config = {
    fleet.userSecretsDir = "/home/${config.fleet.user}/.secrets";

    # `users` is the default group of a normal user on NixOS, which is what
    # modules/fleet/default.nix creates.
    systemd.tmpfiles.rules = [
      "d ${config.fleet.userSecretsDir} 0700 ${config.fleet.user} users - -"
    ];
  };
}
