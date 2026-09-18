# Baseline applied to every machine in the fleet. Tight review.
#
# Security-relevant settings live here, at the system level, and never in
# home-manager — anything under users/ is lightly reviewed (D14).
{ config, lib, pkgs, ... }:

{
  system.stateVersion = "26.05";

  boot.loader.systemd-boot = {
    enable = true;
    # Boot entries, not generations: the recovery mechanism for a bad update
    # is picking the previous generation here (D18).
    configurationLimit = 20;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # Laptops are not servers. Nothing should be reaching in.
  services.openssh.enable = false;

  security.sudo.wheelNeedsPassword = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  # Generation pruning, with a deliberate floor.
  #
  # 30 days is a safety control, not housekeeping: the previous generation in
  # the boot menu is how a machine recovers from an update that breaks
  # networking, and these laptops have no Ethernet port. Do not lower this to
  # reclaim disk space — that trades away the recovery mechanism (D18).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Unfree packages are allowed by explicit name, not blanket-enabled.
  #
  # This is a licensing-visibility control, not a security one: it makes the
  # set of non-free software we ship fleet-wide reviewable in one place, and
  # answers "what proprietary software is on these machines" from the repo.
  # It is not an attempt to restrict what developers run (D15) — anyone can
  # still `nix shell` anything. Adding an entry here is a pull request.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];

  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    htop
  ];

  # Needed for laptops to pull their own configuration.
  programs.git.enable = true;
}
