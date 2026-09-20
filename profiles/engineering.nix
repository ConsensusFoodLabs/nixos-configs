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
        lockerCommand = "${pkgs.i3lock}/bin/i3lock --nofork --color=1E2127";
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
        # Named by oleg's rofi themes and i3 bar. A Nerd Font, so the glyphs
        # the upstream themes use render instead of showing as boxes.
        nerd-fonts.jetbrains-mono
      ];
    })

    {
      services.printing.enable = true;

      services.pipewire = {
        enable = true;
        # The PulseAudio server emulation. Chrome, Slack and Firefox all talk
        # to PulseAudio rather than to PipeWire natively, so without this they
        # find no devices at all even though the hardware is working.
        pulse.enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
      };

      # PipeWire asks rtkit for realtime scheduling priority. Without it the
      # daemon still runs, but at normal priority: audio glitches and drops
      # under load. The NixOS pipewire module does not turn this on for you.
      security.rtkit.enable = true;

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
        # Where the team actually talks. Unfree, so it also needs its
        # allowlist entry in profiles/base.nix (D20).
        slack
        # Microsoft's build, not vscodium: it is what people expect, and the
        # extension marketplace is the reason to use it. Also unfree (D20).
        vscode
        ripgrep
        fd
        jq
        tmux
        gnumake
      ];
    }
  ];
}
