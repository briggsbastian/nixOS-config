# hosts/lan/hacktop/minecraft.nix
#
# AllTheMons Cobblemon server (Minecraft 1.21.1, Fabric). hacktop has the
# fleet's RAM headroom (32 GB, ~29 available), so the game server lives here
# alongside the CI runner. Fully declarative via nix-minecraft: launcher,
# mods, and the AllTheMons datapack are all pinned store paths, so a rebuild
# reproduces the server exactly (world state lives in /srv/minecraft).
#
# AllTheMons is NOT a standalone modpack - it's a datapack + resource-pack
# addon for Cobblemon. Server side: the zip goes in world/datapacks. Client
# side: players need the same zip as a resource pack; server.properties
# pushes it to them on join (require-resource-pack), so vanilla-ish clients
# only need Fabric + Cobblemon + Fabric API installed manually.
#
# Version pins (bump together - AllTheMons 3.5.x needs Cobblemon 1.7+):
#   Fabric API 0.116.13+1.21.1 / Cobblemon 1.7.3+1.21.1 / AllTheMons R3.5.1
{ config, pkgs, lib, inputs, ... }:

let
  fabricApi = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/FHknjVVa/fabric-api-0.116.13%2B1.21.1.jar";
    hash = "sha512-h6jhNsQ/A9Ca+W1rKzXSe1hnnWGhWFhUd/vMklDsr4pYlqGKmxMr3WuLzRuikazXH5YdWJh+dwuac7ZTrCN8Lw==";
  };
  cobblemon = pkgs.fetchurl {
    url = "https://cdn.modrinth.com/data/MdwFAVRL/versions/kF7CvxTo/Cobblemon-fabric-1.7.3%2B1.21.1.jar";
    hash = "sha512-e1N29fSBd9tTeQI3tvslN4gGlytdO3VhUbTY8tPCcjjWtYe3faQivBeAv9NYtHAudDaf2CzvKjUwG0toovE8Lg==";
  };
  allTheMonsUrl = "https://cdn.modrinth.com/data/JV5dvqVX/versions/xP9xTsa0/AllTheMons%20%5BR3.5.1%5D.zip";
  allTheMons = pkgs.fetchurl {
    name = "AllTheMons-R3.5.1.zip";   # CDN filename has spaces/brackets
    url = allTheMonsUrl;
    hash = "sha512-PJzzIW28PSUIFjlqhaRHvQ2MfMVXeHMaI5ENm0G3l2WgUtDofNF0Vy9pj2IQGjesnqHZ+FGNglEQOlgAYdYxIQ==";
  };
in
{
  imports = [ inputs.nix-minecraft.nixosModules.minecraft-servers ];
  nixpkgs.overlays = [ inputs.nix-minecraft.overlays.default ];

  services.minecraft-servers = {
    enable = true;
    eula = true;

    servers.allthemons = {
      enable = true;
      package = pkgs.fabricServers.fabric-1_21_1;
      openFirewall = true;   # 25565/tcp - LAN only, hacktop is behind NAT

      # 32 GB box: a fixed 4-8 GB heap covers Cobblemon comfortably and still
      # leaves >20 GB for CI builds.
      jvmOpts = "-Xms4G -Xmx8G";

      serverProperties = {
        motd = "AllTheMons Cobblemon @ hacktop";
        difficulty = "normal";
        view-distance = 12;
        # Push the AllTheMons resource pack to clients on join; sha1 is the
        # Modrinth-published file hash, so clients cache-validate correctly.
        resource-pack = allTheMonsUrl;
        resource-pack-sha1 = "24cad3bdd37e658213d6186581e1533b4f1fe96a";
        require-resource-pack = true;
      };

      symlinks = {
        mods = pkgs.linkFarmFromDrvs "mods" [ fabricApi cobblemon ];
        # Datapack must sit inside the world dir; nix-minecraft creates the
        # parent path, and the server picks it up at world creation/load.
        "world/datapacks/AllTheMons-R3.5.1.zip" = allTheMons;
      };
    };
  };
}
