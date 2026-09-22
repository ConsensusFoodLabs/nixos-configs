# A graphical session: the parts a laptop needs in order to be usable and
# safe, regardless of who is sitting at it.
#
# This is system configuration under tight review, and that is the whole
# point of it being here rather than in modules/home-i3: screen locking, the
# polkit agent and the notification daemon are security or safety controls, so
# a lightly-reviewed personal file must not be able to remove them (D14, D38).
# Look, feel and preference belong in home-manager.
#
# Imported by profiles/engineering.nix. It is a module rather than part of
# that profile because a second profile would want the same session, and
# because "which desktop" is already a fleet attribute rather than a profile
# one (D33).
{ ... }:

{
  imports = [
    ./gnome.nix
    ./i3
    ./services.nix
    ./audio.nix
  ];

  # The desktop session is chosen per device in fleet/inventory.nix, not per
  # person in a home configuration. The reason is screen locking: it is a
  # security control, so it is declared at the system level where light review
  # cannot reach it (D14). Each branch below is responsible for locking its
  # own session. A desktop with no locking declared is not an option here —
  # that is what makes fleet.desktop an enum rather than a string.
  #
  # Both branches lock after five minutes idle and on suspend.
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
}
