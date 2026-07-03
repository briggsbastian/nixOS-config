# hosts/lan/hacktop/wg-proxy.nix
#
# Dial-out WireGuard peer to cloud1, carrying the public Minecraft traffic.
# hacktop initiates (we're behind home NAT; cloud1 can't reach in) and the
# keepalive holds the mapping open so player traffic can arrive any time.
# The Minecraft server needs nothing special: its openFirewall covers 25565
# on every interface, including this one.
#
# AllowedIPs is only the tunnel subnet - this can never capture the default
# route, so it can't recreate the reply-hijack failures from the wired
# bring-up (see configuration.nix history).
#
# Counterpart: hosts/cloud/cloud1/proxy.nix (DNAT + masquerade end).
{ config, ... }:

{
  sops.secrets.wg_private_key = { };

  networking.wireguard.interfaces.wg-mc = {
    ips = [ "10.100.0.2/24" ];
    privateKeyFile = config.sops.secrets.wg_private_key.path;
    peers = [{
      # cloud1 (Linode us-sea)
      publicKey = "rLBfuy8uF0mQF4OVs9piBZEUIdrs/E2dSpSNPSUjEVk=";
      allowedIPs = [ "10.100.0.0/24" ];
      endpoint = "172.234.232.185:51820";
      persistentKeepalive = 25;   # hold the NAT mapping open from our side
    }];
  };
}
