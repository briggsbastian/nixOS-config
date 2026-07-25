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

  # network-online.target is reached before a route to the NAS actually exists.
  # Measured on the 2026-07-25 reboot: online at 18.13s, mount attempted at
  # 18.39s, failed with ENETUNREACH - which mount.nfs treats as fatal and does
  # NOT retry, unlike a timeout. Every service with RequiresMountsFor=/mnt/media
  # then had its start job cancelled ('result: dependency'), and because a
  # cancelled job is not a failed service, Restart= cannot bring them back. The
  # whole *arr stack stayed down until something touched the mountpoint two
  # minutes later and the automount quietly succeeded.
  #
  # So wait for the NAS to actually answer before letting the mount be attempted.
  systemd.services.wait-for-nas = {
    description = "Wait until the NAS answers before mounting /mnt/media";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.iputils ];
    script = ''
      for _ in $(seq 1 60); do
        if ping -c1 -W1 192.168.1.213 >/dev/null 2>&1; then
          exit 0
        fi
        sleep 1
      done
      echo "NAS 192.168.1.213 did not answer within 60s" >&2
      exit 1
    '';
  };

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
      # See wait-for-nas above: _netdev alone orders after network-online.target,
      # which is not the same thing as the NAS being reachable.
      "x-systemd.requires=wait-for-nas.service"
      "x-systemd.after=wait-for-nas.service"
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
      # stale ScriptDir=/home/media/downloads/scripts persisted in
      # /var/lib/nzbget/nzbget.conf from before the NAS layout migration;
      # undeclared settings aren't overridden by the nixos module, and
      # ProtectHome (media-hardening.nix) hides /home from the sandboxed
      # service, so nzbget got Permission denied instead of just missing it
      ScriptDir = "/var/lib/nzbget/scripts";
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

  # Recyclarr: daily oneshot that syncs TRaSH-guide quality definitions,
  # custom formats and quality profiles into Sonarr (WEB-1080p) and Radarr
  # (HD Bluray+WEB, plus Remux+WEB 2160p for the remux collection). Clones the
  # trash-guides/config-templates repos from GitHub on every sync. API keys
  # come from sops via systemd LoadCredential; the recyclarr user never reads
  # the root-owned secret files directly.
  #
  # The NOTE that used to live here predicted this and was right: recyclarr 8.x
  # removed `include.template` entirely. Upstream's includes.json is now
  # `{"radarr": [], "sonarr": []}` and no includes/ directory ships at all, so
  # every one of the eight templates below was dead - not just the one recyclarr
  # named. It fails fast on the first unresolvable include, which made the error
  # look like a single renamed template rather than a removed mechanism.
  #
  # The bump landed 2026-07-12 and the sync failed every night through
  # 2026-07-25 without anyone noticing, because a oneshot that exits non-zero
  # produces no alert. Covered now by the SystemdUnitFailed rule.
  #
  # What the includes did is expressed directly in the v8 schema:
  #   quality-definition-*  ->  quality_definition.type
  #   quality-profile-*     ->  quality_profiles[].trash_id
  #   custom-formats-*      ->  custom_format_groups; the standard groups sync
  #                             by default, so only extras need naming here.
  # trash_ids still resolve against the live guide, so format scores keep
  # tracking upstream - only the config skeleton is pinned.
  sops.secrets.sonarr_api_key.sopsFile = ../../../secrets/media.yaml;
  sops.secrets.radarr_api_key.sopsFile = ../../../secrets/media.yaml;
  services.recyclarr = {
    enable = true;
    configuration = {
      # instance names must be unique across the sonarr AND radarr sections
      sonarr.tv = {
        base_url = "http://127.0.0.1:8989";
        api_key._secret = config.sops.secrets.sonarr_api_key.path;
        quality_definition.type = "series";
        quality_profiles = [
          {
            trash_id = "72dae194fc92bf828f32cde7744e51a1"; # WEB-1080p
            reset_unmatched_scores.enabled = true;
          }
        ];
        custom_format_groups.add = [
          {
            trash_id = "59c3af66780d08332fdc64e68297098f"; # [Unwanted] Unwanted Formats
            select = [
              "15a05bc7c1a36e2b57fd628f8977e2fc" # AV1
              "32b367365729d530ca1c124a0b180c64" # Bad Dual Groups
              "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
              "6f808933a71bd9666531610cb8c059cc" # BR-DISK (BTN)
              "fbcb31d8dabd2a319072b84fc0b7249c" # Extras
              "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
              "e2315f990da2e2cbfc9fa5b7a6fcfe48" # LQ (Release Title)
              "23297a736ca77c0fc8e70f8edd7ee56c" # Upscaled
            ];
          }
        ];
      };
      radarr.movies = {
        base_url = "http://127.0.0.1:7878";
        api_key._secret = config.sops.secrets.radarr_api_key.path;
        quality_definition.type = "movie";
        # Both profiles live on the one instance, as they did before.
        quality_profiles = [
          {
            trash_id = "d1d67249d3890e49bc12e275d989a7e9"; # HD Bluray + WEB
            reset_unmatched_scores.enabled = true;
          }
          {
            trash_id = "fd161a61e3ab826d3a22d53f935696dd"; # Remux + WEB 2160p
            reset_unmatched_scores.enabled = true;
          }
        ];
        # Deliberately no Golden Rule group. Upstream ships two variants - HD
        # selects x265 (HD), UHD selects x265 (no HDR/DV) - and in v8
        # custom_format_groups is per INSTANCE, not per profile. With both
        # profiles on one instance the two contradict, so neither is applied
        # rather than silently picking one. Split the instance if you want it.
        custom_format_groups.add = [
          {
            trash_id = "a3ac6af01d78e4f21fcb75f601ac96df"; # [Unwanted] Unwanted Formats
            select = [
              "b8cd450cbfa689c0259a01d9e29ba3d6" # 3D
              "cae4ca30163749b891686f95532519bd" # AV1
              "b6832f586342ef70d9c128d40c07b872" # Bad Dual Groups
              "cc444569854e9de0b084ab2b8b1532b2" # Black and White Editions
              "ed38b889b31be83fda192888e2286d83" # BR-DISK
              "0a3f082873eb454bde444150b70253cc" # Extras
              "e6886871085226c3da1830830146846c" # Generated Dynamic HDR
              "90a6f9a284dff5103f6346090e6280c8" # LQ
              "e204b80c87be9497a8a6eaff48f72905" # LQ (Release Title)
              "712d74cd88bceb883ee32f773656b1f5" # Sing-Along Versions
              "bfd8eb01832d646a0a89c4deb46f8564" # Upscaled
            ];
          }
        ];
      };
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
    jellyfin = {
      unitConfig.RequiresMountsFor = [ "/mnt/media" ];
      # render group for /dev/dri/renderD128 (QSV); on the unit rather than
      # the media user so the switch restarts jellyfin and picks it up
      serviceConfig.SupplementaryGroups = [ "render" ];
    };
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
