# Off-box backup of mgmt's irreplaceable state:
#   - /var/lib/private/step-ca   CA root + intermediate + keys + db
#                                (lose this = re-trust the CA on every device)
#   - /var/lib/mgmt-secrets      generated service secrets (NetBox/Snipe-IT/Harmonia)
#   - /var/backup/postgresql     nightly netbox pg_dump (services.postgresqlBackup,
#                                see netbox.nix) - real IPAM data, not regenerable.
#                                OPTIONAL: only exists while netbox.nix is imported.
# Everything else is in the flake or regenerable.
#
# Daily, root tars those dirs straight into `age` (no plaintext hits disk),
# encrypted to the ADMIN age key - same recovery identity as sops, so only the
# desktop's admin key can open the .tar.age. Written to the NAS over NFS; newest 14 kept.
#
# Restore (on the desktop, which holds the admin key):
#   age -d -i ~/.config/sops/age/keys.txt mgmt-state-<ts>.tar.age | tar -C / -xv
#
# 2026-07-24 - why this file is defensive out of proportion to its size:
# an earlier revision passed all three paths to `tar` unconditionally. netbox.nix
# is commented out of mgmt's configuration, so /var/backup/postgresql never
# existed, tar exited 2, and `set -o pipefail` aborted the entire run - taking
# step-ca's only off-box copy with it, every night, silently. It had never once
# succeeded. Three properties now hold, and tests/mgmt-backup.nix fails if any
# of them regresses:
#   1. optional paths are probed, never assumed; a missing one is logged, not fatal
#   2. a missing REQUIRED path is loudly fatal - never a quiet partial backup
#   3. the archive is written as .partial and renamed only after the whole
#      pipeline succeeds, so a truncated stream cannot masquerade as a backup
{ pkgs, ... }:

let
  # Admin age recipient - PUBLIC, identical to the key in ../../../.sops.yaml.
  adminRecipient = "age16xrzea59hwrrwlccyu924e9ggraz7flgkh3grqpepdf2rhurry8s3hm5df";
  # Destination on the NAS (192.168.1.213:/srv/media/_backups/mgmt). Repoint both
  # this and the fileSystems device below if you add a dedicated backup share.
  nasMount = "/mnt/nas";
  nasDir = "${nasMount}/_backups/mgmt";
  keep = 14;
  # node_exporter's textfile collector dir (monitoring.nix) - a successful run
  # here is the only proof the backup actually happened, not just that the
  # timer fired (the BackupStale alert reads this).
  textfileDir = "/var/lib/node-exporter-textfile";

  # Without these there is no backup worth the name; absence is a hard failure.
  requiredPaths = [
    "var/lib/private/step-ca"
    "var/lib/mgmt-secrets"
  ];
  # Produced by services that may legitimately be switched off. Absence is logged
  # and skipped - losing step-ca's only copy because NetBox is disabled is not a
  # trade anyone would choose, and it is precisely what used to happen.
  optionalPaths = [
    "var/backup/postgresql"
  ];
in
{
  # The NAS share media already uses; lazy + non-blocking so a NAS outage can't
  # hang mgmt's boot (this box serves the LAN's DNS/PKI).
  fileSystems.${nasMount} = {
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

  systemd.services.mgmt-backup = {
    description = "Encrypted off-box backup of mgmt step-ca + service secrets";
    after = [
      "network-online.target"
      "postgresqlBackup-netbox.service"
    ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ nasMount ];
    path = [
      pkgs.age
      pkgs.gnutar
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux # mountpoint
    ];
    serviceConfig.Type = "oneshot"; # runs as root - tar reads the root-owned secret dirs
    script = ''
      set -euo pipefail

      # RequiresMountsFor ought to guarantee this, but check anyway: if the NAS is
      # not really mounted then `install -d` cheerfully creates the tree on mgmt's
      # own root filesystem, and every "successful" backup lands on the one disk
      # it exists to survive the loss of.
      if ! mountpoint -q ${nasMount}; then
        echo "FATAL: ${nasMount} is not a mountpoint - refusing to back up onto local disk" >&2
        exit 1
      fi

      paths=()
      for p in ${toString requiredPaths}; do
        if [ ! -e "/$p" ]; then
          echo "FATAL: required path /$p is missing - refusing to write a partial backup" >&2
          exit 1
        fi
        paths+=("$p")
      done
      for p in ${toString optionalPaths}; do
        if [ -e "/$p" ]; then
          paths+=("$p")
        else
          echo "note: optional path /$p absent (its producer is disabled) - skipping"
        fi
      done
      echo "backing up: ''${paths[*]}"

      ts=$(date +%Y%m%d-%H%M%S)
      install -d -m 0700 "${nasDir}"

      # Write under a .partial name and rename only once the pipeline has fully
      # succeeded. `age` produces a perfectly valid file from a truncated tar
      # stream, so without this a failed run leaves something that looks like a
      # backup, survives retention, and is found to be garbage at restore time -
      # the worst possible moment to find out.
      final="${nasDir}/mgmt-state-$ts.tar.age"
      tmp="${nasDir}/.mgmt-state-$ts.tar.age.partial"
      trap 'rm -f "$tmp"' EXIT

      # tar -> age streamed: the plaintext tarball never touches disk. pipefail
      # is what catches a mid-stream tar failure.
      tar -cf - -C / "''${paths[@]}" | age -r "${adminRecipient}" -o "$tmp"

      size=$(stat -c%s "$tmp")
      if [ "$size" -le 0 ]; then
        echo "FATAL: produced an empty archive" >&2
        exit 1
      fi
      mv "$tmp" "$final"
      trap - EXIT

      # Retention: keep the newest ${toString keep} completed archives. .partial
      # files are excluded by the glob, so a failed run can never evict a good one.
      ls -1t "${nasDir}"/mgmt-state-*.tar.age 2>/dev/null | tail -n +${toString (keep + 1)} | xargs -r rm -f
      echo "backup written: $final ($size bytes)"

      # Success metric for the BackupStale alert (monitoring.nix) - write-then-
      # rename so node_exporter never scrapes a half-written file. This is the
      # only evidence that distinguishes "the timer fired" from "a backup exists".
      install -d -m 0755 "${textfileDir}"
      metric=$(mktemp "${textfileDir}/.mgmt_backup.XXXXXX")
      {
        echo "# TYPE mgmt_backup_last_success_timestamp_seconds gauge"
        echo "mgmt_backup_last_success_timestamp_seconds $(date +%s)"
      } > "$metric"
      chmod 0644 "$metric"
      mv "$metric" "${textfileDir}/mgmt_backup.prom"
    '';
  };

  systemd.timers.mgmt-backup = {
    description = "Daily mgmt encrypted backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      Persistent = true; # catch up a missed run on next boot
      RandomizedDelaySec = "10m";
    };
  };
}
