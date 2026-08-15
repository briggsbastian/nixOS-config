# hosts/lan/playground/configuration.nix
#
# playground - AMD box / NVMe 465G. Security lab host: Incus VM/container host
# for the Kali lab (see ./incus.nix, runbook in ./LAB.md) + HTB VPN connectivity
# (./htb.nix). Adopted from the channel install; baseline (key-only SSH, nftables
# w/ 22, deploy user, sops, flakes, zsh) is in ../../../modules/common.nix.
#
# Incus replaced the libvirt + Guacamole + Cockpit trio (2026-07): one web UI on
# https://192.168.1.217:8443 (TLS client-cert auth, no reverse proxy — see
# ./incus.nix) with a built-in graphical console, so the Guacamole VNC gateway
# and Cockpit's VM plugin are gone. The lab itself is tracked in
# "Project 1 - Nixify the Lab".
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./incus.nix
    ./bridge.nix
    ./htb.nix
    ./decepticon.nix
    ./shell.nix
    ./neovim.nix
    ./tmux.nix
    ./devenv.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "playground";
  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Headless - GNOME from the original install is stripped. Access is over SSH +
  # the Incus web UI (:8443, see ./incus.nix).

  # --- User ------------------------------------------------------------------
  # Declarative passwords: with mutableUsers=true, NixOS won't apply
  # hashedPasswordFile to an already-existing user (playground was created during
  # the fold-in without one). All users here are declarative, so false is right.
  users.mutableUsers = false;

  # Opted out of the fleet-wide `briggs` (modules/users.nix): `playground` below
  # already holds uid 1000 here, and this host is on its way out of the flake
  # anyway (it is stock Proxmox now - see chore/retire-playground). Not worth a
  # migration; it stays evaluable for `nix flake check` and nothing more.
  alcove.fleetUsers.enable = false;

  users.users.playground = {
    isNormalUser = true;
    description = "playground";
    extraGroups = [ "wheel" ]; # networkmanager group is gone once NM is off (see bridge.nix)
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
    # sudo/console password from sops. neededForUsers decrypts it before the users
    # module runs. Change it via the sops secret + redeploy.
    hashedPasswordFile = config.sops.secrets.playground_hashed_password.path;
  };

  # playground user's login/sudo password hash (see users.users.playground).
  sops.secrets.playground_hashed_password = {
    sopsFile = ../../../secrets/playground.yaml;
    neededForUsers = true;
  };
  # ship the journal to central Loki on mgmt
  alcove.siemLite.agent.enable = true;

  system.stateVersion = "25.11";
}
