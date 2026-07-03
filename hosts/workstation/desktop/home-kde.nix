{ pkgs, inputs, ... }:

{
  imports = [
    ./dotfiles/starship.nix
    ./dotfiles/jellyfin.nix
    ./dotfiles/zsh.nix
    ./dotfiles/neovim.nix
    ./dotfiles/git.nix
    ./dotfiles/alacritty.nix
    ./dotfiles/tmux.nix
  ];
  home.stateVersion = "25.11";
  home.username = "briggs";
  home.packages = [
    inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code # coding CLI
    inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop # GUI chat client
  ];
}
