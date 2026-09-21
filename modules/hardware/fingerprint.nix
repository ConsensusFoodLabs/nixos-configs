# The fingerprint reader, and the PAM policy that comes with it.
#
# Inseparable, which is why they are one file: enabling fprintd puts
# pam_fprintd into the auth stack of every PAM service on the machine, so the
# exceptions below are part of the same decision rather than a follow-up to it
# (D36).
{ config, lib, ... }:

{
  # Fingerprint reader.
  #
  # The sensor is a Synaptics match-on-chip device: enrolment and matching
  # happen on the reader, and templates do not leave it in raw form. What
  # is stored under /var/lib/fprint is a handle — inside the LUKS volume,
  # machine-local, never in this repository (D36).
  #
  # Note what enabling this actually does: security.pam.services.*
  # .fprintAuth DEFAULTS to services.fprintd.enable, so this one line puts
  # pam_fprintd into the auth stack of every PAM service on the machine,
  # not just the ones named below. That is mostly fine — pam_fprintd
  # authenticates the *target* user, so `su oleg` still needs oleg's
  # finger — but it is not obvious from reading this file, and the two
  # exceptions below are the cases where it matters.
  services.fprintd.enable = true;

  security.pam.services = {
    # Named for the record rather than because they change anything: both
    # are already true by default. These are the paths the reader exists
    # for.
    sudo.fprintAuth = true;
    polkit-1.fprintAuth = true;

    # A remote login must never be approvable by a finger on the local
    # reader. pam_fprintd prompts the reader attached to *this* machine,
    # so if sshd's auth stack were reachable, someone innocently touching
    # the sensor could complete a stranger's SSH login — the person
    # authenticating would not be the person being authenticated.
    #
    # It is not reachable today: modules/fleet/admin.nix turns off both
    # PasswordAuthentication and KbdInteractiveAuthentication, so sshd
    # never runs the PAM auth stack. This is defence against that line
    # changing in a file that says nothing about fingerprints — and the
    # assertion below turns that coupling into a build failure.
    sshd.fprintAuth = false;

    # The fingerprint is meant to be a convenience alternative to the
    # login password. If it can also *rotate* that password, it stops
    # being an alternative and becomes strictly more powerful than the
    # credential it stands in for — the fallback would be resettable by
    # the convenience.
    #
    # This is a structural preference, not a defence against a specific
    # attack: an opportunist at an unattended unlocked laptop does not
    # have your finger either (D36).
    passwd.fprintAuth = false;
    chpasswd.fprintAuth = false;
  };

  assertions = [
    {
      assertion = !(config.security.pam.services.sshd.fprintAuth
        && (config.services.openssh.settings.PasswordAuthentication
        || config.services.openssh.settings.KbdInteractiveAuthentication));
      message = ''
        modules/hardware/fingerprint.nix: sshd accepts password or
        keyboard-interactive authentication while pam_fprintd is in its
        PAM stack. That combination lets a finger on this machine's reader
        approve someone else's remote login.

        Either leave security.pam.services.sshd.fprintAuth = false, or
        turn the ssh authentication methods back off in
        modules/fleet/admin.nix.
      '';
    }
  ];
}
