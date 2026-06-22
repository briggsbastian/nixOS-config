# Forgejo git server at https://git.mgmt.lan (builtin SSH on port 2222).
# Registration is closed; create the first admin with:
#   sudo -u forgejo sh -c 'GITEA_WORK_DIR=/var/lib/forgejo \
#     forgejo --config /var/lib/forgejo/custom/conf/app.ini \
#     admin user create --username briggs --random-password \
#     --email admin@mgmt.lan --admin'
{ ... }:

{
  services.forgejo = {
    enable = true;
    lfs.enable = true;
    settings = {
      server = {
        DOMAIN = "git.mgmt.lan";
        ROOT_URL = "https://git.mgmt.lan/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3004;
        START_SSH_SERVER = true;
        SSH_PORT = 2222;
        SSH_LISTEN_PORT = 2222;
      };
      service.DISABLE_REGISTRATION = true;
      session.COOKIE_SECURE = true;
    };
  };

  networking.firewall.allowedTCPPorts = [ 2222 ];
}
