# hosts/lan/playground/libvirt.nix
#
# playground as the libvirt/KVM host for the security lab (Kali, Parrot, REMnux,
# FlareVM). Host enablement only: libvirtd + TPM 2.0 (swtpm) so the Windows FlareVM
# can boot. UEFI/OVMF firmware is auto-discovered from QEMU on 25.11 (the old
# qemu.ovmf option is gone). AMD-V + /dev/kvm are present.
#
# Companion modules / state: ./bridge.nix is the br0 bridge that puts guests on the
# LAN; ./lan-br0.xml is the libvirt network that attaches them to it; ./mal-isolated.xml
# is an air-gapped host-only network (no uplink/NAT) for malware work (REMnux + a
# victim VM, no LAN/internet path). The VM domains live as committed XMLs under
# ./domains/ (Kali/Parrot/REMnux from official images + a manual FlareVM) — see
# ./domains/README.md for the per-VM build runbook and the network-isolation model.
{ pkgs, ... }:
{
  virtualisation.libvirtd = {
    enable = true;
    # Don't auto-start guests at boot until each domain is vetted; flip per-VM
    # with `virsh autostart <dom>` once it boots cleanly on its network (lan-br0
    # or mal-isolated).
    onBoot = "ignore";
    onShutdown = "shutdown";
    qemu.swtpm.enable = true; # TPM 2.0 - FlareVM (Win11) needs it
  };

  # Manage as the `playground` user (virsh against qemu:///system), or remotely
  # via `virt-manager -c qemu+ssh://playground/system`.
  users.users.playground.extraGroups = [ "libvirtd" ];

  # VM-import tooling: qemu-img (qcow2 convert), p7zip (Kali ships its prebuilt
  # QEMU image as a .7z), wget (fetch the multi-GB appliance images — REMnux/Parrot
  # OVAs). tar/xz/gzip for OVAs are already in the base system.
  environment.systemPackages = with pkgs; [ qemu-utils p7zip wget ];
}
