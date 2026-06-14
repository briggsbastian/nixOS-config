{ pkgs, inputs, ...}: 

{
  imports = [
    ./dotfiles/starship.nix
    ./dotfiles/jellyfin.nix
    ./dotfiles/zsh.nix
    ./hyprland/hypr/hyprland.nix
    ./hyprland/hypr/hypr-binds.nix
    ./hyprland/waybar/waybar.nix
  ];
  home.stateVersion = "25.11";
  home.username = "briggs";


}
