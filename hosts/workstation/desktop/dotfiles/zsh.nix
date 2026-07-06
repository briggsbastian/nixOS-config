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

      # Kali lab VM: tmux-persistent, so reconnecting resumes the same
      # session instead of starting fresh.
      kali = "ssh -t kali 'tmux new-session -A -s kali'";
    };

    # `decep` drives the Decepticon lab from the desktop. Everything except `web`
    # forwards to the on-host wrapper over SSH (with a tty, so `decep cli` attaches
    # the launcher). `decep web` runs LOCALLY - and it has to: Decepticon's web UI
    # is a localhost app (page on :3000, and its terminal panel hard-connects to
    # ws://localhost:3003), so a LAN URL would load the page but break the terminal.
    # The tunnel maps BOTH ports to the VM's localhost; the browser then hits
    # localhost:3000. `decep web stop` closes it. The stack itself stays on
    # playground - this only bridges your browser to it.
    initContent = ''
      decep() {
        local host=playground@192.168.1.217
        if [ "$1" = "web" ]; then
          if [ "$2" = "stop" ]; then
            pkill -f "ssh -fNT .*$host" && echo "decep web: tunnel closed" || echo "decep web: no tunnel running"
            return
          fi
          # Preflight: is the UI actually up on the VM? (It only listens after you
          # bring the stack up in 'decep cli' and spawn it with '/web'.)
          if ! ssh "$host" 'ss -tln 2>/dev/null | grep -q 127.0.0.1:3000'; then
            echo "decep web: nothing on :3000 on playground yet."
            echo "  Run 'decep cli', bring the stack up, then spawn the UI with '/web' - and retry."
            return 1
          fi
          ssh -fNT -L 3000:127.0.0.1:3000 -L 3003:127.0.0.1:3003 "$host" \
            && xdg-open http://localhost:3000/web \
            && echo "decep web: tunnels up (3000 + 3003). Browser -> localhost:3000/web. 'decep web stop' to close."
        else
          ssh -t "$host" decep "$@"
        fi
      }

      # `lab` opens/attaches a two-window tmux session: a Kali terminal and the
      # Decepticon CLI. It deliberately does NOT auto-start decep or htb - those
      # stay manual, explicit actions you run inside the window once attached.
      lab() {
        local session="lab"
        if tmux has-session -t "$session" 2>/dev/null; then
          tmux attach -t "$session"
          return
        fi
        tmux new-session -d -s "$session" -n kali "ssh -t kali 'tmux new-session -A -s kali'"
        tmux new-window  -t "$session"    -n decep "ssh -t playground@192.168.1.217 decep cli"
        tmux select-window -t "$session:kali"
        tmux attach -t "$session"
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
