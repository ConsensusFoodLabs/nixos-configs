# Letting the owner replace the credentials the machine shipped with.
#
# Machines are installed with a generated passphrase and a generated login
# password (D24, D27). Both must be replaceable by the person holding the
# laptop, who is not necessarily an administrator — otherwise "initial
# credentials" is a fiction and everyone keeps the ones in the repository.
#
# Neither tool can touch the organization's recovery keyslot. That is the
# point: the developer owns their own access, and the organization keeps its
# own, and neither can quietly remove the other (D5).
{ config, lib, pkgs, inventory, device, ... }:

let
  user = device.assignedTo;

  # Read from the inventory rather than from config.users.users, which this
  # module's own definitions are part of: asking whether an account exists
  # while helping decide what accounts exist is a fixpoint waiting to bite.
  active = inventory.people.${user}.active or false;

  luksDevice =
    config.disko.devices.disk.main.content.partitions.luks.content.device;

  # `passwd` does the real work — PAM, quality checks, verifying the current
  # password. It writes to /etc/shadow, which users.mutableUsers = false
  # overwrites from hashedPasswordFile at the next rebuild. So we copy the
  # result back into that file, which is what makes the change durable.
  #
  # The privilege this grants is only "persist the hash I already have", which
  # the caller could not use to set a hash of their choosing.
  persistPassword = pkgs.writeShellApplication {
    name = "fleet-persist-password";
    runtimeInputs = with pkgs; [ coreutils gnugrep ];
    text = ''
      caller=''${SUDO_USER:-}
      [ -n "$caller" ] || { echo "fleet-persist-password: run via fleet-passwd" >&2; exit 1; }
      [ "$caller" = ${lib.escapeShellArg user} ] || {
        echo "fleet-persist-password: $caller does not own this machine" >&2
        exit 1
      }

      hash=$(grep "^$caller:" /etc/shadow | cut -d: -f2)
      case "$hash" in
        "" | "!"* | "*") echo "fleet-persist-password: no usable hash for $caller" >&2; exit 1 ;;
      esac

      install -d -m 0755 /var/lib/fleet
      umask 077
      printf '%s\n' "$hash" > "/var/lib/fleet/$caller.passwd"
      echo "password change persisted; it will survive nixos-rebuild"
    '';
  };

  fleetPasswd = pkgs.writeShellApplication {
    name = "fleet-passwd";
    # Deliberately NOT pkgs.shadow: that would put the plain store passwd on
    # PATH ahead of the setuid wrapper, and it cannot write /etc/shadow. Only
    # the wrapper can, so name it by path.
    runtimeInputs = [ pkgs.sudo ];
    text = ''
      echo "Changing the login password for $USER."
      ${config.security.wrapperDir}/passwd
      sudo -n ${persistPassword}/bin/fleet-persist-password
    '';
  };

  # Only ever writes keyslot 0, and refuses unless the passphrase given opens
  # keyslot 0. Without that check, someone holding the recovery key could move
  # it into slot 0 — this tool must not be a way to interfere with escrow.
  changePassphrase = pkgs.writeShellApplication {
    name = "fleet-change-passphrase";
    runtimeInputs = with pkgs; [ coreutils cryptsetup ];
    text = ''
      caller=''${SUDO_USER:-}
      [ "$caller" = ${lib.escapeShellArg user} ] || {
        echo "fleet-change-passphrase: $caller does not own this machine" >&2
        exit 1
      }

      dev=${lib.escapeShellArg luksDevice}

      # cryptsetup takes each passphrase as a whole file, so they go into a
      # directory on /run — a tmpfs — and are removed however this exits.
      # Written without a trailing newline, or the resulting passphrase would
      # contain one and could never be typed at the boot prompt.
      tmp=$(mktemp -d /run/fleet-passphrase.XXXXXX)
      chmod 700 "$tmp"
      trap 'rm -rf "$tmp"' EXIT

      read -rsp "Current disk passphrase: " old; echo
      printf '%s' "$old" > "$tmp/old"

      if ! cryptsetup open --test-passphrase --key-slot 0 \
          --key-file "$tmp/old" "$dev" 2>/dev/null; then
        echo >&2
        echo "That passphrase does not open keyslot 0." >&2
        echo "Only the passphrase this machine was installed with can be changed here;" >&2
        echo "the recovery keyslot is deliberately out of reach." >&2
        exit 1
      fi

      read -rsp "New disk passphrase: " new; echo
      read -rsp "Repeat new passphrase: " again; echo
      [ "$new" = "$again" ] || { echo "passphrases do not match" >&2; exit 1; }
      [ "''${#new}" -ge 12 ] || { echo "use at least 12 characters" >&2; exit 1; }
      printf '%s' "$new" > "$tmp/new"

      # --key-slot names where the NEW key lands; --key-file authorises with
      # the old one. Together with the slot-0 test above, this replaces slot 0
      # and can reach no other slot.
      cryptsetup luksChangeKey --key-slot 0 \
        --key-file "$tmp/old" --new-keyfile "$tmp/new" "$dev"

      echo "disk passphrase changed. The recovery key still works and is unchanged."
    '';
  };

  fleetPassphrase = pkgs.writeShellApplication {
    name = "fleet-passphrase";
    runtimeInputs = [ pkgs.sudo ];
    text = ''sudo -n ${changePassphrase}/bin/fleet-change-passphrase'';
  };
in
{
  config = lib.mkIf active {
    environment.systemPackages = [ fleetPasswd fleetPassphrase ];

    # NixOS installs the setuid passwd wrapper only when users.mutableUsers is
    # true (nixos/modules/programs/shadow.nix wraps chsh and passwd in an
    # `optionalAttrs config.users.mutableUsers`). We set it false, so without
    # this there is no setuid passwd at all and an unprivileged `passwd` dies
    # with "Permission denied" trying to write /etc/shadow.
    #
    # Upstream omits it because immutable users are not supposed to change
    # their own passwords. We do want that (D27) — we just want the change to
    # survive the next rebuild, which is what fleet-passwd adds on top. So the
    # wrapper has to come back.
    #
    # `passwd` without arguments only ever changes the caller's own password,
    # and it still runs the full PAM exchange: the old password is verified and
    # quality rules apply. That is why fleet-passwd drives passwd rather than
    # hashing anything itself.
    security.wrappers.passwd = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${config.security.loginDefs.package.out}/bin/passwd";
    };

    # Narrow, explicit grants. The owner may run exactly these two programs as
    # root and nothing else; this is how a non-administrator changes their own
    # credentials without being given wheel (D12).
    security.sudo.extraRules = [{
      users = [ user ];
      commands = [
        { command = "${persistPassword}/bin/fleet-persist-password"; options = [ "NOPASSWD" ]; }
        { command = "${changePassphrase}/bin/fleet-change-passphrase"; options = [ "NOPASSWD" ]; }
      ];
    }];
  };
}
