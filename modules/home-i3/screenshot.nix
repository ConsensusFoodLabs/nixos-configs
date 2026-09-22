# Screenshots. There was no PrintScreen binding at all after the move off
# GNOME, which provided one.
#
# maim rather than flameshot: no tray icon, no daemon, nothing to keep
# running, and it composes with xclip. Every mode copies to the clipboard
# and also writes a dated file, so a screenshot is never lost to whatever
# lands in the clipboard next.
{ writeShellApplication, maim, xclip, xdotool, libnotify, coreutils }:

writeShellApplication {
  name = "screenshot";
  runtimeInputs = [ maim xclip xdotool libnotify coreutils ];
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
}
