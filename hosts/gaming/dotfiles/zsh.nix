{ ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      # Rebuild from the current flake.lock — no input bumps.
      rebuild-kde       = "sudo /etc/nixos/hosts/gaming/scripts/rebuild.sh switch --flake /etc/nixos#nixos-kde";
      rebuild-hypr      = "sudo /etc/nixos/hosts/gaming/scripts/rebuild.sh switch --flake /etc/nixos#nixos-hyprland";
      rebuild-test-kde  = "sudo /etc/nixos/hosts/gaming/scripts/rebuild.sh test   --flake /etc/nixos#nixos-kde";
      rebuild-test-hypr = "sudo /etc/nixos/hosts/gaming/scripts/rebuild.sh test   --flake /etc/nixos#nixos-hyprland";
      rebuild-boot-kde  = "sudo /etc/nixos/hosts/gaming/scripts/rebuild.sh boot   --flake /etc/nixos#nixos-kde";
      rebuild-boot-hypr = "sudo /etc/nixos/hosts/gaming/scripts/rebuild.sh boot   --flake /etc/nixos#nixos-hyprland";

      # Full upgrade flow: bump flake.lock → build → show closure diff → confirm → switch.
      upgrade           = "/etc/nixos/hosts/gaming/scripts/upgrade.sh";              # auto-detects KDE/Hypr from session
      upgrade-kde       = "/etc/nixos/hosts/gaming/scripts/upgrade.sh kde";
      upgrade-hypr      = "/etc/nixos/hosts/gaming/scripts/upgrade.sh hypr";
      # Same as above but stages for next reboot instead of switching live.
      # Prefer these when the kernel is bumping.
      upgrade-boot-kde  = "/etc/nixos/hosts/gaming/scripts/upgrade.sh boot kde";
      upgrade-boot-hypr = "/etc/nixos/hosts/gaming/scripts/upgrade.sh boot hypr";

      # Maintenance.
      nix-diff     = "/etc/nixos/hosts/gaming/scripts/upgrade.sh diff";       # running vs latest built
      nix-gens     = "/etc/nixos/hosts/gaming/scripts/upgrade.sh gens";       # list system generations
      nix-gc       = "/etc/nixos/hosts/gaming/scripts/upgrade.sh gc";         # delete generations >14d old
      nix-optimise = "/etc/nixos/hosts/gaming/scripts/upgrade.sh optimise";   # dedupe /nix/store
      nix-rollback = "/etc/nixos/hosts/gaming/scripts/upgrade.sh rollback";   # back one generation

      # Back-compat with old alias names.
      update-kde  = "/etc/nixos/hosts/gaming/scripts/upgrade.sh kde";
      update-hypr = "/etc/nixos/hosts/gaming/scripts/upgrade.sh hypr";

      ls = "lsd";
    };

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      share = true;
    };
  };
}

