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
