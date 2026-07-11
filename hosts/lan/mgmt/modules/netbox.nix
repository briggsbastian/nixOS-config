# NetBox - IPAM / network documentation at https://netbox.mgmt.lan.
# The module provisions postgres and a dedicated redis instance itself.
# First admin: sudo -u netbox netbox-manage createsuperuser
{ pkgs, ... }:

{
  # TODO(netbox-4.5): 26.05 flags netbox 4.4 insecure, but 4.5 is a one-way DB
  # migration AND requires services.netbox.apiTokenPeppersFile (new assertion).
  # Deferred to its own window: back up the netbox postgres DB, add a pepper
  # secret to secrets/mgmt.yaml, set package = pkgs.netbox_4_5, drop this allow.
  # LAN-only exposure behind nginx in the meantime.
  nixpkgs.config.permittedInsecurePackages = [ "netbox-4.4.10" ];

  services.netbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 8001;
    secretKeyFile = "/var/lib/mgmt-secrets/netbox-secret";
    settings.ALLOWED_HOSTS = [ "netbox.mgmt.lan" ];
  };

  systemd.services.netbox-secret = {
    description = "Generate NetBox secret key";
    wantedBy = [ "multi-user.target" ];
    before = [
      "netbox.service"
      "netbox-rq.service"
    ];
    requiredBy = [
      "netbox.service"
      "netbox-rq.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # 711: service users must traverse to their own key files
      mkdir -p /var/lib/mgmt-secrets
      chmod 711 /var/lib/mgmt-secrets
      f=/var/lib/mgmt-secrets/netbox-secret
      if [ ! -f "$f" ]; then
        umask 077
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 50 > "$f"
      fi
      chown netbox:netbox "$f"
      chmod 400 "$f"
    '';
  };

  # nginx serves netbox's collected static files directly (see nginx.nix)
  users.users.nginx.extraGroups = [ "netbox" ];
}
