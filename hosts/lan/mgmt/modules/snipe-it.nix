# Snipe-IT - asset/inventory management at https://assets.mgmt.lan.
# The module manages its own mysql and nginx vhost; first-run setup
# wizard creates the admin account.
_:

{
  services.snipe-it = {
    enable = true;
    hostName = "assets.mgmt.lan";
    appKeyFile = "/var/lib/mgmt-secrets/snipeit-app-key";
    database.createLocally = true;
    nginx = {
      forceSSL = true;
      enableACME = true;
    };
  };

  systemd.services.snipeit-app-key = {
    description = "Generate Snipe-IT Laravel APP_KEY";
    wantedBy = [ "multi-user.target" ];
    before = [ "snipe-it-setup.service" ];
    requiredBy = [ "snipe-it-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # 711: service users must traverse to their own key files
      mkdir -p /var/lib/mgmt-secrets
      chmod 711 /var/lib/mgmt-secrets
      f=/var/lib/mgmt-secrets/snipeit-app-key
      if [ ! -f "$f" ]; then
        umask 077
        printf 'base64:%s' "$(head -c 32 /dev/urandom | base64 -w0)" > "$f"
      fi
      chown snipeit:snipeit "$f"
      chmod 400 "$f"
    '';
  };
}
