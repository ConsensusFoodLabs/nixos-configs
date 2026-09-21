# The screen locker, with its settings baked in rather than left to the
# session environment: this command is run by xss-lock from a systemd user
# service, which does not inherit a login shell's variables.
#
# XSECURELOCK_PAM_SERVICE is the one that matters. It defaults to "login",
# and pointing it at a service that does not exist is not a soft failure:
# NixOS's fallback PAM service `other` is pam_deny in every phase, so the
# lock screen would reject every correct password. The matching
# security.pam.services.xsecurelock below is not optional.
{ writeShellApplication, xsecurelock }:

writeShellApplication {
  name = "fleet-lock";
  runtimeInputs = [ xsecurelock ];
  text = ''
    export XSECURELOCK_PAM_SERVICE=xsecurelock
    export XSECURELOCK_SHOW_DATETIME=1
    export XSECURELOCK_SHOW_USERNAME=1
    # Blank after a minute rather than showing the prompt indefinitely.
    export XSECURELOCK_BLANK_TIMEOUT=60
    # Keeps the lock visible if a compositor is running, which one is.
    export XSECURELOCK_COMPOSITE_OBSCURER=1
    exec xsecurelock
  '';
}
