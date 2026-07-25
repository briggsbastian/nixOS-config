# hosts/lan/mgmt/modules/wg-cloud1.nix
#
# Project 4C: dial-out WireGuard peer to cloud1, joining the same wg-mc
# overlay hacktop already uses for the Minecraft tunnel (10.100.0.0/24).
# mgmt is behind home NAT same as hacktop, so it dials OUT; cloud1 gets a
# second peer entry (10.100.0.3/32) alongside hacktop's on its existing
# wg-mc interface - no new keypair needed on cloud1's side.
#
# Unblocks, all addressed via mgmt's tunnel IP 10.100.0.3 (see the matching
# overrides in hosts/cloud/cloud1/configuration.nix):
#   - Prometheus scraping cloud1's node_exporter (fleet-hosts.nix scrapeIp)
#   - cloud1's Alloy shipping logs to this Loki (opened below)
#   - cloud1 using Harmonia as a substituter (443 is already LAN-wide open,
#     see base.nix; cloud1 just needs cache.mgmt.lan to resolve to us)
#
# Counterpart: hosts/cloud/cloud1/proxy.nix (adds this as a second peer).
{ config, lib, ... }:

{
  sops.secrets.wg_cloud1_private_key = {
    sopsFile = ../../../../secrets/mgmt.yaml;
  };

  networking.wireguard.interfaces.wg-mc = {
    ips = [ "10.100.0.3/24" ];
    privateKeyFile = config.sops.secrets.wg_cloud1_private_key.path;
    peers = [
      {
        # cloud1 (Linode) - same key as hacktop's peer entry (hosts/lan/hacktop/wg-proxy.nix)
        publicKey = "rLBfuy8uF0mQF4OVs9piBZEUIdrs/E2dSpSNPSUjEVk=";
        allowedIPs = [ "10.100.0.0/24" ];
        endpoint = "172.234.232.185:51820";
        persistentKeepalive = 25; # hold the NAT mapping open from our side
      }
    ];
  };

  # Loki's :3100 is LAN-cidr-scoped by siem-lite.nix; add cloud1's tunnel
  # address on top of that (both firewall backends, matching that module's
  # pattern - mgmt runs iptables today, nftables would be a no-op silently
  # otherwise). Only cloud1 gets in, nothing else on the tunnel subnet.
  networking.firewall = lib.mkMerge [
    (lib.mkIf config.networking.nftables.enable {
      extraInputRules = ''
        ip saddr 10.100.0.1/32 tcp dport 3100 accept
      '';
    })
    (lib.mkIf (!config.networking.nftables.enable) {
      extraCommands = ''
        iptables -A nixos-fw -p tcp -s 10.100.0.1/32 --dport 3100 -j nixos-fw-accept
      '';
    })
  ];
}
