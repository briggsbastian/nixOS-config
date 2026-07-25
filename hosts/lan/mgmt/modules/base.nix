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

  # mgmt does not take modules/common.nix (its base.nix owns SSH and firewall,
  # and step-ca owns ACME), so the fleet-wide key-only SSH policy never reached
  # it. Until now mgmt was the ONLY host accepting password authentication -
  # and it is the one holding the step-ca root, Forgejo, and the LAN's DNS.
  #
  # Verified against the running sshd before changing anything: it really was
  # `PasswordAuthentication yes`, not just an unset option defaulting oddly.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false; # otherwise it is a password prompt by another name
      PermitRootLogin = "no";
    };
  };

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
    # default docker on nixos-26.05 is 29.x (25.11's 28.x default was flagged
    # insecure, which used to force a docker_29 pin here)
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
