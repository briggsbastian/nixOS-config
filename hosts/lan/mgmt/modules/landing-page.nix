# Landing page at https://mgmt.lan — single pane of glass for the fleet.
# Replaces the Homepage dashboard and Launchpad orbit page.
# Serves static HTML/CSS/JS; all data is fetched client-side via nginx-proxied
# APIs to Prometheus (:9090) and Alertmanager (:9093).
{ lib, ... }:

{
  services.nginx.virtualHosts."mgmt.lan" = {
    default = true;
    forceSSL = true;
    enableACME = true;
    root = ./landing-page/site;
    # Proxy Prometheus and Alertmanager APIs so the page can fetch them
    # over HTTPS from the same origin (no mixed-content or CORS issues).
    locations."/api/prometheus/" = {
      proxyPass = "http://127.0.0.1:9090/";
      proxyWebsockets = true;
    };
    locations."/api/alertmanager/" = {
      proxyPass = "http://127.0.0.1:9093/";
      proxyWebsockets = true;
    };
  };

  # Retire the old Homepage proxy — mgmt.lan is now served by this module.
  # home.mgmt.lan is removed from nginx.nix.
  services.homepage-dashboard.enable = lib.mkForce false;
}
