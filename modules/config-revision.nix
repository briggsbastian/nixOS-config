# modules/config-revision.nix
#
# Every host publishes which git revision it was built from, as a Prometheus
# textfile metric. mgmt publishes what the revision *should* be (read straight
# off Forgejo's bare repo on the same box), and an alert compares the two.
#
# That is the whole drift detector, and it deliberately needs no SSH, no agent
# and no new credentials - the fleet already scrapes node_exporter, and
# system.configurationRevision is stamped into every build by flake.nix. The
# `isc` tool remains the on-demand, exact-closure comparison; this is the
# always-on one that pages.
#
# Why it exists: on 2026-07-24 four separate outages traced to the same cause -
# config written, deployed to one host, never committed or applied to the other.
# cloud1 sat six days behind with a half-configured WireGuard tunnel and nothing
# said so. This makes that condition impossible to keep not noticing.
#
# Imported by modules/common.nix (fleet) and by mgmtModules in flake.nix, since
# mgmt deliberately skips common.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.alcove.configRevision;
  # "unknown" only if flake.nix's mkVersionInfo somehow did not apply; a dirty
  # working tree yields "<sha>-dirty", which will never match the expected
  # revision - deliberately, since a system built from an uncommitted tree is
  # not reproducible from the repo and that is worth being told about.
  revision =
    if config.system.configurationRevision != null then
      config.system.configurationRevision
    else
      "unknown";
in
{
  options.alcove.configRevision = {
    enable =
      (lib.mkEnableOption "publishing this host's built-from git revision as a node_exporter textfile metric")
      // {
        default = true;
      };

    textfileDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/node-exporter-textfile";
      description = "node_exporter textfile collector directory (must match its --collector.textfile.directory).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [ "d ${cfg.textfileDir} 0755 root root -" ];

    systemd.services.nixos-config-revision = {
      description = "Publish this host's config revision as a Prometheus metric";
      wantedBy = [ "multi-user.target" ];
      # The script embeds the revision, so activation restarts this unit exactly
      # when the revision changes - no timer needed, the value only moves on a
      # deploy or a reboot.
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      path = [ pkgs.coreutils ];
      script = ''
        set -euo pipefail
        # A reboot is only actually REQUIRED when the booted kernel, initrd or
        # kernel modules differ from the activated ones. Comparing the system
        # paths themselves (booted != current) is wrong: that is true after any
        # switch at all, so it would fire on every host after every deploy - an
        # alert that is always on is not an alert.
        pending=0
        for part in kernel initrd kernel-modules; do
          b=$(readlink "/run/booted-system/$part" 2>/dev/null || echo "")
          c=$(readlink "/run/current-system/$part" 2>/dev/null || echo "")
          if [ -n "$b" ] && [ -n "$c" ] && [ "$b" != "$c" ]; then
            pending=1
          fi
        done

        tmp=$(mktemp "${cfg.textfileDir}/.nixos_config_revision.XXXXXX")
        {
          echo '# HELP nixos_configuration_revision_info Git revision of the flake this system was built from.'
          echo '# TYPE nixos_configuration_revision_info gauge'
          echo 'nixos_configuration_revision_info{revision="${revision}"} 1'
          echo '# HELP nixos_reboot_pending Activated configuration differs from the booted one.'
          echo '# TYPE nixos_reboot_pending gauge'
          echo "nixos_reboot_pending $pending"
        } > "$tmp"
        chmod 0644 "$tmp"
        mv "$tmp" "${cfg.textfileDir}/nixos_config_revision.prom"
      '';
    };
  };
}
