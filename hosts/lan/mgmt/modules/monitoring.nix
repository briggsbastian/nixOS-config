# Metrics + uptime + landing page: Prometheus scrapes node_exporter,
# Grafana visualizes, Uptime Kuma probes the services, Homepage links it
# all together at https://mgmt.lan.
{ config, lib, pkgs, ... }:

let
  # Scrape targets come from the same host map flake.nix uses for Colmena
  # (fleet-hosts.nix), so the deploy list and the metrics list can't drift.
  # `scrape = true` hosts only; mgmt is added separately below because its own
  # exporter binds 127.0.0.1, so it's scraped over localhost, not by IP.
  fleetHosts = import ../../../../fleet-hosts.nix;
  scrapedHosts = lib.filterAttrs (_: h: h.scrape) fleetHosts;

  # Cert-expiry probe targets = every internal HTTPS vhost, derived straight from
  # nginx so it can't fall behind the vhost list. These names resolve on mgmt
  # itself (step-ca.nix pins *.mgmt.lan -> 192.168.1.222 in /etc/hosts), so the
  # probe stays on-box.
  blackboxPort = 9115;
  acmeVhosts = lib.attrNames (lib.filterAttrs (_: v: v.enableACME) config.services.nginx.virtualHosts);
  certProbeTargets = map (h: "https://${h}") acmeVhosts;

  # blackbox prober that just completes a TLS handshake so probe_ssl_* is
  # populated. insecure_skip_verify: we only read the cert's *expiry* here (to
  # catch a silently-failed step-ca/lego renewal before the 90-day cert lapses) -
  # chain trust is a separate concern, validated on the clients that import the
  # root (modules/internal-ca.nix). Skipping verify also means we still read the
  # expiry even after a renewal has already fallen back to the untrusted minica.
  blackboxConfig = (pkgs.formats.yaml { }).generate "blackbox.yml" {
    modules.http_2xx_tls = {
      prober = "http";
      timeout = "5s";
      http = {
        method = "GET";
        fail_if_not_ssl = true;
        tls_config.insecure_skip_verify = true;
        preferred_ip_protocol = "ip4";
      };
    };
  };
