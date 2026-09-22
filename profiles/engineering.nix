# Engineering laptop profile: desktop environment and shared developer tools.
#
# Changes here reach every engineering machine, so they go through tight
# review. Personal tooling belongs in users/<name>/home.nix instead (D14).
{ config, lib, pkgs, ... }:

let
  # Confine direct-touch devices to the built-in panel.
  #
  # X maps an absolute pointing device onto the whole virtual screen, not onto
  # the display it is physically bonded to. That is invisible on a laptop on
  # its own and badly wrong the moment a second monitor appears: the virtual
  # screen grows, and a touch at the middle of the panel lands wherever that
  # fraction falls across the whole desktop. Touches come out scaled by the
  # ratio of the virtual screen to the panel.
  #
  # Devices are found by the "libinput Calibration Matrix" property rather
  # than by name. Touchscreen product names are vendor strings like
  # "ELAN9008:00 04F3:4A1D" with nothing recognisable in them, and matching on
  # them would break on the next model. The property is present on direct-touch
  # devices — touchscreens and pens — and absent on mice and touchpads, which
  # is exactly the distinction that matters here: a pen should be confined to
  # the same panel its touchscreen is.
  # The screen locker, with its settings baked in rather than left to the
  # session environment: this command is run by xss-lock from a systemd user
  # service, which does not inherit a login shell's variables.
  #
  # XSECURELOCK_PAM_SERVICE is the one that matters. It defaults to "login",
  # and pointing it at a service that does not exist is not a soft failure:
  # NixOS's fallback PAM service `other` is pam_deny in every phase, so the
  # lock screen would reject every correct password. The matching
  # security.pam.services.xsecurelock below is not optional.
  lockCommand = pkgs.writeShellApplication {
    name = "fleet-lock";
    runtimeInputs = [ pkgs.xsecurelock ];
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
  };

  mapTouchscreen = pkgs.writeShellApplication {
    name = "map-touch-to-panel";
    # coreutils for head: writeShellApplication prepends runtimeInputs to PATH
    # but the unit's own environment is minimal, so nothing may be inherited.
    runtimeInputs = with pkgs; [ xinput xrandr gnugrep gawk coreutils ];
    text = ''
      panel=$(xrandr --query | awk '/ connected/ { print $1 }' |
        grep -E '^(eDP|LVDS)' | head -n 1)

      if [ -z "$panel" ]; then
        echo "map-touch-to-panel: no internal panel found; nothing to do"
        exit 0
      fi

      found=0
      while read -r id; do
        [ -n "$id" ] || continue
        if xinput list-props "$id" 2>/dev/null |
            grep -q "libinput Calibration Matrix"; then
          name=$(xinput list --name-only "$id" 2>/dev/null || echo "id $id")
          echo "map-touch-to-panel: $name -> $panel"
          xinput map-to-output "$id" "$panel" || true
          found=1
        fi
      done < <(xinput list --id-only)

      [ "$found" = 1 ] || echo "map-touch-to-panel: no direct-touch devices"
    '';
  };
