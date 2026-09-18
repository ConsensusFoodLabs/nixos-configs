# fleet-wipe-key. Shipped on the installer image and exposed by the flake, so
# the stick can be wiped either from the machine that just used it or from an
# administrator's workstation.
pkgs:

pkgs.writeShellApplication {
  name = "fleet-wipe-key";
  runtimeInputs = with pkgs; [
    coreutils
    dosfstools
    util-linux
  ];
  text = builtins.readFile ../../scripts/fleet-wipe-key;
}
