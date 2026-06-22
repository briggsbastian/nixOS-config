# hosts/cloud1/disko.nix
#
# Declarative disk layout for the Linode Nanode - the fleet's first disko /
# nixos-anywhere install (mgmt/media/playground/hacktop were adopted from running
# systems). disko turns this attrset into the partition -> format -> mount steps
# nixos-anywhere runs before copying the closure in, and generates
# config.fileSystems so configuration.nix doesn't repeat the mounts.
#
# Linode specifics that drive this layout:
#   * Legacy BIOS boot (no /sys/firmware/efi) -> GRUB, not systemd-boot. On a GPT
#     disk that needs a tiny BIOS-boot partition for GRUB's core.img - the one
#     structural difference from a UEFI host like hacktop (which has an ESP).
#   * Two disks: sda (24.5 G -> root) and sdb (~0.5 G -> swap). Keep the split so
#     nothing is wasted; both are declared here.
{
  disko.devices.disk = {
    # Main disk -> GPT: 1 MiB BIOS-boot partition + ext4 root.
    sda = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          # GRUB on GPT+BIOS needs somewhere to embed core.img. This 1 MiB EF02
          # ("BIOS boot") partition is it: no filesystem, never mounted. The piece
          # a UEFI/systemd-boot host doesn't have.
          boot = {
            size = "1M";
            type = "EF02";
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };

    # Reuse Linode's small dedicated swap disk. 1 GB RAM is tight, so real swap is
    # headroom during the install (disko enables it before the closure copy) and
    # at runtime. configuration.nix also turns on zram for compressed RAM swap.
    sdb = {
      type = "disk";
      device = "/dev/sdb";
      content = {
        type = "gpt";
        partitions.swap = {
          size = "100%";
          content = {
            type = "swap";
          };
        };
      };
    };
  };
}
