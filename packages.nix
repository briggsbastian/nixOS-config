{ pkgs, ... }:

{

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    #terminal
    neovim
    tmux
    git
    fish
    fastfetch
    lsd
    alacritty
    starship
    opencode
    btop
    #tools
    obs-studio
    jellyfin-desktop
    obsidian
    tidal-hifi
    proton-vpn
    eddie
  ];

  services.flatpak.enable = true;
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.firefox.enable = true;
  
  programs.steam = {
    enable = true;
  };

  programs.zsh = { enable = true; };

  fonts = {
    enableDefaultPackages = true;
    fontconfig.enable = true;
    packages = with pkgs; [
      nerd-fonts.jetbrains-mono
    ];
  };
  #im not happy putting this here but dont know where else to put it 
  xdg.portal = {  
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
}
