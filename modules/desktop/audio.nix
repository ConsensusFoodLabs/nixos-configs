# Audio.
#
# Not i3- or GNOME-specific, and not optional: a laptop with no working sound
# is a broken laptop.
{ ... }:

{
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
}
