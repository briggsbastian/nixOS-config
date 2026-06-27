# hosts/cloud1/configuration.nix
#
# cloud1 - the off-site leg: a Linode Nanode (1 vCPU / 1 GB), wiped to NixOS with
# nixos-anywhere and managed from this flake + Colmena hive like the house. The
# baseline (key-only SSH, nftables w/ 22, deploy user, zsh, sops, step-ca root
# trust) comes from ../../../modules/common.nix via serverModules in flake.nix;
# this file holds only what's cloud-specific.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "cloud1";

  # --- Boot: legacy BIOS + GRUB on the disk ---------------------------------
  # Linode boots BIOS, and disko gives a GPT disk with a 1 MiB BIOS-boot partition,
  # so GRUB embeds onto /dev/sda. (UEFI hosts like hacktop use systemd-boot + ESP.)
  # The Linode Configuration Profile must be "Direct Disk" so it boots this GRUB,
  # not a Linode-supplied kernel.
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    # Don't set `device`/`devices` here: disko derives boot.loader.grub.devices
    # from the EF02 (BIOS-boot) partition in disko.nix. Setting it again lists
    # /dev/sda twice -> "duplicated devices in mirroredBoots" assertion.
  };

  # 1 GB box -> compressed in-RAM swap on top of the sdb disk swap (disko), for
  # runtime headroom.
  zramSwap.enable = true;

  # --- Off-LAN: don't use mgmt's binary cache yet ---------------------------
  # common.nix enables internalCa + its Harmonia cache fleet-wide, both pinned to
  # 192.168.1.222 - unreachable from the cloud until the WireGuard site-to-site
  # tunnel exists (Project 4C). Trusting the root CA is harmless, but an
  # unreachable substituter would stall every nix build, so opt out until then.
  # (common.nix sets this with lib.mkDefault, so this plain assignment wins.)
  alcove.internalCa.useCache = false;

  # --- Off-LAN: no node_exporter until there's a private path to mgmt ---------
  # common.nix enables a node_exporter fleet-wide (modules/metrics.nix), firewalled
  # so only mgmt (192.168.1.222) can scrape :9100. cloud1 is a PUBLIC VPS with no
  # private link to mgmt, so even a mgmt-scoped rule can't help here and exposing
  # the port publicly is unsafe. Stay off until the WireGuard/Headscale mesh
  # (Project 4C) lands, then flip this true and set cloud1.scrape = true in
  # fleet-hosts.nix. (Default is true, so this plain assignment opts out.)
  alcove.metrics.nodeExporter.enable = false;

  # --- Break-glass admin ----------------------------------------------------
  # Colmena deploys as the unprivileged `deploy` user (modules/deploy-user.nix).
  # This is a separate human login for recovery: wheel sudo (password-gated),
  # key-only like the rest of the fleet. This desktop's key, so `ssh cloud1@<ip>`
  # works from the control node.
  users.users.cloud1 = {
    isNormalUser = true;
    description = "cloud1 admin";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
  };

  # First install is 25.11 (matches the fleet's nixpkgs-stable). Fixed - tracks
  # state-compat, not package versions.
  system.stateVersion = "25.11";
}
