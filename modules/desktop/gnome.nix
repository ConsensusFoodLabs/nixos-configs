# The GNOME session.
#
# Selected by a machine's inventory entry, not by its owner (D33).
{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.fleet.desktop == "gnome") {
    # GNOME, chosen for working defaults on modern hardware and because it
    # provides screen locking out of the box.
    services.desktopManager.gnome.enable = true;

    # Screen locking is not optional and is not a personal preference.
    services.desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.desktop.screensaver]
      lock-enabled=true
      lock-delay=0

      [org.gnome.desktop.session]
      idle-delay=300
    '';
    services.desktopManager.gnome.extraGSettingsOverridePackages =
      [ pkgs.gnome-settings-daemon ];
  };
}
