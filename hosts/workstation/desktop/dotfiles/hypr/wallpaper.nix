# The rice's default background: a procedurally-generated Shibuya-punk/
# synthwave skyline (see assets/generate-wallpaper.sh), built at nix-build
# time so the rice needs no binary image checked into the repo. Sized for
# DP-3, the desktop's single 5120x1440 ultrawide -- regenerate at a new
# resolution if the monitor ever changes.
{ pkgs, ... }:
let
  wallpaper = import ./wallpaper-image.nix { inherit pkgs; };
in
{
  home.packages = [ pkgs.hyprpaper ];

  xdg.configFile."hypr/hyprpaper.conf".text = ''
    preload = ${wallpaper}
    wallpaper = DP-3,${wallpaper}
    splash = false
    ipc = off
  '';
}
