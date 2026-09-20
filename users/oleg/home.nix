# Personal configuration for oleg.
#
# Light review: this file is yours. Add tooling, change the shell, restyle the
# prompt, override anything the shared layers set.
#
# The layers underneath are chosen by the machine, not by this file (D38):
#   modules/home-common.nix   every developer
#   modules/home-i3           every user of a machine whose inventory entry
#                             says desktop = "i3"
#
# Both set their options with lib.mkDefault, so overriding one here is just
# setting it again — no mkForce needed. To use a different terminal, set
# home.sessionVariables.TERMINAL; to use a different i3 config, point
# home.file.".config/i3/config".source at your own.
#
# What does not belong here: anything security-relevant (screen locking,
# firewall, encryption, sudo, the polkit agent). Those live at the system
# level (D14), and administrator rights are granted in fleet/inventory.nix,
# not here (D12).
{ config, lib, pkgs, ... }:

let
  # An rclone FUSE mount as a user service.
  #
  # The remote itself is NOT configured here. `rclone config` writes OAuth
  # tokens to ~/.config/rclone/rclone.conf, which are credentials for a Google
  # account and so must never reach this repository — see the comment on
  # home.activation.rcloneMountpoints below.
  rcloneMount = { remote, dir, description }: {
    Unit = {
      Description = description;
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "notify";
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.rclone}/bin/rclone mount"
        "${remote}: %h/cfoods/mnt/${dir}"
        "--vfs-cache-mode writes"
        "--vfs-cache-max-size 1G"
      ];
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u %h/cfoods/mnt/${dir}";
      Restart = "on-failure";
      RestartSec = "10s";
      # fusermount3 must be the setuid wrapper, not the store binary: an
      # unprivileged mount fails without it. programs.fuse installs it.
      Environment = "PATH=/run/wrappers/bin:${pkgs.fuse3}/bin";
    };
    Install.WantedBy = [ "default.target" ];
  };
in
{
  # My own i3 configuration, replacing the conventional default from
  # modules/home-i3. That layer sets this with lib.mkDefault, so this plain
  # assignment wins with no mkForce (D38).
  #
  # What is different: named workspaces (web/code/term, an aux bank, plan and
  # social), a `go` mode on $mod+g for reaching them, non-standard focus keys,
  # and per-application workspace assignments.
  home.file.".config/i3/config".source = ./etc/i3/config;

  home.packages = with pkgs; [
    # jujutsu and claude-code are not listed here: both are in the shared
    # baseline in profiles/engineering.nix, so every machine gets them.
    telegram-desktop
    sox

    # A file manager. GNOME had Files; i3 has whatever you install. Terminal
    # rather than graphical, to match what this setup came from.
    yazi
    poppler-utils # PDF previews in yazi

    rclone
  ];

  # Google Drive, mounted over FUSE.
  #
  # Both units fail until `rclone config` has created the remotes named here.
  # That step is deliberately manual and deliberately absent from this repo:
  # rclone stores OAuth refresh tokens in ~/.config/rclone/rclone.conf, and a
  # refresh token is a live credential for the whole Drive account. It stays
  # on the machine.
  home.activation.rcloneMountpoints =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$HOME/cfoods/mnt/oleg" "$HOME/cfoods/mnt/shared"
    '';

  systemd.user.services.rclone-cfoods-oleg = rcloneMount {
    remote = "cfoods-oleg";
    dir = "oleg";
    description = "rclone mount: cfoods oleg Google Drive";
  };

  systemd.user.services.rclone-cfoods-shared = rcloneMount {
    remote = "cfoods-shared";
    dir = "shared";
    description = "rclone mount: cfoods shared Google Drive";
  };
}
