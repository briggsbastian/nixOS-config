{ ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      rebuild = "sudo nixos-rebuild switch";
      rebuild-test = "sudo nixos-rebuild test";
      rebuild-kde = "sudo nixos-rebuild switch --flake .#nixos-kde";
      rebuild-hypr = "sudo nixos-rebuild switch --flake .#nixos-hyprland";
      update = "sudo nixos-rebuild switch --upgrade";
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

