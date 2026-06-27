# hosts/hacktop/configuration.nix
#
# hacktop - 11th-gen i / 32 GB / 931 GB NVMe laptop. Staging + CI/build host for
# the fleet (Project 1 -> Project 5 runner). Adopted from the stock installer image
# (NixOS 25.11), so this converges the existing box. Baseline (SSH key-only,
# nftables w/ 22, flakes, zsh, base tools) is in ../../../modules/common.nix.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./forgejo-runner.nix
  ];

  # Bootloader (matches the live install: systemd-boot on the ESP).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "hacktop";

  # Wi-Fi-only again (wlp0s20f3 = 192.168.1.26); Colmena targets .26.
  #
  # The USB Ethernet dongle (enp0s13f0u1 = .198) was unplugged 2026-06-15: its
  # UniFi switch port wasn't forwarding (link up, TX only, no ARP reply from the
  # gateway), so it black-holed the default route, and being a 2nd NIC on the same
  # /24 as Wi-Fi it caused ARP flux that poisoned .26 and knocked the box offline.
  # Pulling it restored clean Wi-Fi WAN.
  # TODO (wired primary): fix/swap that switch port + cable, confirm the dongle
  # pings the gateway and the internet, add a UniFi DHCP reservation (dongle MAC ->
  # .198), then either go wired-only (Wi-Fi autoconnect off) or set
  # arp_ignore=1/arp_announce=2 so the two same-subnet NICs don't flux. Until then
  # don't make Ethernet primary.
  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # --- User ------------------------------------------------------------------
  # Login user matches the box + ~/.ssh/config alias. Key-only (see common.nix),
  # this desktop's key, so `ssh hacktop@<ip>` and Colmena keep working. wheel sudo
  # still needs a password (set with passwd).
  users.users.hacktop = {
    isNormalUser = true;
    description = "hacktop";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
  };

  # --- Staging / CI build tooling -------------------------------------------
  # Just enough to stage fleet configs and drive builds by hand for now; the
  # actual self-hosted runner is stood up in Project 5.
  environment.systemPackages = with pkgs; [
    nix-output-monitor # nom - readable build output when staging configs
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

  # --- Secrets (sops-nix) ----------------------------------------------------
  # Smoke-test secret proving the sops-nix -> Colmena -> /run/secrets pipeline.
  # Decrypts at activation via this host's SSH host key (see common.nix). Owner is
  # `hacktop` only so it's verifiable without root; real secrets get their
  # service's user. Replace demo_secret with real ones (CI runner token, cache
  # signing key) as they appear.
  sops.defaultSopsFile = ../../../secrets/hacktop.yaml;
  sops.secrets.demo_secret = {
    owner = "hacktop";
  };

  # ship the journal to central Loki on mgmt
  alcove.siemLite.agent.enable = true;

  # mgmt's binary cache + root-CA trust now come from modules/internal-ca.nix
  # (alcove.internalCa.enable, set fleet-wide in common.nix).

  # Server power policy (never suspend, ignore lid, Wi-Fi powersave off) now
  # lives in modules/common.nix, so every fleet host inherits it.

  # --- Desktop (inherited from the installer) -------------------------------
  # Disabled: hacktop is headless. NetworkManager (above) is independent of the
  # desktop, and there's an internal display for console recovery, so dropping
  # GNOME doesn't affect remote access. Re-enable for a local GUI.
  #
  # services.xserver.enable = true;
  # services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;
  # services.printing.enable = true;
  # services.pipewire = { enable = true; alsa.enable = true; pulse.enable = true; };
  # security.rtkit.enable = true;

  # Reboot picks up the new kernel; this box should auto-recover headless on
  # Wi-Fi after a reboot (NetworkManager autoconnect + powersave off, in common.nix).

  # First install was 25.11; leave fixed (tracks state compat, not package
  # versions).
  system.stateVersion = "25.11";
}
