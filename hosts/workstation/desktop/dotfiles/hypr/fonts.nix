# Fonts used across the rice: JetBrains Mono Nerd Font for everything
# functional (terminal, waybar body text, rofi list), Orbitron for the
# techy/JSR-digital-readout accents (waybar clock, rofi prompt, hyprlock time).
{ pkgs, ... }:
{
  fonts.fontconfig.enable = true;

  home.packages = [
    pkgs.orbitron
  ];
}
