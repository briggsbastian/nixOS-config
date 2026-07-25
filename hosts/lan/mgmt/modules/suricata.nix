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
{ options, ... }:

{
  services.suricata = {
    enable = true;

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

  alcove.siemLite.agent.extraConfig = ''
    loki.source.file "suricata" {
      targets    = [{ __path__ = "/var/log/suricata/eve.json", job = "suricata" }]
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
