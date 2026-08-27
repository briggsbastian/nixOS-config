# Off-box backup of the ATMons world - the only state on hacktop that a
# rebuild can't regenerate (mods/config are pinned store paths; the world is
# players' work). The server is deliberately open to the internet, so this is
# also the griefing/corruption recovery story: roll back to yesterday's world.
#
# Same pattern as hosts/lan/mgmt/modules/backup.nix: daily, root tars the
# world dir straight into `age` (no plaintext hits disk), encrypted to the
# ADMIN age key, written to the NAS over NFS.
#
# RETENTION IS NOT "the newest N" ANY MORE - see minecraft-prune.nix. It was
# 14 dailies, which at ~12.9 GB an archive is ~180 GB of NAS for one world.
# On 2026-08-20 /mnt/nas was 94% full with 52.5 GiB left and this directory
# was the largest single thing on it; at the then-current rate the share had
# about three weeks of life in it, with a SECOND world still to come. Now:
#
#     3 dailies + 1 weekly + 1 monthly   = at most 5 archives, ~65 GB
#
# Deliberately a tiered set rather than a flat `keep = 3`. Flat 3 would have
# freed ~26 GB more, but these archives are the griefing-recovery story for a
# server that is white-list=false and publicly reachable (see minecraft.nix),
# and a flat 3 shrinks "notice the grief, then roll back" to a 72-hour window.
# The weekly and monthly slots buy back a rollback horizon that is typically
# two to four weeks, for two archives - about a fifth of what dropping 14 -> 3
# recovers in the first place.
#
# Be honest about the shape of that, though: with keepMonthly = 1 the horizon
# oscillates. It is deepest at the end of a calendar month (the monthly slot
# holds last month's last archive, ~30 days back) and collapses to the daily
# window for the day or two after a month turns over, when last month's last
# archive is still inside the daily window and so consumes the monthly slot.
# So this is never WORSE than the flat 3 the space budget asked for, and
# usually much better - but it is not a guaranteed 30 days. Making it one is
# `keepMonthly = 2`: one more archive, ~13 GB, no other change. Worth doing
# once the NAS has headroom again; not while it has three weeks of life left.
#
# NOT COMPRESSED, and that is a decision rather than an oversight - `tar -cf -`
# into `age`, and age does not compress either, which is why a ~12 GB world is
# a ~12.9 GB archive. The obvious next lever is `zstd` in that pipeline, and it
# is deliberately NOT being pulled in the same change as the retention cut:
#
#   * The yield is unknown and probably small. Region files (.mca) hold
#     per-chunk zlib streams already; what is actually compressible is the
#     4 KiB sector padding and tar's own block padding, not the chunk data.
#     Guessing at that number and then designing around the guess is how you
#     end up with a slower backup and no space.
#   * It would trip MinecraftBackupShrank (< 0.5x the 14d peak) for a
#     fortnight if it worked well, and that alert is the only thing that
#     catches a tar which succeeds while archiving almost nothing.
#   * It puts a decompressor in the RESTORE path. GNU tar auto-detects on
#     read, but only if `zstd` is on PATH - and the documented restore runs on
#     the desktop, at 2am, during an incident. `age` already has to be dug out
#     of the closure by hand there (see MAINTENANCE.md).
#
# Measure before deciding. On hacktop, as root, out of hours - this reads the
# whole world and writes nothing:
#   tar -cf - -C /srv/minecraft atmons | zstd -3 -T0 | wc -c
# Compare against minecraft_backup_size_bytes. Under ~15% it is not worth the
# three costs above; over ~30% it probably is, as its own change.
#
# Four things this does beyond a plain tar:
#
#   1. QUIESCE. The tar is wrapped in save-off / save-all flush / save-on, so
#      it no longer catches a mid-autosave tick. Confirming the flush finished
#      means watching for the server's own "Saved the game" line, which is a
#      localised string a pack update could move - so failing to confirm never
#      aborts the backup. It falls back to a crash-consistent tar and records
#      minecraft_backup_quiesced 0, which alerts. A crash-consistent backup
#      beats no backup.
#
#   2. PROOF. A timestamp, the archive size and the quiesced flag go to
#      node_exporter's textfile collector, so "the timer is green" and "there
#      is a backup" stop being the same claim. mgmt alerts on all three.
#
#   3. SELF-VERIFICATION. The archive is encrypted to a SECOND recipient,
#      hacktop's own SSH host key, so the monthly verify job below can decrypt
#      and walk it. Without that, nothing on this box could ever prove the
#      ciphertext on the NAS was intact. The trade: a hacktop compromise can
#      then read historical (pre-grief) worlds, not just the live one it
#      already holds in plaintext. Judged worth it - an unverified backup is
#      not a backup.
#
#   4. CAPACITY. The run also reports how much space the retention set uses
#      and how much is left on the share. Nothing else in the fleet watches
#      the NAS: it is unmanaged (no SNMP, no API, no node_exporter), and
#      monitoring.nix's disk alert excludes fstype=~"nfs.*" on every client,
#      so "94% full" was found by hand rather than by an alert. This is the
#      cheapest place to close that hole, because it is the job that fills it.
#
# Restore (on the desktop, which holds the admin key; stop the server first):
#   age -d -i ~/.config/sops/age/keys.txt atmons-world-<ts>.tar.age | tar -C /srv/minecraft -xv
# Or on hacktop itself, with its host key:
#   age -d -i /etc/ssh/ssh_host_ed25519_key atmons-world-<ts>.tar.age | tar -tvf -
{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Admin age recipient - PUBLIC, identical to the key in ../../../.sops.yaml.
  adminRecipient = "age16xrzea59hwrrwlccyu924e9ggraz7flgkh3grqpepdf2rhurry8s3hm5df";
  nasDir = "/mnt/nas/_backups/minecraft";
  unit = "minecraft-server-atmons";

  # One definition of the archive name, used to build the .partial, the final
  # file, the verify job's glob and the pruner's glob. They MUST agree - a
  # prefix that drifts between the writer and the pruner is a retention rule
  # that silently matches nothing and keeps every archive forever, which on
  # this NAS is how you get here again. When the second world lands it gets
  # its own prefix and its own three counts, and reuses everything else.
  archivePrefix = "atmons-world";

  # Grandfather-father-son; see the header for the space and security
  # arithmetic and minecraft-prune.nix for the semantics. Upper bound on the
  # retention set is keepDaily + keepWeekly + keepMonthly archives, and it is
  # genuinely an upper bound: on the days the previous week's or month's last
  # archive is still inside the daily window, the tiers land on a file tier 1
  # already keeps and the set is smaller.
  keepDaily = 3;
  keepWeekly = 1;
  keepMonthly = 1;

  pruneArchives = import ./minecraft-prune.nix { inherit pkgs; };

  # age accepts an ssh-ed25519 public key as a recipients file (-R) and the
  # matching private key as an identity (-i). Verified with age 1.3.1.
  hostKeyPub = "/etc/ssh/ssh_host_ed25519_key.pub";
  hostKey = "/etc/ssh/ssh_host_ed25519_key";

  # Written by node_exporter's textfile collector (modules/metrics.nix) - the
  # only proof a run actually happened rather than merely being scheduled.
  textfileDir = config.alcove.configRevision.textfileDir;

  mcConsole = lib.getExe config.alcove.mcConsole.package;

  # Serialises the backup against the nightly restart. systemd's After=/Before=
  # only order units WITHIN a transaction, so they are inert between two
  # independently-firing timers; Conflicts= would be worse, since it would stop
  # the backup mid-run. A lock is the only thing that actually works here.
  lockFile = "/run/minecraft-maintenance.lock";

  # Belt and braces for save-on. The in-script trap covers normal exit, set -e,
  # SIGTERM and SIGINT; this covers SIGKILL - OOM, systemctl kill, or a hung
  # NFS write hitting TimeoutStopSec. A server left with saving disabled is the
  # worst outcome in this file, so it gets two independent nets.
  saveOnScript = pkgs.writeShellScript "minecraft-backup-save-on" ''
    if ${mcConsole} up; then
      ${mcConsole} send 'save-on' || true
    fi
  '';
in
{
  # On PATH for humans as well as referenced by store path from the unit -
  # same reasoning as mc-console.nix. The unit gets the exact path this eval
  # built; a person clearing out a backlog of old archives by hand gets a
  # command they can type, and gets the SAME code the timer runs, so a dry run
  # is an exact preview of the policy rather than an approximation of it. That
  # matters: the alternative is a hand-written `ls | tail | xargs rm` typed
  # into a root shell at the exact moment the NAS is nearly full.
  environment.systemPackages = [ pruneArchives ];

  # Same NAS share media/mgmt use; lazy + non-blocking so a NAS outage can't
  # hang boot.
  fileSystems."/mnt/nas" = {
    device = "192.168.1.213:/srv/media";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "noatime"
      "nofail"
      "x-systemd.automount"
      "_netdev"
    ];
  };

  systemd.services.minecraft-backup = {
    description = "Encrypted off-box backup of the ATMons world";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ "/mnt/nas" ];
    path = [
      pkgs.age
      pkgs.gnutar
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux # flock
      pkgs.systemd # journalctl, systemctl
    ];
    serviceConfig = {
      Type = "oneshot"; # root - the world dir is minecraft-owned, umask 0007
      ExecStopPost = "-${saveOnScript}";
    };
    script = ''
      set -euo pipefail

      # Held for the whole run. The nightly restart blocks on this rather than
      # tearing the tar out from under itself.
      exec 9>${lockFile}
      flock 9

      quiesced=0
      save_off_sent=0

      restore_saving() {
        if [ "$save_off_sent" = 1 ]; then
          ${mcConsole} send 'save-on' || \
            echo "WARNING: could not re-enable saving; ExecStopPost is the backstop" >&2
        fi
      }
      trap restore_saving EXIT INT TERM

      started_before=""
      if ${mcConsole} up; then
        started_before=$(systemctl show ${unit} -p ExecMainStartTimestampMonotonic --value)

        # Everything the server prints after this point is fair game for the
        # flush check. Using a timestamp rather than a journal cursor keeps
        # this readable; the window is seconds wide so collisions are not a
        # practical concern.
        flush_since=$(date '+%Y-%m-%d %H:%M:%S')

        ${mcConsole} send 'save-off'
        save_off_sent=1
        ${mcConsole} send 'save-all flush'

        # Wait for the server to say it finished. Bounded: a 371-mod world can
        # take a while, but not forever, and we would rather take a
        # crash-consistent backup than skip a night.
        for _ in $(seq 1 120); do
          if journalctl -u ${unit} --since "$flush_since" --no-pager -o cat 2>/dev/null \
             | grep -qa 'Saved the game'; then
            quiesced=1
            break
          fi
          sleep 1
        done

        if [ "$quiesced" = 1 ]; then
          echo "world quiesced (save-all flush confirmed)"
        else
          echo "WARNING: no 'Saved the game' within 120s - taking a crash-consistent tar" >&2
        fi
      else
        # A stopped server is the most consistent state there is: nothing is
        # writing. Deliberately reported as quiesced so the metric answers "is
        # this archive consistent", not "did we talk to the console".
        quiesced=1
        echo "server not running - plain tar, nothing to quiesce"
      fi

      ts=$(date +%Y%m%d-%H%M%S)
      install -d -m 0700 "${nasDir}"

      # Write to a dotted .partial first: a killed run must not leave a
      # truncated archive that looks valid, and retention must never be able
      # to select one. That is now enforced in two independent places - the
      # leading dot (shell globs skip dotfiles) and the .partial suffix
      # (outside the *.tar.age pattern) - and minecraft-prune.nix rejects both
      # again by hand. Change this name and you must change that file.
      partial="${nasDir}/.${archivePrefix}-$ts.tar.age.partial"
      final="${nasDir}/${archivePrefix}-$ts.tar.age"

      # tar -> age streamed: the plaintext tarball never touches disk. Two
      # recipients: the admin key for real restores, hacktop's own host key so
      # minecraft-backup-verify can check its work.
      tar -cf - -C /srv/minecraft atmons \
        | age -r "${adminRecipient}" -R ${hostKeyPub} -o "$partial"

      restore_saving
      save_off_sent=0

      # If the server restarted while we were reading the world, the archive
      # may straddle a full save. Still keep it - a possibly-torn backup beats
      # none - but do not claim it was quiesced.
      if [ -n "$started_before" ]; then
        started_after=$(systemctl show ${unit} -p ExecMainStartTimestampMonotonic --value)
        if [ "$started_before" != "$started_after" ]; then
          echo "WARNING: server restarted mid-backup; archive may straddle a save" >&2
          quiesced=0
        fi
      fi

      mv "$partial" "$final"
      size=$(stat -c%s "$final")
      echo "backup written: $final ($size bytes, quiesced=$quiesced)"

      # Retention. Runs AFTER the mv, never before: pruning first would, on
      # the night the tar fails, delete an old archive and write no new one.
      # Prints its whole decision to the journal, kept and deleted alike.
      ${lib.getExe pruneArchives} "${nasDir}" "${archivePrefix}" \
        ${toString keepDaily} ${toString keepWeekly} ${toString keepMonthly}

      # What the retention set actually costs, and what is left to spend. Both
      # are read after the prune so they describe the steady state rather than
      # the momentary peak. `du -sb` here is a stat walk over a handful of
      # files, not a read - it does not pull 65 GB back across NFS.
      store=$(du -sb "${nasDir}" | cut -f1)
      free=$(df -B1 --output=avail "${nasDir}" | tail -n1 | tr -d ' ')

      # Same mktemp -> chmod -> atomic mv dance as mgmt's backup.nix, so a
      # scrape can never catch a half-written metrics file.
      install -d -m 0755 "${textfileDir}"
      metric=$(mktemp "${textfileDir}/.minecraft_backup.XXXXXX")
      {
        echo "# HELP minecraft_backup_last_success_timestamp_seconds When the ATMons world backup last succeeded."
        echo "# TYPE minecraft_backup_last_success_timestamp_seconds gauge"
        echo "minecraft_backup_last_success_timestamp_seconds $(date +%s)"
        echo "# HELP minecraft_backup_quiesced Whether saving was flushed and paused for the last backup."
        echo "# TYPE minecraft_backup_quiesced gauge"
        echo "minecraft_backup_quiesced $quiesced"
        echo "# HELP minecraft_backup_size_bytes Size of the last ATMons world archive."
        echo "# TYPE minecraft_backup_size_bytes gauge"
        echo "minecraft_backup_size_bytes $size"
        echo "# HELP minecraft_backup_store_bytes Bytes the ATMons retention set occupies on the NAS."
        echo "# TYPE minecraft_backup_store_bytes gauge"
        echo "minecraft_backup_store_bytes $store"
        echo "# HELP minecraft_backup_store_free_bytes Bytes free on the NAS share holding the world archives."
        echo "# TYPE minecraft_backup_store_free_bytes gauge"
        echo "minecraft_backup_store_free_bytes $free"
      } > "$metric"
      chmod 0644 "$metric"
      mv "$metric" "${textfileDir}/minecraft_backup.prom"
    '';
  };

  systemd.timers.minecraft-backup = {
    description = "Daily ATMons world backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # LOCAL time (America/Los_Angeles, modules/common.nix) - systemd calendar
      # specs use the system timezone unless one is named. Staggered off mgmt's
      # 03:30 NAS write, and 45 minutes ahead of the nightly restart, with the
      # lock as the real interlock.
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true; # catch up a missed run on next boot
      RandomizedDelaySec = "10m";
    };
  };

  # A green timer is not a backup. Monthly, decrypt the newest archive with
  # hacktop's own host key and walk every tar header - the only check that
  # exercises the whole chain (NFS read, age decrypt, tar integrity) rather
  # than just asserting a file exists.
  systemd.services.minecraft-backup-verify = {
    description = "Verify the newest ATMons world backup is decryptable and intact";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ "/mnt/nas" ];
    path = [
      pkgs.age
      pkgs.gnutar
      pkgs.coreutils
      pkgs.gnugrep
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      newest=$(ls -1t "${nasDir}"/${archivePrefix}-*.tar.age 2>/dev/null | head -1 || true)
      if [ -z "$newest" ]; then
        echo "no archive to verify" >&2
        exit 1
      fi
      echo "verifying $newest"

      # Guards against someone "simplifying" the age invocation down to one
      # recipient, which would silently make this job impossible next month.
      if ! grep -qa 'ssh-ed25519' "$newest"; then
        echo "archive has no ssh-ed25519 recipient stanza - hacktop cannot self-verify" >&2
        exit 1
      fi

      # Decrypt and walk every tar header. Holding the listing in a variable
      # keeps this to one decrypt pass; it is a few MB of filenames even for a
      # large world, against the ~GB of ciphertext it avoids re-reading.
      listing=$(age -d -i ${hostKey} "$newest" | tar -tf -)
      count=$(printf '%s\n' "$listing" | wc -l)

      if ! printf '%s\n' "$listing" | grep -qa 'atmons/world/level.dat'; then
        echo "decrypted fine but atmons/world/level.dat is missing - wrong directory archived?" >&2
        exit 1
      fi
      echo "verified: $count members, level.dat present"

      install -d -m 0755 "${textfileDir}"
      metric=$(mktemp "${textfileDir}/.minecraft_backup_verify.XXXXXX")
      {
        echo "# HELP minecraft_backup_verify_last_success_timestamp_seconds When a backup was last decrypted and walked successfully."
        echo "# TYPE minecraft_backup_verify_last_success_timestamp_seconds gauge"
        echo "minecraft_backup_verify_last_success_timestamp_seconds $(date +%s)"
      } > "$metric"
      chmod 0644 "$metric"
      mv "$metric" "${textfileDir}/minecraft_backup_verify.prom"
    '';
  };

  systemd.timers.minecraft-backup-verify = {
    description = "Monthly ATMons backup restore-verification";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-01 06:00:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
