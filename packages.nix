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
    claude-code
    btop
    #tools
    obs-studio
    obsidian
    tidal-hifi
    proton-pass
    proton-vpn
    eddie
    vlc
  ];

  services.flatpak = { 
    enable = true;
    remotes = [{ name = "flathub"; location = "https://flathub.org/repo/flathub.flatpakrepo";}];
    packages = [ "com.github.iwalton3.jellyfin-media-player" "me.proton.Mail" ];
    update.auto = { enable = true; onCalendar = "weekly";};
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.firefox.enable = true;
  
  programs.steam = {
    enable = true;
  };

  programs.zsh = { enable = true; };

  programs.obs-studio = {  
    enable = true;
    enableVirtualCamera = true;
  };

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
