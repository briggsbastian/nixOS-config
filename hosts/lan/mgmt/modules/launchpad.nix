# Animated launchpad prototype at https://launchpad.mgmt.lan - a static
# canvas-particle (matrix rain) landing page mirroring the tiles in the
# Homepage dashboard (monitoring.nix), served from its own vhost so the
# existing dashboard at mgmt.lan/home.mgmt.lan stays untouched while this
# is evaluated. If it sticks, a later change repoints mgmt.lan/home.mgmt.lan
# here and retires services.homepage-dashboard.
_:

{
  services.nginx.virtualHosts."launchpad.mgmt.lan" = {
    forceSSL = true;
    enableACME = true;
    root = ./launchpad/site;
  };
}
