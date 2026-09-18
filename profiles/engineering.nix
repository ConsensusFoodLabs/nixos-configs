# Engineering laptop profile: desktop environment and shared developer tools.
#
# Changes here reach every engineering machine, so they go through tight
# review. Personal tooling belongs in users/<name>/home.nix instead (D14).
{ config, lib, pkgs, ... }:

{
  # GNOME, chosen for working defaults on modern hardware and because it
  # provides screen locking — a security control, which is why it is declared
  # here at the system level rather than in anyone's home configuration (D14).
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
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

  services.printing.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  # Shared baseline. Not a restriction: developers install what they need
  # (docs/software-policy.md). Things that turn out to be broadly useful
  # belong here so everyone gets them.
  environment.systemPackages = with pkgs; [
    firefox
    ripgrep
    fd
    jq
    tmux
    gnumake
  ];
}
