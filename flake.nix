{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-flatpak = { url = "github:gmodena/nix-flatpak"; };
    nixvim = { url = "github:nix-community/nixvim"; };
    noctalia = {url = "github:noctalia-dev/noctalia-shell"; inputs.nixpkgs.follows = "nixpkgs"; };
    claude-code = {url = "github:sadjow/claude-code-nix"; }; 
  };

  outputs = inputs @ {self, home-manager, nix-flatpak, nixvim, nixpkgs, claude-code, ...}:
    let
      mkSystem = { homeFile }: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/gaming/configuration.nix
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
        nixos-hyprland = mkSystem { homeFile = ./hosts/gaming/home-hyprland.nix; };
        nixos-kde = mkSystem { homeFile = ./hosts/gaming/home-kde.nix; };

        # Fleet servers: lean, no home-manager / desktop inputs.
        # Staging + CI/build host — adopt the existing 25.11 install.
        hacktop = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./modules/common.nix
            ./hosts/hacktop/configuration.nix
          ];
        };
      };
    };
}
