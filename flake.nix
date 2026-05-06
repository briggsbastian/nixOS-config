{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-flatpak = { url = "github:gmodena/nix-flatpak"; };
    nixvim = { url = "github:nix-community/nixvim"; };
    noctalia = {url = "github:noctalia-dev/noctalia-shell"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = inputs @ {self, home-manager, nix-flatpak, nixvim, nixpkgs, ...}:
    let
      mkSystem = { homeFile }: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
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
    in { 
      nixosConfigurations = {
        nixos-hyprland = mkSystem { homeFile = ./home-hyprland.nix; };
        nixos-kde = mkSystem { homeFile = ./home-kde.nix; };
      };
    };
}
