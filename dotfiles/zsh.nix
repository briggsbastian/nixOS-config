{ ... }:
{
  programs.zsh {
    enable = true;
    enableAutoCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting. enable = true;

    shellAliases = {
      rebuild = "sudo nixos-rebuild switch";
      rebuild-test = "sudo nixos-rebuild test";

      ls = "lsd";
    };

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      share = true;
    };
  };
}

