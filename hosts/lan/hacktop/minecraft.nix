# hosts/lan/hacktop/minecraft.nix
#
# All the Mons (ATMons) modpack server (Minecraft 1.21.1, NeoForge 21.1.248).
# hacktop has the fleet's RAM headroom (32 GB, ~29 available), so the game
# server lives here alongside the CI runner.
#
# ATMons is a full CurseForge modpack (375 mods + KubeJS scripts), not the
# old AllTheMons-datapack-on-Cobblemon setup this replaced. Server side is
# fully declarative: nix-minecraft's offline NeoForge launcher plus the
# pack's official ServerFiles zip, unpacked into pinned store paths. Clients
# must run the matching "All the Mons 1.2.0" pack from the CurseForge app -
# a vanilla/Fabric client can no longer join, and neither can a client still
# on 1.1.1.
#
# The old Fabric world is preserved at /srv/minecraft/allthemons on hacktop;
# this server starts fresh in /srv/minecraft/atmons.
#
# The ServerFiles zip is ~1 GB. The mediafilez URL is CurseForge's stable
# CDN; to avoid re-downloading when the store path gets GC'd, pre-seed from
# a local copy with: nix-store --add-fixed sha256 ServerFiles-1.2.0.zip
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  serverFiles = pkgs.fetchurl {
    # "All the Mons - ATMons" project 1356598, server pack file 8572602
    url = "https://mediafilez.forgecdn.net/files/8572/602/ServerFiles-1.2.0.zip";
    hash = "sha256-3hEu2NebP/An45mlEItwb2ots750sV0Ntva51qwmjmw=";
  };

  # Unpack once at build time; the zip has no top-level directory. Only the
  # game content is kept - the bundled NeoForge installer and start scripts
  # are replaced by nix-minecraft's offline launcher.
  serverPack = pkgs.stdenvNoCC.mkDerivation {
    pname = "atmons-server-pack";
    version = "1.2.0";
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

  # Role policy (ranks.snbt) and the /color command that drives it. Both are
  # generated from one colour list so the command's arguments and the ranks
  # backing them cannot drift apart. See those files for the whole rationale.
  atmonsRanks = import ./atmons-ranks.nix { inherit pkgs lib; };
  atmonsColor = import ./atmons-color.nix {
    inherit pkgs lib;
    inherit (atmonsRanks) combos;
  };

  # JVM GC/safepoint log target. Deliberately NOT under /srv/minecraft/atmons:
  # minecraft-backup.nix tars that whole directory nightly and keeps 14
  # encrypted copies on the NAS, so a log living there would ride along in
  # every one of them. See the -Xlog flag below for the rest of the rationale.
  gcLogDir = "/var/log/minecraft-atmons";

  # /color, merged into the pack's own kubejs tree.
  #
  # The pack DOES ship server_scripts (133 of them in 1.2.0, 130 in 1.1.1) -
  # an earlier version of this comment claimed it shipped none, which was
  # wrong even then. What makes /color safe is narrower and needs rechecking
  # at each pack update: no pack script is named atmons_color.js, and none
  # registers a "color" command (the only command they add is /wits, in
  # server_scripts/modpack/commands.js). So this is additive by filename and
  # by command name, not because the directory was empty.
  #
  # Merged into one store path rather than added as a second nested `files`
  # entry: that would depend on nix-minecraft applying "kubejs" before
  # "kubejs/server_scripts/...", which is true today only because attrset
  # iteration is sorted. This is order-independent.
  kubejsWithColor = pkgs.runCommand "atmons-kubejs" { } ''
    mkdir -p $out/server_scripts
    cp -r ${serverPack}/kubejs/. $out/
    chmod -R u+w $out
    cp ${atmonsColor} $out/server_scripts/atmons_color.js
  '';
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
      #
      # The `override` pins the JVM, and is load-bearing - do not drop it as
      # tidying. nix-minecraft used to leave `jre_headless` at the nixpkgs
      # default, which is Java 21; as of upstream bc289235 it instead inherits
      # the vanilla server's `java`, and that is `java_versions.getLatest 21` -
      # the newest JDK satisfying >=21, i.e. Java 25 today and climbing. The
      # same NeoForge build silently changed JVM across that bump:
      #
      #   nix-minecraft c8f946c9 -> openjdk-headless-21.0.12
      #   nix-minecraft bfab3c65 -> openjdk-25.0.4        (and not headless)
      #
      # NeoForge 21.1.x targets Java 21, and a 375-mod 1.21.1 pack is exactly
      # the workload that breaks on a newer class file version - Mixin refuses
      # class files it does not know, and JDK 24+ restricts the sun.misc.Unsafe
      # memory access that mods of this vintage still use. Nothing here needs a
      # newer JVM, so take the one the pack was built and tested against.
      package = pkgs.neoforgeServers.neoforge-1_21_1-21_1_248.override {
        jre_headless = pkgs.jdk21_headless;
      };
      openFirewall = true; # 25565/tcp - LAN only, hacktop is behind NAT

      # nix-minecraft defaults to tmux, which parks the console in a pane
      # systemd never sees: `journalctl -u minecraft-server-atmons` showed only
      # unit start/stop lines and not one line of game output. Since the Alloy
      # agent ships the journal to Loki, that left the fleet's log stack blind
      # at its only internet-facing service, and crash traces (see the
      # CrashAssistant note above) died with the process.
      #
      # With systemd-socket the server's stdout/stderr go to the journal and on
      # to Loki, and console input becomes a line-atomic write to a FIFO rather
      # than simulated keystrokes. Cost: no `tmux attach`. Read the console with
      # `journalctl -fu minecraft-server-atmons`, write to it with `mc-console
      # send` (mc-console.nix).
      #
      # NEVER write to the FIFO with a bare `>` redirect: if the socket unit is
      # down the shell creates a REGULAR FILE at that path, and the socket then
      # refuses to start, so the server never comes back. mc-console exists
      # precisely to make that unrepresentable.
      managementSystem = {
        tmux.enable = false;
        systemd-socket.enable = true;
      };

      # ops.json, as a store symlink. This makes in-game /op and /deop
      # non-durable: the module recreates the symlink at every ExecStartPre, so
      # the nightly restart (minecraft-restart.nix) reverts them. Ops live here
      # now.
      #
      # BANS ARE NOT AFFECTED. nix-minecraft only manages banned-players.json
      # when `bannedPlayers` is non-empty, and it is not set below - so
      # in-game /ban writes that file directly and survives restarts. Adding a
      # `bannedPlayers` attrset here would flip that: bans would become
      # declarative and in-game /ban would then start reverting too. Choose
      # deliberately rather than by accident.
      #
      # Either way it has to be a USERNAME ban: cloud1's masquerade makes every
      # player 10.100.0.1 to us, so /ban-ip does nothing useful. The only place
      # an address can actually be blocked is cloud1's nftables.
      operators.br1gg_s = {
        uuid = "525337e6-f77e-413a-8e56-c7d81899a5f5"; # resolved via the Mojang API
        level = 4;
      };

      # Heap: 12 GB, fixed. Raised from 4G/8G (the pack's own user_jvm_args.txt
      # bounds) after the journal showed "Can't keep up!" ~16x/day with only
      # 1-2 players online - stalls of 2.4s to 14.1s, the worst of them late in
      # the nightly restart cycle, while the box itself sat at 5-7% CPU with
      # 23 GiB free. That is the shape of a heap running out of room, not of a
      # server short on hardware. The G1 flags below are unchanged: they are
      # the pack-shipped (Aikar-style) tuning.
      #
      # Xms == Xmx deliberately. Those flags assume a FIXED heap
      # (InitiatingHeapOccupancyPercent=15 means little against a growing one),
      # and pinning it removes heap-resize pauses as a variable while the GC
      # log below is being read. With AlwaysPreTouch this means all 12 GB is
      # faulted in during startup: boot is slower, and RSS starts high instead
      # of climbing to it.
      #
      # RAM budget - CI shares this box and there is NO SWAP
      # (hardware-configuration.nix: swapDevices = []), so this has to be
      # checked rather than assumed:
      #   12 GB heap + ~3.6 GB non-heap  = ~15.6 GB   (non-heap measured: the
      #     pack hit 11.6 GB RSS against the old 8 GB cap - see MAINTENANCE.md)
      #   + ~9 GB CI peak                = ~24.6 GB of 31 GiB
      # Roughly 6 GiB of margin at the worst overlap. Do not raise this again
      # without re-measuring the CI side first.
      jvmOpts = [
        "-Xms12G"
        "-Xmx12G"
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

        # The question this exists to answer: are the multi-second stalls
        # collector pauses, or one tick doing six seconds of honest work? The
        # gc tags alone cannot tell those apart - `safepoint` can, because it
        # times every stop-the-world pause including the ones GC did not cause.
        # gc+cpu additionally splits a pause into user/sys/real, which
        # separates "the collector was busy" from "the collector was waiting".
        #
        # No `gc*` wildcard on purpose. nix-minecraft interpolates jvmOpts
        # UNQUOTED into a bash start script whose cwd is the server directory,
        # so a `*` here is live to pathname expansion. Nothing plausible would
        # match this word today, but explicit tags cost nothing and cannot.
        #
        # A file, not the journal - the opposite of the console decision above
        # (see managementSystem). That switch existed to get game output into
        # Loki; this is high-volume machine-readable telemetry that would bury
        # exactly those lines. The JVM rotates it itself, capped at 5 x 32 MB.
        #
        # HAZARD: if this path is not writable the JVM does not warn and carry
        # on - it fails to initialise, and with Restart=always that is a crash
        # loop into StartLimitBurst. The tmpfiles rule below is what makes the
        # directory's existence guaranteed rather than incidental.
        "-Xlog:gc,gc+cpu,gc+heap,safepoint:file=${gcLogDir}/gc.log:time,uptime,level,tags:filecount=5,filesize=32M"
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
        kubejs = kubejsWithColor;
        # FTB Ranks reads <world>/serverconfig/ftbranks/. Nested `files` paths
        # are safe here: the module mkdir -p's the parent, and its cleanup
        # removes only this exact path, so nothing else under world/ is at
        # risk. A pre-existing ranks.snbt is renamed to .bak rather than
        # clobbered, so adopting a live config loses nothing.
        #
        # Only the POLICY is managed. players.snbt - who is in which rank - is
        # deliberately left unmanaged so `/ftbranks add <player> trusted`
        # persists across restarts.
        "world/serverconfig/ftbranks/ranks.snbt" = atmonsRanks.ranksSnbt;
      };
    };
  };

  # Guarantees the -Xlog target directory exists and is writable before the
  # server starts; see the HAZARD note on that flag. systemd-tmpfiles-setup
  # runs at sysinit, long before multi-user.target pulls the game server up,
  # and it re-asserts the directory on every switch - so this holds on a fresh
  # install and after someone deletes the logs by hand, not just today.
  #
  # ProtectSystem=full on the unit leaves /var writable, and the minecraft uid
  # is mapped inside the unit's PrivateUsers namespace, so the service can
  # write here as itself.
  # 0755 so the directory can at least be listed without sudo. Note this does
  # NOT make the logs readable: the unit sets UMask=0007, so the JVM creates
  # gc.log itself as 0660 minecraft:minecraft regardless of the mode here.
  # Reading them needs sudo (or membership of the minecraft group), which is
  # why the commands in MAINTENANCE.md carry it. Tightening this back to 0750
  # would therefore buy nothing; loosening the FILES would mean fighting the
  # module's umask on every rotation.
  systemd.tmpfiles.rules = [
    "d ${gcLogDir} 0755 minecraft minecraft - -"
  ];

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
    # Now that the console goes to the journal, journald's default burst limit
    # applies to it - and a 371-mod server at boot outruns that easily. Dropped
    # lines here are dropped crash traces, which is the whole reason for the
    # switch, so exempt this one unit. Volume is still bounded by SystemMaxUse.
    LogRateLimitIntervalSec = 0;
  };
}
