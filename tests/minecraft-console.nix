# tests/minecraft-console.nix
#
# Guards the one failure in the ATMons console rework that builds perfectly,
# reviews perfectly, and only fires on a night the server happened to be down.
#
# Since minecraft.nix moved to managementSystem.systemd-socket, the console is
# a FIFO created by minecraft-server-atmons.socket. Writing to it with a bare
# shell redirect while that socket is stopped does not fail - it CREATES A
# REGULAR FILE at that path. systemd then refuses to start the socket, and the
# server never comes back. The daily backup is the thing most likely to try to
# talk to a stopped server, so this is not a hypothetical ordering.
#
# mc-console exists to make that unrepresentable, and this test is what keeps it
# that way. Same reason tests/mgmt-backup.nix exists: the bug lives in a shell
# script inside a systemd unit, so nothing in `nix flake check` would otherwise
# see it.
#
# Rather than run 371 mods, this stands up a FAKE server: a `while read` loop
# wired with the same socket options nix-minecraft generates, echoing vanilla's
# save-feedback strings. That exercises every line of the real backup wrapper -
# quiesce, flush detection, save-on, the trap - against a real FIFO.
{ pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "minecraft-console";

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../modules/config-revision.nix
        ../hosts/lan/hacktop/mc-console.nix
        ../hosts/lan/hacktop/minecraft-backup.nix
      ];

      # Same mkVMOverride reasoning as tests/mgmt-backup.nix: the qemu-vm module
      # applies priority 10 to `fileSystems`, outranking mkForce, so the real
      # module's NFS entry is discarded and only `virtualisation.fileSystems`
      # can put a genuine mount at this path.
      virtualisation.fileSystems."/mnt/nas" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "size=256m" ];
      };

      # The test drives these directly; keep their timers out of the way.
      systemd.timers.minecraft-backup.wantedBy = lib.mkForce [ ];
      systemd.timers.minecraft-backup-verify.wantedBy = lib.mkForce [ ];

      # minecraft-backup encrypts to hacktop's SSH host key as a second
      # recipient, and minecraft-backup-verify decrypts with it. sshd's preStart
      # is what generates that keypair.
      services.openssh.enable = true;

      # The units carry their own `path`, but the test script also decrypts an
      # archive by hand. Without this, `age` is simply not found, the pipeline
      # feeds tar an empty stream, and tar fails with a misleading exit 2.
      environment.systemPackages = [ pkgs.age ];

      users.groups.minecraft = { };
      users.users.minecraft = {
        isSystemUser = true;
        group = "minecraft";
      };

      # The fake server. Socket options mirror what nix-minecraft's
      # systemd-socket management system generates, because those are exactly
      # what mc-console's `up` check and the FIFO hazard depend on.
      systemd.sockets.minecraft-server-atmons = {
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenFIFO = "/run/minecraft/atmons.stdin";
          SocketMode = "0660";
          SocketUser = "minecraft";
          SocketGroup = "minecraft";
          RemoveOnStop = true;
          FlushPending = true;
        };
      };

      systemd.services.minecraft-server-atmons = {
        # nix-minecraft's real unit is autoStart, not purely socket-activated:
        # the server must be running and holding the FIFO open before anything
        # writes to it. Without this it would only start on first write, which
        # is not the shape of the thing under test.
        wantedBy = [ "multi-user.target" ];
        requires = [ "minecraft-server-atmons.socket" ];
        after = [ "minecraft-server-atmons.socket" ];
        serviceConfig = {
          Type = "simple";
          StandardInput = "socket";
          StandardOutput = "journal";
          StandardError = "journal";
          User = "minecraft";
          Group = "minecraft";
          RuntimeDirectory = "minecraft";
          RuntimeDirectoryPreserve = "yes";
          Restart = "always";
        };
        script = ''
          echo 'Done (0.1s)! For help, type "help"'
          while read -r line; do
            case "$line" in
              # Vanilla's actual responses. The backup greps for "Saved the
              # game" and must not hang or abort if it never appears.
              'save-off')        echo 'Automatic saving is now disabled' ;;
              'save-on')         echo 'Automatic saving is now enabled' ;;
              'save-all flush')  echo 'Saving the game (this may take a moment!)'; echo 'Saved the game' ;;
              *)                 echo "Unknown command: $line" ;;
            esac
          done
        '';
      };
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("mnt-nas.mount")
    machine.wait_for_unit("minecraft-server-atmons.service")

    # A world for the backup to archive.
    machine.succeed("mkdir -p /srv/minecraft/atmons/world/region")
    machine.succeed("echo LEVEL_CANARY > /srv/minecraft/atmons/world/level.dat")
    machine.succeed("echo REGION > /srv/minecraft/atmons/world/region/r.0.0.mca")
    machine.succeed("chown -R minecraft:minecraft /srv/minecraft/atmons")

    with subtest("mc-console reports the console up, and can send to it"):
        machine.succeed("mc-console up")
        machine.succeed("mc-console send 'save-off'")
        machine.wait_until_succeeds(
            "journalctl -u minecraft-server-atmons --no-pager | grep -q 'Automatic saving is now disabled'"
        )
        machine.succeed("mc-console send 'save-on'")

    with subtest("a backup quiesces the world and says so"):
        machine.succeed("systemctl start minecraft-backup.service")
        machine.succeed(
            "systemctl show minecraft-backup.service -p Result --value | grep -qx success"
        )
        machine.succeed("journalctl -u minecraft-backup --no-pager | grep -q 'world quiesced'")
        machine.succeed(
            "grep -q '^minecraft_backup_quiesced 1' /var/lib/node-exporter-textfile/minecraft_backup.prom"
        )

    with subtest("the archive exists, is age-encrypted, and left no .partial"):
        machine.succeed("ls /mnt/nas/_backups/minecraft/atmons-world-*.tar.age")
        machine.succeed(
            "head -c 32 /mnt/nas/_backups/minecraft/atmons-world-*.tar.age | grep -q age-encryption.org"
        )
        machine.fail("ls /mnt/nas/_backups/minecraft/.atmons-world-*.partial")

    with subtest("both recipients are present - dropping one is invisible until a restore"):
        # X25519 is the admin key; ssh-ed25519 is hacktop's host key, which is
        # the only reason the verify job below can work at all.
        hdr = machine.succeed(
            "head -c 4096 /mnt/nas/_backups/minecraft/atmons-world-*.tar.age"
        )
        assert "X25519" in hdr, "admin recipient stanza missing"
        assert "ssh-ed25519" in hdr, "host-key recipient stanza missing"

    with subtest("the archive really round-trips with the host key"):
        # Listing to a file rather than piping straight into grep: `grep -q`
        # exits on first match, tar takes SIGPIPE, and pipefail then fails the
        # whole command even though the content was fine.
        machine.succeed(
            "age -d -i /etc/ssh/ssh_host_ed25519_key "
            "$(ls -1t /mnt/nas/_backups/minecraft/atmons-world-*.tar.age | head -1) "
            "| tar -tf - > /tmp/listing"
        )
        machine.succeed("grep -q 'atmons/world/level.dat' /tmp/listing")
        machine.succeed("grep -q 'atmons/world/region/r.0.0.mca' /tmp/listing")

    with subtest("the verify job passes and records it"):
        machine.succeed("systemctl start minecraft-backup-verify.service")
        machine.succeed(
            "systemctl show minecraft-backup-verify.service -p Result --value | grep -qx success"
        )
        machine.succeed(
            "grep -q '^minecraft_backup_verify_last_success_timestamp_seconds [0-9]' "
            "/var/lib/node-exporter-textfile/minecraft_backup_verify.prom"
        )

    # THE ONE THAT MATTERS. With the server and socket stopped, the FIFO is
    # gone. A backup must still succeed, and must NOT leave a regular file
    # where systemd wants a FIFO - because that is unrecoverable without
    # manual intervention: the socket would refuse to start forever after.
    with subtest("server down: backup succeeds and does not poison the FIFO path"):
        machine.succeed("systemctl stop minecraft-server-atmons.service")
        machine.succeed("systemctl stop minecraft-server-atmons.socket")
        machine.fail("test -e /run/minecraft/atmons.stdin")

        machine.fail("mc-console up")
        machine.succeed("systemctl start minecraft-backup.service")
        machine.succeed(
            "systemctl show minecraft-backup.service -p Result --value | grep -qx success"
        )
        machine.succeed(
            "journalctl -u minecraft-backup --no-pager | grep -q 'server not running'"
        )

        # If anything created a regular file here, this is where we find out.
        machine.fail("test -e /run/minecraft/atmons.stdin")

        # And the proof that it matters: the socket still comes back.
        machine.succeed("systemctl start minecraft-server-atmons.socket")
        machine.succeed("test -p /run/minecraft/atmons.stdin")
        machine.succeed("systemctl start minecraft-server-atmons.service")
        machine.wait_for_unit("minecraft-server-atmons.service")

    with subtest("mc-console send refuses outright when the console is down"):
        machine.succeed("systemctl stop minecraft-server-atmons.service")
        machine.succeed("systemctl stop minecraft-server-atmons.socket")
        machine.fail("mc-console send 'save-off'")
        machine.fail("test -e /run/minecraft/atmons.stdin")
  '';
}
