# Reverse proxy: one TLS entry point routing *.mgmt.lan hostnames to the
# services, which all listen on localhost. Certs come from the private
# step-ca via ACME and renew automatically (see step-ca.nix).
# (Snipe-IT's vhost is declared by its own module in snipe-it.nix.)
{ lib, ... }:

let
  proxy = upstream: extra:
    lib.recursiveUpdate
      {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = upstream;
          proxyWebsockets = true;
        };
      }
      extra;
in
{
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    clientMaxBodySize = "500m";

    virtualHosts = {
      "mgmt.lan" = proxy "http://127.0.0.1:8082" { default = true; };
      "home.mgmt.lan" = proxy "http://127.0.0.1:8082" { };
      "adguard.mgmt.lan" = proxy "http://127.0.0.1:3000" { };
      "status.mgmt.lan" = proxy "http://127.0.0.1:3001" { };
      "grafana.mgmt.lan" = proxy "http://127.0.0.1:3002" { };
      "ntop.mgmt.lan" = proxy "http://127.0.0.1:3003" { };
      "git.mgmt.lan" = proxy "http://127.0.0.1:3004" { };
      "news.mgmt.lan" = proxy "http://127.0.0.1:8377" { };
      "cache.mgmt.lan" = proxy "http://127.0.0.1:5000" {
        # binary cache pubkey for client configs
        locations."= /pubkey".alias = "/var/lib/mgmt-public/harmonia.pub";
      };
      "netbox.mgmt.lan" = proxy "http://127.0.0.1:8001" {
        locations."/static/".alias = "/var/lib/netbox/static/";
      };
      # alertmanager UI, no auth, LAN-only like the rest
      "alerts.mgmt.lan" = proxy "http://127.0.0.1:9093" { };
      # ntfy long-polls, so bump timeouts and don't buffer
      "ntfy.mgmt.lan" = proxy "http://127.0.0.1:2586" {
        locations."/".extraConfig = ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          proxy_buffering off;
        '';
      };
      "ca.mgmt.lan" = proxy "https://127.0.0.1:8443" {
        locations."/".extraConfig = "proxy_ssl_verify off;";
        # the root cert devices need to trust
        locations."= /root.crt".alias = "/var/lib/mgmt-public/root_ca.crt";
      };
      # Cockpit runs on the playground host (192.168.1.217:9090), NOT localhost -
      # the fleet's first cross-host proxy. Backend is Cockpit's own self-signed TLS
      # (proxy_ssl_verify off, same as ca.mgmt.lan). Fronting it with a trusted
      # step-ca cert here fixes Firefox's self-signed-cert WebSocket bounce that
      # broke the direct https://192.168.1.217:9090 login (auth ok, ws dropped).
      "cockpit.mgmt.lan" = proxy "https://192.168.1.217:9090" {
        locations."/".extraConfig = "proxy_ssl_verify off;";
      };
    };
  };
}
