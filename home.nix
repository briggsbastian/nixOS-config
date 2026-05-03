{ pkgs, ...}: 

{

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
    };
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    terminal = "screen-256color";
    historyLimit = 10000;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history.size = 10000;


    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "thefuck" ];
      theme = "robbyrussell";
   };
  };
}
