# hosts/cloud/cloud1/proxy.nix
#
# Public entry point for the Minecraft server on hacktop: players connect to
# cloud1:25565 and the kernel DNATs the flow down a WireGuard tunnel to
# hacktop. The home IP is never published, no home ports open (hacktop dials
# OUT to us with keepalives), and internet noise lands on the Linode.
#
# Path: player -> enp0s3:24799 -> DNAT 10.100.0.2:25565 (hacktop over wg-mc)
#       reply <- masquerade (postrouting) so hacktop answers back through the
#       tunnel instead of trying its own default route (asymmetric = broken).
# Measured cost: home<->cloud1 is ~6-11 ms; players see ~10-25 ms extra.
#
# The public port is 24799, NOT 25565: an SRV record
# (_minecraft._tcp.play.briggsbastian.com -> port 24799) lets players still
# type the bare hostname, while the constant internet-wide scans of 25565 see
# nothing. hacktop keeps listening on 25565 (LAN players connect direct).
#
# Trade: masquerade means every player appears to the server as 10.100.0.1 -
# IP bans/whitelists are meaningless, use the username whitelist instead.
#
# Counterpart: hosts/lan/hacktop/wg-proxy.nix (the dial-out peer).
# Linode Cloud Firewall opens 51820/udp + 24799/tcp (Code/Linode terraform).
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
        iifname "enp0s3" tcp dport 24799 dnat to 10.100.0.2:25565
      }
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "wg-mc" tcp dport 25565 masquerade
      }
      # Per-source-IP throttle on NEW connections into the tunnel. This is the
      # only place a per-IP limit can exist: hacktop sees every player as
      # 10.100.0.1 after the masquerade, but here (forward hook, post-DNAT)
      # the real source is still on the packet. 10 new conns/min with a
      # burst of 10 is generous for humans (a reconnect is rare) and starves
      # join-flood bots. Entries age out after a minute.
      set mc_ratelimit {
        type ipv4_addr
        flags dynamic
        timeout 1m
      }
      chain forward-limit {
        type filter hook forward priority filter; policy accept;
        oifname "wg-mc" tcp dport 25565 ct state new \
          add @mc_ratelimit { ip saddr limit rate over 10/minute burst 10 packets } drop
      }
    '';
  };
}
