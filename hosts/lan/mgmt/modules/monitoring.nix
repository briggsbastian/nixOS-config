# Metrics + uptime + landing page: Prometheus scrapes node_exporter,
# Grafana visualizes, Uptime Kuma probes the services, Homepage links it
# all together at https://mgmt.lan.
{
  config,
  lib,
  pkgs,
  ...
}:

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
  # world-readable: node-exporter (fixed system user, see node.nix) only needs
  # read access; writers (mgmt-backup.service, root) write+rename atomically.
  textfileDir = "/var/lib/node-exporter-textfile";
  # Forgejo lives on this host, so the authoritative main revision is readable
  # straight off disk. Forgejo lowercases repository directory names.
  fleetRepoGitDir = "/var/lib/forgejo/repositories/briggs/nixos-config.git";
  nasIp = "192.168.1.213";
  acmeVhosts = lib.attrNames (
    lib.filterAttrs (_: v: v.enableACME) config.services.nginx.virtualHosts
  );
  certProbeTargets = map (h: "https://${h}") acmeVhosts;

  # blackbox prober that just completes a TLS handshake so probe_ssl_* is
  # populated. insecure_skip_verify: we only read the cert's *expiry* here (to
  # catch a silently-failed step-ca/lego renewal before the 90-day cert lapses) -
  # chain trust is a separate concern, validated on the clients that import the
  # root (modules/internal-ca.nix). Skipping verify also means we still read the
  # expiry even after a renewal has already fallen back to the untrusted minica.
  blackboxConfig = (pkgs.formats.yaml { }).generate "blackbox.yml" {
    # Plain TCP connect - used for the public Minecraft path probe.
    modules.tcp_connect = {
      prober = "tcp";
      timeout = "5s";
    };
    modules.http_tls = {
      prober = "http";
      timeout = "5s";
      http = {
        method = "GET";
        fail_if_not_ssl = true;
        # Any status counts as alive: the probe exists to read the cert (and
        # prove the vhost answers over TLS), not to health-check the app.
        # step-ca serves 404 at /, which is fine - requiring 2xx made
        # ca.mgmt.lan a permanent TlsProbeDown false positive.
        valid_status_codes = [
          200
          301
          302
          303
          304
          307
          308
          400
          401
          403
          404
          405
        ];
        tls_config.insecure_skip_verify = true;
        preferred_ip_protocol = "ip4";
      };
    };
  };
