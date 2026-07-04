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

      # playground (security lab host): quick shell + HTB VPN control from the
      # desktop. `htb up|down|status|ip` runs the on-host wrapper over SSH, so the
      # same word works here as it does on the box (see the playground decepticon
      # module). `-t` gives a tty for clean status output. `decep` (the whole-lab
      # driver) is a function below, not an alias, since `decep web` runs locally.
      pg = "ssh playground@192.168.1.217";
      htb = "ssh -t playground@192.168.1.217 htb";
    };

    # `decep` drives the Decepticon lab from the desktop. Everything except `web`
    # forwards to the on-host wrapper over SSH (with a tty, so `decep cli` attaches
    # the launcher). `decep web` runs LOCALLY: it opens a background SSH tunnel to
    # the localhost-only dashboard and launches the browser; `decep web stop`
    # closes it. Keeps the UI unexposed on the LAN (see the playground module).
    initContent = ''
      decep() {
        if [ "$1" = "web" ]; then
          local tun="ssh -fNT -L 3000:127.0.0.1:3000 playground@192.168.1.217"
          if [ "$2" = "stop" ]; then
            pkill -f "$tun" && echo "decep web: tunnel closed" || echo "decep web: no tunnel running"
          else
            eval "$tun" && xdg-open http://localhost:3000/web \
              && echo "decep web: tunnel up on localhost:3000 ('decep web stop' to close)"
          fi
        else
          ssh -t playground@192.168.1.217 decep "$@"
        fi
      }
    '';

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      share = true;
    };
  };
}
