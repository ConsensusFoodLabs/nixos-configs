# x1c-oleg — configuration for this one machine, not for its model and not
# for its owner's home directory.
#
# The per-machine layer exists because neither of the other two fits a home
# VPN: hosts/thinkpad-x1c-gen14 would put oleg's tunnel on every X1 Carbon
# the company ever buys, and users/oleg/home.nix is home-manager, which
# cannot bring up a network interface (D40).
{ config, lib, pkgs, ... }:

let
  # The interface name, the unit name (wg-quick-<name>.service), and the
  # basename of the hand-delivered file are all this string.
  iface = "x1c-oleg-h";

  # Delivered by hand, never by this repository.
  #
  # The repository is public and the tunnel is oleg's home network, so what
  # would be in a declarative wg-quick block — address, peer public key,
  # endpoint, DNS — is not written here at all. sops was not used either:
  # fleet/secrets/ is provisioning credentials the installer needs, and this
  # is neither provisioning nor fleet business (D40).
  #
  # Consequence worth being explicit about: the file holds a private key and
  # lives in the owner's home directory, so it is readable by the owner and
  # by root, and it is protected by nothing but the disk encryption and the
  # 0700 directory below. That is the same footing as the rclone OAuth tokens
  # in users/oleg/home.nix.
  conf = "/home/${config.fleet.user}/.secrets/${iface}.conf";

  # How "home" is recognised. These two are here rather than in the delivered
  # file because neither is a secret — a wifi network name and an RFC1918
  # address disclose nothing that matters, unlike the key, the peer and the
  # endpoint, which stay out of band.
  homeSsid = "mingahome";
  homeGateway = "172.26.249.254";

  # Off switch for the pair below, kept as a plain param rather than deleted
  # code so re-enabling is a one-line flip back to `true`. The services stay
  # defined either way — this only keeps them out of multi-user.target, so a
  # `systemctl start wg-${iface}-monitor.service` still works if wanted
  # by hand.
  autoconnectEnabled = false;

  # Bring the tunnel up when away, take it down when home.
  #
  # Down at home is the part that matters: the tunnel's routes for the home
  # subnets would otherwise shadow the real LAN.
  autoconnect = pkgs.writeShellApplication {
    name = "wg-${iface}-autoconnect";
    runtimeInputs = with pkgs; [ iw iproute2 iputils gawk gnugrep systemd coreutils ];
    text = ''
      conf=${lib.escapeShellArg conf}
      unit=${lib.escapeShellArg "wg-quick-${iface}.service"}
      home_ssid=${lib.escapeShellArg homeSsid}
      home_gateway=${lib.escapeShellArg homeGateway}

      if [ ! -r "$conf" ]; then
        echo "$conf is not readable; leaving the tunnel alone"
        exit 0
      fi

      # Every up link except loopback and the tunnel itself. Names can carry
      # a peer suffix (veth0@if7), which is not a name you can bind to.
      local_links() {
        ip link show up |
          awk -F': ' '/^[0-9]+:/ { print $2 }' |
          cut -d@ -f1 |
          grep -v -x -e lo -e ${lib.escapeShellArg iface} || true
      }

      at_home() {
        # The cheap test first: on wifi the SSID is an instant answer.
        while read -r wifi; do
          [ -n "$wifi" ] || continue
          ssid=$(iw dev "$wifi" link 2>/dev/null |
            awk -F': ' '/SSID/ { print $2 }' || true)
          if [ "$ssid" = "$home_ssid" ]; then
            return 0
          fi
        done < <(iw dev 2>/dev/null | awk '/Interface/ { print $2 }' || true)

        # Then the gateway, which also covers the dock and a borrowed cable.
        #
        # -I with an interface name is SO_BINDTODEVICE, so the probe leaves by
        # that link rather than following the routing table — which is the
        # point, since with the tunnel up the routing table sends the home
        # subnets into it and every answer would look like "home".
        while read -r link; do
          [ -n "$link" ] || continue
          if ping -c 1 -W 2 -I "$link" "$home_gateway" >/dev/null 2>&1; then
            return 0
          fi
        done < <(local_links)

        return 1
      }

      if at_home; then
        echo "on the home network; tunnel down"
        systemctl stop "$unit"
      elif ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        echo "away and online; tunnel up"
        systemctl start "$unit"
      else
        # Flapping the tunnel on every transient outage buys nothing, and a
        # laptop that is offline has no traffic to carry either way.
        echo "no internet; leaving the tunnel as it is"
      fi
    '';
  };
in
{
  # Somewhere to put the file, with permissions already right, so that
  # delivering it is a copy and not a copy plus two chmods.
  systemd.tmpfiles.rules = [
    "d /home/${config.fleet.user}/.secrets 0700 ${config.fleet.user} users - -"
  ];

  networking.wg-quick.interfaces.${iface} = {
    configFile = conf;

    # Never at boot. The unit is started and stopped by the pair below, which
    # is also what makes a machine with no file delivered yet boot cleanly
    # rather than into a failed unit.
    autostart = false;
  };

  systemd.services."wg-${iface}-autoconnect" = {
    description = "Bring ${iface} up when away from the home network";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = lib.optional autoconnectEnabled "multi-user.target";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe autoconnect;
    };
  };

  # What actually drives the thing: addresses appearing and disappearing is
  # what joining and leaving a network looks like from here, and it covers
  # resuming from suspend too, which is the common case on a laptop.
  systemd.services."wg-${iface}-monitor" = {
    description = "Re-check ${iface} whenever the network changes";
    after = [ "network.target" ];
    wantedBy = lib.optional autoconnectEnabled "multi-user.target";
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      ExecStart = lib.getExe (pkgs.writeShellApplication {
        name = "wg-${iface}-monitor";
        runtimeInputs = with pkgs; [ iproute2 systemd ];
        text = ''
          ip monitor address | while read -r _change; do
            # --no-block: a oneshot already running must not stall the
            # monitor, and the next change will re-trigger it anyway.
            systemctl start --no-block ${lib.escapeShellArg "wg-${iface}-autoconnect.service"} || true
          done
        '';
      });
    };
  };
}
