# Arr media stack: Prowlarr, Sonarr, Radarr, Bazarr, Jellyfin, NZBGet
#
# Carried verbatim from the live media box. All media data lives on the NAS
# (192.168.1.213), NFS-mounted at /mnt/media. Services run as the "media" user
# off that mount:
#
#   /mnt/media/                    (NAS: /srv/media, 916G)
#   |-- data/nzbget/               # NZBGet completed (tv/movies cats) + queue/nzbs;
#   |                              # write-hot inter/tmp dirs are local, see below
#   `-- Media/                     # TV (Sonarr), Movies (Radarr), Books, etc.

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # ---------- NAS mount ----------
  boot.supportedFilesystems = [ "nfs" ];

  fileSystems."/mnt/media" = {
    device = "192.168.1.213:/srv/media";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "noatime"
      # don't hang boot if the NAS is down; mount on first access
      "nofail"
      "x-systemd.automount"
      "_netdev"
    ];
  };

  # ---------- services ----------
  services.prowlarr = {
    enable = true;
    openFirewall = true; # 9696
  };

  services.sonarr = {
    enable = true;
    user = "media";
    group = "users";
    openFirewall = true; # 8989
  };

  services.radarr = {
    enable = true;
    user = "media";
    group = "users";
    openFirewall = true; # 7878
  };

  services.bazarr = {
    enable = true;
    user = "media";
    group = "users";
    openFirewall = true; # 6767
  };

  services.jellyfin = {
    enable = true;
    user = "media";
    group = "users";
    openFirewall = true; # 8096 (http), 8920 (https), discovery ports
  };

  services.nzbget = {
    enable = true;
    user = "media";
    group = "users";
    settings = {
      # completed files, queue state, and nzbs stay on the NAS; the write-hot
      # intermediate/temp dirs live on the local ext4 root (468G) so download,
      # par-repair, and unpack don't run over NFS — data crosses the wire once,
      # at unpack into DestDir
      MainDir = "/mnt/media/data/nzbget";
      DestDir = "/mnt/media/data/nzbget/completed";
      InterDir = "/var/lib/nzbget/intermediate";
      NzbDir = "/mnt/media/data/nzbget/nzb";
      QueueDir = "/mnt/media/data/nzbget/queue";
      TempDir = "/var/lib/nzbget/tmp";
      ControlIP = "0.0.0.0";
      ControlPort = 6789;
      # throughput: Eweka allows 50 SSL connections; 8 was the bottleneck.
      # 50 (provider max) because the ~160ms RTT to NL caps each connection low.
      # Cache+buffer assemble articles in RAM (box has 16G) instead of small
      # NFS writes; direct rename/unpack overlap post-processing with download.
      "Server1.Connections" = 50;
      ArticleCache = 500;
      WriteBuffer = 1024;
      DirectRename = "yes";
      DirectUnpack = "yes";
      # hygiene: pause before the local intermediate disk actually fills;
      # bigger par2 verify buffer (box has 16G); delete unrepairable downloads
      # so Sonarr/Radarr's failed-download handling grabs a replacement instead
      # of parking them for manual repair
      DiskSpace = 10240;
      ParBuffer = 256;
      HealthCheck = "Delete";
      "Category1.Name" = "tv";
      "Category1.DestDir" = "/mnt/media/data/nzbget/completed/tv";
      "Category2.Name" = "movies";
      "Category2.DestDir" = "/mnt/media/data/nzbget/completed/movies";
    };
  };

  # Kavita: books/comics/manga reader. Library on the NAS under
  # /mnt/media/Media/{Books,Comics,Audiobooks}; add those in the web UI on first
  # run. JWT signing key from sops.
  sops.secrets.kavita_token_key.sopsFile = ../../../secrets/media.yaml;
  services.kavita = {
    enable = true;
    tokenKeyFile = config.sops.secrets.kavita_token_key.path;
    settings.Port = 5000;
  };
  # let kavita read the media group's files on the NFS share
  users.users.kavita.extraGroups = [ "users" ];

  # NZBGet + Kavita have no openFirewall option
  networking.firewall.allowedTCPPorts = [
    6789
    5000
  ];

  # Every service that touches media data must wait for the NAS mount;
  # arrs start after the download client and indexer
  systemd.services = {
    nzbget.unitConfig.RequiresMountsFor = [ "/mnt/media" ];
    jellyfin.unitConfig.RequiresMountsFor = [ "/mnt/media" ];
    kavita.unitConfig.RequiresMountsFor = [ "/mnt/media" ];
    sonarr = {
      unitConfig.RequiresMountsFor = [ "/mnt/media" ];
      after = [
        "nzbget.service"
        "prowlarr.service"
      ];
    };
    radarr = {
      unitConfig.RequiresMountsFor = [ "/mnt/media" ];
      after = [
        "nzbget.service"
        "prowlarr.service"
      ];
    };
    bazarr = {
      unitConfig.RequiresMountsFor = [ "/mnt/media" ];
      after = [
        "sonarr.service"
        "radarr.service"
      ];
    };
  };
}
