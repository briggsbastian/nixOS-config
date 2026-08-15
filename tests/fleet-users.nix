# tests/fleet-users.nix
#
# Prove that uid 1000 changes hands cleanly.
#
# modules/users.nix retires each host's own admin (mgmt, hacktop, cloud1) and
# gives its uid - 1000 on every one of them - to a new `briggs`. That is a single
# activation in which one account is deleted and another claims its number, and
# it is not obvious that NixOS's update-users-groups.pl frees the old uid before
# allocating the new one. If it does not, activation fails, and on cloud1 that
# means a box with no console, off-LAN, mid-switch.
#
# So this asserts the migration at runtime rather than the numbering at eval:
# boot a machine in the *old* shape (host-named admin holding 1000, mutableUsers
# on, a file it owns), switch to the real module, and check what actually landed
# in /etc/passwd and on disk.
#
# The before/after split is a specialisation gated on `fleetUsersTest.migrated`,
# rather than a second system built with pkgs.nixos. That is not a style choice:
# a standalone system declares its own fileSystems and bootloader, and switching
# to it inside the test VM made systemd unmount /nix/.ro-store and /tmp/shared
# out from under the running machine - the test then hung until the driver timed
# out. A specialisation inherits the node's config, so only the users differ.
#
# What it does NOT cover: sops. The `sops` option surface is stubbed below rather
# than pulling in sops-nix, so this says nothing about whether the password hash
# decrypts. That path is already guarded at build time - sops-install-secrets
# validates the key exists in the yaml and fails the build if it does not, which
# is how the missing `briggs_hashed_password` surfaced in the first place.
{ pkgs, ... }:

let
  keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
  ];

  # yescrypt hash of "correct-horse", so the test can prove the account is
  # actually usable rather than merely present - a user with `!` in shadow looks
  # fine in /etc/passwd and cannot sudo.
  password = "correct-horse";
  passwordFile = pkgs.writeText "briggs-hash" "$y$j9T$FBfTvamw8hn7Z7HlE/Ny80$Ln4VjrRm9oM/qne8qGwBW/MaOcQyjKNK3cl/fUm3l4A";

  # Just enough of sops-nix's option surface for modules/users.nix to evaluate,
  # with `.path` defaulted to the plain file above - so the module's own
  # `hashedPasswordFile = config.sops.secrets.briggs_hashed_password.path` is
  # exercised as written, with nothing overridden. Deliberately a stub: the real
  # sops-nix would drag a host key, an age identity and an encrypted fixture into
  # a test that is about uid allocation.
  sopsStub =
    { lib, ... }:
    {
      options.sops.secrets = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              # str, not path: users.users.<n>.hashedPasswordFile is `null or
              # string`, and handing it a derivation fails the type check.
              path = lib.mkOption {
                type = lib.types.str;
                default = "${passwordFile}";
              };
              sopsFile = lib.mkOption { type = lib.types.path; };
              neededForUsers = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
            };
          }
        );
      };
    };
in

pkgs.testers.runNixOSTest {
  name = "fleet-users";

  nodes.machine =
    { config, lib, ... }:
    {
      imports = [
        sopsStub
        ../modules/users.nix
        ../modules/deploy-user.nix
      ];

      options.fleetUsersTest.migrated = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Flipped by the `migrated` specialisation to swap the old admin for briggs.";
      };

      config = {
        alcove.fleetUsers.enable = config.fleetUsersTest.migrated;
        alcove.fleetUsers.passwordSopsFile = ../secrets/hacktop.yaml; # unused - sops is stubbed

        # The shape every migrating host is in today: an admin named after the
        # box holding uid 1000, mutable users, no declarative password.
        users.users.hacktop = lib.mkIf (!config.fleetUsersTest.migrated) {
          isNormalUser = true;
          uid = 1000;
          description = "hacktop";
          openssh.authorizedKeys.keys = keys;
        };
        users.mutableUsers = lib.mkIf (!config.fleetUsersTest.migrated) true;

        specialisation.migrated.configuration.fleetUsersTest.migrated = lib.mkForce true;
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Resolve to the store path *before* switching. Specialisations do not nest,
    # so once /run/current-system is the migrated system the relative path
    # /run/current-system/specialisation/migrated no longer exists - reusing it
    # for the idempotency check below fails with exit 127, not a real regression.
    migrated = machine.succeed(
        "readlink -f /run/current-system/specialisation/migrated"
    ).strip()
    switch = f"{migrated}/bin/switch-to-configuration"

    with subtest("the old shape is what we think it is"):
        assert "hacktop:x:1000:" in machine.succeed("getent passwd hacktop")
        machine.fail("getent passwd briggs")

    # A file owned by the outgoing admin. Its uid on disk does not change, so
    # after the switch it must read back as owned by briggs - the same mechanism
    # the NAS relies on, checked locally where it is cheap.
    machine.succeed("touch /home/hacktop/inherited && chown 1000:100 /home/hacktop/inherited")

    with subtest("the switch itself succeeds"):
        # The whole question. A non-zero exit here is the deploy breaking on
        # cloud1 with no console attached.
        machine.succeed(f"{switch} test >&2")

    with subtest("the machine survived the switch"):
        # An earlier version of this test tore down the VM's own mounts mid-
        # switch and then hung for 15 minutes. Fail fast instead.
        machine.succeed("test -e /nix/store")
        machine.succeed("systemctl is-system-running --wait || true")

    with subtest("briggs holds uid 1000 and the old admin is gone"):
        assert "briggs:x:1000:" in machine.succeed("getent passwd briggs")
        machine.fail("getent passwd hacktop")

    with subtest("primary group is users (100), not a new group at 1000"):
        # A per-user group at gid 1000 would collide with the NAS group on the
        # media host, so modules/users.nix deliberately does not create one.
        assert machine.succeed("id -gn briggs").strip() == "users"
        assert machine.succeed("id -g briggs").strip() == "100"
        machine.fail("getent group briggs")

    with subtest("files keep their owner across the handover"):
        assert machine.succeed("stat -c %U /home/hacktop/inherited").strip() == "briggs"

    with subtest("the account is actually usable, not just present"):
        # wheel + a real password hash. `!` or `*` in shadow would pass every
        # check above and still leave sudo unusable.
        assert "wheel" in machine.succeed("id -nG briggs")
        machine.succeed("getent shadow briggs | cut -d: -f2 | grep -q '^\\$y\\$'")
        machine.succeed("echo ${password} | su briggs -c 'sudo -S true'")

    with subtest("deploy lands on its pinned 1001, beside briggs"):
        # Both accounts are allocated in the same activation, so this also covers
        # briggs claiming 1000 pushing deploy somewhere new.
        assert "deploy:x:1001:" in machine.succeed("getent passwd deploy")

    with subtest("switching again changes nothing"):
        # Colmena re-applies the same closure routinely. A migration that only
        # works once - or that renumbers on every run - would show up here.
        machine.succeed(f"{switch} test >&2")
        assert "briggs:x:1000:" in machine.succeed("getent passwd briggs")
        assert "deploy:x:1001:" in machine.succeed("getent passwd deploy")
  '';
}
