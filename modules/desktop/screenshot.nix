# Screenshots: one `screenshot` command on every machine, whichever desktop
# it boots into. The i3 config binds it to Print, Shift+Print and $mod+Print;
# GNOME binds its own UI to Print and the command is there for the terminal
# and for scripts.
#
# The two sessions share nothing underneath, so this is one front door with
# two implementations behind it, chosen at run time by the session type:
#
#   X11 (i3)         maim, composed with xclip and xdotool. No tray icon, no
#                    daemon, nothing to keep running. Every mode copies to
#                    the clipboard and also writes a dated file under
#                    ~/Pictures/screenshots, so a screenshot is never lost to
#                    whatever lands in the clipboard next.
#
#   Wayland (GNOME)  GNOME's own screenshot UI, opened through the
#                    xdg-desktop-portal. Nothing else can take one on GNOME
#                    50: the shell's D-Bus screenshot service answers only
#                    its own media-keys daemon and the GNOME portal backend
#                    (gnome-shell, js/ui/screenshot.js), which is what
#                    retired gnome-screenshot, and mutter does not speak the
#                    wlroots protocols that grim and friends need. The UI
#                    saves to ~/Pictures/Screenshots and copies to the
#                    clipboard by itself. It has its own picker for screen,
#                    window or area, so the mode argument is only honoured
#                    on X11.
#
# The portal half is a page of Python rather than a `gdbus call`: the portal
# closes a request the moment its sender's bus connection goes away, which
# would cancel the UI as soon as gdbus returned. The client has to stay on
# the bus until the Response signal arrives (screenshot-portal.py).
{ writeShellApplication, maim, xclip, xdotool, libnotify, coreutils, python3 }:

let
  portalPython = python3.withPackages (p: [ p.pygobject3 ]);
in
writeShellApplication {
  name = "screenshot";
  runtimeInputs = [ maim xclip xdotool libnotify coreutils ];
  text = ''
    mode=''${1:-screen}
    case "$mode" in
      screen|select|window) ;;
      *) echo "usage: screenshot [screen|select|window]" >&2; exit 2 ;;
    esac

    if [ "''${XDG_SESSION_TYPE:-}" = wayland ] || [ -n "''${WAYLAND_DISPLAY:-}" ]; then
      exec ${portalPython}/bin/python3 ${./screenshot-portal.py}
    fi

    dir=''${XDG_PICTURES_DIR:-$HOME/Pictures}/screenshots
    mkdir -p "$dir"
    file=$dir/$(date +%Y-%m-%d_%H-%M-%S).png

    case "$mode" in
      screen) maim --hidecursor "$file" ;;
      # --nokeyboard so Escape cancels the selection instead of being
      # swallowed; maim exits non-zero, and that is not an error.
      select) maim --nokeyboard --select "$file" || exit 0 ;;
      window) maim --hidecursor --window "$(xdotool getactivewindow)" "$file" ;;
    esac

    [ -s "$file" ] || { rm -f "$file"; exit 0; }

    xclip -selection clipboard -t image/png -i "$file"
    notify-send "Screenshot" "copied to clipboard
    $file" --icon=camera-photo
  '';
}
