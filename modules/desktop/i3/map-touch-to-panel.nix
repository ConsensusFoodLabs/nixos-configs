# Confine direct-touch devices to the built-in panel.
#
# X maps an absolute pointing device onto the whole virtual screen, not onto
# the display it is physically bonded to. That is invisible on a laptop on
# its own and badly wrong the moment a second monitor appears: the virtual
# screen grows, and a touch at the middle of the panel lands wherever that
# fraction falls across the whole desktop. Touches come out scaled by the
# ratio of the virtual screen to the panel.
#
# Devices are found by the "libinput Calibration Matrix" property rather
# than by name. Touchscreen product names are vendor strings like
# "ELAN9008:00 04F3:4A1D" with nothing recognisable in them, and matching on
# them would break on the next model. The property is present on direct-touch
# devices — touchscreens and pens — and absent on mice and touchpads, which
# is exactly the distinction that matters here: a pen should be confined to
# the same panel its touchscreen is.
{ writeShellApplication, xinput, xrandr, gnugrep, gawk, coreutils }:

writeShellApplication {
  name = "map-touch-to-panel";
  # coreutils for head: writeShellApplication prepends runtimeInputs to PATH
  # but the unit's own environment is minimal, so nothing may be inherited.
  runtimeInputs = [ xinput xrandr gnugrep gawk coreutils ];
  text = ''
    panel=$(xrandr --query | awk '/ connected/ { print $1 }' |
      grep -E '^(eDP|LVDS)' | head -n 1)

    if [ -z "$panel" ]; then
      echo "map-touch-to-panel: no internal panel found; nothing to do"
      exit 0
    fi

    found=0
    while read -r id; do
      [ -n "$id" ] || continue
      if xinput list-props "$id" 2>/dev/null |
          grep -q "libinput Calibration Matrix"; then
        name=$(xinput list --name-only "$id" 2>/dev/null || echo "id $id")
        echo "map-touch-to-panel: $name -> $panel"
        xinput map-to-output "$id" "$panel" || true
        found=1
      fi
    done < <(xinput list --id-only)

    [ "$found" = 1 ] || echo "map-touch-to-panel: no direct-touch devices"
  '';
}
