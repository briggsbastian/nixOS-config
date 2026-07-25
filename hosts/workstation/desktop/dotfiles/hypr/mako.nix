# mako: notification daemon, themed to match the rest of the rice.
{ pkgs, ... }:
let
  c = import ./colors.nix;
in
{
  home.packages = [ pkgs.mako ];

  xdg.configFile."mako/config".text = ''
    sort=-time
    layer=overlay
    anchor=top-right
    width=380
    height=120
    margin=12
    padding=14
    border-size=2
    border-radius=10
    icons=1
    max-icon-size=48
    default-timeout=6000

    background-color=${c.hex.panel}ee
    text-color=${c.hex.fg}
    border-color=${c.hex.magenta}
    progress-color=over ${c.hex.cyan}

    font=JetBrainsMono Nerd Font 11

    [urgency=low]
    border-color=${c.hex.muted}

    [urgency=critical]
    border-color=${c.hex.urgent}
    default-timeout=0
  '';
}
