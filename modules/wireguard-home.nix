# A WireGuard tunnel to a private network, configured out of band.
#
# The shape this generalises: someone wants their laptop on a network that is
# theirs and not the company's — a home LAN, a lab, a customer's VPN. Three
# things follow from that, and none of them is specific to whose network it
# is (D40).
#
# 1. The configuration cannot be in this repository. It is public, and the
#    endpoint, the peer's key and the addresses are facts about a private
#    network. It is not a fleet secret either — fleet/secrets/ is what the
#    installer needs (D27). So the `.conf` is delivered by hand, into
#    fleet.userSecretsDir, and this module only points wg-quick at it.
#
# 2. It must not come up at home, where its routes for the private subnets
#    would shadow the real LAN, and must come up everywhere else. That needs
#    two facts about the network, and unlike the contents of the `.conf`,
#    neither is a secret: a wifi network name and an RFC1918 address name no
#    host and reach nothing. They are options, declared per machine.
#
# 3. A laptop changes networks by surprise. The decision therefore re-runs on
#    every address change rather than at boot.
#
# The tunnel is off unless a machine asks for it, so importing this module
# fleet-wide costs the machines that do not.
{ config, lib, pkgs, ... }:

let
  cfg = config.fleet.homeTunnel;
in
{
  options.fleet.homeTunnel = {
    enable = lib.mkEnableOption ''
      a WireGuard tunnel whose configuration is delivered by hand rather than
      declared here
    '';

    interface = lib.mkOption {
      type = lib.types.str;
      description = ''
        Interface name. Also names the unit (wg-quick-<interface>.service)
        and, by default, the file that must be delivered. Fifteen characters
        at most, as for any network interface.
      '';
      example = "x1c-oleg-h";
    };

    configFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.fleet.userSecretsDir}/${cfg.interface}.conf";
      defaultText = lib.literalExpression
        ''"''${config.fleet.userSecretsDir}/''${interface}.conf"'';
      description = ''
        Where the hand-delivered wg-quick configuration lives on the machine.

        A plain path string, deliberately: it is read at unit start and never
        copied into the Nix store at build time. A machine where it has not
        been delivered yet boots clean — the unit does not autostart, and the
        decision below does nothing while the file is unreadable.
      '';
    };

    autoconnect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the decision below runs by itself. Turning it off keeps both
        units defined but out of multi-user.target, so re-enabling is a flip
        back rather than resurrecting deleted code, and
        `systemctl start wg-<interface>-monitor.service` still works by hand.
      '';
    };

    homeSsid = lib.mkOption {
      type = lib.types.str;
      description = ''
        Wifi network name that means "the tunnel is not needed". Checked
        first, because on wifi it is an instant answer.
      '';
      example = "mingahome";
    };

    homeGateway = lib.mkOption {
      type = lib.types.str;
      description = ''
        An address on that network which answers ping. The fallback test, and
        the one that covers arriving by dock or by cable, where there is no
        SSID to read.
      '';
      example = "172.26.249.254";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      iface = cfg.interface;

      autoconnect = pkgs.writeShellApplication {
        name = "wg-${iface}-autoconnect";
        runtimeInputs = with pkgs; [ iw iproute2 iputils gawk gnugrep systemd coreutils ];
        text = ''
          conf=${lib.escapeShellArg cfg.configFile}
          unit=${lib.escapeShellArg "wg-quick-${iface}.service"}
          home_ssid=${lib.escapeShellArg cfg.homeSsid}
          home_gateway=${lib.escapeShellArg cfg.homeGateway}

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
      networking.wg-quick.interfaces.${iface} = {
        configFile = cfg.configFile;

        # Never at boot. The unit is started and stopped by the pair below,
        # which is also what makes a machine with no file delivered yet boot
        # cleanly rather than into a failed unit.
        autostart = false;
      };

      systemd.services."wg-${iface}-autoconnect" = {
        description = "Bring ${iface} up when away from the home network";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = lib.optional cfg.autoconnect "multi-user.target";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe autoconnect;
        };
      };

      # What actually drives the thing: addresses appearing and disappearing
      # is what joining and leaving a network looks like from here, and it
      # covers resuming from suspend too, which is the common case on a
      # laptop.
      systemd.services."wg-${iface}-monitor" = {
        description = "Re-check ${iface} whenever the network changes";
        after = [ "network.target" ];
        wantedBy = lib.optional cfg.autoconnect "multi-user.target";
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
  );
}
