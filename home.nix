{ pkgs, ...}: 

{
  imports = [
    ./dotfiles/starship.nix
    ./dotfiles/jellyfin.nix
    ./dotfiles/zsh.nix
  ];
  home.stateVersion = "25.11";


  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        normal = { family = "JetBrainsMono Nerd Font"; style = "Regular"; };
	bold = { family = "JetBrainsMono Nerd Font"; style = "Bold"; };
	italic = { family = "JetBrainsMono Nerd Font"; style = "Italic"; };
	size = 12;
      };
    window.opacity = 0.8; 

    };
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    terminal = "screen-256color";
    historyLimit = 10000;
  };

  programs.neovim = { 
    enable = true;
    defaultEditor = true;
    extraConfig = ''
      set number
    '';
  };

}
