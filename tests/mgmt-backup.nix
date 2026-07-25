# tests/mgmt-backup.nix
#
# mgmt-backup check: prove the encrypted off-box backup actually produces an
# archive and its success metric -- and, specifically, that it still does so when
# an OPTIONAL source path is absent.
#
# This test exists because of a real outage. An earlier revision of backup.nix
# handed `tar` all three source paths unconditionally. netbox.nix is commented out
# of mgmt's configuration, so /var/backup/postgresql never existed, tar exited 2,
# and `set -o pipefail` aborted the whole run -- silently taking step-ca's only
# off-box copy with it. It failed every night for days and had never once
# succeeded. Nothing in the flake could catch that, because the bug lived in a
# shell script inside a systemd unit: it evaluates and builds perfectly.
#
# It imports the REAL hosts/lan/mgmt/modules/backup.nix, only swapping the NFS
# share for a tmpfs so the mountpoint guard is satisfied on a single node with no
# network and no NAS.
{ pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "mgmt-backup";

  nodes.machine =
    { lib, ... }:
    {
      imports = [ ../hosts/lan/mgmt/modules/backup.nix ];

      # The real module mounts the NAS over NFS. `virtualisation.fileSystems` is
      # the only way to add one in a VM test: the qemu-vm module applies
      # mkVMOverride (priority 10) to `fileSystems`, which outranks mkForce (50),
      # so the module's NFS entry is discarded for us and a plain `fileSystems`
      # override here would be silently dropped too.
      #
      # A tmpfs at the same path gives the unit's RequiresMountsFor and its
      # `mountpoint -q` guard a genuine mount, so the guard is exercised rather
      # than bypassed.
      virtualisation.fileSystems."/mnt/nas" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "size=64m" ];
      };

      # The timer would fire this on its own schedule; the test drives the unit
      # directly, so keep the timer out of the way.
      systemd.timers.mgmt-backup.wantedBy = lib.mkForce [ ];
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("mnt-nas.mount")

    # Stand in for the two REQUIRED sources. /var/backup/postgresql is deliberately
    # NOT created -- that is the exact condition that broke the real backup.
    machine.succeed("mkdir -p /var/lib/private/step-ca /var/lib/mgmt-secrets")
    machine.succeed("echo CA_ROOT_CANARY > /var/lib/private/step-ca/root_ca.crt")
    machine.succeed("echo SECRET_CANARY  > /var/lib/mgmt-secrets/netbox-secret")
    machine.fail("test -e /var/backup/postgresql")

    with subtest("runs to completion with an optional path missing"):
        machine.succeed("systemctl start mgmt-backup.service")
        machine.succeed("systemctl is-active --quiet mgmt-backup.service || true")
        # oneshot units go inactive on success; assert the result, not the state.
        machine.succeed(
            "systemctl show mgmt-backup.service -p Result --value | grep -qx success"
        )

    with subtest("it said so, rather than silently skipping everything"):
        machine.succeed(
            "journalctl -u mgmt-backup --no-pager | grep -q 'optional path /var/backup/postgresql absent'"
        )

    with subtest("an archive exists, is non-empty, and is really age-encrypted"):
        machine.succeed("ls /mnt/nas/_backups/mgmt/mgmt-state-*.tar.age")
        machine.succeed(
            "test $(stat -c%s /mnt/nas/_backups/mgmt/mgmt-state-*.tar.age) -gt 0"
        )
        machine.succeed(
            "head -c 32 /mnt/nas/_backups/mgmt/mgmt-state-*.tar.age | grep -q age-encryption.org"
        )

    with subtest("no .partial leftovers"):
        machine.fail("ls /mnt/nas/_backups/mgmt/.mgmt-state-*.partial")

    with subtest("the success metric is written -- BackupStale depends on it"):
        machine.succeed(
            "grep -q '^mgmt_backup_last_success_timestamp_seconds [0-9]' "
            "/var/lib/node-exporter-textfile/mgmt_backup.prom"
        )

    with subtest("a missing REQUIRED path fails loudly and writes nothing"):
        before = machine.succeed("ls /mnt/nas/_backups/mgmt/ | wc -l").strip()
        machine.succeed("rm -rf /var/lib/private/step-ca")
        machine.fail("systemctl start mgmt-backup.service")
        machine.succeed(
            "journalctl -u mgmt-backup --no-pager | grep -q 'required path /var/lib/private/step-ca is missing'"
        )
        after = machine.succeed("ls /mnt/nas/_backups/mgmt/ | wc -l").strip()
        assert before == after, f"failed run changed the archive set: {before} -> {after}"
  '';
}