in
{
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9100;
      enabledCollectors = [ "systemd" ];
    };

    # Blackbox prober for the cert-expiry check below. localhost-bound; Prometheus
    # reaches it over loopback and points it at each vhost via relabeling.
    exporters.blackbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = blackboxPort;
      configFile = blackboxConfig;
    };
    # One "node" job covering the whole fleet. instance = hostname (not ip:port)
    # keeps labels low-cardinality and makes alerts read "node media down". mgmt
    # is scraped over localhost; everyone else by IP, derived from fleet-hosts.nix
    # so this list never drifts from the Colmena host map. cloud1 is absent
    # (scrape = false) until it has a private path to mgmt.
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = [ "127.0.0.1:9100" ];
            labels.instance = "mgmt";
          }
        ]
        ++ lib.mapAttrsToList (name: h: {
          targets = [ "${h.ip}:9100" ];
          labels.instance = name;
        }) scrapedHosts;
      }

      # TLS cert expiry: have blackbox probe each internal HTTPS vhost. The
      # relabel dance is the standard blackbox pattern - the real URL rides as
      # __param_target and becomes the instance label, while __address__ is
      # rewritten to the blackbox exporter that does the probing.
      {
        job_name = "blackbox-tls";
        metrics_path = "/probe";
        params.module = [ "http_2xx_tls" ];
        static_configs = [ { targets = certProbeTargets; } ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:${toString blackboxPort}";
          }
        ];
      }
    ];

    # Send fired metric alerts to the Alertmanager siem-lite.nix already runs on
    # 127.0.0.1:9093 (the ntfy bridge lives there). Loki's ruler is already wired
    # to the same Alertmanager for log alerts, so metrics + logs share one path
    # out to ntfy.mgmt.lan/homelab-alerts.
    alertmanagers = [
      { static_configs = [ { targets = [ "127.0.0.1:9093" ]; } ]; }
    ];

    # Conservative host-metric alerts. Long `for:` windows so a single missed
    # scrape or a transient spike doesn't page. instance = hostname (set in the
    # scrape config above) so every alert names the box.
    rules = [
      ''
        groups:
          - name: fleet-node
            rules:
              # Host/exporter unreachable: down, crashed, or :9100 firewalled.
              - alert: NodeDown
                expr: up{job="node"} == 0
                for: 5m
                labels:
                  severity: critical
                annotations:
                  summary: "node_exporter unreachable on {{ $labels.instance }}"
                  description: "Prometheus has not scraped {{ $labels.instance }} for 5m (host down, exporter stopped, or :9100 blocked)."

              # Any real local filesystem over 85% full. Network (nfs) + ephemeral
              # (tmpfs/overlay/...) filesystems are excluded: the NAS is monitored
              # at the NAS, and /mnt/media is an autofs automount node_exporter
              # can't see reliably anyway.
              - alert: NodeDiskFull
                expr: |
                  (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay|squashfs|fuse.*|nfs.*|autofs|devtmpfs|efivarfs"}
                       / node_filesystem_size_bytes) > 0.85
                for: 30m
                labels:
                  severity: warning
                annotations:
                  summary: "Disk over 85% on {{ $labels.instance }} ({{ $labels.mountpoint }})"
                  description: "{{ $labels.mountpoint }} on {{ $labels.instance }} is {{ $value | humanizePercentage }} full."

              # Sustained low free memory (not a momentary spike).
              - alert: NodeMemoryPressure
                expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10
                for: 15m
                labels:
                  severity: warning
                annotations:
                  summary: "Low memory on {{ $labels.instance }}"
                  description: "Under 10% memory available on {{ $labels.instance }} for 15m."

              # Swap almost full. zram swap is *meant* to be used, so only a nearly
              # exhausted swap (real pressure) fires, not mere swap activity.
              - alert: NodeSwapAlmostFull
                expr: |
                  node_memory_SwapTotal_bytes > 0
                  and (node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes) < 0.10
                for: 15m
                labels:
                  severity: warning
                annotations:
                  summary: "Swap almost full on {{ $labels.instance }}"
                  description: "Swap is over 90% used on {{ $labels.instance }} for 15m."

              # Any systemd unit stuck in failed state (the exporter's systemd
              # collector, enabled fleet-wide in modules/metrics.nix). 10m lets a
              # unit that auto-restarts settle before paging.
              - alert: SystemdUnitFailed
                expr: node_systemd_unit_state{state="failed"} == 1
                for: 10m
                labels:
                  severity: warning
                annotations:
                  summary: "systemd unit failed on {{ $labels.instance }}"
                  description: "{{ $labels.name }} is in failed state on {{ $labels.instance }}."

          - name: tls-certs
            rules:
              # Catch a silently-failed step-ca/lego renewal long before the
              # 90-day cert actually lapses. The time-difference is the first
              # operand so $value is the seconds remaining; the `> 0` guard means
              # a failed probe (expiry absent/0) can't masquerade as "expiring".
              - alert: CertExpiringSoon
                expr: |
                  (probe_ssl_earliest_cert_expiry - time()) < (14 * 24 * 3600)
                  and probe_ssl_earliest_cert_expiry > 0
                for: 1h
                labels:
                  severity: warning
                annotations:
                  summary: "TLS cert for {{ $labels.instance }} expires in under 14 days"
                  description: "{{ $labels.instance }} expires in {{ $value | humanizeDuration }} - step-ca/lego renewal may have failed."
      ''
    ];
  };

  services.grafana = {
    enable = true;
    settings.server = {
      http_addr = "127.0.0.1";
      http_port = 3002;
      domain = "grafana.mgmt.lan";
      root_url = "https://grafana.mgmt.lan/";
    };
    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        url = "http://127.0.0.1:9090";
        isDefault = true;
      }
    ];
  };

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = "3001";
    };
  };

  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "mgmt.lan,home.mgmt.lan";
    settings = {
      title = "mgmt";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      useEqualHeights = true;
      hideVersion = true;
      layout = {
        Security       = { style = "row"; columns = 2; };
        Observability  = { style = "row"; columns = 3; };
        Infrastructure = { style = "row"; columns = 3; };
        Media          = { style = "row"; columns = 3; };
        Lab            = { style = "row"; columns = 2; };
      };
    };
    # header bar: live host resources + a clock
    widgets = [
      {
        resources = {
          label = "mgmt";
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = { dateStyle = "long"; timeStyle = "short"; hour12 = true; };
        };
      }
    ];
    services = [
      {
        "Security" = [
          { "AdGuard Home" = {
              href = "https://adguard.mgmt.lan";
              description = "DNS filtering for the LAN";
            }; }
        ];
      }
      {
        "Observability" = [
          { "Grafana" = {
              href = "https://grafana.mgmt.lan";
              description = "Metrics + log dashboards (Prometheus + Loki)";
            }; }
          { "Logs (Explore)" = {
              href = "https://grafana.mgmt.lan/explore";
              description = "Search the fleet's journals in Loki";
            }; }
          { "Alertmanager" = {
              href = "https://alerts.mgmt.lan";
              description = "Fired alerts - view, silence, routing";
            }; }
          { "ntfy" = {
              href = "https://ntfy.mgmt.lan";
              description = "Push alerts - subscribe to /homelab-alerts";
            }; }
          { "Uptime Kuma" = {
              href = "https://status.mgmt.lan";
              description = "Service uptime monitoring";
            }; }
          { "ntopng" = {
              href = "https://ntop.mgmt.lan";
              description = "Network traffic analysis";
            }; }
        ];
      }
      {
        "Infrastructure" = [
          { "NetBox" = {
              href = "https://netbox.mgmt.lan";
              description = "IPAM & network documentation";
            }; }
          { "Forgejo" = {
              href = "https://git.mgmt.lan";
              description = "Git hosting";
            }; }
          { "Snipe-IT" = {
              href = "https://assets.mgmt.lan";
              description = "Asset inventory";
            }; }
          { "Root CA cert" = {
              href = "https://ca.mgmt.lan/root.crt";
              description = "Install on devices to trust *.mgmt.lan";
            }; }
          { "Nix cache pubkey" = {
              href = "https://cache.mgmt.lan/pubkey";
              description = "Binary cache at https://cache.mgmt.lan";
            }; }
        ];
      }
      {
        # Direct IP:port - these run on the media/lab hosts, not behind mgmt's nginx.
        "Media" = [
          { "Jellyfin" = {
              href = "http://192.168.1.189:8096";
              description = "Media streaming";
            }; }
          { "Radarr" = {
              href = "http://192.168.1.189:7878";
              description = "Movies";
            }; }
          { "Sonarr" = {
              href = "http://192.168.1.189:8989";
              description = "TV shows";
            }; }
          { "Prowlarr" = {
              href = "http://192.168.1.189:9696";
              description = "Indexer manager";
            }; }
          { "Bazarr" = {
              href = "http://192.168.1.189:6767";
              description = "Subtitles";
            }; }
          { "NZBGet" = {
              href = "http://192.168.1.189:6789";
              description = "Usenet downloader";
            }; }
          { "Kavita" = {
              href = "http://192.168.1.189:5000";
              description = "Books, comics & manga";
            }; }
        ];
      }
      {
        "Lab" = [
          { "Guacamole" = {
              href = "http://192.168.1.217:8080/guacamole/";
              description = "Browser remote-desktop gateway (RDP/VNC/SSH)";
            }; }
        ];
      }
    ];
  };
}
