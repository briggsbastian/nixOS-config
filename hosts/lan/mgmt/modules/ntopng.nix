# ntopng - live network traffic analysis at https://ntop.mgmt.lan.
# Default login admin/admin (forced change on first visit).
# Binds 0.0.0.0:3003 (no bind-address option in the module) but the firewall
# doesn't open 3003, so it's only reachable through nginx.
# Without switch port mirroring it sees only traffic to/from this host -
# which includes every DNS query, since AdGuard lives here.
{ ... }:

{
  services.ntopng = {
    enable = true;
    interfaces = [ "eno1" ];
    httpPort = 3003;
  };
}
