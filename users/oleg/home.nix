# Personal configuration for oleg.
#
# Light review: this file is yours. Add tooling, change the shell, restyle the
# prompt. Shared defaults come from modules/home-common.nix and can be
# overridden here.
#
# What does not belong here: anything security-relevant (screen locking,
# firewall, encryption, sudo). Those live at the system level (D14), and
# administrator rights are granted in fleet/inventory.nix, not here (D12).
#
# In particular the i3 session's screen locking is declared in
# profiles/engineering.nix. Nothing in this file can turn it off.
{ config, lib, pkgs, ... }:

let
  # Power menu for $mod+Shift+e. The reference config bound this to a vendored
  # script that probed /usr/bin/betterlockscreen and /usr/bin/i3lock — both
  # absent on NixOS, so its lock entry did nothing at all. This one asks
  # logind, which is also what the $mod+Shift+x binding does.
  rofiPowermenu = pkgs.writeShellApplication {
    name = "rofi-powermenu";
    # procps for uptime; coreutils `uname -n` rather than `hostname`, which
    # coreutils does not install on NixOS.
    runtimeInputs = with pkgs; [ rofi systemd coreutils procps i3 gnused ];
    text = ''
      lock=" lock"
      suspend=" suspend"
      logout=" log out"
      reboot=" reboot"
      shutdown=" shut down"

      theme=$HOME/.config/rofi/powermenu.rasi

      menu() {
        rofi -dmenu -p "$(uname -n)" -mesg "up $(uptime -p | sed 's/^up //')" \
          -theme "$theme"
      }

      confirm() {
        printf 'no\nyes\n' |
          rofi -dmenu -p confirm -mesg "$1" -theme "$theme" \
            -theme-str 'listview { lines: 2; }'
      }

      chosen=$(printf '%s\n%s\n%s\n%s\n%s\n' \
        "$lock" "$suspend" "$logout" "$reboot" "$shutdown" | menu)

      case "$chosen" in
        "$lock")     loginctl lock-session ;;
        "$suspend")  systemctl suspend ;;
        "$logout")   [ "$(confirm "log out?")" = yes ] && i3-msg exit ;;
        "$reboot")   [ "$(confirm "reboot?")" = yes ] && systemctl reboot ;;
        "$shutdown") [ "$(confirm "shut down?")" = yes ] && systemctl poweroff ;;
      esac
    '';
  };

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
  imports = [ ../../modules/home-common.nix ];

  home.packages = with pkgs; [
    jujutsu
    claude-code

    # Desktop. Chrome is not listed here: it is part of the shared baseline
    # in profiles/engineering.nix, so every machine gets it (D20).
    ghostty
    telegram-desktop
    # rofi-emoji is a plugin: rofi only finds it inside its own lib/rofi, so
    # it has to be built into the wrapper. Installing it alongside rofi would
    # leave `rofi -modi emoji` reporting an unknown mode.
    (rofi.override { plugins = [ rofi-emoji ]; })
    rofiPowermenu
    picom
    dunst
    libnotify
    feh
    # Point-and-click xrandr, for working out a layout worth saving with
    # `autorandr --save`.
    arandr
    networkmanagerapplet
    pavucontrol

    # Needed on PATH by the i3 config and the i3blocks scripts: wpctl for
    # volume, nmcli for the network block, dex for XDG autostart.
    wireplumber
    dex

    # Icon theme named by rofi's config.rasi.
    papirus-icon-theme

    rclone
    sox
  ];

  home.sessionVariables = {
    TERMINAL = "ghostty";
  };

  # One cursor theme and size, declared once.
  #
  # Nothing set these before, so every toolkit fell back to its own default —
  # which is why the pointer changed size crossing into a Chrome window. The
  # X server, GTK and Chrome each pick differently when XCURSOR_THEME and
  # XCURSOR_SIZE are unset; GNOME papers over this by setting them for you and
  # i3 does not.
  #
  # This writes ~/.icons/default/index.theme, the Xresources entries and the
  # GTK settings together, so all three agree. Raise size if 24 is small on
  # this panel.
  home.pointerCursor = {
    package = pkgs.adwaita-icon-theme;
    name = "Adwaita";
    size = 24;
    x11.enable = true;
    gtk.enable = true;
  };

  # home.pointerCursor's gtk.enable only sets gtk.cursorTheme; the settings
  # file that GTK and Chrome actually read is written by this module, and
  # without it the cursor size reaches everything except the GTK apps.
  gtk.enable = true;

  # i3, i3blocks, rofi and picom configuration, kept as plain files under
  # users/oleg/etc rather than generated by home-manager's i3 module: these
  # were ported from an existing setup and stay diffable against it.
  home.file = {
    ".config/i3/config".source = ./etc/i3/config;
    ".config/i3blocks/config".source = ./etc/i3blocks/config;
    ".config/i3blocks/blocks" = {
      source = ./etc/i3blocks/blocks;
      recursive = true;
    };
    ".config/rofi/config.rasi".source = ./etc/rofi/config.rasi;
    ".config/rofi/colors.rasi".source = ./etc/rofi/colors.rasi;
    ".config/rofi/launcher.rasi".source = ./etc/rofi/launcher.rasi;
    ".config/rofi/powermenu.rasi".source = ./etc/rofi/powermenu.rasi;
    ".config/rofi/calendar.rasi".source = ./etc/rofi/calendar.rasi;
    ".config/picom/picom.conf".source = ./etc/picom/picom.conf;
    # Theme names are the file names under ghostty's share/ghostty/themes,
    # spaces included. onedark, to match the rofi themes.
    ".config/ghostty/config".text = ''
      theme = Atom One Dark
      window-decoration = none
    '';
  };

  # Notification daemon and network applet, as user services rather than i3
  # `exec` lines, so they restart on failure and survive an i3 restart.
  systemd.user.services.dunst = {
    Unit = {
      Description = "dunst notification daemon";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.dunst}/bin/dunst";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Compositor. A service rather than an i3 `exec_always`, which re-runs on
  # every reload and restart and leaves the second instance failing with
  # "Another composite manager is already running". systemd restarts it if it
  # dies and never starts a second copy.
  systemd.user.services.picom = {
    Unit = {
      Description = "picom compositor";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.picom}/bin/picom --config %h/.config/picom/picom.conf";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.nm-applet = {
    Unit = {
      Description = "NetworkManager applet";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # A polkit agent, so anything asking for authorisation in the session gets a
  # prompt instead of failing silently. GNOME provides one; i3 does not.
  systemd.user.services.polkit-gnome-authentication-agent = {
    Unit = {
      Description = "polkit authentication agent";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart =
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

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
