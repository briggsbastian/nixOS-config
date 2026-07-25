# Alacritty, recolored for the rice. Separate from ../alacritty.nix (the
# shared gruvbox config the KDE home file uses) since home-manager options
# can't have two modules disagree on the same settings keys.
{ ... }:
let
  c = import ./colors.nix;
in
{
  programs.alacritty = {
    enable = true;
    settings = {
      window.opacity = 0.85;
      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Italic";
        };
        size = 12;
      };
      colors = {
        primary = {
          background = c.hex.void;
          foreground = c.hex.fg;
        };
        cursor = {
          text = c.hex.void;
          cursor = c.hex.magenta;
        };
        normal = {
          black = c.hex.void;
          red = c.hex.urgent;
          green = c.hex.green;
          yellow = c.hex.yellow;
          blue = c.hex.cyan;
          magenta = c.hex.magenta;
          cyan = c.hex.cyan;
          white = c.hex.fg;
        };
        bright = {
          black = c.hex.muted;
          red = c.hex.urgent;
          green = c.hex.green;
          yellow = c.hex.yellow;
          blue = c.hex.cyan;
          magenta = c.hex.magenta;
          cyan = c.hex.cyan;
          white = c.hex.fg;
        };
      };
    };
  };
}
