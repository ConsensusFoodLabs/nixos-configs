# Personal configuration for oleg.
#
# Light review: this file is yours. Add tooling, change the shell, restyle the
# prompt. Shared defaults come from modules/home-common.nix and can be
# overridden here.
#
# What does not belong here: anything security-relevant (screen locking,
# firewall, encryption, sudo). Those live at the system level (D14), and
# administrator rights are granted in fleet/inventory.nix, not here (D12).
{ config, lib, pkgs, ... }:

{
  imports = [ ../../modules/home-common.nix ];

  home.packages = with pkgs; [
    jujutsu
    claude-code
  ];
}
