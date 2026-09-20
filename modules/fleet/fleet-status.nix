# fleet-status: what is this machine actually running? (D17)
#
# A debugging aid, not monitoring. Nothing collects this centrally and nobody
# reviews it on a schedule, so it must not be described as a detective control.
{ pkgs, config, lib, ... }:

let
  inherit (config.fleet) repoUrl flakeRef;

  # Accounts whose password comes from a file. An absent file leaves the
  # account locked with only a warning at activation, which is easy to miss and
  # then presents as sudo rejecting a password that is definitely correct.
  passwordFiles = lib.mapAttrsToList (n: u: "${n} ${u.hashedPasswordFile}")
    (lib.filterAttrs (_: u: u.hashedPasswordFile != null) config.users.users);

  fleet-status = pkgs.writeShellApplication {
    name = "fleet-status";
    runtimeInputs = with pkgs; [ nix git jq coreutils ];
    text = ''
      rev=${lib.escapeShellArg (config.system.configurationRevision or "unknown")}

      echo "host:        $(hostname)"
      echo "nixos:       $(nixos-version)"
      echo "built from:  $rev"

      if [ "$rev" = "dirty" ]; then
        echo
        echo "WARNING: built from an uncommitted tree. This system cannot be"
        echo "traced back to a source state. Rebuild from a pushed revision."
      fi

      echo
      echo "upstream:"
      if upstream=$(git ls-remote ${repoUrl} HEAD 2>/dev/null | cut -f1); then
        echo "  main is at $upstream"
        if [ "$upstream" = "$rev" ]; then
          echo "  this machine is up to date"
        else
          echo "  this machine is NOT on the current revision"
          echo "  update: run fleet-update"
        fi
      else
        echo "  could not reach upstream"
      fi

      echo
      echo "account passwords:"
      ${lib.concatMapStringsSep "
      " (entry: ''
        set -- ${entry}
        if [ -e "$2" ]; then
          echo "  $1: set"
        else
          echo "  $1: MISSING $2 — this account is locked out."
          echo "      fix with: sudo fleet-set-password $1"
        fi
      '') passwordFiles}

      echo
      echo "packages installed outside the declared baseline:"
      if profile=$(nix profile list 2>/dev/null) && [ -n "$profile" ]; then
        while IFS= read -r line; do printf '  %s\n' "$line"; done <<< "$profile"
      else
        echo "  none"
      fi
    '';
  };
in
{
  environment.systemPackages = [ fleet-status ];
}