in
{
  systemd.tmpfiles.rules = [ "d ${textfileDir} 0755 root root -" ];

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9100;
      enabledCollectors = [ "systemd" ];
      # textfile collector: one-off/job metrics that don't fit a normal
      # exporter (see the backup-freshness metric backup.nix writes here).
      extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
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
    # so this list never drifts from the Colmena host map. cloud1 is scraped over
    # its wg-mc tunnel address (h.scrapeIp), not its public deploy IP.
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
          targets = [ "${h.scrapeIp or h.ip}:9100" ];
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
        params.module = [ "http_tls" ];
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

      # The NAS (192.168.1.213): unmanaged, no SNMP/API, so this is a bare
      # reachability check - TCP connect to the NFS port. Proves both "NAS is
      # up" and "NFS is actually serving", which is what media + backups need.
      {
        job_name = "blackbox-nas";
        metrics_path = "/probe";
        params.module = [ "tcp_connect" ];
        static_configs = [ { targets = [ "${nasIp}:2049" ]; } ];
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

      # The public Minecraft front door, probed end to end: this TCP connect
      # traverses Linode's firewall, cloud1's DNAT, the WireGuard tunnel, and
      # the server on hacktop - if any link breaks, MinecraftPathDown fires.
      # Name+port match the _minecraft._tcp SRV record players use (Prometheus
      # doesn't resolve SRV, so the port is repeated here - keep in sync with
      # cloud1's proxy.nix).
      {
        job_name = "blackbox-minecraft";
        metrics_path = "/probe";
        params.module = [ "tcp_connect" ];
        static_configs = [ { targets = [ "play.briggsbastian.com:24799" ]; } ];
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
              # (tmpfs/overlay/...) filesystems are excluded: /mnt/media is an
              # autofs automount node_exporter can't see reliably anyway.
              #
              # An older version of this comment claimed "the NAS is monitored at
              # the NAS". It is not, and never was - the NAS is unmanaged (see
              # blackbox-nas above: no SNMP, no API, no node_exporter), so this
              # exclusion left its capacity watched by nobody. On 2026-08-20 the
              # share was found by hand at 94% full with ~20 days of life left,
              # most of it the ATMons world archives. NasBackupStore* below is
              # the replacement: hacktop's backup job df's the share it writes
              # to, which is the one process guaranteed to be looking.
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

              # CertExpiringSoon is guarded by `> 0`, so a vhost that can't be
              # reached at all (no probe_ssl_* series) is silent. This covers that:
              # a failed TLS handshake means a down vhost or a cert nginx couldn't
              # load. 15m absorbs an nginx reload during a deploy.
              - alert: TlsProbeDown
                expr: probe_success{job="blackbox-tls"} == 0
                for: 15m
                labels:
                  severity: warning
                annotations:
                  summary: "TLS probe failing for {{ $labels.instance }}"
                  description: "Blackbox could not complete a TLS handshake with {{ $labels.instance }} for 15m (endpoint down, or nginx could not load its cert)."

              # The public Minecraft path (Linode firewall -> cloud1 DNAT ->
              # WireGuard -> hacktop). 10m absorbs a modpack restart (the
              # NeoForge boot takes minutes and the port is closed meanwhile).
              - alert: MinecraftPathDown
                expr: probe_success{job="blackbox-minecraft"} == 0
                for: 10m
                labels:
                  severity: warning
                annotations:
                  summary: "Public Minecraft path down ({{ $labels.instance }})"
                  description: "TCP connect to {{ $labels.instance }} has failed for 10m - a link in Linode FW -> cloud1 DNAT -> tunnel -> hacktop server is broken."

              # NAS is unmanaged (no SNMP/API) - all we get is "is NFS answering".
              - alert: NasDown
                expr: probe_success{job="blackbox-nas"} == 0
                for: 10m
                labels:
                  severity: critical
                annotations:
                  summary: "NAS unreachable ({{ $labels.instance }})"
                  description: "NFS on the NAS has not answered for 10m - media library and the only backup copy of PKI/secrets/IPAM both live there."

          - name: backups
            rules:
              # mgmt-backup.service writes this timestamp on every successful
              # run (backup.nix); daily at 03:30, so 26h gives >1h grace before
              # paging. Absent metric (never run, or textfile dir wiped) counts
              # as stale via the `or` clause instead of going silent.
              # A host running something other than main. Covers both "behind"
              # (an older sha) and "built from a dirty tree" (<sha>-dirty, which
              # can never match) - the second is arguably the more important of
              # the two, and is exactly what went unnoticed for six days.
              # 6h of grace so a deploy window doesn't page.
              - alert: HostConfigDrift
                expr: |
                  nixos_configuration_revision_info unless on (revision) fleet_expected_revision_info
                for: 6h
                labels:
                  severity: warning
                annotations:
                  summary: "{{ $labels.instance }} is not running main"
                  description: "{{ $labels.instance }} was built from revision {{ $labels.revision }}, which is not the current main. Either it is behind, or it was deployed from an uncommitted tree."

              # Activated but not rebooted: the running kernel and initrd are
              # from the previous configuration, so any kernel fix in the new
              # one is not actually in effect.
              - alert: HostRebootPending
                expr: nixos_reboot_pending == 1
                for: 24h
                labels:
                  severity: warning
                annotations:
                  summary: "{{ $labels.instance }} has a configuration activated but not booted"
                  description: "{{ $labels.instance }} is running a kernel or initrd from an older configuration - any kernel-level fix in the activated system is not actually in effect until it reboots."

              - alert: BackupStale
                expr: |
                  (time() - mgmt_backup_last_success_timestamp_seconds > 26 * 3600)
                  or absent(mgmt_backup_last_success_timestamp_seconds)
                for: 0m
                labels:
                  severity: critical
                annotations:
                  summary: "mgmt's encrypted off-box backup is stale or has never run"
                  description: "No successful mgmt-backup.service run recorded in the last 26h - step-ca, service secrets, and the NetBox DB dump are the only copies of that state."

              # hacktop's minecraft-backup.service writes this on every
              # successful run (hosts/lan/hacktop/minecraft-backup.nix); daily
              # at 04:00 local plus up to 10m jitter, so 26h gives >1h grace.
              # Same `or absent(...)` clause as BackupStale above and for the
              # same reason: a metric that has never existed must be loud.
              #
              # critical, not warning: the ATMons world is the only state on
              # hacktop a rebuild cannot regenerate, and the server is
              # deliberately open to the internet - this backup IS the griefing
              # recovery story that minecraft.nix's white-list=false leans on.
              - alert: MinecraftBackupStale
                expr: |
                  (time() - minecraft_backup_last_success_timestamp_seconds > 26 * 3600)
                  or absent(minecraft_backup_last_success_timestamp_seconds)
                for: 0m
                labels:
                  severity: critical
                annotations:
                  summary: "The ATMons world backup is stale or has never run"
                  description: "No successful minecraft-backup.service run on hacktop in the last 26h. The world is players' work and the only unregenerable state on that box."

              # The backup quiesces the world (save-off, save-all flush, wait
              # for the server's own "Saved the game") before tarring. When the
              # console does not answer - server down, or that string moved
              # under a pack update - it takes a crash-consistent tar anyway
              # and reports it here rather than failing. That is the right
              # trade, but it must not be silent: several nights at 0 means the
              # quiesce logic has quietly died and every archive since is a
              # mid-save snapshot.
              - alert: MinecraftBackupNotQuiesced
                expr: minecraft_backup_quiesced == 0
                for: 0m
                labels:
                  severity: warning
                annotations:
                  summary: "ATMons backup ran without quiescing the world"
                  description: "minecraft-backup.service could not confirm `save-all flush` completed, or the server restarted mid-tar. The archive is usable but may catch a partial save - check the unit's journal for which."

              # A world does not lose half its size overnight. This catches the
              # failure the .partial rename cannot: a tar that SUCCEEDS while
              # archiving almost nothing - a renamed world dir, a dataDir a
              # failed deploy emptied, a bind mount that went away.
              # max_over_time rather than `offset 7d` so one bad night cannot
              # become the new baseline and quietly un-fire the alert.
              - alert: MinecraftBackupShrank
                expr: |
                  minecraft_backup_size_bytes
                    < 0.5 * max_over_time(minecraft_backup_size_bytes[14d])
                for: 1h
                labels:
                  severity: warning
                annotations:
                  summary: "The ATMons backup is under half its recent size"
                  description: "Last archive was {{ $value | humanize1024 }}B against its 14d peak - the tar may be picking up an empty or wrong directory."

              # Monthly, hacktop decrypts the newest archive with its own SSH
              # host key and walks every tar header. Nothing else proves the
              # ciphertext on the NAS is intact end to end, and it is only
              # possible because the archive carries a second recipient. 40d =
              # the monthly cadence plus one missed run.
              - alert: MinecraftBackupUnverified
                expr: |
                  (time() - minecraft_backup_verify_last_success_timestamp_seconds > 40 * 24 * 3600)
                  or absent(minecraft_backup_verify_last_success_timestamp_seconds)
                for: 0m
                labels:
                  severity: warning
                annotations:
                  summary: "The ATMons backup has not been restore-verified in over 40 days"
                  description: "minecraft-backup-verify.service last succeeded more than 40d ago, or never. A green timer is not a backup."

              # The NAS share, watched from the only host that both writes to it
              # and runs node_exporter. See the NodeDiskFull comment above for
              # why nothing else does. Absolute floor, not a percentage: what
              # matters is whether one more 12.9 GB world archive fits, and on
              # an 853 GB share a percentage threshold answers that far too
              # late. 60 GiB is a bit over four archives' worth.
              - alert: NasBackupStoreLow
                expr: minecraft_backup_store_free_bytes < 60 * 1024 * 1024 * 1024
                for: 0m
                labels:
                  severity: warning
                annotations:
                  summary: "The NAS share holding the world backups is nearly full"
                  description: "{{ $value | humanize1024 }}B free on 192.168.1.213:/srv/media. Under ~13 GB the nightly ATMons archive stops fitting and the backup starts failing - which is also when the media library stops accepting writes."

              # The alert that would actually have caught this one early: the
              # share does not fall off a cliff, it fills at a steady few GB a
              # day and nobody looks. predict_linear over a fortnight is long
              # enough that one big media import does not trip it and short
              # enough to see a retention change land.
              #
              # Deliberately paired with, not replaced by, the floor above: a
              # sudden 200 GB import breaks the trend line and only the floor
              # catches it, while a slow fill trips this weeks before the floor.
              - alert: NasBackupStoreFillingUp
                expr: |
                  predict_linear(minecraft_backup_store_free_bytes[14d], 30 * 24 * 3600) < 0
                for: 6h
                labels:
                  severity: warning
                annotations:
                  summary: "The NAS share will be full within 30 days at the current rate"
                  description: "192.168.1.213:/srv/media is trending to zero free within 30d ({{ $value | humanize1024 }}B projected). Check retention in hosts/lan/hacktop/minecraft-backup.nix and the media library's growth before it becomes urgent."

          - name: minecraft-proxy
            rules:
              # cloud1's per-source-IP throttle (hosts/cloud/cloud1/proxy.nix)
              # only drops when a single address opens more than 10 new
              # connections a minute. A human reconnecting does not do that; a
              # join-flood bot or a scanner does. Sustained for 10m means
              # something is hammering the public path.
              #
              # Counter, not a log line, on purpose: a drop storm is exactly
              # when per-packet logging would turn an attack on the game into
              # an attack on the journal. The source addresses are still
              # recorded - proxy.nix logs the ATTEMPTS, rate-limited.
              - alert: MinecraftConnectionFlood
                expr: rate(minecraft_proxy_ratelimit_dropped_packets_total[5m]) > 0
                for: 10m
                labels:
                  severity: warning
                annotations:
                  summary: "Sustained connection flooding against the public Minecraft path"
                  description: "cloud1's rate limiter has been dropping new connections for 10m. Query {host=\"cloud1\"} |= \"mc-conn \" in Loki for the source addresses."

          # hacktop is a laptop doing a server's job, so mains power is a
          # dependency of the game server the same way the disk is. On
          # 2026-08-04 it lost power at 11:09:48 and was gone for 16 minutes:
          # the journal stops mid-line with no shutdown sequence, no kernel
          # message, no OOM. The battery was at 3%, so there was no ride-through
          # at all - the box died the instant the mains blinked, and the world
          # took an unclean shutdown (no chunk damage that time; not a promise).
          #
          # Nothing alerted. NodeDown fired only after the fact, saying "host
          # unreachable" - true but useless, because by then it had already
          # happened. These three say it *before*, or at least say *why*.
          #
          # No instance selector on purpose: node_exporter only emits
          # power_supply metrics where /sys/class/power_supply is populated, so
          # today these series exist for hacktop alone and the rules scope
          # themselves. Another laptop joining the fleet is covered for free.
          - name: power
            rules:
              # Running on battery: a countdown, not a state. Alert fast.
              #
              # `max by (instance)` rather than a match on power_supply="AC" is
              # load-bearing. hacktop has two inputs - the barrel "AC" and a
              # USB-C PD source - and only one is online at a time. Pinning the
              # rule to AC would fire every time the machine was legitimately
              # powered over USB-C. Only when EVERY input reads 0 is it actually
              # on battery.
              - alert: HostOnBatteryPower
                expr: max by (instance) (node_power_supply_online) == 0
                for: 1m
                labels:
                  severity: critical
                annotations:
                  summary: "{{ $labels.instance }} is running on battery"
                  description: "No mains or USB-C input is online. This box holds ~60% of its design battery capacity, so assume minutes, not hours. Shut the game server down cleanly before the battery does it for you: sudo mc-console send 'save-all flush' then 'stop'."

              # The state that actually caused the outage: a battery sitting
              # low while ON mains, so there is no reserve when power blinks.
              # Invisible without this rule - everything looks healthy right up
              # until the moment it isn't.
              #
              # `for: 2h` because a genuine recharge from near-empty on this
              # machine takes 1-2h, and alerting during that recovery would
              # mean paging about the outage that just ended. Still firing
              # after 2h means it is not charging, which is the real fault.
              - alert: HostBatteryLow
                expr: node_power_supply_capacity{power_supply=~"BAT.*"} < 30
                for: 2h
                labels:
                  severity: warning
                annotations:
                  summary: "{{ $labels.instance }} battery at {{ $value }}% and not recovering"
                  description: "Below 30% for 2h, so it is not merely recharging after an outage. Until this comes up there is no ride-through: the next mains blip is a hard power cut and an unclean world shutdown. Check the charger and that the barrel/USB-C input is actually seated."

              # Wear, which the capacity alert structurally cannot see: capacity
              # is a percentage of what the battery holds NOW, not of design.
              # A worn cell reads a confident 100% and still dies in a fraction
              # of the original time. Measured 60.2% on 2026-08-04; the
              # threshold sits below that so this reports real further decay
              # rather than firing on day one and being muted.
              - alert: HostBatteryWorn
                expr: |
                  node_power_supply_charge_full{power_supply=~"BAT.*"}
                    / node_power_supply_charge_full_design < 0.5
                for: 6h
                labels:
                  severity: warning
                annotations:
                  summary: "{{ $labels.instance }} battery has degraded to {{ $value | humanizePercentage }} of design"
                  description: "The reserve behind HostOnBatteryPower is now less than half of what the hardware shipped with. A full charge no longer buys the time you would assume. Replace the cell, or accept that mains loss means immediate loss of the game server."
      ''
    ];
  };

  # LogQL alerts for the Minecraft path, as a SECOND file in the same tenant
  # directory rather than an edit to modules/siem-lite.nix. Three reasons:
  # siem-lite sets alerts.yaml with `.text`, so it cannot be appended to from
  # here; the ruler reads every file in the directory, so a second one just
  # works; and a game-server rule does not belong in a fleet-wide security
  # module that every host imports.
  environment.etc."loki/rules/fake/minecraft.yaml".text = ''
    groups:
      - name: minecraft
        rules:
          # Sustained tick starvation. This is both an ordinary health signal
          # and the visible symptom of resource exhaustion, which is the shape
          # an attack on a modded server actually takes - nobody bothers with
          # packet floods when a hopper array will do.
          #
          # Threshold from measurement, not taste: the live server produced ~8
          # of these in 4h of uptime, clustered around startup and player
          # joins, worst case 8.7s behind. >10 inside 15m is a stall storm.
          - alert: MinecraftTickLag
            expr: |
              sum(count_over_time({unit="minecraft-server-atmons.service"} |= `Can't keep up` [15m])) > 10
            for: 0m
            labels: { severity: warning }
            annotations:
              summary: "ATMons server is repeatedly failing to keep up"
              description: "{{ $value }} tick-lag warnings in 15m. Run `spark tps` and `spark profiler start` on the console to find the cause."

          # Matches the vanilla crash line specifically. Deliberately NOT a
          # generic ERROR match: this pack logs a wall of mekmm loot-table
          # errors at every single boot, so an ERROR-based rule would fire on
          # every restart and be muted within a week.
          - alert: MinecraftServerCrash
            expr: |
              sum(count_over_time({unit="minecraft-server-atmons.service"} |= `Encountered an unexpected exception` [10m])) > 0
            for: 0m
            labels: { severity: critical }
            annotations:
              summary: "ATMons server hit an unhandled exception"
              description: "The server logged a crash. journalctl -u minecraft-server-atmons on hacktop has the trace - it survives the process now that the console goes to the journal."
  '';

  # Grafana's DB encryption key. Grafana 13 (nixos-26.05) dropped the module's
  # implicit default, and this was briefly pinned to upstream's old fallback
  # ("SW2YcwTIb9zpOOhoPsMm") to keep existing encrypted DB values readable across
  # the upgrade. Two things retired that compromise:
  #
  #   - the pinned value is public knowledge - it is printed verbatim in nixpkgs'
  #     own assertion message - so anything in the DB was encrypted with a key
  #     anyone can look up, and gitleaks was right to fail CI over it
  #   - grafana.service had been dead since 2026-07-17 anyway, so there were no
  #     encrypted values left to preserve and the compatibility argument was moot
  #
  # A real key now comes from sops. Rotating it makes any pre-existing encrypted
  # DB values unreadable, which is why /var/lib/grafana/grafana.db has to be reset
  # once by hand alongside this change - see MAINTENANCE.md.
  # Name must match the key in secrets/mgmt.yaml exactly - sops-nix looks it up
  # by attribute name, and a mismatch fails activation with the secret simply
  # never appearing under /run/secrets.
  sops.secrets.grafana_key = {
    sopsFile = ../../../../secrets/mgmt.yaml;
    owner = "grafana";
  };

  services.grafana = {
    enable = true;
    settings.security.secret_key = "$__file{${config.sops.secrets.grafana_key.path}}";
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
        uid = "prometheus"; # referenced by dashboards/fleet-overview.json
        url = "http://127.0.0.1:9090";
        isDefault = true;
      }
    ];

    # Fleet Overview: node/backup/cert health at a glance, one panel per
    # existing alert rule above plus the trends behind them. siem-lite.nix
    # provisions its own (Loki) dashboards under a separate "siem-lite"
    # provider; this one is Prometheus-only and mgmt-specific.
    provision.dashboards.settings.providers = [
      {
        name = "metrics";
        options.path = ./metrics-dashboards;
        options.foldersFromFilesStructure = false;
      }
    ];
  };

  # The upstream module gives grafana.service WorkingDirectory=/var/lib/grafana
  # but no StateDirectory, so nothing recreates that directory if it is ever
  # absent - the unit just dies at step CHDIR with status=200. That makes the
  # documented "reset Grafana's state" procedure a footgun, and would also bite
  # a restore onto a clean box. StateDirectory makes systemd create it with the
  # right owner and mode before ExecStartPre runs.
  systemd.services.grafana.serviceConfig = {
    StateDirectory = "grafana";
    StateDirectoryMode = "0700";
  };

  # --- Expected fleet revision -------------------------------------------
  # What every host *should* be running, read straight off Forgejo's bare repo
  # on this same box - no network, no token, no key. Paired with
  # nixos_configuration_revision_info from modules/config-revision.nix, the
  # HostConfigDrift alert below is the whole always-on drift detector.
  systemd.services.fleet-expected-revision = {
    description = "Publish the fleet's expected config revision as a Prometheus metric";
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.git
      pkgs.coreutils
    ];
    script = ''
      set -euo pipefail
      rev=$(git --git-dir=${fleetRepoGitDir} rev-parse refs/heads/main)
      tmp=$(mktemp "${textfileDir}/.fleet_expected_revision.XXXXXX")
      {
        echo '# HELP fleet_expected_revision_info Revision of main in the config repo - what every host should be running.'
        echo '# TYPE fleet_expected_revision_info gauge'
        echo "fleet_expected_revision_info{revision=\"$rev\"} 1"
      } > "$tmp"
      chmod 0644 "$tmp"
      mv "$tmp" "${textfileDir}/fleet_expected_revision.prom"
    '';
  };

  systemd.timers.fleet-expected-revision = {
    description = "Refresh the fleet's expected config revision";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m"; # main moves when a PR merges, not often
      Persistent = true;
    };
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
        Security = {
          style = "row";
          columns = 2;
        };
        Observability = {
          style = "row";
          columns = 3;
        };
        Infrastructure = {
          style = "row";
          columns = 3;
        };
        Media = {
          style = "row";
          columns = 3;
        };
        Lab = {
          style = "row";
          columns = 2;
        };
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
          format = {
            dateStyle = "long";
            timeStyle = "short";
            hour12 = true;
          };
        };
      }
    ];
    services = [
      {
        "Security" = [
          {
            "AdGuard Home" = {
              href = "https://adguard.mgmt.lan";
              description = "DNS filtering for the LAN";
            };
          }
        ];
      }
      {
        "Observability" = [
          {
            "Grafana" = {
              href = "https://grafana.mgmt.lan";
              description = "Metrics + log dashboards (Prometheus + Loki)";
            };
          }
          {
            "Logs (Explore)" = {
              href = "https://grafana.mgmt.lan/explore";
              description = "Search the fleet's journals in Loki";
            };
          }
          {
            "Alertmanager" = {
              href = "https://alerts.mgmt.lan";
              description = "Fired alerts - view, silence, routing";
            };
          }
          {
            "ntfy" = {
              href = "https://ntfy.mgmt.lan";
              description = "Push alerts - subscribe to /homelab-alerts";
            };
          }
          {
            "Uptime Kuma" = {
              href = "https://status.mgmt.lan";
              description = "Service uptime monitoring";
            };
          }
          {
            "ntopng" = {
              href = "https://ntop.mgmt.lan";
              description = "Network traffic analysis";
            };
          }
        ];
      }
      {
        "Infrastructure" = [
          {
            "NetBox" = {
              href = "https://netbox.mgmt.lan";
              description = "IPAM & network documentation";
            };
          }
          {
            "Forgejo" = {
              href = "https://git.mgmt.lan";
              description = "Git hosting";
            };
          }
          {
            "Snipe-IT" = {
              href = "https://assets.mgmt.lan";
              description = "Asset inventory";
            };
          }
          {
            "Root CA cert" = {
              href = "https://ca.mgmt.lan/root.crt";
              description = "Install on devices to trust *.mgmt.lan";
            };
          }
          {
            "Nix cache pubkey" = {
              href = "https://cache.mgmt.lan/pubkey";
              description = "Binary cache at https://cache.mgmt.lan";
            };
          }
        ];
      }
      {
        # Direct IP:port - these run on the media/lab hosts, not behind mgmt's nginx.
        "Media" = [
          {
            "Jellyfin" = {
              href = "http://192.168.1.189:8096";
              description = "Media streaming";
            };
          }
          {
            "Radarr" = {
              href = "http://192.168.1.189:7878";
              description = "Movies";
            };
          }
          {
            "Sonarr" = {
              href = "http://192.168.1.189:8989";
              description = "TV shows";
            };
          }
          {
            "Prowlarr" = {
              href = "http://192.168.1.189:9696";
              description = "Indexer manager";
            };
          }
          {
            "Bazarr" = {
              href = "http://192.168.1.189:6767";
              description = "Subtitles";
            };
          }
          {
            "NZBGet" = {
              href = "http://192.168.1.189:6789";
              description = "Usenet downloader";
            };
          }
          {
            "Kavita" = {
              href = "http://192.168.1.189:5000";
              description = "Books, comics & manga";
            };
          }
          # unlike the rest of this group, runs on mgmt itself (newspaper.nix)
          {
            "Newspaper" = {
              href = "https://news.mgmt.lan";
              description = "Morning e-ink RSS edition";
            };
          }
        ];
      }
      {
        "Lab" = [
          # Direct IP on purpose: the Incus UI authenticates with TLS client
          # certs, which nginx can't proxy (see hosts/lan/playground/incus.nix).
          {
            "Incus" = {
              href = "https://192.168.1.217:8443";
              description = "playground VM/container lab - UI + console (client-cert auth)";
            };
          }
        ];
      }
      {
        "Games" = [
          # Not a web service - tile documents the connect address (hacktop).
          {
            "All the Mons" = {
              href = "https://www.curseforge.com/minecraft/modpacks/all-the-mons";
              description = "ATMons modpack server - connect to 192.168.1.26:25565";
            };
          }
        ];
      }
    ];
  };
}
