# NetBox - IPAM / network documentation at https://netbox.mgmt.lan.
# The module provisions postgres and a dedicated redis instance itself.
# First admin: sudo -u netbox netbox-manage createsuperuser
{ config, pkgs, ... }:

{
  # netbox-4.5 upgrade (one-way DB migration, runs automatically in the
  # package's preStart on first start with the new package). Pre-migration
  # backup: services.postgresqlBackup below dumps `netbox` nightly, and gets
  # picked up into the encrypted off-box backup in backup.nix.
  sops.secrets.netbox_api_token_pepper = {
    sopsFile = ../../../../secrets/mgmt.yaml;
    owner = "netbox";
  };

  services.netbox = {
    enable = true;
    package = pkgs.netbox_4_5;
    listenAddress = "127.0.0.1";
    port = 8001;
    secretKeyFile = "/var/lib/mgmt-secrets/netbox-secret";
    apiTokenPeppersFile = config.sops.secrets.netbox_api_token_pepper.path;
    settings.ALLOWED_HOSTS = [ "netbox.mgmt.lan" ];
  };

  # nightly netbox DB dump, folded into backup.nix's encrypted off-box backup
  services.postgresqlBackup = {
    enable = true;
    databases = [ "netbox" ];
    startAt = "*-*-* 03:00:00"; # before mgmt-backup's 03:30 tar
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
