{ pkgs, ...}: 

{
  imports = [
    ./dotfiles/starship.nix
    ./dotfiles/jellyfin.nix
    ./dotfiles/zsh.nix
    ./dotfiles/neovim.nix
    ./dotfiles/alacritty.nix
  ];
  home.stateVersion = "25.11";


  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    terminal = "screen-256color";
    historyLimit = 10000;
  };


}
