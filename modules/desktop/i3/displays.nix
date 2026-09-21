# Monitors, and the touchscreen that has to follow them.
#
# One file because they are one problem: autorandr changes the screen
# geometry, and every geometry change silently un-maps the touchscreen, so
# whatever drives the first must also drive the second.
{ config, lib, pkgs, ... }:

let
  mapTouchscreen = pkgs.callPackage ./map-touch-to-panel.nix { };
in
{
  config = lib.mkIf (config.fleet.desktop == "i3") {
    # Displays, on hotplug.
    #
    # GNOME's mutter reconfigures outputs by itself; i3 does not do display
    # management at all, so plugging in a dock gets you a second screen that
    # is connected, powered, and showing nothing until something calls
    # xrandr. autorandr is that something: it ships a udev rule on
    # SUBSYSTEM=="drm" that starts autorandr.service, and the service runs
    # --batch, which applies the layout inside each running X session rather
    # than only for root.
    #
    # defaultTarget is the fallback used when no saved profile matches the
    # connected set of monitors, which is every profile until someone saves
    # one. "horizontal" lays the outputs out left to right at their
    # preferred modes — so a new dock or a borrowed monitor lights up
    # without anyone having configured anything, and unplugging falls back
    # to the laptop panel.
    #
    # Saved layouts are per-user and live in ~/.config/autorandr, matched by
    # the monitors' EDIDs (docs/operations.md). They are not declared here:
    # a fingerprint is specific to one desk, not to the fleet.
    services.autorandr = {
      enable = true;
      defaultTarget = "horizontal";

      # Re-confine the touchscreen after every layout change. Mapping is
      # lost whenever the screen geometry changes, so plugging in a dock
      # silently un-does it.
      hooks.postswitch."10-map-touchscreen" =
        "${mapTouchscreen}/bin/map-touch-to-panel";
    };

    # And once when the session starts, since no layout change happens at
    # login.
    systemd.user.services.map-touch-to-panel = {
      description = "Confine touchscreen input to the built-in panel";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${mapTouchscreen}/bin/map-touch-to-panel";
      };
    };
  };
}
