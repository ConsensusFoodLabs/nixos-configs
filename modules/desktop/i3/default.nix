# The i3 session, at the system level.
#
# i3 is a window manager and nothing else: everything a desktop environment
# would have brought with it has to be declared somewhere. The parts that are
# preference — bar, launcher, compositor, dotfiles — are in modules/home-i3,
# where a personal file overrides them. The parts that are not are here, split
# by what they do:
#
#   locking.nix    the screen locker, in the three halves it takes
#   displays.nix   monitors on hotplug, and the touchscreen that follows them
#   session.nix    the daemons a session needs in order to behave
#
# This file holds what is left: the window manager itself, the packages the
# session's own tools call, and the hardware knobs GNOME would have driven.
{ config, lib, pkgs, ... }:

let
  mapTouchscreen = pkgs.callPackage ./map-touch-to-panel.nix { };
in
{
  imports = [
    ./locking.nix
    ./displays.nix
    ./session.nix
  ];

  config = lib.mkIf (config.fleet.desktop == "i3") {
    services.displayManager.defaultSession = "none+i3";

    services.xserver.windowManager.i3 = {
      enable = true;
      # i3blocks, not i3status: the bar is configured in the owner's home
      # directory and its blocks are shipped from users/<name>/etc.
      extraPackages = with pkgs; [ i3blocks ];
    };

    environment.systemPackages = [
      mapTouchscreen
      pkgs.xinput
      # notify-send, so anything in the session can raise a notification.
      pkgs.dunst
      pkgs.libnotify
      # nm-applet's tray icon comes from the unit above, but the package
      # also carries nm-connection-editor, which the bar's network block
      # opens on click. Moving the unit here without the package took that
      # off PATH.
      pkgs.networkmanagerapplet
    ];

    # Brightness keys. acpilight provides an xbacklight-compatible command
    # that writes sysfs, which works on hardware where the X RANDR backlight
    # property does not exist. Users in `video` may use it.
    hardware.acpilight.enable = true;

    # Bluetooth tray applet. GNOME has its own; i3 has nothing.
    services.blueman.enable = true;

    services.libinput.enable = true;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-color-emoji
      fira-code
      # Named by oleg's rofi themes and i3 bar. A Nerd Font, so the glyphs
      # the upstream themes use render instead of showing as boxes.
      nerd-fonts.jetbrains-mono
    ];
  };
}