in
{
  # The desktop session is chosen per device in fleet/inventory.nix, not per
  # person in a home configuration. The reason is screen locking: it is a
  # security control, so it is declared at the system level where light review
  # cannot reach it (D14). Each branch below is responsible for locking its
  # own session. A desktop with no locking declared is not an option here —
  # that is what makes fleet.desktop an enum rather than a string.
  #
  # Both branches lock after five minutes idle and on suspend.

  config = lib.mkMerge [
    {
      services.xserver.enable = true;
      services.displayManager.gdm.enable = true;
    }

    (lib.mkIf (config.fleet.desktop == "gnome") {
      # GNOME, chosen for working defaults on modern hardware and because it
      # provides screen locking out of the box.
      services.desktopManager.gnome.enable = true;

      # Screen locking is not optional and is not a personal preference.
      services.desktopManager.gnome.extraGSettingsOverrides = ''
        [org.gnome.desktop.screensaver]
        lock-enabled=true
        lock-delay=0

        [org.gnome.desktop.session]
        idle-delay=300
      '';
      services.desktopManager.gnome.extraGSettingsOverridePackages =
        [ pkgs.gnome-settings-daemon ];
    })

    (lib.mkIf (config.fleet.desktop == "i3") {
      services.displayManager.defaultSession = "none+i3";

      services.xserver.windowManager.i3 = {
        enable = true;
        # i3blocks, not i3status: the bar is configured in the owner's home
        # directory and its blocks are shipped from users/<name>/etc.
        extraPackages = with pkgs; [ i3blocks ];
      };

      # i3 ships no screen locking of its own, so it is declared here in two
      # halves. Removing either one silently leaves an unlocked laptop, which
      # is exactly the kind of regression system-level review exists to catch.
      #
      # xss-lock covers the event-driven cases: suspend, lid close, and
      # `loginctl lock-session` (bound to $mod+Shift+x in the i3 config).
      # --ignore-sleep is deliberately NOT set, so the screen is locked before
      # the machine suspends rather than after it wakes.
      programs.xss-lock = {
        enable = true;
        lockerCommand = "${lockCommand}/bin/fleet-lock";
      };

      # The locker's own PAM stack. unixAuth is on by default, so this accepts
      # the login password; fprintAuth adds the reader.
      #
      # i3lock was the locker here first and was replaced because its PAM
      # conversation is password-shaped: with pam_fprintd in the stack it
      # appears to hang until you press Enter. xsecurelock drives PAM
      # properly and shows the "place your finger" prompt (D36).
      security.pam.services.xsecurelock.fprintAuth = true;

      # xautolock covers the idle case. Five minutes, matching the GNOME
      # branch's idle-delay=300 — the two sessions must not differ in how long
      # an unattended laptop stays readable.
      #
      # It calls loginctl rather than i3lock directly so that the lock goes
      # through xss-lock and logind agrees the session is locked.
      services.xserver.xautolock = {
        enable = true;
        time = 5;
        locker = "${pkgs.systemd}/bin/loginctl lock-session";
      };

      # xautolock only knows about keyboard/mouse idle time, so a video call
      # still locks: Chrome asks the desktop to hold off locking via the
      # freedesktop.org ScreenSaver Inhibit D-Bus call, but nothing on i3
      # answers that call — GNOME's session manager normally does. xssproxy
      # is the missing listener: it forwards Inhibit/UnInhibit to the X11
      # idle counter that xautolock and xss-lock already read, bringing i3
      # to parity with what GNOME already lets apps do (D14: this is not a
      # new weakening, both branches already yield to an app-requested
      # inhibit — i3 just didn't have anything to receive the request).
      systemd.user.services.xssproxy = {
        description = "Forward ScreenSaver D-Bus inhibit calls to Xss";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.xssproxy}/bin/xssproxy";
          Restart = "always";
        };
      };

      # Displays, on hotplug.
      #
      # GNOME's mutter reconfigures outputs by itself; i3 does not do display
      # management at all, so plugging in a dock gets you a second screen that
      # is connected, powered, and showing nothing until something calls
      # xrandr. autorandr is that something: it ships a udev rule on
      # SUBSYSTEM=="drm" that starts autorandr.service, and the service runs
      # --batch, which applies the layout inside each running X session rather
      # than only for root.
      #
      # defaultTarget is the fallback used when no saved profile matches the
      # connected set of monitors, which is every profile until someone saves
      # one. "horizontal" lays the outputs out left to right at their
      # preferred modes — so a new dock or a borrowed monitor lights up
      # without anyone having configured anything, and unplugging falls back
      # to the laptop panel.
      #
      # Saved layouts are per-user and live in ~/.config/autorandr, matched by
      # the monitors' EDIDs (docs/operations.md). They are not declared here:
      # a fingerprint is specific to one desk, not to the fleet.
      services.autorandr = {
        enable = true;
        defaultTarget = "horizontal";

        # Re-confine the touchscreen after every layout change. Mapping is
        # lost whenever the screen geometry changes, so plugging in a dock
        # silently un-does it.
        hooks.postswitch."10-map-touchscreen" =
          "${mapTouchscreen}/bin/map-touch-to-panel";
      };

      # And once when the session starts, since no layout change happens at
      # login.
      systemd.user.services.map-touch-to-panel = {
        description = "Confine touchscreen input to the built-in panel";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${mapTouchscreen}/bin/map-touch-to-panel";
        };
      };

      environment.systemPackages = [
        mapTouchscreen
        pkgs.xinput
        # notify-send, so anything in the session can raise a notification.
        pkgs.dunst
        pkgs.libnotify
        # nm-applet's tray icon comes from the unit above, but the package
        # also carries nm-connection-editor, which the bar's network block
        # opens on click. Moving the unit here without the package took that
        # off PATH.
        pkgs.networkmanagerapplet
      ];

      # Brightness keys. acpilight provides an xbacklight-compatible command
      # that writes sysfs, which works on hardware where the X RANDR backlight
      # property does not exist. Users in `video` may use it.
      hardware.acpilight.enable = true;

      # Bluetooth tray applet. GNOME has its own; i3 has nothing.
      services.blueman.enable = true;

      # The three daemons a session needs in order to behave, rather than to
      # look a particular way. They are here and not in modules/home-i3
      # because a personal file must not be able to remove them: without the
      # polkit agent an authorisation request fails with no prompt at all,
      # and without a notification daemon the battery warning, the automount
      # notice and the screenshot confirmation go nowhere (D38).
      systemd.user.services.dunst = {
        description = "dunst notification daemon";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.dunst}/bin/dunst";
          Restart = "on-failure";
        };
      };

      systemd.user.services.nm-applet = {
        description = "NetworkManager applet";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet";
          Restart = "on-failure";
        };
      };

      systemd.user.services.polkit-gnome-authentication-agent = {
        description = "polkit authentication agent";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart =
            "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
        };
      };



      # Automounting removable media.
      #
      # udisks2 is already running — it is on by default — but it only ever
      # mounts when something asks. GNOME's Files was the thing asking. With
      # no desktop, inserting a USB stick does nothing observable at all:
      # no error, no icon, no mount.
      systemd.user.services.udiskie = {
        description = "Automount removable media";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.udiskie}/bin/udiskie --tray --automount --notify";
          Restart = "on-failure";
        };
      };

      # Battery warnings.
      #
      # Nothing else tells you the battery is nearly flat. logind will act at
      # the very end, but there is no warning before it, so the first signal
      # is the machine going away with unsaved work. The bar's battery block
      # turns red at 15%, which only helps if you are looking at it.
      systemd.user.services.poweralertd = {
        description = "Battery and power notifications";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.poweralertd}/bin/poweralertd";
          Restart = "on-failure";
        };
      };

      services.libinput.enable = true;

      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-color-emoji
        fira-code
        # Named by oleg's rofi themes and i3 bar. A Nerd Font, so the glyphs
        # the upstream themes use render instead of showing as boxes.
        nerd-fonts.jetbrains-mono
      ];
    })

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
            profiles/engineering.nix: sshd accepts password or
            keyboard-interactive authentication while pam_fprintd is in its
            PAM stack. That combination lets a finger on this machine's reader
            approve someone else's remote login.

            Either leave security.pam.services.sshd.fprintAuth = false, or
            turn the ssh authentication methods back off in
            modules/fleet/admin.nix.
          '';
        }
      ];

      services.pipewire = {
        enable = true;
        # The PulseAudio server emulation. Chrome, Slack and Firefox all talk
        # to PulseAudio rather than to PipeWire natively, so without this they
        # find no devices at all even though the hardware is working.
        pulse.enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
      };

      # PipeWire asks rtkit for realtime scheduling priority. Without it the
      # daemon still runs, but at normal priority: audio glitches and drops
      # under load. The NixOS pipewire module does not turn this on for you.
      security.rtkit.enable = true;

      # A dynamic loader at the path everything else on Linux expects.
      #
      # NixOS has no /lib64/ld-linux-x86-64.so.2, so a prebuilt binary that
      # was not built for Nix dies with "No such file or directory" — which is
      # about the least helpful error the kernel produces, since the file it
      # cannot find is the loader, not the binary you named. VS Code's
      # Remote-SSH server and a good number of extensions ship exactly such
      # binaries, as do language toolchains that download their own.
      #
      # This grants no privilege and forbids nothing: it makes something work
      # that developers can already do the long way round. D15 is explicit
      # that we do not try to prevent software being installed, so making the
      # normal case work is consistent with it rather than a retreat from it
      # (D35).
      programs.nix-ld.enable = true;

      # Shared baseline. Not a restriction: developers install what they need
      # (docs/software-policy.md). Things that turn out to be broadly useful
      # belong here so everyone gets them.
      environment.systemPackages = with pkgs; [
        # Two browsers on purpose. Firefox is the free default; Chrome is here
        # because web work needs testing against Blink and because several
        # things the team depends on are only supported there. Chrome is
        # unfree, so it also needs its allowlist entry in profiles/base.nix
        # (D20) — the two have to move together.
        firefox
        # --password-store is not cosmetic. Chrome picks its credential store
        # by sniffing the desktop environment, and under i3 it recognises
        # nothing and chooses "basic", which writes passwords in plaintext.
        # Naming the store explicitly is what makes gnome-keyring get used.
        # Correct under GNOME too, where it is what would be chosen anyway.
        (google-chrome.override {
          commandLineArgs = "--password-store=gnome-libsecret";
        })
        # Where the team actually talks. Unfree, so it also needs its
        # allowlist entry in profiles/base.nix (D20).
        slack
        # Microsoft's build, not vscodium: it is what people expect, and the
        # extension marketplace is the reason to use it. Also unfree (D20).
        vscode
        ripgrep
        fd
        jq
        bat
        btop
        tmux
        gnumake

        python3
        texliveFull

        # jujutsu is Apache-2.0; claude-code is unfree and has its allowlist
        # entry in profiles/base.nix (D20). Identity for both comes from the
        # inventory via modules/home-common.nix — shipping the binary without
        # it would leave jj refusing to commit until each person configured a
        # name by hand.
        jujutsu
        claude-code
      ];
    }
  ];
}
