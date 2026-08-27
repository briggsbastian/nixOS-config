# hosts/cloud/cloud1/proxy-metrics.nix
#
# Exports the Minecraft proxy's rate-limit counter (proxy.nix) as a Prometheus
# metric, via node_exporter's textfile collector.
#
# Why a metric and not a log line: the throttle drops packets exactly when
# someone is flooding, which is precisely when writing a line per packet is the
# wrong thing to do - it converts an attack on the game into an attack on the
# journal and on Loki's ingest path. A counter carries the same signal at fixed
# cost, and Prometheus can alert on its rate.
#
# The connection ATTEMPTS themselves are logged (rate-limited) by proxy.nix, so
# an investigation still has source addresses to work from; this is the "is it
# happening, and how hard" half.
#
# mgmt scrapes cloud1's node_exporter over the wg-mc tunnel (fleet-hosts.nix -
# cloud1 sets scrapeIp; :9100 stays shut on the public interface).
{
  config,
  pkgs,
  ...
}:

let
  textfileDir = config.alcove.configRevision.textfileDir;
in
{
  systemd.services.minecraft-proxy-metrics = {
    description = "Export the Minecraft proxy rate-limit counter for node_exporter";
    after = [ "nftables.service" ];
    path = [
      pkgs.nftables
      pkgs.jq
      pkgs.coreutils
      pkgs.gnugrep
    ];
    serviceConfig.Type = "oneshot"; # root: nft needs netlink
    script = ''
      set -euo pipefail

      # The chain holds one counter, on the drop rule. Sum defensively rather
      # than indexing a fixed position, so adding another counted rule later
      # cannot silently start reporting the wrong one.
      #
      # `// empty` then `// 0` matters: a chain that exists but has never
      # matched yields no counter object at all, and jq would emit null. A
      # null here would be written to the .prom file verbatim and poison the
      # whole scrape - node_exporter rejects the entire file on one bad line.
      packets=$(nft -j list chain ip minecraft-proxy forward-limit \
        | jq '[.nftables[]?.rule?.expr[]?.counter?.packets // empty] | add // 0')

      # Deliberately a grep and not a shell `case` glob: the empty-string
      # pattern in a case arm is a doubled single-quote, which terminates a Nix
      # indented string and makes this file fail to evaluate.
      if ! printf '%s' "$packets" | grep -qE '^[0-9]+$'; then
        echo "counter parse produced a non-numeric value: $packets" >&2
        exit 1
      fi

      install -d -m 0755 "${textfileDir}"
      metric=$(mktemp "${textfileDir}/.minecraft_proxy.XXXXXX")
      {
        echo "# HELP minecraft_proxy_ratelimit_dropped_packets_total New connections into the tunnel dropped by the per-source-IP throttle."
        echo "# TYPE minecraft_proxy_ratelimit_dropped_packets_total counter"
        echo "minecraft_proxy_ratelimit_dropped_packets_total $packets"
      } > "$metric"
      chmod 0644 "$metric"
      mv "$metric" "${textfileDir}/minecraft_proxy.prom"
    '';
  };

  systemd.timers.minecraft-proxy-metrics = {
    description = "Sample the Minecraft proxy rate-limit counter";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
      # The counter resets to zero whenever the ruleset is reloaded - a deploy
      # or a reboot. That is fine: it is declared a counter, and Prometheus'
      # rate() handles resets correctly. Worth knowing before reading the raw
      # value and concluding the drops "went away".
      AccuracySec = "10s";
    };
  };
}
