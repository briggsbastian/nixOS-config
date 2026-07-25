# The generated rice wallpaper as a plain derivation, shared by
# ./wallpaper.nix (hyprpaper) and ./hyprlock.nix (lock screen background) so
# both reference the exact same nix-store image.
{ pkgs }:
pkgs.runCommand "jsr-wallpaper.png" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
  bash ${./assets/generate-wallpaper.sh} 5120 1440 "$out"
''
