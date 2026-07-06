# hosts/lan/playground/configuration.nix
#
# playground - AMD box / NVMe 465G. Security lab host: the libvirt/KVM host for the
# Kali/Parrot/REMnux/FlareVM lab (see ./libvirt.nix) + Guacamole remote-desktop
# gateway. Adopted from the channel install; baseline (key-only SSH, nftables w/ 22,
# deploy user, sops, flakes, zsh) is in ../../../modules/common.nix.
#
# Guacamole is declarative now (see ./guacamole.nix), replacing the old imperative
# per-user Tomcat under the removed secvm user. VM connections are NOT auto-discovered
# from libvirt — add each as a VNC connection in the UI (host `localhost`, port =
# `5900 + virsh vncdisplay <vm>`); REMnux is built + connected, the rest as you build
# them. Port 8080 is opened below so it stays reachable once the firewall is on. The
# lab itself is tracked in "Project 1 - Nixify the Lab".
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./libvirt.nix
    ./bridge.nix
    ./guacamole.nix
    ./cockpit.nix
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
  # Guacamole (web gateway on :8080).

  # --- User ------------------------------------------------------------------
  # Declarative passwords: with mutableUsers=true, NixOS won't apply
  # hashedPasswordFile to an already-existing user (playground was created during
  # the fold-in without one). All users here are declarative, so false is right.
  users.mutableUsers = false;

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

  # Guacamole web UI (Tomcat :8080) - keep it LAN-reachable now that common.nix
  # turns the firewall on. Merges with common's [ 22 ].
  networking.firewall.allowedTCPPorts = [ 8080 ];

  # playground user's login/sudo password hash (see users.users.playground).
  sops.secrets.playground_hashed_password = {
    sopsFile = ../../../secrets/playground.yaml;
    neededForUsers = true;
  };
  # ship the journal to central Loki on mgmt
  alcove.siemLite.agent.enable = true;

  system.stateVersion = "25.11";
}
