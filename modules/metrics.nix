# modules/metrics.nix
#
# Fleet host metrics: a node_exporter on every server, scrapeable ONLY by mgmt.
# Imported by modules/common.nix (like deploy-user.nix), so every host that takes
# the fleet baseline gets it. Two hosts are special:
#   - mgmt   never imports common.nix; it runs its own node_exporter bound to
#            127.0.0.1 (hosts/lan/mgmt/modules/monitoring.nix) and scrapes itself
#            over localhost, so it is never a remote scrape target.
#   - cloud1 a public VPS with no private link to mgmt yet, so opening :9100 there
#            is not safe. It opts out below (alcove.metrics.nodeExporter.enable =
#            false in hosts/cloud/cloud1/configuration.nix). Re-enable once the
#            WireGuard/Headscale mesh (Project 4C) gives mgmt a private route.
#
# The scrape side (mgmt's Prometheus) derives its target list from fleet-hosts.nix,
# the same data flake.nix uses for Colmena, so the two lists can't drift.
{ config, lib, ... }:

let
  cfg = config.alcove.metrics;
  nodePort = 9100;
in
{
  options.alcove.metrics = {
    nodeExporter.enable =
      (lib.mkEnableOption "the fleet node_exporter (Prometheus host metrics, scraped by mgmt only)")
      // {
        default = true;
      };

    scraperIp = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.222"; # mgmt; same default internal-ca.nix / siem-lite.nix use
      description = ''
        The only host allowed to reach node_exporter on :9100. node_exporter
        listens on all interfaces, but the firewall accepts :9100 from this IP
        alone (a single /32), so the metrics port is never LAN- or world-open.
      '';
    };
  };

  config = lib.mkIf cfg.nodeExporter.enable {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "0.0.0.0"; # reachable by mgmt; locked down by the firewall below
      port = nodePort;
      enabledCollectors = [ "systemd" ]; # unit states feed the "systemd unit failed" alert on mgmt
    };

    # Open :9100 to mgmt's IP only. Reuses the LAN-scoped nftables pattern
    # siem-lite.nix uses for Loki's :3100, but tightened from a CIDR to a single
    # host. Both firewall backends handled so it's correct either way.
    networking.firewall = lib.mkMerge [
      (lib.mkIf config.networking.nftables.enable {
        extraInputRules = ''
          ip saddr ${cfg.scraperIp} tcp dport ${toString nodePort} accept
        '';
      })
      (lib.mkIf (!config.networking.nftables.enable) {
        extraCommands = ''
          iptables -A nixos-fw -p tcp -s ${cfg.scraperIp} --dport ${toString nodePort} -j nixos-fw-accept
        '';
      })
    ];
  };
}
