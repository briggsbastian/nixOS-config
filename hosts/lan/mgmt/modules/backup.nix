# Off-box backup of mgmt's irreplaceable state:
#   - /var/lib/private/step-ca   CA root + intermediate + keys + db
#                                (lose this = re-trust the CA on every device)
#   - /var/lib/mgmt-secrets      generated service secrets (NetBox/Snipe-IT/Harmonia)
# Everything else is in the flake or regenerable.
#
# Daily, root tars those two dirs straight into `age` (no plaintext hits disk),
# encrypted to the ADMIN age key - same recovery identity as sops, so only the
# desktop's admin key can open the .tar.age. Written to the NAS over NFS; newest 14 kept.
#
# Restore (on the desktop, which holds the admin key):
#   age -d -i ~/.config/sops/age/keys.txt mgmt-state-<ts>.tar.age | tar -C / -xv
{ pkgs, ... }:

let
  # Admin age recipient - PUBLIC, identical to the key in ../../../.sops.yaml.
  adminRecipient = "age16xrzea59hwrrwlccyu924e9ggraz7flgkh3grqpepdf2rhurry8s3hm5df";
  # Destination on the NAS (192.168.1.213:/srv/media/_backups/mgmt). Repoint both
  # this and the fileSystems device below if you add a dedicated backup share.
  nasDir = "/mnt/nas/_backups/mgmt";
  keep = 14;
in
{
  # The NAS share media already uses; lazy + non-blocking so a NAS outage can't
  # hang mgmt's boot (this box serves the LAN's DNS/PKI).
  fileSystems."/mnt/nas" = {
    device = "192.168.1.213:/srv/media";
    fsType = "nfs";
    options = [ "nfsvers=4.2" "noatime" "nofail" "x-systemd.automount" "_netdev" ];
  };

  systemd.services.mgmt-backup = {
    description = "Encrypted off-box backup of mgmt step-ca + service secrets";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ "/mnt/nas" ];
    path = [ pkgs.age pkgs.gnutar pkgs.coreutils pkgs.findutils ];
    serviceConfig.Type = "oneshot"; # runs as root - tar reads the root-owned secret dirs
    script = ''
      set -euo pipefail
      ts=$(date +%Y%m%d-%H%M%S)
      install -d -m 0700 "${nasDir}"
      # tar -> age streamed: the plaintext tarball never touches disk.
      tar -cf - -C / var/lib/private/step-ca var/lib/mgmt-secrets \
        | age -r "${adminRecipient}" -o "${nasDir}/mgmt-state-$ts.tar.age"
      # retention: keep the newest ${toString keep}
      ls -1t "${nasDir}"/mgmt-state-*.tar.age 2>/dev/null | tail -n +${toString (keep + 1)} | xargs -r rm -f
      echo "backup written: ${nasDir}/mgmt-state-$ts.tar.age ($(stat -c%s "${nasDir}/mgmt-state-$ts.tar.age") bytes)"
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
