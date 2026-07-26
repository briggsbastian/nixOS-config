# Log aggregation + alerting, replaces Wazuh.
#   server role (mgmt): Loki + Alertmanager + ntfy + a Grafana datasource + Alloy
#   agent role (fleet): Alloy only, ships the journal to the central Loki
# Loki/Alloy configs are free-form text, so eval won't catch schema errors - only
# runtime does. Grafana/Prometheus already exist on mgmt (monitoring.nix), so we
# merge into them rather than redefine. Port 3000 is AdGuard, don't touch it.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.alcove.siemLite;

  lokiPort = 3100;
  alertmanagerPort = 9093;

  alloyNeeded = cfg.server.enable || cfg.agent.enable;

  # server pushes to its own Loki, agents to the central one
  pushEndpoint =
    if cfg.server.enable then
      "http://127.0.0.1:${toString lokiPort}/loki/api/v1/push"
    else
      cfg.lokiEndpoint;

  # Noise filter, inserted between the journal source and loki.write. When the
  # drop list is empty the component is omitted entirely and the source writes
  # direct, so an empty list is genuinely a no-op rather than an always-false
  # matcher sitting in the path.
  dropUnits = cfg.agent.dropInfoFrom;
  journalSink =
    if dropUnits == [ ] then "loki.write.default.receiver" else "loki.process.drop_noise.receiver";
  dropNoiseComponent = lib.optionalString (dropUnits != [ ]) ''

    // Selector is LogQL over the labels the relabel rules above have already
    // applied, so `unit` and `level` are both set by the time a line reaches
    // here.
    //
    // The dots are deliberately NOT escaped. Escaping them is the obvious
    // instinct - =~ is a full RE2 match, so a bare `.` is a wildcard - but it
    // silently breaks the filter. There are three unquoting layers here (Nix
    // emits the file, Alloy unquotes the selector string, LogQL unquotes the
    // matcher value), and a `\\.` in this file arrives at LogQL as `\.`.
    // Measured against the live Loki:
    //
    //     {unit=~"nzbget\.service|...", level="info"}   ->  0 results, NO ERROR
    //     {unit=~"nzbget\\.service|...", level="info"}  ->  6869
    //     {unit=~"nzbget.service|...", level="info"}    ->  6869
    //
    // So the escaped form drops nothing at all, and `alloy validate` passes it
    // happily because the syntax is fine. Getting the escaping "right" would
    // mean writing four backslashes here and hoping the next person counts
    // correctly. The wildcard can only over-match unit names that do not
    // exist, which is a smaller risk than a filter that silently does nothing.
    loki.process "drop_noise" {
      forward_to = [loki.write.default.receiver]

      stage.match {
        selector = "{unit=~\"${lib.concatStringsSep "|" dropUnits}\", level=\"info\"}"
        action   = "drop"
      }
    }
  '';

  # journal -> Loki. labels stay unit/host/level only (cardinality)
  alloyConfigText = ''
    loki.write "default" {
      endpoint {
        url = "${pushEndpoint}"
      }
    }

    ${cfg.agent.extraConfig}

    // only here to provide .rules to the journal source below; nothing flows
    // through this component. one attribute per line or it won't parse.
    loki.relabel "journal" {
      forward_to = [loki.write.default.receiver]
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal__hostname"]
        target_label  = "host"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
    }

    loki.source.journal "system" {
      // __journal_* fields are only visible to relabel_rules here; a downstream
      // loki.relabel component never sees them (the source strips them first).
      forward_to    = [${journalSink}]
      relabel_rules = loki.relabel.journal.rules
      labels        = { job = "systemd-journal" }
      max_age       = "12h"
    }
    ${dropNoiseComponent}
  '';

  # points the grafana cli at the server's real db for the password reset below
  grafanaCliConfig = pkgs.writeText "grafana-cli.ini" ''
    [paths]
    data = /var/lib/grafana
  '';
