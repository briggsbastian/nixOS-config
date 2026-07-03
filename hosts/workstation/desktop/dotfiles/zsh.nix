_: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      # Rebuild from the current flake.lock - no input bumps.
      rebuild-kde = "sudo /etc/nixos/hosts/workstation/desktop/scripts/rebuild.sh switch --flake /etc/nixos#nixos-kde";
      rebuild-test-kde = "sudo /etc/nixos/hosts/workstation/desktop/scripts/rebuild.sh test   --flake /etc/nixos#nixos-kde";
      rebuild-boot-kde = "sudo /etc/nixos/hosts/workstation/desktop/scripts/rebuild.sh boot   --flake /etc/nixos#nixos-kde";

      # Full upgrade flow: bump flake.lock -> build -> closure diff -> confirm -> switch.
      upgrade = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh"; # auto-detects KDE/Hypr from session
      upgrade-kde = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh kde";
      # Same as above but stages for next reboot instead of switching live.
      # Prefer these when the kernel is bumping.
      upgrade-boot-kde = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh boot kde";

      # Maintenance.
      nix-diff = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh diff"; # running vs latest built
      nix-gens = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh gens"; # list system generations
      nix-gc = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh gc"; # delete generations >14d old
      nix-optimise = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh optimise"; # dedupe /nix/store
      nix-rollback = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh rollback"; # back one generation

      # Back-compat with old alias names.
      update-kde = "/etc/nixos/hosts/workstation/desktop/scripts/upgrade.sh kde";

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
