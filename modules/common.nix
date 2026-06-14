# modules/common.nix
#
# Shared fleet baseline — imported by every server host (and eventually the
# desktop). Keep this host-agnostic: hostname, users, and per-host ports live
# in hosts/<name>/. The foundation tasks in "Project 1 - Nixify the Lab" will
# grow this (internal-CA trust, Wazuh agent, sops) — start small and reusable.
{ lib, pkgs, ... }:

{
  # Flakes everywhere.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # --- SSH: key-only, no root, no passwords ---------------------------------
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # --- Firewall: nftables backend, deny-by-default, SSH open ----------------
  # The stock installer leaves the firewall OFF. Every fleet host should have
  # it on; 22 is the one port we always need (Colmena/SSH deploys).
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # --- Shell + locale + time (whole fleet is one region) --------------------
  programs.zsh.enable = true;
  time.timeZone = lib.mkDefault "America/Los_Angeles";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  # --- Minimal admin toolkit present on every box ---------------------------
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    tmux
    curl
    rsync
  ];
}
