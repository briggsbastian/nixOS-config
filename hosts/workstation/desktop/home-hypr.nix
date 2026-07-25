{ pkgs, inputs, ... }:

# Home-manager entry point for the Hyprland "rice" session. Shares the same
# base dotfiles as ./home-kde.nix (shell, editor, git, ...) but drops the
# shared alacritty in favour of the rice-recoloured one in dotfiles/hypr/ and
# adds the whole Hyprland stack (WM, waybar, rofi, mako, lock/idle, wallpaper).
# Wired into the flake as the `nixos-hypr` target; pick it at the SDDM login
# screen (the system enables both the Plasma and Hyprland sessions).
{
  imports = [
    # shared, session-agnostic dotfiles (same set as home-kde.nix, minus the
    # shared alacritty which the rice overrides below)
    ./dotfiles/starship.nix
    ./dotfiles/jellyfin.nix
    ./dotfiles/zsh.nix
    ./dotfiles/neovim.nix
    ./dotfiles/git.nix
    ./dotfiles/tmux.nix
    ./dotfiles/nixpkgs-overlays.nix

    # the rice. hyprland.nix pulls in binds.nix; colors.nix and
    # wallpaper-image.nix are plain `import`ed by the modules, not home modules.
    ./dotfiles/hypr/hyprland.nix
    ./dotfiles/hypr/alacritty.nix
    ./dotfiles/hypr/waybar.nix
    ./dotfiles/hypr/rofi.nix
    ./dotfiles/hypr/mako.nix
    ./dotfiles/hypr/hyprlock.nix
    ./dotfiles/hypr/hypridle.nix
    ./dotfiles/hypr/wallpaper.nix
    ./dotfiles/hypr/wlogout.nix
    ./dotfiles/hypr/gtk.nix
    ./dotfiles/hypr/fonts.nix
  ];
  home.stateVersion = "25.11";
  home.username = "briggs";
  home.packages = [
    inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code # coding CLI
    inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop # GUI chat client
  ];
}
