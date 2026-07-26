# tests/audit.nix
#
# Prove the audit pipeline works end to end INSIDE the box: rules load, the
# kernel emits events when the watched files are touched, and journald actually
# receives them.
#
# This test exists because every part of that chain fails silently. Audit rules
# that fail to parse leave the others loaded and log a line nobody reads. A
# watch on a path that turns out to be a symlink fires on nothing. And if
# systemd-journald-audit.socket is not running, the kernel emits events into a
# void - no error, no dropped-message counter anyone looks at, and `security.audit.enable = true`
# still evaluates, builds and deploys perfectly.
#
# That last one is the specific failure this estate has produced repeatedly:
# telemetry that is configured correctly, reports healthy, and is connected to
# nothing. Asserting "the rule is in the config" would reproduce it exactly, so
# the assertions here are all against runtime behaviour.
#
# It imports the REAL modules/audit.nix rather than restating its rules, so a
# change to the default ruleset is covered by this test rather than drifting
# away from it.
{ pkgs, ... }:

pkgs.testers.runNixOSTest {
  name = "audit";

  nodes.machine = {
    imports = [ ../modules/audit.nix ];
    alcove.audit.enable = true;

    # Mutable users so /etc/shadow and /etc/passwd are real files the test can
    # write to, matching mgmt and cloud1 where this actually runs.
    users.mutableUsers = true;
  };

  testScript = ''
    import re

    machine.wait_for_unit("multi-user.target")

    with subtest("the kernel audit subsystem is actually enabled"):
        # Via auditctl, not /proc/sys/kernel/audit_enabled - that path does not
        # exist. Reading it returns empty, and `test  -eq 1` then fails with a
        # shell syntax error rather than a useful one, so a naive version of
        # this check reports "audit is off" on a box where audit is fine.
        status = machine.succeed("auditctl -s")
        assert "enabled 1" in status, f"audit not enabled:\n{status}"

    with subtest("journald is listening for audit events"):
        # Without this socket the kernel emits into a void. Nothing errors.
        machine.succeed("systemctl is-active systemd-journald-audit.socket")

    with subtest("every rule loaded - not just some of them"):
        loaded = machine.succeed("auditctl -l")
        # auditctl reports watches as -w paths and syscall rules separately.
        for path in ["/etc/shadow", "/etc/passwd", "/etc/group",
                     "/etc/sudoers", "/etc/ssh/authorized_keys.d"]:
            assert path in loaded, f"watch missing from loaded ruleset: {path}\n{loaded}"
        assert "init_module" in loaded, f"module-loading rule not loaded:\n{loaded}"

    with subtest("rate and backlog limits took effect"):
        status = machine.succeed("auditctl -s")
        assert "rate_limit 100" in status, status
        assert "backlog_limit 8192" in status, status

    with subtest("touching a watched file produces an event IN THE JOURNAL"):
        # The whole point: not "auditctl says the rule exists" but "the event
        # reaches the log pipeline". Alloy ships the journal, so if it lands
        # here it lands in Loki.
        machine.succeed("touch /etc/shadow")
        machine.wait_until_succeeds(
            "journalctl --no-pager | grep -q 'key=\"identity\"'", timeout=30
        )

    with subtest("the file that was touched is identifiable"):
        # The key and the filename are NOT on the same line. Audit emits a
        # group of records per event: SYSCALL carries key="identity", PATH
        # carries name="/etc/shadow", and they are tied together only by the
        # serial in audit(TIMESTAMP:SERIAL). A detection matching key= alone
        # tells you an identity file changed but not which one - which is the
        # kind of gap that only shows up while you are reading an alert at 3am.
        out = machine.succeed(
            "journalctl --no-pager | grep -E 'audit\\(' | grep -c 'shadow'"
        )
        assert int(out.strip()) > 0, "no audit record names /etc/shadow at all"

        # And prove the correlation is possible: the SYSCALL record carrying the
        # key, and the PATH record naming the file, share an audit serial.
        keyed = machine.succeed(
            "journalctl --no-pager | grep 'key=\"identity\"' | tail -3"
        )
        named = machine.succeed(
            "journalctl --no-pager | grep -E 'audit\\(' | grep shadow | tail -3"
        )
        serials_keyed = set(re.findall(r"audit\([0-9.]+:([0-9]+)\)", keyed))
        serials_named = set(re.findall(r"audit\([0-9.]+:([0-9]+)\)", named))
        shared = serials_keyed & serials_named
        assert shared, (
            "no audit serial links a keyed record to one naming the file.\n"
            f"keyed serials: {sorted(serials_keyed)}\n{keyed}\n"
            f"named serials: {sorted(serials_named)}\n{named}"
        )

    with subtest("ssh trust changes are caught"):
        machine.succeed("mkdir -p /etc/ssh/authorized_keys.d")
        machine.succeed("touch /etc/ssh/authorized_keys.d/testuser")
        machine.wait_until_succeeds(
            "journalctl --no-pager | grep -q 'key=\"ssh_trust\"'", timeout=30
        )

    with subtest("an unwatched path produces nothing"):
        # Guards against a rule so broad it matches everything, which would
        # look like working detection while burying the signal.
        machine.succeed("mkdir -p /tmp/unwatched && touch /tmp/unwatched/file")
        machine.fail("journalctl --no-pager | grep -q '/tmp/unwatched/file'")
  '';
}
