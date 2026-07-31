# Budget tracker — paycheck-aware fixed-cost planner, fronted by nginx at
# https://budget.mgmt.lan (vhost in nginx.nix). The app listens on localhost
# only; it has no authentication of its own, so the reverse proxy is the
# boundary. Source + package come from the `budget-tracker` flake input
# (git.mgmt.lan/briggs/budgettracker); bump it with
# `nix flake update budget-tracker` then `colmena apply --on mgmt`.
#
# Its SQLite database is snapshotted nightly into
# /var/lib/budget-tracker/backup, which backup.nix collects. The snapshot
# exists because the database runs in WAL mode: tarring budget.db without its
# -wal sidecar captures an incomplete database and says nothing about it.
{ inputs, ... }:

{
  imports = [ inputs.budget-tracker.nixosModules.default ];

  services.budget-tracker = {
    enable = true;
    address = "127.0.0.1"; # nginx terminates TLS and proxies; don't expose directly
    port = 8378;
    openFirewall = false; # reached only via the nginx vhost

    # Decides what the app considers "today", which decides which pay period is
    # current. Stored dates are naive, so this only affects the boundary.
    timezone = "America/Denver";

    # SvelteKit compares this against the Origin header on every form POST.
    # Behind a TLS-terminating proxy it MUST be the external URL: unset, the
    # adapter assumes https://<listen address> and rejects every submission as
    # cross-site while GETs keep working — so the app looks healthy and is
    # entirely unusable.
    origin = "https://budget.mgmt.lan";

    # 03:00 leaves the snapshot in place before mgmt-backup runs at 03:30.
    backup = {
      enable = true;
      time = "03:00";
      keep = 7;
    };
  };
}
