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
  # Blank the unused HDMI output at the DRM level. HDMI-A-1 on the dGPU (card1)
  # has a TV on it that has been powered off for weeks, but its hotplug-detect
  # line oscillates anyway: ~70 udev `change` events a day on connector 117
  # since 2026-06-30, with the sink dark the entire time. That is a fault in the
  # physical path (cable/port/passthrough), not something the sink is doing.
  #
  # Each event makes KWin re-enumerate outputs, which destroys and recreates the
  # kde_output_device_v2 Wayland globals. plasmashell then races to bind a global
  # that is already gone and takes a fatal protocol error. Twice that killed the
  # shell outright (Aug 13, Aug 14, exit 255/EXCEPTION); the rest of the time it
  # survived but wedged - no wallpaper, dead kickoff and task bar, and the panel
  # jumping between monitors as screen indices get reassigned underneath it.
  # KWin itself survives either way, which is why the rest of the screen looks
  # untouched while the panel moves.
  #
  # `:d` disables the connector, so the flap never reaches userspace at all. The
  # name is unambiguous across both amdgpu cards here - the iGPU's port enumerates
  # as HDMI-A-2. Drop this parameter to get the TV back, but note the underlying
  # HPD fault is unrepaired and the flapping will return with it.
  boot.kernelParams = [ "video=HDMI-A-1:d" ];
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
  # Memory headroom for big JVM games. The AllTheMons Minecraft client asks for
  # an 8 GiB heap and carries ~7 GiB of native memory on top (malloc arenas,
  # LWJGL/GL buffers, and direct buffers, whose default cap equals -Xmx), so it
  # sits near 15 GiB of a 30 GiB machine. hardware-configuration.nix leaves
  # swapDevices empty, which meant the kernel's only reclaim option was evicting
  # page cache: it fell to ~220 MiB before the OOM killer fired, and every
  # process re-reading its own executable off disk is what hung the whole
  # desktop for a minute before the game finally died.
  #
  # zram is deliberately modest. The game's heap is *hot*, and compressing hot
  # pages would just trade the freeze for in-game stutter; this is sized to park
  # genuinely cold pages (backgrounded Discord, baloo, idle shells) so they stop
  # competing with the page cache.
  zramSwap = {
    enable = true;
    memoryPercent = 25; # ~7.5 GiB device (uncompressed capacity), not 25% of RAM spent
  };
  # systemd-oomd is enabled by default but does nothing out of the box: every
  # slice ships ManagedOOMMemoryPressure=auto, i.e. off, so we always fell
  # through to the kernel's late global OOM killer. This sets it to `kill` at
  # 80% sustained pressure on user.slice and every user-owned slice, which
  # covers the app.slice scope the game runs in. Sustained 80% pressure only
  # happens in the pathological case, so ordinary heavy builds won't trip it.
  systemd.oomd.enableUserSlices = true;
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

  # The same `briggs` the servers get from modules/users.nix, kept as its own
  # definition rather than importing that module: this host has no sops, so the
  # module's hashedPasswordFile would be unresolvable, and the password here is
  # the interactive one you type at the greeter.
  #
  # uid 1000 was already what auto-allocation picked; it is written down now
  # because it became load-bearing. The NAS at 192.168.1.213 exports /srv/media
  # over NFSv4 with no identity mapping and owns the library uid=1000 gid=1000,
  # so nas.nix writes land by owner match on this number. Changing it orphans
  # ~916G. See modules/users.nix.
  users.users.briggs = {
    isNormalUser = true;
    uid = 1000;
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
