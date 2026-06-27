# modules/common.nix
#
# Shared fleet baseline, imported by every server host. Keep it host-agnostic:
# hostname, users, and per-host ports live in hosts/<zone>/<name>/.
{ lib, pkgs, ... }:

{
  # The Colmena deploy identity (deploy user + trusted-user + scoped sudo) lives
  # in its own module so mgmt can reuse just that without the rest of this file.
  # metrics.nix adds a mgmt-only node_exporter to every fleet host (cloud1 opts
  # out; mgmt runs its own, localhost-bound).
  imports = [
    ./deploy-user.nix
    ./metrics.nix
  ];

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

  # --- Secrets (sops-nix) ---------------------------------------------------
  # Each host decrypts its own secrets at activation with its SSH host key -
  # no separate age key to distribute. (Recipients in .sops.yaml are each box's
  # ssh_host_ed25519_key.pub run through ssh-to-age.) Needs the host's module
  # set to also import sops-nix.nixosModules.sops (see flake.nix).
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Trust mgmt's step-ca root + use its Harmonia cache + ACME endpoint.
  # (Option defined in modules/internal-ca.nix.)
  # mkDefault so an off-LAN host (cloud1) can opt out with a plain assignment.
  # On-LAN hosts set nothing -> these stay true.
  alcove.internalCa.enable = lib.mkDefault true;
  alcove.internalCa.useCache = lib.mkDefault true; # cache.mgmt.lan serves a real cert now (2026-06-15)

  # --- Firewall: nftables, deny-by-default, SSH open ----------------
  # The stock installer leaves the firewall off. 22 is the one port we always
  # need (Colmena/SSH deploys).
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # --- Server power policy: never sleep, ignore the lid ----------------------
  # Some boxes are laptops with the lid shut. Without a desktop session to
  # inhibit it, logind would suspend on lid-close/idle and drop the host off the
  # LAN. Disable sleep, ignore lid + idle, and keep Wi-Fi from powering down.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    IdleAction = "ignore";
  };
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };
  networking.networkmanager.wifi.powersave = false;

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

  # --- Remote deploy identity (Colmena) -------------------------------------
  # Moved to modules/deploy-user.nix (imported above) so mgmt can share it.
}
