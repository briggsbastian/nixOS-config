# mgmt server - DNS filtering, reverse proxy, SIEM, monitoring
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/base.nix
    ./modules/step-ca.nix
    ./modules/adguard.nix
    ./modules/nginx.nix
    ./modules/monitoring.nix
    ./modules/netbox.nix
    ./modules/forgejo.nix
    ./modules/ntopng.nix
    ./modules/harmonia.nix
    ./modules/netboot.nix
    ./modules/snipe-it.nix
    ./modules/backup.nix
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  networking.hostName = "mgmt";
  networking.networkmanager.enable = true;
  # stop NetworkManager taking the DHCP hostname, else logs show "nixos"
  networking.networkmanager.settings.main.hostname-mode = "none";

  # This box serves DNS for the whole LAN - it must keep 192.168.1.222.
  # Preferred: add a DHCP reservation on the router. Alternatively go static:
  # networking.networkmanager.enable = lib.mkForce false;
  # networking.interfaces.eno1.ipv4.addresses = [ { address = "192.168.1.222"; prefixLength = 24; } ];
  # networking.defaultGateway = "192.168.1.1";
  # networking.nameservers = [ "127.0.0.1" "9.9.9.9" ];

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.mgmt = {
    isNormalUser = true;
    description = "mgmt";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
  };

  # mgmt skips common.nix, so wire sops here (for the grafana password below)
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # central log + alerting server
  sops.secrets.grafana_admin_password = {
    sopsFile = ../../../secrets/mgmt.yaml;
    owner = "grafana";
  };
  alcove.siemLite.server = {
    enable = true;
    grafanaAdminPasswordFile = config.sops.secrets.grafana_admin_password.path;
    alertmanagerExternalUrl = "https://alerts.mgmt.lan"; # vhost in nginx.nix
    # alerts go to ntfy.mgmt.lan/homelab-alerts (subscribe a phone there)
  };

  system.stateVersion = "25.11";
}
