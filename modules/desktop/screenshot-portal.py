# Open the desktop's screenshot UI through the xdg-desktop-portal and stay on
# the bus until it is done. Run by `screenshot` on Wayland sessions; see
# screenshot.nix for why a one-shot `gdbus call` cannot do this.
#
# Interactive, so the portal skips its "allow applications to take
# screenshots?" permission dialog and the desktop opens its own picker. On
# GNOME that picker saves the file and fills the clipboard itself, so there
# is nothing left to do with the result but report how it ended.
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PORTAL = "org.freedesktop.portal.Desktop"
DESKTOP = "/org/freedesktop/portal/desktop"

loop = GLib.MainLoop()
outcome = {"status": 0}


def on_response(_conn, _sender, _path, _iface, _signal, params):
    # 0: success, 1: the user cancelled, 2: ended some other way.
    code, _results = params.unpack()
    if code == 2:
        print("screenshot: the portal request failed", file=sys.stderr)
        outcome["status"] = 1
    loop.quit()


try:
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    # The portal names the request after the caller's unique name and the
    # token we hand it, so the Response can be subscribed to before the call
    # is made and cannot be missed.
    token = f"screenshot{os.getpid()}"
    sender = bus.get_unique_name()[1:].replace(".", "_")
    request = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    bus.signal_subscribe(
        PORTAL, "org.freedesktop.portal.Request", "Response", request,
        None, Gio.DBusSignalFlags.NONE, on_response,
    )

    options = {
        "handle_token": GLib.Variant("s", token),
        "interactive": GLib.Variant("b", True),
    }
    bus.call_sync(
        PORTAL, DESKTOP, "org.freedesktop.portal.Screenshot", "Screenshot",
        GLib.Variant("(sa{sv})", ("", options)),
        None, Gio.DBusCallFlags.NONE, -1, None,
    )
except GLib.Error as e:
    print(f"screenshot: {e.message}", file=sys.stderr)
    sys.exit(1)

loop.run()
sys.exit(outcome["status"])
