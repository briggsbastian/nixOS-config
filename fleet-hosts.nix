# fleet-hosts.nix
#
# Single source of truth for host -> LAN IP, imported by exactly two consumers:
#   - flake.nix                              : Colmena deployment.targetHost (+ the
#                                              nixosConfigurations/hive host set)
#   - hosts/lan/mgmt/modules/monitoring.nix  : Prometheus node_exporter scrape targets
#
# so the deploy host list and the metrics scrape list can never drift apart. This
# is a plain data attrset, NOT a NixOS module - import it and read attributes.
#
# Why a data file and not specialArgs (the two options the brief offered): a data
# file imported directly has one definition and cannot drift. Threading the same
# map through specialArgs would mean wiring it at four call sites that must agree -
# mkServerSystem + mkColmenaNode (servers, nixos + colmena) and mkMgmtSystem +
# mkMgmtColmenaNode (mgmt, nixos + colmena) - any one missed and the deploy view
# and the metrics view silently diverge. The data file is the lower-risk option.
#
# IPs, never names: mgmt's AdGuard serves *.mgmt.lan, so any name that has to
# resolve before DNS is up (a deploy target, a scrape target) would deadlock.
#
# `scrape` = does mgmt's Prometheus scrape this host's node_exporter on :9100?
#   mgmt   : false - it scrapes its own node_exporter over localhost (its exporter
#            binds 127.0.0.1, see hosts/lan/mgmt/modules/monitoring.nix), so a
#            remote job pointed at 192.168.1.222:9100 would never connect.
#   cloud1 : true, via the Project 4C wg-mc tunnel (hosts/lan/mgmt/modules/wg-cloud1.nix
#            + hosts/cloud/cloud1/proxy.nix). :9100 stays firewalled shut on
#            cloud1's public interface either way.
#
# `scrapeIp` (optional, defaults to `ip`) = where mgmt's Prometheus actually
# reaches :9100. Only needed when it differs from the deploy IP above - cloud1's
# node_exporter is reachable over its wg-mc tunnel address, not its public IP.
{
  mgmt = {
    ip = "192.168.1.222";
    scrape = false;
  };
  hacktop = {
    ip = "192.168.1.26";
    scrape = true;
  };
  media = {
    ip = "192.168.1.189";
    scrape = true;
  };
  cloud1 = {
    # recreated 2026-07-02 (terraform apply); IP changes on every recreate
    ip = "172.234.232.185";
    scrape = true;
    # Project 4C: node_exporter is reachable only over the wg-mc tunnel
    # (mgmt's tunnel address), never the public `ip` above - :9100 stays
    # firewalled shut on the public interface. See hosts/lan/mgmt/modules/wg-cloud1.nix.
    scrapeIp = "10.100.0.1";
  };
}
