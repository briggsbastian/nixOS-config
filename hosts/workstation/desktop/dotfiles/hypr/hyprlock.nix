# hyprlock: lock screen, reusing the same generated wallpaper (blurred
# further at lock-time) so the rice feels consistent between desktop and lock.
{ pkgs, ... }:
let
  c = import ./colors.nix;
  wallpaper = import ./wallpaper-image.nix { inherit pkgs; };
in
{
  home.packages = [ pkgs.hyprlock ];

  xdg.configFile."hypr/hyprlock.conf".text = ''
    background {
      path = ${wallpaper}
      blur_passes = 3
      blur_size = 8
      brightness = 0.55
    }

    general {
      hide_cursor = false
      grace = 2
    }

    input-field {
      size = 300, 60
      position = 0, -40
      halign = center
      valign = center
      dots_center = true
      outer_color = rgb(${c.bare.magenta})
      inner_color = rgb(${c.bare.panel})
      font_color = rgb(${c.bare.fg})
      fade_on_empty = false
      placeholder_text = <span foreground="##${c.bare.muted}">password...</span>
      rounding = 12
    }

    label {
      text = cmd[update:1000] echo "$(date +"%H:%M")"
      font_family = Orbitron
      font_size = 96
      color = rgb(${c.bare.yellow})
      position = 0, 220
      halign = center
      valign = center
    }

    label {
      text = cmd[update:60000] echo "$(date +"%A, %B %d")"
      font_family = JetBrainsMono Nerd Font
      font_size = 20
      color = rgb(${c.bare.cyan})
      position = 0, 150
      halign = center
      valign = center
    }
  '';
}
