# hosts/cloud/cloud1/proxy.nix
#
# Public entry point for the Minecraft server on hacktop: players connect to
# cloud1:25565 and the kernel DNATs the flow down a WireGuard tunnel to
# hacktop. The home IP is never published, no home ports open (hacktop dials
# OUT to us with keepalives), and internet noise lands on the Linode.
#
# Path: player -> enp0s3:25565 -> DNAT 10.100.0.2:25565 (hacktop over wg-mc)
#       reply <- masquerade (postrouting) so hacktop answers back through the
#       tunnel instead of trying its own default route (asymmetric = broken).
# Measured cost: home<->cloud1 is ~6-11 ms; players see ~10-25 ms extra.
#
# Trade: masquerade means every player appears to the server as 10.100.0.1 -
# IP bans/whitelists are meaningless, use the username whitelist instead.
#
# Counterpart: hosts/lan/hacktop/wg-proxy.nix (the dial-out peer).
# Linode Cloud Firewall opens 51820/udp + 25565/tcp (Code/Linode terraform).
{ config, ... }:

{
  # First secret on this host: the tunnel's private key. cloud1 is scoped to
  # its own sops file only - see .sops.yaml (internet-facing box, no LAN
  # secrets).
  sops.defaultSopsFile = ../../../secrets/cloud1.yaml;
  sops.secrets.wg_private_key = { };

  networking.wireguard.interfaces.wg-mc = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets.wg_private_key.path;
    peers = [
      {
        # hacktop - the only peer; nothing else can join the tunnel
        publicKey = "LnThq+lGAjbnT4cdST4cueGX1dv3icEqVZf9EwKiEH8=";
        allowedIPs = [ "10.100.0.2/32" ];
      }
    ];
  };

  # WG handshakes are silent to anyone without a valid peer key, so an open
  # 51820 leaks nothing. 25565 is NOT opened here on purpose: the DNAT in
  # prerouting rewrites those flows before they'd ever hit the input chain,
  # so the forwarded port needs no input-chain hole.
  networking.firewall.allowedUDPPorts = [ 51820 ];

  # Forwarding stays unfiltered (NixOS firewall filterForward defaults off):
  # the only route through this box is the single-peer tunnel, whose reach is
  # pinned by allowedIPs above.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.nftables.tables.minecraft-proxy = {
    family = "ip";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname "enp0s3" tcp dport 25565 dnat to 10.100.0.2:25565
      }
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "wg-mc" tcp dport 25565 masquerade
      }
    '';
  };
}
