# hosts/hacktop/configuration.nix
#
# hacktop — 11th-gen i / 32 GB / 931 GB NVMe laptop.
# Role: staging + CI/build host for the fleet (Project 1 → Project 5 runner).
#
# Adopted from the stock installer image (NixOS 25.11) rather than re-imaged,
# so this converges the existing box. Shared baseline (SSH key-only, nftables
# firewall with 22 open, flakes, zsh, base tools) comes from ../../modules/common.nix.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Bootloader (matches the live install: systemd-boot on the ESP).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "hacktop";

  # IMPORTANT: this box is on Wi-Fi only (wlp0s20f3) and NetworkManager owns
  # that connection. Keep NM enabled or the host drops off the LAN after a
  # rebuild. The Wi-Fi credentials live in /etc/NetworkManager/system-connections
  # (root-owned, survives rebuilds) — they are NOT in this repo.
  # TODO: wire up wired ethernet + a static lease before promoting to CI prod.
  networking.networkmanager.enable = true;
  # Server NIC: don't let the Wi-Fi radio power-save itself into unreachability.
  networking.networkmanager.wifi.powersave = false;

  nixpkgs.config.allowUnfree = true;

  # --- User ------------------------------------------------------------------
  # Login user matches the box + ~/.ssh/config alias. Key-only (see common.nix);
  # this is THIS desktop's key, so `ssh hacktop@<hacktop-lan-ip>` and Colmena keep
  # working after the switch. wheel sudo still needs a password (set with passwd).
  users.users.hacktop = {
    isNormalUser = true;
    description = "hacktop";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
  };

  # --- Staging / CI build tooling -------------------------------------------
  # Just enough to stage fleet configs and drive builds by hand for now; the
  # actual self-hosted runner is stood up in Project 5.
  environment.systemPackages = with pkgs; [
    nix-output-monitor   # nom — readable build output when staging configs
    nixos-rebuild
    jq
    just
  ];

  # Roomier Nix builder: this box exists to build/stage for the rest of the
  # fleet, so let it use its cores and keep more history before GC.
  nix.settings.max-jobs = "auto";
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # --- mgmt Harmonia binary cache (commented until internal-CA trust lands) --
  # Wire this once the internal-ca module trusts mgmt's root CA, otherwise the
  # TLS handshake to <cache-host> fails and it needs internal DNS to resolve.
  # nix.settings = {
  #   substituters = [ "https://<cache-host>" ];
  #   trusted-public-keys = [ "<cache-host>-1:<cache-public-key>" ];
  # };

  # --- Treat this as a server, not a laptop ---------------------------------
  # It lives on a shelf with the lid shut. Never suspend/sleep/hibernate, and
  # ignore the lid + idle entirely, so it can't drop off the LAN like a laptop.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    IdleAction = "ignore";
  };
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # --- Desktop (inherited from the installer) -------------------------------
  # Disabled: hacktop is a headless staging/CI box. NetworkManager (above) is
  # independent of the desktop, and there's an internal display for console
  # recovery, so dropping GNOME does not affect remote access. Re-enable this
  # block if you want a local GUI on the laptop.
  #
  # services.xserver.enable = true;
  # services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;
  # services.printing.enable = true;
  # services.pipewire = { enable = true; alsa.enable = true; pulse.enable = true; };
  # security.rtkit.enable = true;

  # Reboot picks up the new kernel; this box should auto-recover headless on
  # Wi-Fi after a reboot (NetworkManager autoconnect + powersave off above).

  # First install was 25.11 — leave this fixed (it tracks state compat, not
  # package versions).
  system.stateVersion = "25.11";
}
