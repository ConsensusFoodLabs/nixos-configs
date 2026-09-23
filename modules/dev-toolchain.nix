# The shared developer baseline: what is on a machine before anyone installs
# anything.
#
# Not a restriction. Developers install what they need
# (docs/software-policy.md, D15); this is the set everyone gets so that nobody
# has to, and the place to add something that turns out to be broadly useful.
#
# A module rather than part of profiles/engineering.nix because a second
# profile would start by wanting exactly this list.
{ pkgs, ... }:

{
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

  # go installs binaries built with `go install` under $GOPATH/bin, which
  # defaults to ~/go/bin, and nothing else here adds that directory to PATH.
  # This mirrors NixOS's own environment.homeBinInPath / localBinInPath idiom
  # (nixos/modules/config/shells-environment.nix) rather than
  # environment.sessionVariables.PATH, which would replace PATH outright
  # instead of appending to it.
  environment.extraInit = ''
    export PATH="$HOME/go/bin:$PATH"
  '';

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
    gh

    python3
    poetry
    uv
    texliveFull

    # cgo shells out to a C compiler at build time — nix-ld above only helps
    # *running* prebuilt binaries, not compiling. Without this, `go build`/
    # `go install` on anything that pulls in a cgo dependency (clipboard
    # access, sqlite drivers, etc.) fails with "gcc: executable file not
    # found in $PATH".
    gcc
    go

    # jujutsu is Apache-2.0; claude-code is unfree and has its allowlist
    # entry in profiles/base.nix (D20). Identity for both comes from the
    # inventory via modules/home-common.nix — shipping the binary without
    # it would leave jj refusing to commit until each person configured a
    # name by hand.
    jujutsu
    claude-code
  ];
}
