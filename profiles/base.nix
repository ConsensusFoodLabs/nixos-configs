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
    #
    # The limit is set by the ESP, which is 1 GiB (hosts/*/disko.nix). Each
    # entry costs a kernel plus an initrd — 54 MiB on this hardware today, and
    # growing as firmware does. Twenty entries is 1096 MiB: over budget. An
    # ESP with no room left fails the bootloader install during
    # nixos-rebuild, which leaves fewer working entries than any limit would.
    #
    # Ten is ~540 MiB, leaving room for kernels to grow and for the transient
    # extra copy while an update installs. If this is ever raised, check the
    # arithmetic against the ESP first — `fleet-status` prints how full it is.
    configurationLimit = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # SSH is enabled, in modules/fleet/admin.nix, and configured there.
  #
  # This said `enable = false` with the note "laptops are not servers, nothing
  # should be reaching in" — which was the right default until administrators
  # needed to reach a machine whose owner cannot help. That is a deliberate
  # reversal, not an oversight, and it is why the settings live next to the
  # admin account they exist for rather than here (D32).

  security.sudo.wheelNeedsPassword = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;

    # Collect garbage under disk pressure, not only on a schedule.
    #
    # The weekly timer below bounds how *old* generations get. It does
    # nothing about a single afternoon that fills the disk — which is the
    # failure that actually happens, and it happens mid-build, where the
    # error is confusing and the work is lost.
    #
    # These make the daemon do it instead: when free space drops below
    # min-free during a build, it collects until max-free is free and carries
    # on. Roots are respected, so nothing in use or reachable from a live
    # generation is touched.
    min-free = 5 * 1024 * 1024 * 1024; # 5 GiB: start collecting
    max-free = 20 * 1024 * 1024 * 1024; # 20 GiB: stop collecting
  };

  # Generation pruning, with a deliberate floor.
  #
  # 30 days is a safety control, not housekeeping: the previous generation in
  # the boot menu is how a machine recovers from an update that breaks
  # networking, and these laptops have no Ethernet port. Do not lower this to
  # reclaim disk space — that trades away the recovery mechanism (D18).
  # nix.gc.persistent defaults to true, which matters here: these are laptops,
  # they are asleep at 03:15, and a non-persistent weekly timer on a machine
  # that is never awake at the scheduled minute simply never runs.
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
      "google-chrome"
      "slack"
      "vscode"
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
