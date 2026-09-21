# Screen locking for the i3 session.
#
# Three declarations that only work together, which is why they are in one
# file: xss-lock for the event-driven cases, a PAM stack for the locker, and
# xautolock for the idle case. Removing any one of them silently leaves an
# unlocked laptop — exactly the regression system-level review exists to catch
# (D14, D36).
{ config, lib, pkgs, ... }:

let
  lockCommand = pkgs.callPackage ./fleet-lock.nix { };
in
{
  config = lib.mkIf (config.fleet.desktop == "i3") {
    # xss-lock covers the event-driven cases: suspend, lid close, and
    # `loginctl lock-session` (bound to $mod+Shift+x in the i3 config).
    # --ignore-sleep is deliberately NOT set, so the screen is locked before
    # the machine suspends rather than after it wakes.
    programs.xss-lock = {
      enable = true;
      lockerCommand = "${lockCommand}/bin/fleet-lock";
    };

    # The locker's own PAM stack. unixAuth is on by default, so this accepts
    # the login password; fprintAuth adds the reader.
    #
    # i3lock was the locker here first and was replaced because its PAM
    # conversation is password-shaped: with pam_fprintd in the stack it
    # appears to hang until you press Enter. xsecurelock drives PAM
    # properly and shows the "place your finger" prompt (D36).
    security.pam.services.xsecurelock.fprintAuth = true;

    # xautolock covers the idle case. Five minutes, matching the GNOME
    # branch's idle-delay=300 — the two sessions must not differ in how long
    # an unattended laptop stays readable.
    #
    # It calls loginctl rather than i3lock directly so that the lock goes
    # through xss-lock and logind agrees the session is locked.
    services.xserver.xautolock = {
      enable = true;
      time = 5;
      locker = "${pkgs.systemd}/bin/loginctl lock-session";
    };

    # xautolock only knows about keyboard/mouse idle time, so a video call
    # still locks: Chrome asks the desktop to hold off locking via the
    # freedesktop.org ScreenSaver Inhibit D-Bus call, but nothing on i3
    # answers that call — GNOME's session manager normally does. xssproxy
    # is the missing listener: it forwards Inhibit/UnInhibit to the X11
    # idle counter that xautolock and xss-lock already read, bringing i3
    # to parity with what GNOME already lets apps do (D14: this is not a
    # new weakening, both branches already yield to an app-requested
    # inhibit — i3 just didn't have anything to receive the request).
    systemd.user.services.xssproxy = {
      description = "Forward ScreenSaver D-Bus inhibit calls to Xss";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.xssproxy}/bin/xssproxy";
        Restart = "always";
      };
    };
  };
}
