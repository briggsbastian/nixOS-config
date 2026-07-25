# hosts/cloud1/configuration.nix
#
# cloud1 - the off-site leg: a Linode Nanode (1 vCPU / 1 GB), wiped to NixOS with
# nixos-anywhere and managed from this flake + Colmena hive like the house. The
# baseline (key-only SSH, nftables w/ 22, deploy user, zsh, sops, step-ca root
# trust) comes from ../../../modules/common.nix via serverModules in flake.nix;
# this file holds only what's cloud-specific.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ./proxy.nix
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

  # --- Project 4C: private path to mgmt over the wg-mc tunnel ---------------
  # mgmt joined the existing wg-mc overlay as 10.100.0.3 (hosts/lan/mgmt/modules/
  # wg-cloud1.nix); cloud1 reaches it there, never at its real LAN IP
  # 192.168.1.222 (that subnet isn't routed over the tunnel - allowedIPs on
  # both ends pins this to point-to-point 10.100.0.0/24 only).
  #
  # Harmonia cache: common.nix's alcove.internalCa.useCache = true default now
  # applies (this host used to opt out here). Pin the mgmtIp override so
  # cache.mgmt.lan/ca.mgmt.lan resolve to the tunnel address instead of the
  # unreachable LAN one; 443 is already LAN-wide open on mgmt (base.nix), no
  # firewall change needed there.
  alcove.internalCa.mgmtIp = "10.100.0.3";

  # node_exporter: common.nix's default (enabled) now applies (this host used
  # to opt out here). Scraped over the tunnel address, not mgmt's real IP -
  # see alcove.metrics.scraperIp and fleet-hosts.nix's cloud1.scrapeIp.
  alcove.metrics.scraperIp = "10.100.0.3";

  # Ship this host's journal to mgmt's Loki, same as every other fleet host,
  # just over the tunnel instead of the LAN. mgmt opens :3100 to this host's
  # tunnel address specifically (hosts/lan/mgmt/modules/wg-cloud1.nix).
  alcove.siemLite.agent.enable = true;
  alcove.siemLite.lokiEndpoint = "http://10.100.0.3:3100/loki/api/v1/push";

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
