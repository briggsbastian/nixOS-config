# hosts/playground/bridge.nix
#
# br0 - a Linux bridge enslaving the single wired uplink (enp1s0) so libvirt/KVM
# guests sit on the LAN (their reserved MACs pull their reserved DHCP leases) and
# the host can still reach them. macvtap is out because Guacamole/guacd runs on
# this box (macvtap blocks host<->guest). Backend: systemd-networkd.
#
# Self-contained on purpose: the whole NetworkManager->networkd cutover is this one
# import. Removing it from configuration.nix reverts to NetworkManager.
#
# br0 takes a static .217 (a fixed reservation anyway), which kills the "br0 came
# up with no/wrong DHCP lease" failure class. Its MAC is pinned to a fixed LAA
# address (02:*) so the host's L2 identity stays stable and guest taps
# (52:54:00:*) can't re-derive it.
{ lib, pkgs, ... }:

let
  uplink    = "enp1s0";
  uplinkMac = "02:00:00:00:01:17"; # br0's pinned MAC: a stable locally-administered addr (any 02:* works)
in
{
  # --- Backend swap: NetworkManager -> systemd-networkd ----------------------
  # configuration.nix sets `networkmanager.enable = true` as a PLAIN assignment,
  # so mkForce is required to override it from this module.
  networking.networkmanager.enable = lib.mkForce false;
  networking.useNetworkd = true; # enable systemd-networkd; disable scripted/dhcpcd
  networking.useDHCP = false; # no catch-all 99-ethernet-default-dhcp.network
  services.resolved.enable = true; # resolved owns /etc/resolv.conf now (NM doesn't)
  # -> keeps cache.mgmt.lan / ACME resolvable.

  # --- The bridge device, MAC-pinned to the uplink ---------------------------
  systemd.network.netdevs."20-br0" = {
    netdevConfig = {
      Kind = "bridge";
      Name = "br0";
      MACAddress = uplinkMac; # pin -> defeats "lowest-port-MAC" drift forever
    };
    bridgeConfig.STP = false; # single uplink, no loop -> forward immediately
  };

  # --- Enslave the physical uplink (no L3 of its own) ------------------------
  systemd.network.networks."30-${uplink}" = {
    matchConfig.Name = uplink;
    networkConfig = {
      Bridge = "br0";
      LinkLocalAddressing = "no"; # no stray IPv6-LL on the slave port
    };
    linkConfig.RequiredForOnline = "enslaved"; # don't gate "online" on the slave
  };

  # --- br0 carries the host identity: STATIC .217 (no DHCP-at-boot gamble) ----
  systemd.network.networks."40-br0" = {
    matchConfig.Name = "br0";
    address = [ "192.168.1.217/24" ];
    routes = [ { Gateway = "192.168.1.1"; } ]; # flattened form (25.11; routeConfig removed)
    dns = [ "192.168.1.222" ]; # AdGuard on mgmt (resolves *.mgmt.lan)
    networkConfig.IPv6AcceptRA = false; # v4-only host; guests still SLAAC independently
    linkConfig = {
      RequiredForOnline = "routable";
      RequiredFamilyForOnline = "ipv4"; # IPv4 satisfies "online"; never wait on v6
    };
  };

  # --- Don't let wait-online hang boot/activation ----------------------------
  systemd.network.wait-online = {
    anyInterface = false; # gate on br0's real routable address, not the enslaved slave
    ignoredInterfaces = [ "wlo1" ]; # wifi is DOWN/unused
    timeout = 30;
  };

  # --- Keep bridged guest L2 frames off the host's nftables hooks -------------
  # NixOS only filters INPUT (firewall.filterForward defaults false in 25.11), so
  # bridged guest traffic + Guacamole work today regardless. Defense in depth for
  # when filterForward is enabled or a NAT/routed libvirt net is added (which flips
  # br_netfilter call-iptables on). Oneshot so the sysctls also hold during a live
  # `test` activation, not just at boot.
  boot.kernelModules = [ "br_netfilter" ]; # merges with hardware-config's kvm-amd
  systemd.services.bridge-nf-off = {
    description = "Pin bridge netfilter call-* off (guest L2 bypasses host nftables)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    before = [ "systemd-networkd.service" ];
    path = [ pkgs.kmod ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      modprobe br_netfilter || true
      for k in iptables ip6tables arptables; do
        echo 0 > /proc/sys/net/bridge/bridge-nf-call-$k
      done
    '';
  };

  # --- Recovery backstop: reboot 10s after a kernel panic --------------------
  boot.kernelParams = [ "panic=10" ];
}
