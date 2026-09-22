# The daemons an i3 session needs in order to behave, rather than to look a
# particular way.
#
# All user services, all declared at the system level so that a personal
# home-manager file cannot remove them (D38).
{ config, lib, pkgs, ... }:

{
  config = lib.mkIf (config.fleet.desktop == "i3") {
    # The three daemons a session needs in order to behave, rather than to
    # look a particular way. They are here and not in modules/home-i3
    # because a personal file must not be able to remove them: without the
    # polkit agent an authorisation request fails with no prompt at all,
    # and without a notification daemon the battery warning, the automount
    # notice and the screenshot confirmation go nowhere (D38).
    systemd.user.services.dunst = {
      description = "dunst notification daemon";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.dunst}/bin/dunst";
        Restart = "on-failure";
      };
    };

    systemd.user.services.nm-applet = {
      description = "NetworkManager applet";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet";
        Restart = "on-failure";
      };
    };

    systemd.user.services.polkit-gnome-authentication-agent = {
      description = "polkit authentication agent";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart =
          "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
      };
    };

    # Automounting removable media.
    #
    # udisks2 is already running — it is on by default — but it only ever
    # mounts when something asks. GNOME's Files was the thing asking. With
    # no desktop, inserting a USB stick does nothing observable at all:
    # no error, no icon, no mount.
    systemd.user.services.udiskie = {
      description = "Automount removable media";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.udiskie}/bin/udiskie --tray --automount --notify";
        Restart = "on-failure";
      };
    };

    # Battery warnings.
    #
    # Nothing else tells you the battery is nearly flat. logind will act at
    # the very end, but there is no warning before it, so the first signal
    # is the machine going away with unsaved work. The bar's battery block
    # turns red at 15%, which only helps if you are looking at it.
    systemd.user.services.poweralertd = {
      description = "Battery and power notifications";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.poweralertd}/bin/poweralertd";
        Restart = "on-failure";
      };
    };
  };
}
