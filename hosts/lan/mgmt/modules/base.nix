# Headless server baseline: no desktop, firewall on, never sleep.
# docker stays enabled but is now unused (TRMM removed) - safe to drop later.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    neovim
    btop
    tmux
    curl
    wget
    docker-compose
    dig
  ];

  services.openssh.enable = true;

  # the GNOME install this replaces auto-suspended; a server must never sleep
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22 # ssh
      53 # adguard dns
      80 # nginx (redirects to 443)
      443 # nginx
    ];
    allowedUDPPorts = [ 53 ];
  };

  virtualisation.docker = {
    enable = true;
    # default docker 28.x is flagged insecure in nixos-25.11
    package = pkgs.docker_29;
    autoPrune.enable = true;
  };

  # headroom on 15GB RAM for the native siem-lite + services
  zramSwap.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
