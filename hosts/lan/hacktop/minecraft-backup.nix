# Off-box backup of the ATMons world - the only state on hacktop that a
# rebuild can't regenerate (mods/config are pinned store paths; the world is
# players' work). The server is deliberately open to the internet, so this is
# also the griefing/corruption recovery story: roll back to yesterday's world.
#
# Same pattern as hosts/lan/mgmt/modules/backup.nix: daily, root tars the
# world dir straight into `age` (no plaintext hits disk), encrypted to the
# ADMIN age key, written to the NAS over NFS, newest 14 kept.
#
# The tar is crash-consistent: the world is live and autosaves every ~5 min,
# so a backup may catch a mid-save tick. Fine for a homelab restore point; a
# console `save-off`/`save-all`/`save-on` wrapper around the tar would make it
# clean - future nicety.
#
# Restore (on the desktop, which holds the admin key; stop the server first):
#   age -d -i ~/.config/sops/age/keys.txt atmons-world-<ts>.tar.age | tar -C / -xv
{ pkgs, ... }:

let
  # Admin age recipient - PUBLIC, identical to the key in ../../../.sops.yaml.
  adminRecipient = "age16xrzea59hwrrwlccyu924e9ggraz7flgkh3grqpepdf2rhurry8s3hm5df";
  nasDir = "/mnt/nas/_backups/minecraft";
  keep = 14;
in
{
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
    ];
    serviceConfig.Type = "oneshot"; # root - the world dir is minecraft-owned, umask 0007
    script = ''
      set -euo pipefail
      ts=$(date +%Y%m%d-%H%M%S)
      install -d -m 0700 "${nasDir}"
      # tar -> age streamed: the plaintext tarball never touches disk.
      tar -cf - -C /srv/minecraft atmons \
        | age -r "${adminRecipient}" -o "${nasDir}/atmons-world-$ts.tar.age"
      # retention: keep the newest ${toString keep}
      ls -1t "${nasDir}"/atmons-world-*.tar.age 2>/dev/null | tail -n +${toString (keep + 1)} | xargs -r rm -f
      echo "backup written: ${nasDir}/atmons-world-$ts.tar.age ($(stat -c%s "${nasDir}/atmons-world-$ts.tar.age") bytes)"
    '';
  };

  systemd.timers.minecraft-backup = {
    description = "Daily ATMons world backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00"; # staggered off mgmt's 03:30 NAS write
      Persistent = true; # catch up a missed run on next boot
      RandomizedDelaySec = "10m";
    };
  };
}
