# The i3 session, as shared defaults.
#
# Imported for every user on a machine whose inventory entry says
# `desktop = "i3"` — see modules/fleet/default.nix. Not imported on GNOME
# machines, where all of this is either provided or unwanted.
#
# Everything here is `lib.mkDefault` or a package, so a personal
# users/<name>/home.nix overrides any of it by just setting the same option.
# This is a starting point, not a house style: a developer who wants different
# keybindings, a different bar or a different terminal changes them in their
# own lightly-reviewed file (D14, D38).
#
# What is NOT here: anything the session needs in order to be *safe* or to
# work at all regardless of preference. Screen locking, the polkit agent, the
# notification daemon, automounting and the touchscreen mapping are declared
# at the system level in profiles/engineering.nix, where a personal file
# cannot remove them.
{ config, lib, pkgs, ... }:

let
  # Power menu for $mod+Shift+e. The reference config this was ported from
  # bound it to a script that probed /usr/bin/betterlockscreen and
  # /usr/bin/i3lock — neither exists on NixOS, so its lock entry did nothing
  # at all. This one asks logind, as the $mod+Shift+x binding does.
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

  # Screenshots. There was no PrintScreen binding at all after the move off
  # GNOME, which provided one.
  #
  # maim rather than flameshot: no tray icon, no daemon, nothing to keep
  # running, and it composes with xclip. Every mode copies to the clipboard
  # and also writes a dated file, so a screenshot is never lost to whatever
  # lands in the clipboard next.
  screenshot = pkgs.writeShellApplication {
    name = "screenshot";
    runtimeInputs = with pkgs; [ maim xclip xdotool libnotify coreutils ];
    text = ''
      dir=''${XDG_PICTURES_DIR:-$HOME/Pictures}/screenshots
      mkdir -p "$dir"
      file=$dir/$(date +%Y-%m-%d_%H-%M-%S).png

      case "''${1:-screen}" in
        screen) maim --hidecursor "$file" ;;
        # --nokeyboard so Escape cancels the selection instead of being
        # swallowed; maim exits non-zero, and that is not an error.
        select) maim --nokeyboard --select "$file" || exit 0 ;;
        window) maim --hidecursor --window "$(xdotool getactivewindow)" "$file" ;;
        *) echo "usage: screenshot [screen|select|window]" >&2; exit 2 ;;
      esac

      [ -s "$file" ] || { rm -f "$file"; exit 0; }

      xclip -selection clipboard -t image/png -i "$file"
      notify-send "Screenshot" "copied to clipboard
      $file" --icon=camera-photo
    '';
  };
in
{
  home.packages = with pkgs; [
    # rofi-emoji is a plugin: rofi only finds it inside its own lib/rofi, so
    # it has to be built into the wrapper. Installing it alongside rofi would
    # leave `rofi -modi emoji` reporting an unknown mode.
    (rofi.override { plugins = [ rofi-emoji ]; })
    rofiPowermenu
    screenshot

    picom
    feh
    # Point-and-click xrandr, for working out a layout worth saving with
    # `autorandr --save`.
    arandr
    pavucontrol

    # The default terminal. Overridable: the i3 binding runs
    # i3-sensible-terminal, which honours $TERMINAL.
    ghostty

    # Named by the shared configs: wpctl for the volume block, dex for XDG
    # autostart, papirus for rofi's icon theme.
    wireplumber
    dex
    papirus-icon-theme
  ];

  # i3-sensible-terminal reads this. It reaches the session because
  # home-manager writes it into ~/.profile, which the X session wrapper
  # sources — so overriding TERMINAL in a personal file is enough to change
  # the terminal without touching the i3 config.
  home.sessionVariables.TERMINAL = lib.mkDefault "ghostty";

  # One cursor theme and size, declared once.
  #
  # With XCURSOR_THEME and XCURSOR_SIZE unset, the X server, GTK and Chrome
  # each pick their own default, and the pointer changes size crossing between
  # windows. GNOME sets these for you; i3 does not.
  #
  # This writes ~/.icons/default/index.theme, the Xresources entries and the
  # GTK settings together, so all three agree.
  home.pointerCursor = {
    package = lib.mkDefault pkgs.adwaita-icon-theme;
    name = lib.mkDefault "Adwaita";
    size = lib.mkDefault 24;
    x11.enable = lib.mkDefault true;
    gtk.enable = lib.mkDefault true;
  };

  # home.pointerCursor's gtk.enable only sets gtk.cursorTheme; the settings
  # files GTK and Chrome actually read are written by this module, and without
  # it the cursor size reaches everything except the GTK applications.
  gtk.enable = lib.mkDefault true;

  # Kept as plain files rather than generated by home-manager's i3 module:
  # they were ported from an existing setup and stay diffable against it.
  home.file = {
    ".config/i3/config".source = lib.mkDefault ./etc/i3/config;
    ".config/i3blocks/config".source = lib.mkDefault ./etc/i3blocks/config;
    ".config/i3blocks/blocks" = {
      source = lib.mkDefault ./etc/i3blocks/blocks;
      recursive = lib.mkDefault true;
    };
    ".config/rofi/config.rasi".source = lib.mkDefault ./etc/rofi/config.rasi;
    ".config/rofi/colors.rasi".source = lib.mkDefault ./etc/rofi/colors.rasi;
    ".config/rofi/launcher.rasi".source = lib.mkDefault ./etc/rofi/launcher.rasi;
    ".config/rofi/powermenu.rasi".source = lib.mkDefault ./etc/rofi/powermenu.rasi;
    ".config/rofi/calendar.rasi".source = lib.mkDefault ./etc/rofi/calendar.rasi;
    ".config/picom/picom.conf".source = lib.mkDefault ./etc/picom/picom.conf;
    # Theme names are the file names under ghostty's share/ghostty/themes,
    # spaces included. onedark, to match the rofi themes.
    ".config/ghostty/config".text = lib.mkDefault ''
      theme = Atom One Dark
      window-decoration = none
    '';
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
}
