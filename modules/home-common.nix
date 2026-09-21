# home-manager baseline, applied to every developer.
#
# Everything here uses lib.mkDefault: these are defaults to override, not walls
# to fight. Personal configuration lives in users/<name>/home.nix (D14).
#
# Security-relevant settings do NOT belong in this file or any home-manager
# file — screen locking, firewall, disk encryption, sudo, audit and login
# policy stay at the NixOS system level, where light review cannot reach them.
{ config, lib, pkgs, person, ... }:

{
  home.stateVersion = lib.mkDefault "26.05";

  programs.git = {
    enable = lib.mkDefault true;
    settings.user = {
      name = lib.mkDefault person.fullName;
      email = lib.mkDefault person.email;
    };
  };

  # jujutsu ships fleet-wide (modules/dev-toolchain.nix), and refuses to
  # commit without a name and email. Same source as git's, so the two cannot
  # disagree about who you are.
  programs.jujutsu = {
    enable = lib.mkDefault true;
    # Config only: the binary comes from the shared baseline, so without this
    # jj is installed twice and the home profile's copy shadows the system
    # one on PATH.
    package = lib.mkDefault null;
    settings.user = {
      name = lib.mkDefault person.fullName;
      email = lib.mkDefault person.email;
    };
  };

  programs.bash.enable = lib.mkDefault true;
  programs.starship.enable = lib.mkDefault true;
  programs.direnv = {
    enable = lib.mkDefault true;
    nix-direnv.enable = lib.mkDefault true;
  };

  home.packages = with pkgs; [
    ripgrep
    fd
    jq
  ];
}
