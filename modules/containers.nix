# Containers: podman, rootless.
#
# Podman rather than Docker because it runs containers as the user who
# started them, with no daemon and no root-equivalent socket. Docker's
# `docker` group is root by another name — anyone in it can mount the host
# filesystem into a container — and granting it to every developer would
# undo D12 quietly. Rootless podman needs nothing of the sort: the kernel's
# user namespaces do the work, using the subordinate uid range NixOS already
# allocates to every normal user (users.users.<name>.autoSubUidGidRange).
#
# Imported by profiles/engineering.nix. A module of its own, per D41:
# a second profile that wants containers wants exactly this.
{ pkgs, ... }:

{
  virtualisation.podman = {
    enable = true;

    # A `docker` command that is podman. Most tooling and most READMEs say
    # `docker`; this lets them work unchanged. Real Docker cannot coexist with
    # it on the same machine, which is intended.
    dockerCompat = true;

    # Containers on the default network resolve each other by name. Off by
    # default upstream for historical reasons; without it a compose file
    # with two services that talk to each other does not work.
    defaultNetwork.settings.dns_enabled = true;

    # NOT enabled: dockerSocket. It would publish a Docker-compatible socket
    # from the root podman instance, and access to it is access to root.
    # Tools that need a socket get the rootless one at
    # $XDG_RUNTIME_DIR/podman/podman.sock via `systemctl --user start
    # podman.socket`, which is the same user, not root.
  };

  environment.systemPackages = with pkgs; [
    # `podman compose` delegates to this. Speaks compose files to a rootless
    # podman; docker-compose v2 would instead need the Docker socket above.
    podman-compose
  ];
}
