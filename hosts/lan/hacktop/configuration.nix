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
    ./minecraft.nix
    ./minecraft-backup.nix
    ./wg-proxy.nix
  ];

  # Bootloader (matches the live install: systemd-boot on the ESP).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "hacktop";

  # WIRED PRIMARY as of 2026-07-02: lan0 (USB-C dongle, UniFi fixed-IP .26)
  # carries everything; Colmena targets .26. Wi-Fi (wlp0s20f3, fixed-IP .241)
  # stays connected as an autoconnect fallback - safe next to the wired NIC
  # thanks to the ARP sysctls + loose rp_filter below.
  #
  # Hard-won history (2026-06-15 + 2026-07-02): the original switch port
  # would not forward unicast to the dongle's MAC (broadcast passed, so DHCP
  # worked while everything else died) - moving one port over fixed it. On
  # top of that, NM's auto-generated fallback profile (DHCP, metric 100)
  # twice hijacked same-subnet replies into the dead port and took the box
  # off the network; no-auto-default + the pinned profile below prevent that
  # class of failure. Diagnosis notes in Homelab/log.md.
  networking.networkmanager.enable = true;

  # ARP hygiene for two NICs on the same /24 (Wi-Fi + USB-C Ethernet during
  # the wired cutover): only answer ARP on the interface that owns the
  # address, and announce with the outgoing interface's address. Without
  # these, the 2026-06-15 dongle attempt caused ARP flux that poisoned .26
  # and knocked the box offline. Kept permanently - they make Wi-Fi a safe
  # emergency fallback next to the wired NIC.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
  };

  # Two NICs on one /24 make routing asymmetric by design (traffic for the
  # deprioritized NIC arrives on it but reverse-routes to the other). The
  # default strict reverse-path check drops those flows entirely - IP on the
  # secondary NIC goes dark while its ARP still answers. Loose = still
  # anti-spoof (source must be reachable via SOME interface), multihome-safe.
  networking.firewall.checkReversePath = "loose";

  # Cap the adapter at 1G for now - it negotiates 2.5GBASE-T, but the wired
  # path was only ever validated at 1G (the 2.5G unicast failures during
  # bring-up were on the bad port, so 2.5G on this port is untested). To try
  # 2.5G: drop Advertise, replug, re-run the ping matrix.
  # Match the adapter by MAC and name it lan0 - stable across USB ports (the
  # default path-based name enp0s13f0u1 changes with the port, and a custom
  # .link file drops the default NamePolicy anyway, which silently renamed the
  # NIC to eth0 on first deploy of the speed cap).
  systemd.network.links."10-usb-dongle-1g" = {
    matchConfig.PermanentMACAddress = "6c:1f:f7:c7:02:84";
    linkConfig = {
      Name = "lan0";
      Advertise = [ "1000baset-full" ];
    };
  };

  # Never let NM invent a fallback "Wired connection 1" (DHCP, metric 100) for
  # an unclaimed NIC - that's what silently hijacked all same-subnet replies
  # into the broken wired path after a USB re-enumeration (2026-07-02, twice).
  networking.networkmanager.settings.main.no-auto-default = "*";

  networking.networkmanager.ensureProfiles.profiles.wired-primary = {
    connection = {
      id = "wired-primary";
      type = "ethernet";
      # exact name, not a match glob - a glob profile failed to re-bind on
      # USB re-enumeration and NM fell back to its auto profile. lan0 is
      # pinned to the adapter's MAC by the .link file above.
      interface-name = "lan0";
      autoconnect = true;
      autoconnect-priority = 999;
    };
    # DHCP: UniFi serves the .26 fixed-IP for the adapter's MAC. Ethernet's
    # default metric (100) beats Wi-Fi's (600), so lan0 owns the default
    # route whenever it's up.
    ipv4.method = "auto";
    ipv6.method = "auto";
  };

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
