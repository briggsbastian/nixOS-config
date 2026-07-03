# hosts/cloud1/hardware-configuration.nix
#
# Hand-written (not generated) so `nix build .#cloud1` passes offline, before
# nixos-anywhere touches the box. Minimal on purpose: a Linode Nanode is a
# KVM/QEMU guest, so the qemu-guest profile + virtio modules are about all the
# "hardware" there is. No fileSystems/swapDevices here; disko.nix owns those.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # Linode disks show up as /dev/sdX (virtio-scsi, not virtio-blk's /dev/vdX).
  # These are the modules initrd needs to find the root disk at boot.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "ahci"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # Public IPv4 comes up via DHCP on the Linode network. mkDefault so a per-host
  # static config could override it if a lease ever fails to appear.
  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
