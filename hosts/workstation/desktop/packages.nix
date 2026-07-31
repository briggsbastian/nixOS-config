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
    sops # edit /etc/nixos secrets: `sops secrets/<host>.yaml`
    age
    ssh-to-age
    efibootmgr # one-shot boot into Windows: see reboot-windows alias in zsh.nix
    # SPICE client for the playground lab guests. This - not the choice of
    # hypervisor - is what actually makes the Kali/REMnux consoles feel local: a
    # browser console (noVNC) is websocket-tunnelled VNC and always feels laggy,
    # while SPICE does client-side cursor, audio and clipboard. Proxmox's console
    # dropdown hands you a `.vv` file; opening it launches remote-viewer.
    virt-viewer
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
      enable = true;
      onCalendar = "weekly";
    };
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
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
