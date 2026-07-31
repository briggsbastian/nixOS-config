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

      # One-shot boot into Windows: next reboot only, then back to the GRUB
      # default. 0000 is the firmware's "Windows Boot Manager" entry (efibootmgr).
      reboot-windows = "sudo efibootmgr --bootnext 0000 && sudo reboot";

      ls = "lsd";

      # playground (security lab box): shell on the hypervisor itself. Stock
      # Proxmox VE since the 2026-07-31 re-image, so it is no longer a NixOS host
      # and there is no `playground` user - root is the login. Day-to-day you want
      # the web UI (https://192.168.1.217:8006) or a guest directly, not this.
      #
      # The `htb` alias is gone with the re-image: the OpenVPN tunnel used to
      # terminate on the host because nothing there had /dev/net/tun. Proxmox
      # guests are full VMs, so HTB belongs inside Kali now.
      pg = "ssh root@192.168.1.217";

      # Kali lab VM: tmux-persistent, so reconnecting resumes the same
      # session instead of starting fresh.
      kali = "ssh -t kali 'tmux new-session -A -s kali'";
    };

    # `decep` (the Decepticon driver) lived here until the 2026-07-31 re-image took
    # its host side with it. The module is parked in attic/decepticon.nix; restore
    # this function from git history if you stand the stack back up in a guest.
    initContent = ''
      # `lab` opens/attaches a persistent tmux session for the lab guests, one
      # window each. Down to a single window since Decepticon left - REMnux is the
      # obvious second one once that guest exists (add an ssh_config Host for it,
      # then a tmux new-window here to match the kali line).
      lab() {
        local session="lab"
        if tmux has-session -t "$session" 2>/dev/null; then
          tmux attach -t "$session"
          return
        fi
        tmux new-session -d -s "$session" -n kali "ssh -t kali 'tmux new-session -A -s kali'"
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
