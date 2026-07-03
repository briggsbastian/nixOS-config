# tests/log-path.nix
#
# log-path check: prove the siem-lite *agent* config actually flows -- a journal
# line on a host running the real Alloy agent lands in Loki. This is the half of
# the observability story that's invisible until something breaks: if the Alloy
# config (free-form text, so eval can't catch it) is wrong, hosts silently stop
# shipping logs and you only notice when you go looking for a log that isn't there.
#
# It imports the SAME modules/siem-lite.nix the real hosts use and enables the
# real agent role (alcove.siemLite.agent.enable, exactly what media / playground /
# hacktop set), only redirecting the push endpoint at an in-test Loki on the same
# node instead of mgmt. Single node, no network, no real hosts.
{ pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "log-path";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../modules/siem-lite.nix ];

      environment.systemPackages = [ pkgs.curl ];

      # The real agent role -- the same Alloy journal->Loki config the fleet runs.
      alcove.siemLite.agent.enable = true;
      # Ship to the in-test Loki on this node instead of mgmt.
      alcove.siemLite.lokiEndpoint = "http://127.0.0.1:3100/loki/api/v1/push";

      # A minimal single-binary Loki receiver. NOT the full server role (which
      # also pulls Grafana/Alertmanager/ntfy) -- we only need to prove the agent's
      # journal pipeline reaches a Loki and is queryable.
      services.loki = {
        enable = true;
        configuration = {
          auth_enabled = false;
          server = {
            http_listen_port = 3100;
            http_listen_address = "127.0.0.1";
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
        };
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("loki.service")
    machine.wait_for_unit("alloy.service")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:3100/ready", timeout=120)

    # Emit a unique line into the journal; the Alloy agent should ship it to Loki.
    machine.succeed("logger -t logcanary 'ALLOY_FLOW_CANARY_42'")

    # Query Loki until the canary shows up under the agent's job label (Alloy
    # tails the journal and pushes within seconds).
    machine.wait_until_succeeds(
        "curl -sG http://127.0.0.1:3100/loki/api/v1/query_range "
        "--data-urlencode 'query={job=\"systemd-journal\"} |= `ALLOY_FLOW_CANARY_42`' "
        "--data-urlencode \"start=$(date -d '-5 min' +%s)000000000\" "
        "--data-urlencode \"end=$(date +%s)000000000\" "
        "| grep -q ALLOY_FLOW_CANARY_42",
        timeout=120,
    )

    # The query above only needs `job`, which loki.source.journal sets directly.
    # Re-query requiring a non-empty `host` label too: that label only exists if
    # the loki.relabel.journal pipeline (__journal__hostname -> host) actually
    # ran, so this proves the agent's relabel config flows, not just the source.
    machine.succeed(
        "curl -sG http://127.0.0.1:3100/loki/api/v1/query_range "
        '--data-urlencode \'query={job="systemd-journal", host=~".+"} |= `ALLOY_FLOW_CANARY_42`\' '
        "--data-urlencode \"start=$(date -d '-5 min' +%s)000000000\" "
        "--data-urlencode \"end=$(date +%s)000000000\" "
        "| grep -q ALLOY_FLOW_CANARY_42"
    )
  '';
}
