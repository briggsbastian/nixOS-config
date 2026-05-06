{ pkgs, inputs, ...}: 

{
  imports = [
    ./dotfiles/starship.nix
    ./dotfiles/jellyfin.nix
    ./dotfiles/zsh.nix
    ./dotfiles/neovim.nix
    ./dotfiles/alacritty.nix
    ./dotfiles/tmux.nix
    ./hyprland/waybar/waybar.nix
  ];
  home.stateVersion = "25.11";
  home.username = "briggs";


}
