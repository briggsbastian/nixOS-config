# modules/audit.nix
#
# Kernel audit telemetry, opt-in per host via alcove.audit.enable.
#
# Why the kernel audit subsystem and NOT the auditd daemon:
#
#   systemd-journald-audit.socket is already active on this estate, so audit
#   events land in the journal, which Alloy already ships to Loki. That is the
#   whole pipeline - no daemon, no /var/log/audit/audit.log, no logrotate, no
#   second loki.source.file, no new failure mode.
#
#   The cost, named honestly: no ausearch/aureport against a local file. In
#   exchange the events are queryable in LogQL across the whole fleet from one
#   place, which suits an estate of five hosts better than per-box forensics.
{
  config,
  lib,
  ...
}:

let
  cfg = config.alcove.audit;
in
{
  options.alcove.audit = {
    enable = lib.mkEnableOption "kernel audit telemetry (journald -> Loki)";

    rules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Identity and credentials. These are REAL files on NixOS, not symlinks
        # into the store, so a watch on the path sees the content change.
        # Activation rewrites them, so expect one burst per deploy - which is
        # itself worth seeing, since an identity file changing outside a deploy
        # is the interesting case.
        "-w /etc/shadow -p wa -k identity"
        "-w /etc/passwd -p wa -k identity"
        "-w /etc/group -p wa -k identity"
        "-w /etc/sudoers -p wa -k identity"

        # Who is allowed to log in. Real directory on both target hosts.
        "-w /etc/ssh/authorized_keys.d -p wa -k ssh_trust"

        # Kernel module loading: rootkits and unsigned drivers. Near-zero volume
        # on a steady-state NixOS box, and there is no benign reason for this to
        # fire between deploys.
        "-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k modules"
      ];
      description = ''
        Audit rules, in auditctl syntax.

        Deliberately does NOT include a blanket execve rule, which is the first
        thing most audit guides reach for. Measured fork rates before deciding:

          mgmt      ~97,200 processes/day
          cloud1    ~21,600 processes/day

        The entire fleet journal is ~66,000 lines/day after the noise drop in
        the siem-lite agent. A blanket `-S execve` on mgmt alone would produce
        more events than every other log source on the estate combined, and
        would undo that work within a day. Process-execution auditing is worth
        having, but it needs to be scoped to something narrower than "all of
        it", and that scoping should follow a measurement rather than a habit.

        Watching /etc/ssh/sshd_config or /etc/systemd/system is likewise
        omitted: both are symlinks into /etc/static and thence the store, so a
        watch sees the link swap at deploy time and nothing else. Their real
        contents are already under Git, which is a better control than a file
        watch that only fires when Nix rewrites it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The kernel subsystem, not the daemon. auditd would take over the netlink
    # socket and journald would stop receiving events entirely - so enabling it
    # would silently REMOVE this telemetry from Loki while appearing to add it.
    security.audit = {
      enable = true;
      inherit (cfg) rules;

      # A cap, so a rule that turns out to be far chattier than expected costs
      # throughput rather than taking the box or the log pipeline down with it.
      # 100/s is roughly 8.6M/day - far above anything these rules should ever
      # produce, and far below what would hurt.
      rateLimit = 100;

      # Default is 64, which is small enough to drop events during a burst
      # (every deploy rewrites the identity files this watches). Dropped audit
      # events are invisible by definition, which is the failure mode this
      # project keeps finding.
      backlogLimit = 8192;
    };

    # Explicit rather than relied upon. Without this socket the kernel emits
    # audit events into a void: nothing collects them, no error is raised, and
    # every check short of querying Loki still looks correct.
    systemd.sockets.systemd-journald-audit.wantedBy = [ "sockets.target" ];
  };
}
