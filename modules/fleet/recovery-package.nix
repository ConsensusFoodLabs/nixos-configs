# fleet-rotate-recovery. Defined apart from the module that installs it so the
# flake can expose it too: `nix flake check` then builds it, shellcheck runs
# over it, and tests/recovery-rotation.sh can drive it against a throwaway
# container with --device.
#
# The machine's own LUKS device is supplied through the environment rather than
# baked into the script text, so the same script serves both.
pkgs: luksDevice:

pkgs.writeShellApplication {
  name = "fleet-rotate-recovery";
  runtimeInputs = with pkgs; [ coreutils cryptsetup gawk gnugrep ];
  text =
    (if luksDevice == null then "" else ''
      export FLEET_LUKS_DEVICE=${pkgs.lib.escapeShellArg luksDevice}
    '')
    + builtins.readFile ../../scripts/fleet-rotate-recovery;
}
