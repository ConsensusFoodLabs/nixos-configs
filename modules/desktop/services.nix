# What a desktop session needs from the system, whichever session it is.
#
# Printing and discovery, portals, trash and removable-media plumbing, a
# secret store, and Bluetooth. GNOME ships most of this itself; under i3
# every line here is something whose absence looked like nothing at all until
# it was missed (D37).
{ pkgs, ... }:

{
  services.printing.enable = true;

  # Printer and service discovery on the local network.
  #
  # Browse-only: publish.enable stays at its default of false, so this
  # machine asks who is on the network and never announces itself. That
  # distinction matters on a laptop that joins cafe and hotel networks —
  # openFirewall does open UDP 5353 to receive responses, which is the
  # cost of discovery working at all.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Portals, so an application asking the desktop to open a file picker or
  # share a screen gets an answer.
  #
  # Less load-bearing than it looks on X11: Chrome and Slack capture the
  # screen through X11 directly and do not need a portal for it. The
  # reason to have one is the applications that ask for a portal first and
  # degrade awkwardly when nothing answers — file choosers mainly. The
  # explicit `config.common.default` matters: with a portal enabled and no
  # default set, requests can hang waiting for a backend to volunteer.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "gtk" ];
  };

  # Trash, phones over MTP, and network shares. GNOME pulls this in; on
  # its own, "move to trash" fails and a plugged-in phone is invisible.
  services.gvfs.enable = true;

  # A secret store, so browsers and chat clients have somewhere safe to
  # put credentials.
  #
  # GNOME ships this. i3 does not, and without a Secret Service on the
  # bus Chrome silently falls back to its "basic" password store, which
  # is plaintext in the profile directory — a regression that arrived
  # with the desktop switch and looked like nothing at all (D37).
  #
  # pam_gnome_keyring unlocks the keyring with the login password. GDM
  # handles the fingerprint-login case itself through pam_gdm, which
  # retrieves the stored credential, so logging in with a finger does not
  # leave the keyring locked.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # Bluetooth, for headsets. PipeWire already handles the audio side.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };
}
