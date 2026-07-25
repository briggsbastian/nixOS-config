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
_:

{
  services.suricata = {
    enable = true;
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
