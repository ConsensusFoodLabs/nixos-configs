# Engineering laptop profile: desktop environment and shared developer tools.
#
# Changes here reach every engineering machine, so they go through tight
# review. Personal tooling belongs in users/<name>/home.nix instead (D14).
{ config, lib, pkgs, ... }:

{
  # The desktop session is chosen per device in fleet/inventory.nix, not per
  # person in a home configuration. The reason is screen locking: it is a
  # security control, so it is declared at the system level where light review
  # cannot reach it (D14). Each branch below is responsible for locking its
  # own session. A desktop with no locking declared is not an option here —
  # that is what makes fleet.desktop an enum rather than a string.
  #
  # Both branches lock after five minutes idle and on suspend.

  config = lib.mkMerge [
    {
      services.xserver.enable = true;
      services.displayManager.gdm.enable = true;
    }

    (lib.mkIf (config.fleet.desktop == "gnome") {
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
    })

    (lib.mkIf (config.fleet.desktop == "i3") {
      services.displayManager.defaultSession = "none+i3";

      services.xserver.windowManager.i3 = {
        enable = true;
        # i3blocks, not i3status: the bar is configured in the owner's home
        # directory and its blocks are shipped from users/<name>/etc.
        extraPackages = with pkgs; [ i3blocks i3lock ];
      };

      # i3 ships no screen locking of its own, so it is declared here in two
      # halves. Removing either one silently leaves an unlocked laptop, which
      # is exactly the kind of regression system-level review exists to catch.
      #
      # xss-lock covers the event-driven cases: suspend, lid close, and
      # `loginctl lock-session` (bound to $mod+Shift+x in the i3 config).
      # --ignore-sleep is deliberately NOT set, so the screen is locked before
      # the machine suspends rather than after it wakes.
      programs.xss-lock = {
        enable = true;
        lockerCommand = "${pkgs.i3lock}/bin/i3lock --nofork --color=1d2021";
      };

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

      # Brightness keys. acpilight provides an xbacklight-compatible command
      # that writes sysfs, which works on hardware where the X RANDR backlight
      # property does not exist. Users in `video` may use it.
      hardware.acpilight.enable = true;

      services.libinput.enable = true;

      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-color-emoji
        fira-code
        nerd-fonts.droid-sans-mono
      ];
    })

    {
      services.printing.enable = true;
      services.pipewire = {
        enable = true;
        pulse.enable = true;
      };

      # Shared baseline. Not a restriction: developers install what they need
      # (docs/software-policy.md). Things that turn out to be broadly useful
      # belong here so everyone gets them.
      environment.systemPackages = with pkgs; [
        # Two browsers on purpose. Firefox is the free default; Chrome is here
        # because web work needs testing against Blink and because several
        # things the team depends on are only supported there. Chrome is
        # unfree, so it also needs its allowlist entry in profiles/base.nix
        # (D20) — the two have to move together.
        firefox
        google-chrome
        ripgrep
        fd
        jq
        tmux
        gnumake
      ];
    }
  ];
}
