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
virsh -c qemu:///system define /etc/nixos/hosts/lan/playground/domains/<name>.xml
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

## Network isolation & safe detonation

Two libvirt networks exist on this host:

- **`lan-br0`** (`../lan-br0.xml`) — `forward=bridge`: guests become first-class
  hosts on the home LAN (`192.168.1.0/24`). Convenient, but **anything detonated on
  it can scan/spread/phone-home across the whole network.** Fine for tools you never
  *run* live (Kali, Parrot, your own boxes), wrong for live malware.
- **`mal-isolated`** (`../mal-isolated.xml`) — no `<forward>`: a host-only bridge
  (`virmal0`) with **no uplink and no NAT**, so guests have no path to the LAN or
  internet at all. This is where malware runs.

Define the isolated net once (idempotent):
```sh
sudo virsh -c qemu:///system net-define   /path/to/mal-isolated.xml
sudo virsh -c qemu:///system net-autostart mal-isolated
sudo virsh -c qemu:///system net-start     mal-isolated
sudo virsh -c qemu:///system net-list --all          # mal-isolated + lan-br0 active?
```

**Detonation pattern:** REMnux + a victim VM both on `mal-isolated`, statically
addressed (REMnux `10.13.37.10`, victim `10.13.37.20`, gateway/DNS = REMnux). On
REMnux, run **INetSim** (`sudo inetsim`) so the sample's callbacks resolve into a
fake internet instead of the real one. The victim's default route + DNS point at
`10.13.37.10`. The victim has **no** `lan-br0` NIC — ever.

**REMnux's LAN NIC is a deliberate foot-gun, kept down:** REMnux is dual-homed
(NIC1 `mal-isolated` up; NIC2 `lan-br0` `<link state='down'/>`). Raise the LAN NIC
ONLY to update tooling, with no live sample present:
```sh
sudo virsh -c qemu:///system domif-setlink remnux 52:54:00:1a:b0:13 up
#   …in-guest: `remnux upgrade`…
sudo virsh -c qemu:///system domif-setlink remnux 52:54:00:1a:b0:13 down
sudo virsh -c qemu:///system snapshot-create-as remnux clean-base "updated, lan down"
```

**Snapshot discipline:** snapshot a clean state and revert after each run:
```sh
sudo virsh -c qemu:///system snapshot-create-as <vm> clean "pristine"
sudo virsh -c qemu:///system snapshot-revert     <vm> clean    # after analysis
```

**Verify the isolation actually holds** — from the REMnux console with the LAN NIC
down: `ping -c1 192.168.1.1`, `… 192.168.1.222`, `… 8.8.8.8` must ALL fail; raising
the LAN NIC makes only the last two work. (Guacamole console access is unaffected —
it's VNC on the host's loopback, independent of guest NICs.)

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

## REMnux  (`remnux.xml`, MAC `…:03` mal-isolated, `…:13` lan-br0)
Official **OVA** appliance (login `remnux`/`malware`). **Define `mal-isolated`
first** (see "Network isolation & safe detonation" above) — `remnux.xml` is
dual-homed and references it.
1. Download from <https://docs.remnux.org/install-distro/get-virtual-appliance>.
2. `tar -xf remnux-*.ova` → `.ovf` + `.vmdk`.
3. `qemu-img convert -O qcow2 remnux-*-disk*.vmdk /var/lib/libvirt/images/remnux.qcow2`
4. Define + start. If virtio disk fails to boot, edit the XML disk to
   `bus='sata' dev='sda'` (the OVA was authored for a SATA controller).
5. In-guest, set NIC1 (`mal-isolated`) static `10.13.37.10/24`. The LAN NIC is
   down by default — raise it only to run `remnux upgrade` (see isolation section),
   then snapshot a `clean-base`.

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
