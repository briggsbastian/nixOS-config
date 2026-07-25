# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./packages.nix
    ./udev.nix
    ../../../modules/internal-ca.nix # trust mgmt's step-ca root so *.mgmt.lan TLS verifies
  ];
  # Bootloader: GRUB (EFI). systemd-boot can't show Windows when it lives on the
  # other NVMe's own ESP; GRUB chainloads it, and gets us a themed menu.
  # The old systemd-boot install stays on the ESP as a firmware-menu fallback.
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub = {
    enable = true;
    device = "nodev"; # EFI: no MBR device; grub-install goes to the ESP
    efiSupport = true;
    configurationLimit = 15; # menu entries only; older generations still roll back via nix
    theme = pkgs.catppuccin-grub;
    gfxmodeEfi = "1920x1080"; # theme renders at 640x480 without an explicit mode
    extraEntries = ''
      menuentry "Windows" --class windows {
        insmod part_gpt
        insmod fat
        insmod chain
        search --no-floppy --fs-uuid --set=root A89D-31B8
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
      }
    '';
  };
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  # Enable networking
  networking.networkmanager.enable = true;
  # Resolve *.mgmt.lan via mgmt's AdGuard; public resolver as fallback if mgmt is
  # down. Use a public-only list to keep desktop DNS off AdGuard's filtering.
  networking.nameservers = [
    "192.168.1.222"
    "9.9.9.9"
  ];
  networking.networkmanager.dns = "none";

  # Trust mgmt's step-ca root so https://*.mgmt.lan verifies. Firefox needs
  # enterprise roots too (set in packages.nix).
  alcove.internalCa.enable = true;

  time.timeZone = "America/Los_Angeles";
  # Windows keeps the RTC in local time; match it so the clock survives dual-boot.
  time.hardwareClockInLocalTime = true;
  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;
  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  # Also offer the Hyprland "rice" session at the SDDM login screen. This pulls
  # in the Wayland session entry and xdg-desktop-portal-hyprland; the per-user
  # rice config lives in home-hypr.nix (the `nixos-hypr` flake target).
  programs.hyprland.enable = true;
  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  #Enable Hardware accelaration availability (fixes jellyfin media player)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  # Enable CUPS to print documents, even though I don't own a printer.
  services.printing.enable = true;
  # Out of box pipewire, everything goes through Volt 2/76 anyways.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;
  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.briggs = {
    isNormalUser = true;
    description = "briggs";
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };
  services.openssh.enable = true;
  networking.firewall.enable = false;
  system.stateVersion = "25.11"; # Did you read the comment?
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