in
{
  options.alcove.siemLite = {
    server.enable = lib.mkEnableOption "the central SIEM-lite server (Loki + Alertmanager + Grafana Loki datasource + local Alloy)";

    agent.enable = lib.mkEnableOption "the SIEM-lite log shipper (Alloy: systemd journal -> central Loki)";

    agent.extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra Alloy config appended after the built-in journal source (e.g. an
        extra loki.source.file component). Must forward_to
        [loki.write.default.receiver] like the built-in journal pipeline does.
      '';
    };

    agent.dropInfoFrom = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "nzbget.service"
        "loki.service"
      ];
      description = ''
        Units whose `info`-level journal lines are dropped at the agent, before
        anything is shipped. Higher levels from the same units are always kept.

        Measured over 24h before this existed: 345,569 journal lines fleet-wide,
        of which nzbget contributed 144,766 and loki 134,605 - 81% of everything
        - and every single one of those was level=info. Zero warnings, zero
        errors. Loki logging 134k lines a day about itself, into itself.

        Dropped at the agent rather than by Loki retention because volume that
        is never shipped costs no network, no storage and no index.

        Scoped by unit AND level rather than by level alone, because sshd is
        100% info too: 719 lines in the same 24h, every one of them an auth
        event. A blanket info filter would delete the single most useful
        security source on the estate to remove chatter from a Usenet client.
      '';
    };

    lokiEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://192.168.1.222:${toString lokiPort}/loki/api/v1/push";
      # IP not a name: AdGuard serves *.mgmt.lan, so a name here would deadlock
      description = "Where agents push logs (central Loki on mgmt). Ignored by the server role.";
    };

    lanCidr = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.0/24";
      description = "Source range allowed to reach the central Loki push port (server role only).";
    };

    server.grafanaAdminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/grafana_admin_password";
      description = "sops secret path for Grafana's admin password (read via Grafana's $__file{}).";
    };

    server.ntfyBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.mgmt.lan";
      description = "Public base URL of the self-hosted ntfy server (what the phone subscribes to).";
    };

    server.ntfyTopic = lib.mkOption {
      type = lib.types.str;
      default = "homelab-alerts";
      # not a secret: ntfy is localhost-bound + LAN-only behind nginx
      description = "ntfy topic fired alerts publish to.";
    };

    server.alertmanagerExternalUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://alerts.mgmt.lan";
      description = "External URL when fronted by a proxy, so the UI routes right. Null = bind address.";
    };
  };

  config = lib.mkMerge [

    # Alloy collector, both roles (server scrapes itself too)
    (lib.mkIf alloyNeeded {
      services.alloy.enable = true;
      services.alloy.configPath = "/etc/alloy/config.alloy";
      environment.etc."alloy/config.alloy".text = alloyConfigText;

      # Alloy is invoked with a stable path (/etc/alloy/config.alloy), not a
      # store path, so changing the config changes NOTHING about the unit and
      # switch-to-configuration has no reason to restart it. The new config
      # lands on disk and the running process keeps the old one.
      #
      # This exact shape has now bitten three times: suricata's ruleset, alloy's
      # eve.json tail, and this. Anywhere a service reads state that Nix writes
      # to a fixed path, the unit needs an explicit trigger or the deploy is
      # cosmetic. Triggering on the config text itself means any change to the
      # pipeline - drop rules, extraConfig, endpoint - restarts the agent.
      systemd.services.alloy.restartTriggers = [ alloyConfigText ];

      # needs the systemd-journal group to read the full journal
      systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "systemd-journal" ];
    })

    # Server role: Loki, Alertmanager, ntfy, Grafana datasource
    (lib.mkIf cfg.server.enable {

      # Loki: storage + ruler. single-binary TSDB/v13, single tenant ("fake").
      services.loki = {
        enable = true;
        configuration = {
          auth_enabled = false;
          server = {
            http_listen_port = lokiPort;
            http_listen_address = "0.0.0.0"; # LAN agents reach it; firewalled below
          };

          common = {
            instance_addr = "127.0.0.1";
            path_prefix = "/var/lib/loki";
            replication_factor = 1;
            ring.kvstore.store = "inmemory";
            storage.filesystem = {
              chunks_directory = "/var/lib/loki/chunks";
              rules_directory = "/var/lib/loki/rules";
            };
          };

          schema_config.configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];

          limits_config = {
            retention_period = "30d";
            reject_old_samples = true;
            reject_old_samples_max_age = "168h";
          };

          compactor = {
            working_directory = "/var/lib/loki/compactor";
            retention_enabled = true;
            delete_request_store = "filesystem";
          };

          ruler = {
            alertmanager_url = "http://127.0.0.1:${toString alertmanagerPort}";
            enable_alertmanager_v2 = true;
            enable_api = true;
            rule_path = "/var/lib/loki/ruler-wal";
            storage = {
              type = "local";
              local.directory = "/etc/loki/rules"; # rules under <dir>/<tenant>/ -> fake/
            };
          };
        };
      };

      # LogQL alert rules. tenant dir "fake" (auth off).
      environment.etc."loki/rules/fake/alerts.yaml".text = ''
        groups:
          - name: security
            rules:
              # sshd logs under sshd.service
              - alert: SSHBruteForce
                expr: |
                  sum by (host) (count_over_time({unit="sshd.service"} |= `Failed password` [5m])) > 10
                for: 0m
                labels: { severity: warning }
                annotations:
                  summary: "Repeated SSH auth failures on {{ $labels.host }}"
                  description: "{{ $value }} failed SSH logins in 5m on {{ $labels.host }}"

              # sudo logs as SYSLOG_IDENTIFIER=sudo, not its own unit, so this has to
              # match on content rather than select a unit like SSHBruteForce does.
              #
              # unit!="loki.service" is load-bearing, not tidiness. Loki's ruler
              # logs every query it runs, verbatim, to the journal; Alloy ships
              # mgmt's journal back into Loki; so this rule's own evaluation log
              # contains the strings this rule matches on. Without the exclusion it
              # fires on itself forever - it did, continuously, from 2026-07-11
              # until this was found, while zero real sudo failures existed.
              #
              # Note that NO content filter can fix this. Tightening the match to
              # `pam_unix(sudo:auth): authentication failure` fails the same way,
              # because that string then appears in the ruler's log of the query.
              # Only a label selector breaks the loop - which is why SSHBruteForce,
              # scoped to {unit="sshd.service"}, was never affected.
              - alert: SudoFailure
                expr: |
                  sum by (host) (count_over_time({job="systemd-journal", unit!="loki.service"} |= `sudo:` |~ `authentication failure` [10m])) > 3
                for: 0m
                labels: { severity: warning }
                annotations:
                  summary: "Multiple failed sudo attempts on {{ $labels.host }}"
                  description: "{{ $value }} failed sudo attempts in 10m on {{ $labels.host }}"

          - name: reliability
            rules:
              # Covers the blind spot in Prometheus' SystemdUnitFailed, which is
              # `node_systemd_unit_state{state="failed"} == 1`. A unit with
              # Restart=on-failure never settles in `failed` - it cycles through
              # `activating` and back, so that alert can NEVER fire for it.
              #
              # Found by suricata.service on mgmt: Restart=on-failure with
              # RestartUSec=100ms, 173 restarts, crash-looping since 2026-07-17,
              # ~78 failures every 15 minutes. Eight days with the IDS dead, no
              # alert, and SuricataAlert silently waiting on events that could
              # never arrive because the thing producing them was not running.
              #
              # unit="init.scope" is load-bearing twice over:
              #
              #   1. systemd (PID 1) emits these lines, so `_SYSTEMD_UNIT` is
              #      `init.scope` - NOT the unit that failed. The failing unit is
              #      in journald's `UNIT` field, which the relabel config above
              #      deliberately does not map (see the cardinality note at the
              #      loki.relabel block). So it is extracted at query time into
              #      `failed_unit` instead, keeping stream labels unchanged.
              #
              #   2. It gives this rule the self-reference immunity that
              #      SudoFailure had to bolt on. Loki's ruler logs every query it
              #      runs, verbatim, to the journal, and Alloy ships that back
              #      into Loki - so this rule's own evaluation log contains
              #      `Failed with result`. Those lines come from loki.service, so
              #      the init.scope selector excludes them by construction rather
              #      than by an exclusion that has to be remembered.
              #      (If loki.service itself crash-looped, PID 1 would log it
              #      under init.scope and this rule would be correct to fire -
              #      though Loki being down, it could not.)
              #
              # `> 5 in 15m` separates a crash loop from deploy noise. A NixOS
              # activation restarts mnt-media.mount and everything with
              # RequiresMountsFor on it, so jellyfin/nzbget/mnt-media/lxcfs each
              # log exactly ONE failure per deploy. Measured over 7 days of real
              # journal history, this threshold fires for exactly two series -
              # suricata (the crash loop) and grafana (a genuine incident) - and
              # for zero deploy artefacts. A `> 0 in 24h` version was tried first
              # and would have raised four false alerts on every single deploy,
              # which is the cry-wolf failure this estate already made once.
              #
              # Deliberately NOT a general "unit failed recently" rule. Prometheus
              # already covers a unit that stays failed, and it works - it caught
              # recyclarr and fired correctly for ten days. This covers only what
              # that structurally cannot see.
              - alert: SystemdUnitCrashLooping
                expr: |
                  sum by (host, failed_unit) (count_over_time({job="systemd-journal", unit="init.scope"} |= `Failed with result` | regexp `(?P<failed_unit>\S+): Failed with result` [15m])) > 5
                for: 5m
                labels: { severity: warning }
                annotations:
                  summary: "{{ $labels.failed_unit }} is crash-looping on {{ $labels.host }}"
                  description: "{{ $labels.failed_unit }} failed {{ $value }} times in 15m on {{ $labels.host }}. A restarting unit never enters `failed` state, so SystemdUnitFailed cannot see this."
      '';

      # Alertmanager -> the ntfy bridge. additive under the existing prometheus.
      services.prometheus.alertmanager = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = alertmanagerPort;
        webExternalUrl = lib.mkIf (
          cfg.server.alertmanagerExternalUrl != null
        ) cfg.server.alertmanagerExternalUrl;
        configuration = {
          route = {
            receiver = "ntfy";
            # host: the label log alerts carry (sum by (host)); instance: the label
            # the Prometheus metric + cert alerts carry. Both listed so each kind
            # groups per box (a label absent on one kind groups as empty there).
            group_by = [
              "alertname"
              "host"
              "instance"
            ];
            group_wait = "30s";
            group_interval = "5m";
            repeat_interval = "4h";
          };
          # the bridge formats it into a real ntfy notification
          receivers = [
            {
              name = "ntfy";
              webhook_configs = [
                {
                  url = "http://127.0.0.1:8000/hook";
                  send_resolved = true;
                }
              ];
            }
          ];
        };
      };

      # ntfy: localhost-bound, fronted by nginx (vhost in nginx.nix). LAN-only,
      # no ntfy-side auth.
      services.ntfy-sh = {
        enable = true;
        settings = {
          base-url = cfg.server.ntfyBaseUrl;
          listen-http = "127.0.0.1:2586";
        };
      };

      # bridge: Alertmanager webhook -> formatted ntfy message. publishes to the
      # local ntfy (no TLS hairpin). title/priority/tags from module defaults.
      services.prometheus.alertmanager-ntfy = {
        enable = true;
        settings = {
          http.addr = "127.0.0.1:8000";
          ntfy = {
            baseurl = "http://127.0.0.1:2586";
            notification.topic = cfg.server.ntfyTopic;
          };
        };
      };

      # add a Loki datasource to the existing Grafana (list merges, Prometheus
      # stays default). don't re-declare grafana itself.
      services.grafana.provision.datasources.settings.datasources = [
        {
          name = "Loki";
          type = "loki";
          uid = "loki";
          access = "proxy";
          url = "http://127.0.0.1:${toString lokiPort}";
          isDefault = false;
        }
      ];

      # admin password from sops (guarded so a pre-secret build still evals)
      services.grafana.settings.security = lib.mkIf (cfg.server.grafanaAdminPasswordFile != null) {
        admin_password = "$__file{${toString cfg.server.grafanaAdminPasswordFile}}";
      };

      # dashboards from the repo, read-only in the UI
      services.grafana.provision.dashboards.settings.providers = [
        {
          name = "siem-lite";
          options.path = ./siem-dashboards;
          options.foldersFromFilesStructure = false;
        }
      ];

      # grafana only applies admin_password on first db init, so re-apply it each
      # start to stop config/reality drifting. idempotent, never fails activation.
      systemd.services.grafana-enforce-admin-pw = lib.mkIf (cfg.server.grafanaAdminPasswordFile != null) {
        description = "Re-apply the Grafana admin password from sops";
        after = [ "grafana.service" ];
        wants = [ "grafana.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "grafana";
          Group = "grafana";
        };
        script = ''
          for i in 1 2 3 4 5; do
            if ${config.services.grafana.package}/bin/grafana cli \
                 -homepath ${config.services.grafana.package}/share/grafana \
                 -config ${grafanaCliConfig} \
                 admin reset-admin-password --password-from-stdin \
                 < ${cfg.server.grafanaAdminPasswordFile}; then
              exit 0
            fi
            sleep 3
          done
          echo "grafana-enforce-admin-pw: could not set admin password after retries" >&2
          exit 0
        '';
      };

      # open only the Loki push port, LAN-scoped. handle both fw backends.
      networking.firewall = lib.mkMerge [
        (lib.mkIf config.networking.nftables.enable {
          extraInputRules = ''
            ip saddr ${cfg.lanCidr} tcp dport ${toString lokiPort} accept
          '';
        })
        (lib.mkIf (!config.networking.nftables.enable) {
          extraCommands = ''
            iptables -A nixos-fw -p tcp -s ${cfg.lanCidr} --dport ${toString lokiPort} -j nixos-fw-accept
          '';
        })
      ];
    })
  ];
}
