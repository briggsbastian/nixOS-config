{ pkgs, ... }:

{

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    #terminal
    tmux
    git
    gh
    fastfetch
    lsd
    alacritty
    starship
    opencode
    btop
    fzf
    #tools
    age # decrypt backups (see MAINTENANCE.md)
    efibootmgr # one-shot boot into Windows: see reboot-windows alias in zsh.nix
    obs-studio
    obsidian
    # python3 + psutil/pywinctl/typing-extensions: PTY backend for the Obsidian "Terminal" plugin
    (python3.withPackages (
      ps: with ps; [
        psutil
        pywinctl
        typing-extensions
      ]
    ))
    tidal-hifi
    proton-pass
    proton-vpn
    wootility
    eddie
    reaper
    bitwig-studio
    vlc
    spotify
    blender
    gimp
    godot
  ];

  services.flatpak = {
    enable = true;
    remotes = [
      {
        name = "flathub";
        location = "https://flathub.org/repo/flathub.flatpakrepo";
      }
    ];
    packages = [
      "com.github.iwalton3.jellyfin-media-player"
      "me.proton.Mail"
      "org.DolphinEmu.dolphin-emu"
    ];
    update.auto = {
      enable = false;
      onCalendar = "weekly";
    };
  };

  programs.firefox = {
    enable = true;
    policies.Certificates.ImportEnterpriseRoots = true;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    package = pkgs.steam.override {
      extraArgs = "-pipewire";
    };
  };

  programs.zsh = {
    enable = true;
  };

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
}
