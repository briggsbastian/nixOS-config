# playground lab VMs

Domain definitions for the security lab guests on `playground`. The **host is
ready** — `libvirtd` + swtpm + the `lan-br0` bridged network are live, and the
import tools (`qemu-img`, `7z`, `tar`, `xz`) are installed (see `../libvirt.nix`).
Each guest sits **directly on the LAN** via `lan-br0` (= `br0`), so it pulls a
real DHCP lease and is reachable from anywhere on the network (and from Guacamole
on this host).

The disk images are **not committed** (multi-GB, and licensing) — only these
domain XMLs are. Build each VM by fetching its image, converting to qcow2,
dropping it in `/var/lib/libvirt/images/`, then `virsh define` + `virsh start`.

> **Why this is a runbook and not "already built":** these are GUI VMs with no SSH
> by default, so a headless build can't be *verified* — first boot needs a console.
> Use **Guacamole** (`https://playground:8080` / the box) or `virt-viewer
> -c qemu+ssh://playground/system <name>` to drive the console and confirm boot.

All commands run **on playground**, and the image steps need root (the libvirt
pool is root-owned): `ssh playground@192.168.1.217`, then `sudo` as shown.

---

## Common flow

```sh
cd /var/lib/libvirt/images          # sudo for writes here
# 1. fetch + convert the image to <name>.qcow2 (per-VM below)
# 2. define + start from the committed XML:
virsh -c qemu:///system define /etc/nixos/hosts/playground/domains/<name>.xml
virsh -c qemu:///system start <name>
virsh -c qemu:///system list                       # Running?
# 3. open the console in Guacamole (VNC) and finish setup
```

**Firmware:** the Linux templates (`kali`, `parrot`, `remnux`) default to **BIOS**
(most prebuilt appliance images are MBR). If a VM shows no boot device, edit its
XML `<os>` to UEFI: `<os firmware='efi'>…</os>`. FlareVM is already UEFI.

**Find a guest's IP:** it's a LAN DHCP client — check the AdGuard/router lease
table, or from another host `arp -n | grep <mac>`. For a stable address, add a
DHCP reservation on the router for the guest's MAC (the `52:54:00:1a:b0:0X` in
each XML). `ssh kali` works once you enable sshd in the guest + add a host entry.

---

## Kali  (`kali.xml`, MAC `…:01`)
Official prebuilt **QEMU** image (boots directly, login `kali`/`kali`):
1. Download the "QEMU" image from <https://www.kali.org/get-kali/#kali-virtual-machines>
   (a `.7z` containing a qcow2).
2. `7z x kali-linux-*-qemu-amd64.7z` → yields a `.qcow2`.
3. `sudo mv <extracted>.qcow2 /var/lib/libvirt/images/kali.qcow2`
4. Define + start (common flow). If it won't boot, flip the XML to UEFI.

## Parrot  (`parrot.xml`, MAC `…:02`)
From the **OVA** (VirtualBox "Virtual" / Security edition) at
<https://parrotsec.org/download/>:
1. `tar -xf Parrot-*.ova` → `.ovf` + one or more `.vmdk`.
2. `qemu-img convert -O qcow2 Parrot-*.vmdk /var/lib/libvirt/images/parrot.qcow2`
   (then `sudo` to move it into place if you converted elsewhere).
3. Define + start. *(Alt: install from the Parrot ISO — interactive, slower.)*

## REMnux  (`remnux.xml`, MAC `…:03`)
Official **OVA** appliance (login `remnux`/`malware`):
1. Download from <https://docs.remnux.org/install-distro/get-virtual-appliance>.
2. `tar -xf remnux-*.ova` → `.ovf` + `.vmdk`.
3. `qemu-img convert -O qcow2 remnux-*-disk*.vmdk /var/lib/libvirt/images/remnux.qcow2`
4. Define + start. If virtio disk fails to boot, edit the XML disk to
   `bus='sata' dev='sda'` (the OVA was authored for a SATA controller).

## FlareVM  (`flarevm.xml`, MAC `…:04`) — manual Windows build
No downloadable image exists; you build it on your own Windows install.
1. Get a **Windows 10/11 ISO** (<https://www.microsoft.com/software-download>).
   No license needed for a lab — create a **local account** and skip activation
   (an unactivated Windows runs fine with only cosmetic limits).
2. `sudo qemu-img create -f qcow2 /var/lib/libvirt/images/flarevm.qcow2 80G`, drop the
   ISO at `/var/lib/libvirt/images/Win11.iso`, then in `flarevm.xml` **uncomment the
   cdrom disk** and set `<boot dev='cdrom'/>`.
3. Define + start, open Guacamole, install Windows.
   - **Secure Boot:** only the non-Secure-Boot OVMF is on this host. Win11 setup
     normally checks for it; if it blocks, either bypass the check (Shift+F10 →
     `regedit` → `LabConfig` keys `BypassSecureBootCheck`/`BypassTPMCheck=1`) or
     add the Secure-Boot OVMF to `../libvirt.nix` and re-point the loader.
4. After Windows is up: snapshot (`virsh snapshot-create-as flarevm clean-win`),
   then in the VM (elevated PowerShell) run the **FLARE-VM** installer per
   <https://github.com/mandiant/flare-vm> — set the network profile to *Private*,
   expect ~1 hr and several reboots. Snapshot again when done.
5. Switch `<boot>` back to `hd` and remove/disable the cdrom.

---

## Once a VM boots cleanly
- `virsh -c qemu:///system autostart <name>` to start it at host boot (only after
  it's verified — the host's `libvirtd` is `onBoot = "ignore"` by design).
- Commit any XML you tweaked here so the domain stays reproducible.
