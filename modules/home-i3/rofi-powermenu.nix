# Power menu for $mod+Shift+e. The reference config this was ported from
# bound it to a script that probed /usr/bin/betterlockscreen and
# /usr/bin/i3lock — neither exists on NixOS, so its lock entry did nothing
# at all. This one asks logind, as the $mod+Shift+x binding does.
{ writeShellApplication, rofi, systemd, coreutils, procps, i3, gnused }:

writeShellApplication {
  name = "rofi-powermenu";
  # procps for uptime; coreutils `uname -n` rather than `hostname`, which
  # coreutils does not install on NixOS.
  runtimeInputs = [ rofi systemd coreutils procps i3 gnused ];
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
}
