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
