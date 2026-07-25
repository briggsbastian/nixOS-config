# hosts/lan/mgmt/modules/suricata.nix
#
# IDS on mgmt's LAN interface, alongside the existing ntopng flow monitor
# (ntopng.nix, same eno1). Suricata only sees traffic that actually crosses
# eno1 - to/from mgmt itself plus LAN broadcast/multicast - not the whole LAN;
# full network-wide visibility needs a switch SPAN/mirror port, out of scope
# here (that's networking hardware work, see the VLAN segmentation task).
# Emerging Threats Open ruleset (services.suricata.enabledSources default).
#
# Alerts (eve.json, event_type=alert) get tailed into the existing Loki by
# alcove.siemLite.agent.extraConfig, then a LogQL rule below routes them
# through the same Alertmanager -> ntfy pipeline as SSHBruteForce/SudoFailure.
{
  config,
  options,
  pkgs,
  ...
}:

let
  # Named once: the tail target, the tmpfiles guarantee and alloy's restart
  # trigger must all refer to the same path or the guarantee is worthless.
  eveLog = "/var/log/suricata/eve.json";
in
{
  # Changing the ruleset does not change the running engine.
  #
  # suricata.service has no ExecReload, and switch-to-configuration only
  # restarts a unit whose own definition changed. Editing enabledSources or
  # disabledRules changes neither - it changes what suricata-update writes to
  # /var/lib/suricata/rules/suricata.rules. So the deploy regenerates the rules
  # on disk, systemd leaves the running engine alone, and it keeps matching on
  # the ruleset it loaded at boot.
  #
  # Measured on the deploy that trimmed the sources: rules regenerated at
  # 13:45:29 with sid 2200121 correctly commented out, and the engine was still
  # emitting 2200121 alerts at 13:46:34 from the copy in memory. Every check
  # said the change had landed. Nothing had changed.
  #
  # restartTriggers ties the unit to the values that decide its ruleset, so a
  # ruleset change restarts the engine as part of the deploy - ordering already
  # holds, since suricata is After=suricata-update.
  systemd.services.suricata.restartTriggers = [
    (builtins.toJSON config.services.suricata.enabledSources)
    (builtins.toJSON config.services.suricata.disabledRules)
  ];

  # `enabledSources` is not authoritative on its own, and silently so.
  #
  # suricata-update keeps its enabled sources as one yaml per source under
  # /var/lib/suricata/update/sources/. The module's script only ever runs
  # `enable-source` for each configured source - it never disables the rest.
  # So removing an entry from enabledSources removes nothing: the stale file
  # stays, `suricata-update update` keeps pulling it, and the declared config
  # and the running ruleset diverge with nothing to show for it.
  #
  # Verified on this box: after trimming ten sources to five, all ten yaml
  # files were still present and would still have been fetched.
  #
  # Clearing them before the enable-source calls makes the Nix config the only
  # input. Files rather than the directory, so index.yaml beside it survives.
  #
  # Wrapped in sh because systemd does NOT glob in ExecStartPre - a bare
  # `rm -f .../*.yaml` passes the asterisk through literally, matches nothing,
  # and exits 0 under -f. A silent no-op inside the fix for a silent no-op.
  systemd.services.suricata-update.serviceConfig.ExecStartPre = [
    "${pkgs.bash}/bin/sh -c '${pkgs.coreutils}/bin/rm -f /var/lib/suricata/update/sources/*.yaml'"
  ];

  services.suricata = {
    enable = true;

    # The module default enables TEN sources. That was never a deliberate
    # choice here - the header comment above said "Emerging Threats Open
    # ruleset (enabledSources default)", which was only ever a third true.
    #
    # Trimmed to five on the principle that an alert reaching a phone must be
    # something a person would act on. Rulesets built to generate *leads for an
    # analyst to triage* are a different tool, and routing them into the same
    # ntfy pipeline as NodeDown is how a notification channel becomes noise.
    #
    # Kept:
    #   et/open              the baseline. Broad, curated, actively maintained.
    #   abuse.ch/sslbl-*     small, high-signal C2/JA3 certificate intel. Almost
    #                        never fires; when it does, it means something.
    #   stamus/lateral       lateral movement. The most relevant source on this
    #                        estate, given playground runs Kali and a live HTB
    #                        VPN on the same flat segment as everything else.
    #
    # Dropped:
    #   pawpatrules          rates the gateway doing mDNS as severity 1, with
    #                        emoji, category "Potential Corporate Privacy
    #                        Violation". Only 6 of 680 observed alerts, but it
    #                        was the ONLY source producing severity 1 - so it
    #                        actively corrupts severity-based triage. Measured:
    #                        every high-severity alert on this network was
    #                        pawpatrules calling multicast DNS an incident.
    #   tgreen/hunting       hunting rules are designed to surface leads, not to
    #                        page. Wrong end of the funnel for this pipeline.
    #   etnetera/aggressive  aggressive IP blocklist; high false-positive rate
    #                        by name and design, and overlaps abuse.ch.
    #   oisf/trafficid       identifies applications and TLS fingerprints. Alerts
    #                        on normal traffic by design - informational.
    #   ptrules/open         decent quality, but adds volume on top of et/open
    #                        without covering anything this estate needs.
    #
    # This trim removes ~1% of observed alert volume. It is about signal
    # quality, not volume - the volume problem is sid 2200121, handled below.
    enabledSources = [
      "et/open"
      "abuse.ch/sslbl-blacklist"
      "abuse.ch/sslbl-c2"
      "abuse.ch/sslbl-ja3"
      "stamus/lateral"
    ];

    # Ten ICS signatures kept the whole IDS down from 2026-07-17 to 2026-07-25.
    #
    # ExecStartPre runs `suricata -T`, and -T treats a rule that fails to parse
    # as fatal. These reference the modbus and dnp3 app-layer protocols, whose
    # parsers are disabled by default and are not enabled here (nothing on this
    # network speaks either - there is no ICS/SCADA equipment). So the rules
    # cannot parse, -T exits non-zero, and the service never leaves start-pre.
    # 10 unusable rules out of 85,186 blocked all of them.
    #
    # The module's own default already disables 2270000-2270004 for exactly this
    # reason. That list simply has not kept up with the ruleset - upstream added
    # dnp3 2270005/2270006 and the modbus 225000x family since. Extending the
    # list rather than enabling the parsers: turning on ICS protocol decoders on
    # a network with no ICS devices would add parser attack surface to make ten
    # signatures loadable that could only ever produce false positives here.
    #
    # Enumerated rather than pattern-matched, matching the module's own form. If
    # a future ruleset adds another ICS rule this breaks again - but no longer
    # silently: SystemdUnitCrashLooping (siem-lite.nix) now catches a unit stuck
    # in restart, which is precisely how this went unnoticed for eight days.
    #
    # `++ default` is load-bearing. This is types.listOf, so a plain assignment
    # REPLACES the module's default rather than merging with it - which would
    # silently drop 2270000-2270004 and leave the engine just as dead, for a
    # different five rules. Verified by evaluating the result, not by reading
    # the source.
    disabledRules = options.services.suricata.disabledRules.default ++ [
      # 2200121 "SURICATA Ethertype unknown" - 86% of all alerts on this box.
      #
      # A decoder diagnostic, not a threat signature: classtype
      # protocol-command-decode, triggered by decode-event
      # ethernet.unknown_ethertype. It reports that suricata saw an ethernet
      # frame whose ethertype it does not parse. On a LAN full of UniFi
      # discovery and link-layer chatter that is constant, expected, and not
      # something anyone will ever act on.
      #
      # It ships with a rate limit of its own - `threshold: type limit, track
      # by_rule, seconds 60, count 1` - which is NOT being honoured. Measured
      # over the first 1228 seconds after the engine came up: 656 alerts, 32
      # per minute against a rule that says at most one. Decode-phase events
      # appear to bypass the detect engine's thresholding. That is the reason
      # this one rule buries everything else.
      #
      # Only this sid is disabled, not the other 21 decoder-event rules - they
      # are quiet here and some (invalid IP headers, oversized packets) would
      # be worth seeing.
      "2200121"

      # dnp3 - beyond the module's default 2270000-2270004
      "2270005" # DNP3 Too many points in message
      "2270006" # DNP3 Too many objects
      # modbus (2250004 is not present in the current ruleset)
      "2250001" # Modbus invalid Protocol version
      "2250002" # Modbus unsolicited response
      "2250003" # Modbus invalid Length
      "2250005" # Modbus invalid Function code
      "2250006" # Modbus invalid Value
      "2250007" # Modbus Exception code invalid
      "2250008" # Modbus Data mismatch
      "2250009" # Modbus Request flood detected
    ];

    settings = {
      vars.address-groups.HOME_NET = "192.168.1.0/24";
      af-packet = [ { interface = "eno1"; } ];
      outputs = [
        {
          eve-log = {
            enabled = true;
            filetype = "regular";
            filename = "eve.json";
            types = [ { alert = { }; } ];
          };
        }
      ];
    };
  };

  # eve.json is suricata:suricata-owned; Alloy (siem-lite.nix) needs group
  # read access to tail it. Lists merge, so this adds to the existing
  # systemd-journal supplementary group rather than replacing it.
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "suricata" ];

  # Alloy's loki.source.file gives up permanently if its target is missing at
  # startup. It does not retry, and it does not fail the service - one
  # component dies and everything else carries on looking healthy.
  #
  # What that produced here, in order:
  #
  #   2026-07-17 23:04  suricata dies on the ICS rules, stops writing eve.json
  #   2026-07-18 06:04  alloy restarts, cannot stat the file, logs
  #                     "failed to create source, skipping" and never looks again
  #   2026-07-25 13:54  suricata fixed and writing again - alloy still not tailing
  #
  # So `{job="suricata"}` has never existed in Loki, and SuricataAlert - which
  # queries exactly that - has never been capable of firing. Not "did not
  # fire": could not. The IDS pipeline was broken end to end in two independent
  # places, and fixing the engine alone would have left alerts going nowhere
  # while every dashboard showed green.
  #
  # tmpfiles guarantees the file exists regardless of suricata's state, so the
  # tail always starts and simply waits for content. This removes the ordering
  # dependency rather than papering over it with After=.
  systemd.tmpfiles.rules = [
    "f ${eveLog} 0644 suricata suricata -"
  ];

  # Alloy needs one restart to pick up the file it gave up on. Its own config
  # is unchanged, so nothing would otherwise restart it - the same trap as
  # suricata and its ruleset. Naming the tail target as the trigger means any
  # future change to that path also forces the restart it implies.
  systemd.services.alloy.restartTriggers = [ "tail-target:${eveLog}" ];

  alcove.siemLite.agent.extraConfig = ''
    loki.source.file "suricata" {
      targets    = [{ __path__ = "${eveLog}", job = "suricata" }]
      forward_to = [loki.write.default.receiver]
    }
  '';

  environment.etc."loki/rules/fake/suricata-alerts.yaml".text = ''
    groups:
      - name: suricata
        rules:
          - alert: SuricataAlert
            expr: |
              sum by (host) (count_over_time({job="suricata"} | json | event_type="alert" [5m])) > 0
            for: 0m
            labels: { severity: warning }
            annotations:
              summary: "Suricata IDS alert on {{ $labels.host }}"
              description: "{{ $value }} Suricata alert(s) in the last 5m on {{ $labels.host }}"
  '';
}
