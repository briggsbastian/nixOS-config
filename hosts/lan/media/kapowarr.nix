# Kapowarr — comic/manga download manager, Docker-based.
# Pairs with Kavita (already on this host) for a complete comics pipeline:
#   Kapowarr downloads/organizes → Kavita serves/reads.
# Library lives on the NAS under /mnt/media/Media/Comics; downloads are staged
# in a local temp dir so the NAS only sees the final renamed files.
{ config, pkgs, ... }:

{
  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers.kapowarr = {
    image = "mrcas/kapowarr:latest";
    ports = [ "5656:5656" ];
    volumes = [
      "kapowarr-db:/app/db"
      "/var/lib/kapowarr/temp_downloads:/app/temp_downloads"
      "/mnt/media/Media/Comics:/comics"
    ];
    environment = {
      PUID = "1000";
      PGID = "100";
      TZ = "America/Los_Angeles";
    };
  };

  # Kapowarr must wait for the NAS mount before it can see the Comics folder.
  systemd.services."container-kapowarr".unitConfig.RequiresMountsFor = [ "/mnt/media" ];
  systemd.services."container-kapowarr".after = [ "mnt-media.automount" ];

  # Local temp download dir (write-hot, stays off NFS).
  systemd.tmpfiles.rules = [
    "d /var/lib/kapowarr/temp_downloads 0755 media users -"
  ];

  # Firewall: Kapowarr listens on 5656.
  networking.firewall.allowedTCPPorts = [ 5656 ];
}
