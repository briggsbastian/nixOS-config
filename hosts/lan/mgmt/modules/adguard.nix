# AdGuard Home: LAN DNS filtering, and answers *.mgmt.lan with this host so
# nginx can route by name. Web UI on localhost:3000 via https://adguard.mgmt.lan.
# Settings below are just the seed (mutableSettings = true) - manage it from the
# web UI once it's up.
_:

{
  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = 3000;
    mutableSettings = true;
    settings = {
      # No admin login here on purpose: a bcrypt hash in a public repo is
      # crackable. With mutableSettings, set/rotate the admin in the web UI;
      # seed hash lives in sops (secrets/mgmt.yaml: adguard_password).
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "https://dns.quad9.net/dns-query"
          "9.9.9.9"
          "1.1.1.1"
        ];
        bootstrap_dns = [
          "9.9.9.9"
          "1.1.1.1"
        ];
      };
      # "enabled" must be explicit; AdGuard defaults a missing field to false
      filtering.rewrites = [
        {
          domain = "mgmt.lan";
          answer = "192.168.1.222";
          enabled = true;
        }
        {
          domain = "*.mgmt.lan";
          answer = "192.168.1.222";
          enabled = true;
        }
        # playground is a separate host (.217); exact name beats the
        # *.mgmt.lan wildcard, so it resolves to the box not mgmt.
        {
          domain = "playground.mgmt.lan";
          answer = "192.168.1.217";
          enabled = true;
        }
      ];
      filters = [
        {
          enabled = true;
          id = 1;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        }
      ];
    };
  };
}
