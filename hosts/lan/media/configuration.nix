# hosts/media/configuration.nix
#
# media - *arr stack + Jellyfin (SATA 477G). Stack lives in ./arr.nix; the NAS is
# NFS-mounted there. Adopted from the channel install; baseline (key-only SSH,
# nftables firewall, deploy user, sops, flakes, zsh) is in ../../../modules/common.nix.
#
# Firewall is safe to enable here: every *arr service sets openFirewall = true, so
# its ports open themselves (no-ops while the stock install left the firewall off).
# NFS to the NAS is outbound, unaffected.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./arr.nix
    ../../../modules/media-hardening.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "media";
  networking.networkmanager.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Headless - GNOME from the original install is stripped; everything is reached
  # over the network.

  # Intel N150 iGPU for Jellyfin Quick Sync: iHD VAAPI driver, oneVPL runtime
  # (QSV on Gen12+ Xe), and OpenCL for HDR->SDR tone mapping. Jellyfin gets
  # /dev/dri access via SupplementaryGroups in arr.nix; enable QSV in
  # Dashboard -> Playback -> Transcoding after deploy.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime
    ];
  };

  # --- User ------------------------------------------------------------------
  # Opted out of the fleet-wide `briggs` (modules/users.nix) until Phase B.
  #
  # This is not cosmetic: `media` below is not just a login, it is the service
  # account the *arr stack runs as (arr.nix sets user = "media" for sonarr,
  # radarr, bazarr, jellyfin and nzbget), and it sits on uid 1000 - the same
  # number the NAS export at 192.168.1.213 owns its files with. briggs also wants
  # uid 1000, so both cannot live here, and moving *either* off 1000 by itself
  # breaks NFS owner-match on the library.
  #
  # Phase B: give the *arr services their own account, join it to gid 1000 (the
  # library is mode 775, so group access is enough), chown /var/lib/{sonarr,...},
  # then drop this line. Needs a quiet window - nzbget mid-download is how you
  # corrupt a queue.
  alcove.fleetUsers.enable = false;

  users.users.media = {
    isNormalUser = true;
    description = "media";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [ neovim ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
  };

  # ship the journal to central Loki on mgmt
  alcove.siemLite.agent.enable = true;

  # Usenet runs ~160ms RTT to Eweka (NL); BBR + bigger TCP windows lift
  # per-connection throughput on that long fat pipe. fq is BBR's pacing qdisc.
  boot.kernelModules = [ "tcp_bbr" ];
  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 1048576 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";
  };

  system.stateVersion = "25.11";
}
