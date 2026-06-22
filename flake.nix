{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-flatpak = { url = "github:gmodena/nix-flatpak"; };
    nixvim = { url = "github:nix-community/nixvim"; };
    claude-code = {url = "github:sadjow/claude-code-nix"; };
    # Claude Desktop GUI client (community repackage; no official Linux build).
    # Only the gaming host uses it; servers never reference it.
    # follows nixpkgs-stable (25.11), not unstable: needs nodePackages.asar,
    # which unstable dropped 2026-03-03. stable still has it and we already fetch
    # that tree for the servers, so no extra nixpkgs in the lock.
    claude-desktop = { url = "github:k3d3/claude-desktop-linux-flake"; inputs.nixpkgs.follows = "nixpkgs-stable"; };
    colmena = { url = "github:zhaofengli/colmena"; inputs.nixpkgs.follows = "nixpkgs"; };
    sops-nix = { url = "github:Mic92/sops-nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    # disko - declarative disk partitioning, for the first nixos-anywhere
    # install (cloud1). follows nixpkgs-stable like the servers.
    disko = { url = "github:nix-community/disko"; inputs.nixpkgs.follows = "nixpkgs-stable"; };
    # desktop tracks nixpkgs (unstable); servers track stable (nixos-25.11,
    # what the boxes already run, so zero version churn).
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    # mgmt pinned to the exact nixpkgs rev it already runs, so the first Colmena
    # cutover is a no-op (no package churn -> no DNS/PKI/SIEM restarts). bump
    # this deliberately, later.
    nixpkgs-mgmt.url = "github:NixOS/nixpkgs/755f5aa91337890c432639c60b6064bb7fe67769";
  };

  outputs = inputs @ {self, home-manager, nix-flatpak, nixvim, nixpkgs, nixpkgs-stable, nixpkgs-mgmt, claude-code, colmena, sops-nix, ...}:
    let
      mkSystem = { homeFile }: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/workstation/desktop/configuration.nix
          home-manager.nixosModules.home-manager
          nix-flatpak.nixosModules.nix-flatpak
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.briggs = import homeFile;
          }
        ];
      };

      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      # Every server = shared baseline + sops + its own host module. One module
      # list feeds both the nixosConfiguration and the Colmena node, so they
      # never drift.
      serverModules = name: meta: [
        ./modules/common.nix
        ./modules/internal-ca.nix
        ./modules/siem-lite.nix
        sops-nix.nixosModules.sops
        inputs.disko.nixosModules.disko   # inert unless the host sets disko.devices (only cloud1 does)
        ./hosts/${meta.zone}/${name}/configuration.nix
      ];

      # The servers: host -> deploy metadata. `zone` is both the hosts/ subdir
      # (hosts/<zone>/<name>/) and a Colmena tag, so `colmena apply --on @lan` /
      # `@cloud` work. Adding a server is one line here + a hosts/<zone>/<name>/
      # dir. targetHost is always an IP - the internal domain is served by mgmt's
      # AdGuard, so resolving it here would be a DNS deadlock.
      #   mgmt (192.168.1.222) is folded in last and gated - it serves the LAN's
      #   DNS + PKI, so a bad deploy takes down the whole house (see Project 1).
      servers = {
        hacktop    = { zone = "lan";   targetHost = "192.168.1.26";   tags = [ "server" "lan" "staging" ]; };
        media      = { zone = "lan";   targetHost = "192.168.1.189";  tags = [ "server" "lan" "media" ]; };
        playground = { zone = "lan";   targetHost = "192.168.1.217";  tags = [ "server" "lan" "lab" ]; };
        cloud1     = { zone = "cloud"; targetHost = "172.232.161.44"; tags = [ "server" "cloud" ]; };
      };

      # Servers build against stable nixpkgs (nixos-25.11), matching the boxes'
      # current versions, so zero version churn. The desktop stays on unstable.
      mkServerSystem = name: meta: nixpkgs-stable.lib.nixosSystem {
        system = "x86_64-linux";
        modules = serverModules name meta;
      };

      mkColmenaNode = name: meta: { ... }: {
        deployment = {
          targetHost = meta.targetHost;
          targetUser = "deploy";
          tags = meta.tags;
        };
        imports = serverModules name meta;
      };

      # mgmt - the LAN's DNS + PKI + SIEM box, folded in last and gated. It does
      # not take the fleet common.nix (its own base.nix owns SSH/firewall, and
      # step-ca owns ACME - common.nix would fight both); it gets only the deploy
      # identity. Built against its pinned nixpkgs for a churn-free cut.
      mgmtModules = [
        ./modules/deploy-user.nix
        sops-nix.nixosModules.sops      # mgmt needs sops (Grafana admin password)
        ./modules/siem-lite.nix         # mgmt is the central Loki/Grafana/Alertmanager server
        ./hosts/lan/mgmt/configuration.nix
      ];
      mkMgmtSystem = nixpkgs-mgmt.lib.nixosSystem {
        system = "x86_64-linux";
        modules = mgmtModules;
      };
      mkMgmtColmenaNode = { ... }: {
        deployment = {
          targetHost = "192.168.1.222";
          targetUser = "deploy";
          tags = [ "server" "mgmt" "gated" ];
        };
        imports = mgmtModules;
      };
    in {
      nixosConfigurations = {
        nixos-kde = mkSystem { homeFile = ./hosts/workstation/desktop/home-kde.nix; };
        mgmt = mkMgmtSystem;
      } // nixpkgs.lib.mapAttrs mkServerSystem servers;

      # --- Remote deploy from this desktop (the Colmena control node) ----------
      #   nix develop                          # shell with colmena + sops/age
      #   colmena build --on media             # build only
      #   colmena apply --on playground             # build + push + activate (as deploy)
      #   colmena apply --on @server           # everything tagged "server"
      colmenaHive = colmena.lib.makeHive (
        {
          meta = {
            nixpkgs = import nixpkgs-stable { system = "x86_64-linux"; };
            # mgmt builds against its own pinned nixpkgs -> churn-free cutover.
            nodeNixpkgs.mgmt = import nixpkgs-mgmt { system = "x86_64-linux"; };
          };
          mgmt = mkMgmtColmenaNode;
        }
        // nixpkgs.lib.mapAttrs mkColmenaNode servers
      );

      devShells.x86_64-linux.default = pkgs.mkShell {
        # colmena (deploy) + the sops/age toolchain (edit + re-key secrets).
        # sops auto-reads your admin key from ~/.config/sops/age/keys.txt.
        packages = [
          colmena.packages.x86_64-linux.colmena
          pkgs.sops
          pkgs.age
          pkgs.ssh-to-age
        ];
      };
    };
}
