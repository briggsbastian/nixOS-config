# hosts/lan/playground/incus.nix
#
# Incus VM/container host for the security lab, replacing the old
# libvirt + Guacamole + Cockpit trio (2026-07). One stack, one UI: incus-ui-canonical
# is served on the HTTPS API listener (:8443) with TLS client-cert auth — no
# reverse proxy possible (nginx can't forward the browser's client cert), so
# access is direct: https://192.168.1.217:8443. First-connect trust flow and the
# per-VM build runbook live in ./LAB.md.
#
# Networking: Incus does NOT manage br0 — that stays owned by systemd-networkd in
# ./bridge.nix. The default profile attaches guest NICs to br0 (nictype "bridged",
# for unmanaged bridges) so VMs are first-class LAN hosts, exactly as the old
# libvirt lan-br0 network did. malbr0 is an Incus-managed bridge with no uplink,
# no NAT and no DHCP — the air-gapped detonation net replacing mal-isolated.xml.
{ pkgs, ... }:
{
  virtualisation.incus = {
    enable = true;
    ui.enable = true;

    # Day-0 state via `incus admin init --preseed` (runs once at activation;
    # additive — it won't delete entities you create later in the UI/CLI).
    preseed = {
      # Bind the API + web UI on all interfaces for LAN access.
      config."core.https_address" = ":8443";

      storage_pools = [
        {
          # dir backend: root disk is plain ext4 (no ZFS/btrfs on this box).
          # Lives under /var/lib/incus/storage-pools/default.
          name = "default";
          driver = "dir";
        }
      ];

      networks = [
        {
          # Air-gapped malware-analysis net: no uplink, no NAT, no DHCP
          # (guests get static 10.13.37.x inside the OS, as before).
          name = "malbr0";
          type = "bridge";
          config = {
            "ipv4.address" = "10.13.37.1/24";
            "ipv4.nat" = "false";
            "ipv4.dhcp" = "false";
            "ipv6.address" = "none";
          };
        }
      ];

      profiles = [
        {
          name = "default";
          devices = {
            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
            eth0 = {
              name = "eth0";
              nictype = "bridged";
              parent = "br0";
              type = "nic";
            };
          };
        }
        {
          # `incus init <name> --vm --profile isolated` for detonation guests.
          name = "isolated";
          devices = {
            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
            eth0 = {
              name = "eth0";
              network = "malbr0";
              type = "nic";
            };
          };
        }
      ];
    };
  };

  # Manage as the `playground` user without sudo (admin socket group), or
  # remotely via `incus remote add playground https://192.168.1.217:8443`.
  users.users.playground.extraGroups = [ "incus-admin" ];

  # API + web UI. Merges with common's [ 22 ].
  networking.firewall.allowedTCPPorts = [ 8443 ];

  # Image-fetch helpers kept from the libvirt days: Kali ships prebuilt images
  # as .7z, wget for the multi-GB downloads. qemu/OVMF/spice come in via the
  # incus module itself.
  environment.systemPackages = with pkgs; [
    p7zip
    wget
  ];
}
