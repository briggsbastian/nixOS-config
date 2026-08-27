{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak = {
      url = "github:gmodena/nix-flatpak";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
    };
    # nixvim's main branch tracks unstable nixpkgs - it maintains release
    # branches matching nixpkgs channels for exactly this.
    nixvim-stable = {
      url = "github:nix-community/nixvim/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    claude-code = {
      url = "github:sadjow/claude-code-nix";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Dev tooling: nix fmt + lint (nixfmt + statix + deadnix) as `nix fmt` and a
    # flake check. follows nixpkgs so it adds no second tree to the lock.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # disko - declarative disk partitioning, for the first nixos-anywhere
    # install (cloud1). follows nixpkgs-stable like the servers.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    # desktop tracks nixpkgs (unstable); servers track stable (nixos-26.05).
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    # mgmt pinned to an exact nixpkgs rev, bumped deliberately in maintenance
    # windows (a bad deploy takes down the house's DNS/PKI). Currently the same
    # nixos-26.05 rev as nixpkgs-stable, proven on the other servers first.
    nixpkgs-mgmt.url = "github:NixOS/nixpkgs/8f0500b9660505dc3cb647775fe9a978a74b5283";
    # The morning newspaper app, fetched from Forgejo over SSH. follows
    # nixpkgs-stable so it adds no extra nixpkgs to the lock; the app builds
    # against stable, independent of mgmt's deliberately-stale pin.
    newspaper = {
      # https, not ssh. nix fetches flake inputs as its own user, and the CI
      # runner has no Forgejo SSH identity - so this input has NEVER actually
      # been fetched in CI. It resolved only because its source happened to
      # already be in hacktop's nix store from an earlier build, and hacktop
      # garbage-collects weekly. mgmt's build would eventually have broken for a
      # reason nobody would connect to garbage collection.
      #
      # The repo is public and hosts trust the internal CA (modules/internal-ca.nix),
      # so this needs no credentials anywhere. Same change isc got in #10.
      #
      # Side effect, and a wanted one: lock-bump.yml derives its update list by
      # excluding ssh:// inputs, so newspaper starts being auto-bumped again -
      # it has silently not been since it was added in June.
      url = "git+https://git.mgmt.lan/briggs/newspaper.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    # Budget tracker: models the biweekly pay cycle against calendar-dated fixed
    # costs and reports what is actually left over each paycheck. Runs on mgmt
    # behind nginx at budget.mgmt.lan (hosts/lan/mgmt/modules/budget-tracker.nix).
    budget-tracker = {
      # https, not ssh, for the same reason as newspaper and isc above: nix
      # fetches inputs as its own user and CI has no Forgejo SSH identity. The
      # repo must be readable without credentials; hosts trust the internal CA
      # (modules/internal-ca.nix), so nothing else is needed.
      #
      # Also keeps it inside lock-bump.yml's auto-update set, which excludes
      # ssh:// inputs.
      url = "git+https://git.mgmt.lan/briggs/budget_tracker.git?ref=main";
      # The app's own flake pins nixos-25.11; following stable builds it against
      # the same 26.05 tree as the rest of the servers and adds no extra nixpkgs
      # to this lock.
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    # Infrastructure Security Controller: scans each host's closure for known
    # vulnerabilities and turns the delta across a flake.lock bump into a PR
    # comment. Pinned here rather than `nix run`-ed unpinned in CI so the lock
    # records exactly which isc produced a given comment. follows nixpkgs-stable
    # like the servers, adding no extra nixpkgs to this lock.
    isc = {
      # https, not ssh: the CI runner has no Forgejo SSH identity, and nix
      # fetches inputs as its own user rather than the workflow's. The repo is
      # public and hosts trust the internal CA (modules/internal-ca.nix), so
      # this needs no credentials anywhere.
      #
      # Note inputs.newspaper below still uses git+ssh and only resolves in CI
      # because its source already happens to be in hacktop's store - one
      # nix-collect-garbage away from breaking the build. Worth moving too.
      url = "git+https://git.mgmt.lan/briggs/isc.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    # Declarative Minecraft servers (NeoForge/Fabric/vanilla launchers, mod
    # symlinks). Used by hacktop for the All the Mons (ATMons) modpack server;
    # follows stable like the servers it runs on.
    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
  };

  outputs =
    inputs@{
      self,
      home-manager,
      nix-flatpak,
      nixvim,
      nixpkgs,
      nixpkgs-stable,
      nixpkgs-mgmt,
      claude-code,
      colmena,
      sops-nix,
      treefmt-nix,
      ...
    }:
    let
      # Single source of truth for host -> LAN IP, shared with mgmt's Prometheus
      # scrape config (hosts/lan/mgmt/modules/monitoring.nix) so the deploy host
      # list and the metrics scrape list can't drift. See fleet-hosts.nix.
      fleetHosts = import ./fleet-hosts.nix;

      mkSystem =
        { homeFile }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/workstation/desktop/configuration.nix
            home-manager.nixosModules.home-manager
            nix-flatpak.nixosModules.nix-flatpak
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              # On activation, move any pre-existing unmanaged file that HM wants
              # to own to <file>.hm-bak instead of aborting the whole switch. The
              # rice's hyprland.conf / GTK files collide with hand-written and
              # Plasma-written ones on first switch; this lets HM take them over.
              home-manager.backupFileExtension = "hm-bak";
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users.briggs = import homeFile;
            }
          ];
        };

      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # `nix fmt` + lint: nixfmt (RFC style) + statix (anti-patterns) + deadnix
      # (dead code), wired once and exposed both as the formatter and as a check.
      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.statix.enable = true;
        programs.deadnix = {
          enable = true;
          # Leave function arguments alone. Removing an unused module-header arg
          # ({ config, pkgs, lib, ... }) is a semantic edit, not formatting, and
          # would churn nearly every file -- keep `nix fmt` purely cosmetic.
          no-lambda-pattern-names = true;
          no-lambda-arg = true;
        };
      };

      # Version metadata, pinned explicitly so both eval paths agree.
      #
      # Colmena evaluates nodes through nixpkgs' nixos/lib/eval-config.nix, so it
      # sees nixpkgs' *plain* lib; nixosConfigurations goes through
      # nixpkgs-stable.lib.nixosSystem and sees the flake-extended one. Two things
      # differ as a result: lib.trivial.versionSuffix falls back to its hardcoded
      # "pre-git" (the .version-suffix file is never present in a fetched flake
      # input), and nixpkgs.flake.source is left unset, which leaves a deployed
      # host with an empty flake registry and NIX_PATH pointing at channels that
      # do not exist on a flake-managed box.
      #
      # The upshot was that colmenaHive.nodes.<h> and nixosConfigurations.<h>
      # built different closures for every host at the same commit -- so CI's
      # build-hosts matrix was validating an artifact that never shipped. Setting
      # these explicitly makes the two converge.
      mkVersionInfo = np: {
        system.nixos.versionSuffix = ".${builtins.substring 0 8 np.lastModifiedDate}.${np.shortRev}";
        system.nixos.revision = np.rev;
        nixpkgs.flake.source = np.outPath;
        # Stamp the config commit into the built system, so a host can be asked
        # what it is running instead of it being inferred from store-path
        # equality. Surfaces in `nixos-version --json`.
        system.configurationRevision = self.rev or self.dirtyRev or "dirty";
      };

      # Every server = shared baseline + sops + its own host module. One module
      # list feeds both the nixosConfiguration and the Colmena node, so they
      # never drift.
      serverModules = name: meta: [
        (mkVersionInfo nixpkgs-stable)
        ./modules/common.nix
        ./modules/users.nix # pinned-UID `briggs`; media opts out (Phase B)
        ./modules/internal-ca.nix
        ./modules/siem-lite.nix
        ./modules/audit.nix # inert unless the host sets alcove.audit.enable
        sops-nix.nixosModules.sops
        inputs.disko.nixosModules.disko # inert unless the host sets disko.devices (only cloud1 does)
        ./hosts/${meta.zone}/${name}/configuration.nix
      ];

      # The servers: host -> deploy metadata. `zone` is both the hosts/ subdir
      # (hosts/<zone>/<name>/) and a Colmena tag, so `colmena apply --on @lan` /
      # `@cloud` work. Adding a server is one line here + a hosts/<zone>/<name>/
      # dir. targetHost is always an IP - the internal domain is served by mgmt's
      # AdGuard, so resolving it here would be a DNS deadlock.
      #   mgmt (192.168.1.222) is folded in last and gated - it serves the LAN's
      #   DNS + PKI, so a bad deploy takes down the whole house (see Project 1).
      # IPs come from fleetHosts (above) so they're defined once; zone + tags stay
      # here as they're deploy-only (zone is also the hosts/<zone>/<name>/ subdir).
      servers = {
        hacktop = {
          zone = "lan";
          targetHost = fleetHosts.hacktop.ip;
          tags = [
            "server"
            "lan"
            "staging"
          ];
        };
        media = {
          zone = "lan";
          targetHost = fleetHosts.media.ip;
          tags = [
            "server"
            "lan"
            "media"
          ];
        };
        cloud1 = {
          zone = "cloud";
          targetHost = fleetHosts.cloud1.ip;
          tags = [
            "server"
            "cloud"
          ];
        };
      };

      # Servers build against stable nixpkgs (nixos-26.05). The desktop stays
      # on unstable.
      mkServerSystem =
        name: meta:
        nixpkgs-stable.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; }; # lets a host module reach another input
          modules = serverModules name meta;
        };

      mkColmenaNode = name: meta: { ... }: {
        deployment = {
          inherit (meta) targetHost;
          targetUser = "deploy";
          inherit (meta) tags;
        };
        imports = serverModules name meta;
      };

      # mgmt - the LAN's DNS + PKI + SIEM box, folded in last and gated. It does
      # not take the fleet common.nix (its own base.nix owns SSH/firewall, and
      # step-ca owns ACME - common.nix would fight both); it gets only the deploy
      # identity. Built against its pinned nixpkgs for a churn-free cut.
      mgmtModules = [
        (mkVersionInfo nixpkgs-mgmt) # mgmt's own pin, not nixpkgs-stable
        ./modules/config-revision.nix # mgmt skips common.nix, so import it directly
        ./modules/deploy-user.nix
        ./modules/users.nix # pinned-UID `briggs` (brings its own programs.zsh - mgmt has none)
        sops-nix.nixosModules.sops # mgmt needs sops (Grafana admin password)
        ./modules/siem-lite.nix # mgmt is the central Loki/Grafana/Alertmanager server
        ./modules/audit.nix # inert unless the host sets alcove.audit.enable
        ./hosts/lan/mgmt/configuration.nix
      ];
      mkMgmtSystem = nixpkgs-mgmt.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; }; # mirror the Colmena node + mkServerSystem so modules can reach inputs.newspaper
        modules = mgmtModules;
      };
      mkMgmtColmenaNode = { ... }: {
        deployment = {
          targetHost = fleetHosts.mgmt.ip;
          targetUser = "deploy";
          tags = [
            "server"
            "mgmt"
            "gated"
          ];
        };
        imports = mgmtModules;
      };
    in
    {
      nixosConfigurations = {
        nixos-kde = mkSystem { homeFile = ./hosts/workstation/desktop/home-kde.nix; };
        mgmt = mkMgmtSystem;
      }
      // nixpkgs.lib.mapAttrs mkServerSystem servers;

      # --- Remote deploy from this desktop (the Colmena control node) ----------
      #   nix develop                          # shell with colmena + sops/age
      #   colmena build --on media             # build only
      #   colmena apply --on media             # build + push + activate (as deploy)
      #   colmena apply --on @server           # everything tagged "server"
      colmenaHive = colmena.lib.makeHive (
        {
          meta = {
            nixpkgs = import nixpkgs-stable { system = "x86_64-linux"; };
            # mgmt builds against its own pinned nixpkgs -> churn-free cutover.
            nodeNixpkgs.mgmt = import nixpkgs-mgmt { system = "x86_64-linux"; };
            specialArgs = { inherit inputs; }; # mirror mkServerSystem so host modules can reach other inputs under Colmena too
          };
          mgmt = mkMgmtColmenaNode;
        }
        // nixpkgs.lib.mapAttrs mkColmenaNode servers
      );

      # NixOS VM tests, picked up by `nix flake check` (and therefore CI) with no
      # workflow change -- the runner on hacktop advertises kvm + nixos-test, so
      # the daemon can build and run them. Hermetic: no network, no real hosts.
      checks.x86_64-linux = {
        mgmt-ca = import ./tests/mgmt-ca.nix { inherit pkgs; };
        log-path = import ./tests/log-path.nix { inherit pkgs; };
        # Guards a real outage: the backup aborted whenever an optional source
        # path was absent, so step-ca's only off-box copy was never written.
        mgmt-backup = import ./tests/mgmt-backup.nix { inherit pkgs; };
        # Audit telemetry is exactly the class of thing that configures cleanly,
        # reports healthy and is connected to nothing. Asserts runtime behaviour
        # only: rules loaded, events emitted, journald actually receiving them.
        audit = import ./tests/audit.nix { inherit pkgs; };
        # uid 1000 changes hands from each host's own admin to `briggs` in a
        # single activation. Whether NixOS frees the old uid before allocating
        # the new one is not obvious, and cloud1 has no console to recover from
        # a half-applied switch.
        fleet-users = import ./tests/fleet-users.nix { inherit pkgs; };
        # Guards the ATMons console failure that builds and evaluates perfectly:
        # a write to the server's stdin FIFO while its socket is down leaves a
        # REGULAR FILE there, after which the socket refuses to start and the
        # server never comes back. Also pins both age recipients on the world
        # backup - dropping one is invisible until the day you need a restore.
        minecraft-console = import ./tests/minecraft-console.nix { inherit pkgs; };
        # World-archive retention, the one rule in the backup chain whose
        # failure mode is entirely silent: one archive too greedy, and the
        # night you need a rollback is the night it is not there. Pins the
        # .partial invariant too. Not a VM test - it is a pure function from a
        # directory listing to a set of unlinks, so it runs in seconds.
        minecraft-prune = import ./tests/minecraft-prune.nix { inherit pkgs; };
        # fmt + lint gate. Fails on an unformatted tree -- the `style: nix fmt the
        # tree` commit is what makes it green (drop that commit and this goes red).
        formatting = treefmtEval.config.build.check self;
      };

      # `nix fmt` formats + lints the whole tree.
      formatter.x86_64-linux = treefmtEval.config.build.wrapper;

      # Re-exported so CI (and a human) can `nix run .#isc` and get the exact
      # revision this flake.lock pins, rather than whatever isc's main happens
      # to be at the time.
      packages.x86_64-linux.isc = inputs.isc.packages.x86_64-linux.isc;

      devShells.x86_64-linux.default = pkgs.mkShell {
        # colmena (deploy) + the sops/age toolchain (edit + re-key secrets).
        # sops auto-reads your admin key from ~/.config/sops/age/keys.txt.
        # treefmt wrapper so `treefmt` / `nix fmt` work in the shell.
        packages = [
          colmena.packages.x86_64-linux.colmena
          pkgs.sops
          pkgs.age
          pkgs.ssh-to-age
          treefmtEval.config.build.wrapper
        ];
      };
    };
}
