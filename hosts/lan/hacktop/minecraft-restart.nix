# hosts/lan/hacktop/minecraft-restart.nix
#
# Nightly restart of the ATMons server, with in-game warnings.
#
# Why: a 371-mod pack leaks. The server was sitting at 11.6 GB RSS after five
# days against an 8 GB heap cap, and the fix for that in modded Minecraft is a
# scheduled restart, not a heap tune. Doing it on a timer at a known hour beats
# doing it reactively when someone notices the TPS has gone.
#
# Ordering against the backup matters and is NOT expressed with After=/Before=:
# those only order units within a single systemd transaction, so they are inert
# between two independently-firing timers. Conflicts= would be worse - it would
# stop the backup mid-run and tear the archive. Both jobs take the same flock
# instead, so whichever starts first finishes first. The 04:45 start is 45
# minutes after the backup's 04:00, which is headroom, not the mechanism.
#
# The countdown is deliberately sent with `say` rather than `tellraw`: it is
# one console line per warning, it needs no JSON, and it reaches every player
# regardless of client mods.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  unit = "minecraft-server-atmons";
  mcConsole = lib.getExe config.alcove.mcConsole.package;
  textfileDir = config.alcove.configRevision.textfileDir;
  lockFile = "/run/minecraft-maintenance.lock";
in
{
  systemd.services.minecraft-restart = {
    description = "Nightly ATMons restart with in-game warnings";
    path = [
      pkgs.coreutils
      pkgs.util-linux # flock
      pkgs.systemd
      pkgs.gnugrep
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      # Blocks rather than skips: an overrunning backup should delay the
      # restart, never race it.
      exec 9>${lockFile}
      flock 9

      # If the pack is crash-looping the unit parks in `failed` and a plain
      # restart refuses. Clearing it first turns this job into one recovery
      # attempt per night, which is usually how a wedged server gets noticed
      # and fixed before morning.
      systemctl reset-failed ${unit}.service ${unit}.socket 2>/dev/null || true

      if ${mcConsole} up; then
        for warning in "15 minutes" "5 minutes" "1 minute"; do
          ${mcConsole} send "say Server restarting in $warning." || true
          case "$warning" in
            "15 minutes") sleep 600 ;;  # -> 5 minutes left
            "5 minutes")  sleep 240 ;;  # -> 1 minute left
            "1 minute")   sleep 60  ;;  # -> now
          esac
        done
        ${mcConsole} send 'say Restarting now - back in a few minutes.' || true
        # Give the message a tick to reach clients before the stop begins.
        sleep 2
      else
        echo "console unavailable - restarting without warnings"
      fi

      # nix-minecraft's ExecStop sends `stop` and waits for the JVM to exit, so
      # the world is saved properly; TimeoutStopSec is 1min15s.
      systemctl restart ${unit}.service

      # A restart that brings the server back into a crash loop is worse than
      # no restart, so do not report success until it is actually serving.
      # NeoForge boot on this pack is ~3 minutes; 10 is generous, and failing
      # loudly here is what makes SystemdUnitFailed fire.
      started=$(date '+%Y-%m-%d %H:%M:%S')
      for _ in $(seq 1 120); do
        if journalctl -u ${unit} --since "$started" --no-pager -o cat 2>/dev/null \
           | grep -qa 'For help, type'; then
          echo "server is back up"
          install -d -m 0755 "${textfileDir}"
          metric=$(mktemp "${textfileDir}/.minecraft_restart.XXXXXX")
          {
            echo "# HELP minecraft_restart_last_success_timestamp_seconds When the nightly restart last completed with the server confirmed back up."
            echo "# TYPE minecraft_restart_last_success_timestamp_seconds gauge"
            echo "minecraft_restart_last_success_timestamp_seconds $(date +%s)"
          } > "$metric"
          chmod 0644 "$metric"
          mv "$metric" "${textfileDir}/minecraft_restart.prom"
          exit 0
        fi
        sleep 5
      done

      echo "server did not report ready within 10 minutes of restart" >&2
      exit 1
    '';
  };

  systemd.timers.minecraft-restart = {
    description = "Nightly ATMons restart";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # 04:45 LOCAL (America/Los_Angeles, modules/common.nix) plus the ~15
      # minute countdown puts the actual restart around 05:00.
      OnCalendar = "*-*-* 04:45:00";

      # Deliberately NOT Persistent. A missed nightly restart is worth nothing;
      # catching it up would restart a server that just came up on boot, and
      # subject whoever is online to a 15-minute countdown nobody asked for.
      Persistent = false;

      # systemd's default AccuracySec is 1min, which would make "restarting in
      # 15 minutes" up to a minute of a lie. No RandomizedDelaySec either -
      # jitter here only widens the overlap window with the backup.
      AccuracySec = "1s";
    };
  };
}
