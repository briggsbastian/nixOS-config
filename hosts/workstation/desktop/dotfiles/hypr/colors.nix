# Shared palette for the whole rice (waybar, rofi, mako, hyprlock, hyprland
# borders, wallpaper) so every piece stays in sync from one place.
# Y2K / Shibuya-punk / cyberpunk / Jet Set Radio: spray-paint magenta and
# electric cyan over a near-black asphalt base, acid yellow for accents.
#
# `hex.*` are plain "#rrggbb" strings for CSS/rasi. `bare.*` are the same
# without the leading "#", for Hyprland's rgb(rrggbb)/rgba(rrggbbaa) syntax.
rec {
  hex = {
    void = "#060008";
    panel = "#12081c";
    magenta = "#ff2bd6";
    cyan = "#22e5ff";
    yellow = "#f9ff21";
    green = "#39ff88";
    fg = "#f2f0ff";
    muted = "#8b7aa8";
    urgent = "#ff3355";
  };

  bare = builtins.mapAttrs (_: v: builtins.substring 1 6 v) hex;
}
