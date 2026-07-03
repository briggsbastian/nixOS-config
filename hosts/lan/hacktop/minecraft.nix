# hosts/lan/hacktop/minecraft.nix
#
# All the Mons (ATMons) modpack server (Minecraft 1.21.1, NeoForge 21.1.234).
# hacktop has the fleet's RAM headroom (32 GB, ~29 available), so the game
# server lives here alongside the CI runner.
#
# ATMons is a full CurseForge modpack (373 mods + KubeJS scripts), not the
# old AllTheMons-datapack-on-Cobblemon setup this replaced. Server side is
# fully declarative: nix-minecraft's offline NeoForge launcher plus the
# pack's official ServerFiles zip, unpacked into pinned store paths. Clients
# must run the matching "All the Mons 1.0.1" pack from the CurseForge app -
# a vanilla/Fabric client can no longer join.
#
# The old Fabric world is preserved at /srv/minecraft/allthemons on hacktop;
# this server starts fresh in /srv/minecraft/atmons.
#
# The ServerFiles zip is ~1 GB. The mediafilez URL is CurseForge's stable
# CDN; to avoid re-downloading when the store path gets GC'd, pre-seed from
# a local copy with: nix-store --add-fixed sha256 ServerFiles-1.0.1.zip
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  serverFiles = pkgs.fetchurl {
    # "All the Mons - ATMons" project 1356598, server pack file 8360747
    url = "https://mediafilez.forgecdn.net/files/8360/747/ServerFiles-1.0.1.zip";
    hash = "sha256-FXK/iFkcwAJJwnZTnzvmzvKb9a8YM6KZfpJjPHxtLck=";
  };

  # Unpack once at build time; the zip has no top-level directory. Only the
  # game content is kept - the bundled NeoForge installer and start scripts
  # are replaced by nix-minecraft's offline launcher.
  serverPack = pkgs.stdenvNoCC.mkDerivation {
    pname = "atmons-server-pack";
    version = "1.0.1";
    src = serverFiles;
    nativeBuildInputs = [ pkgs.unzip ];
    sourceRoot = ".";
    installPhase = ''
      mkdir -p $out
      cp -r config kubejs mods server-icon.png $out/
      # Crash Assistant is a client-side crash-report GUI; its required mixin
      # plugin dies at bootstrap on this setup (MixinInitialisationError for
      # crash_assistant.mixins.json) and crash-loops the server. Not needed
      # headless - drop it.
      rm $out/mods/CrashAssistant-neoforge-*.jar
    '';
  };
in
{
  imports = [ inputs.nix-minecraft.nixosModules.minecraft-servers ];
  nixpkgs.overlays = [ inputs.nix-minecraft.overlays.default ];

  services.minecraft-servers = {
    enable = true;
    eula = true;

    servers.atmons = {
      enable = true;
      # Pin the exact loader build the pack ships (see startserver.sh in the zip).
      package = pkgs.neoforgeServers.neoforge-1_21_1-21_1_234;
      openFirewall = true; # 25565/tcp - LAN only, hacktop is behind NAT

      # Heap bounds match the pack's user_jvm_args.txt; the G1 flags are the
      # pack-shipped (Aikar-style) tuning. 8 GB max still leaves >20 GB for
      # CI builds.
      jvmOpts = [
        "-Xms4G"
        "-Xmx8G"
        "-XX:+UseG1GC"
        "-XX:+ParallelRefProcEnabled"
        "-XX:MaxGCPauseMillis=200"
        "-XX:+UnlockExperimentalVMOptions"
        "-XX:+DisableExplicitGC"
        "-XX:+AlwaysPreTouch"
        "-XX:G1NewSizePercent=30"
        "-XX:G1MaxNewSizePercent=40"
        "-XX:G1HeapRegionSize=8M"
        "-XX:G1ReservePercent=20"
        "-XX:G1HeapWastePercent=5"
        "-XX:G1MixedGCCountTarget=4"
        "-XX:InitiatingHeapOccupancyPercent=15"
        "-XX:G1MixedGCLiveThresholdPercent=90"
        "-XX:G1RSetUpdatingPauseTimePercent=5"
        "-XX:SurvivorRatio=32"
        "-XX:+PerfDisableSharedMem"
        "-XX:MaxTenuringThreshold=1"
      ];

      # Pack-recommended settings from its startserver.sh, plus our motd.
      serverProperties = {
        # § is the Minecraft color-code marker (section sign); Java's
        # Properties parser decodes the escapes, giving each meow its own
        # color (red/gold/green/light-purple).
        motd = "\\u00A7cmeow \\u00A76meow \\u00A7ameow \\u00A7dmeow";
        difficulty = "normal";
        # Open to anyone: no whitelist by choice. Note the server is publicly
        # reachable via the cloud1 proxy, and its masquerade makes every
        # player 10.100.0.1 to us, so IP bans are meaningless - username
        # bans (/ban) are the only lever if someone misbehaves. Compensating
        # controls: Mojang auth pinned below, per-IP rate limit on cloud1,
        # daily world backups (minecraft-backup.nix), hardened unit.
        white-list = false;
        # Vanilla defaults to true, but only implicitly (the key was absent).
        # Pin it so no pack update or module change can ever silently turn
        # Mojang auth off - on an open public server that would mean anyone
        # could join as any username.
        online-mode = true;
        allow-flight = true;
        max-tick-time = 180000;
        simulation-distance = 5;
        view-distance = 8;
      };

      # Mods are fine read-only; NeoForge's config system rewrites files in
      # config/ at startup (and KubeJS can too), so those go in as writable
      # copies - refreshed from the store on every start, edits discarded.
      symlinks = {
        mods = "${serverPack}/mods";
        # Pancham beats the pack's stock icon. Must be exactly 64x64 PNG;
        # regenerate with: magick <src> -resize 64x64^ -gravity center
        # -extent 64x64 pancham-icon.png
        "server-icon.png" = ./pancham-icon.png;
      };
      files = {
        config = "${serverPack}/config";
        kubejs = "${serverPack}/kubejs";
      };
    };
  };

  # nix-minecraft's unit is already well sandboxed (CapabilityBoundingSet="",
  # PrivateUsers, ProtectHome, ...) but misses these two. Same rationale as
  # modules/media-hardening.nix: the JVM JIT needs W+X so MemoryDenyWriteExecute
  # stays off, and /srv must stay writable so "full" rather than "strict".
  # This closes the escalation path from a compromised modpack (373 mods +
  # KubeJS all execute arbitrary code as the minecraft user) toward the
  # root-owned CI runner token and WireGuard key on this box.
  systemd.services.minecraft-server-atmons.serviceConfig = {
    NoNewPrivileges = true;
    ProtectSystem = "full";
  };
}
