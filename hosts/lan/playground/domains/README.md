# playground lab VMs

Domain definitions for the security lab guests on `playground`. The **host is
ready** — `libvirtd` + the `lan-br0` bridged network are live, and the import
tools (`qemu-img`, `7z`, `tar`, `xz`) are installed (see `../libvirt.nix`). The
guest sits **directly on the LAN** via `lan-br0` (= `br0`), so it pulls a real
DHCP lease and is reachable from anywhere on the network (and from Guacamole on
this host).

The disk images are **not committed** (multi-GB, and licensing) — only the
domain XMLs are. Build a VM by fetching its image, converting to qcow2, dropping
it in `/var/lib/libvirt/images/`, then `virsh define` + `virsh start`.

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

**Firmware:** the `kali` template defaults to **BIOS** (most prebuilt appliance
images are MBR). If a VM shows no boot device, edit its XML `<os>` to UEFI:
`<os firmware='efi'>…</os>`.

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

---

## Isolated network (for future malware work)

`mal-isolated` (`../mal-isolated.xml`) is a host-only bridge (`virmal0`) with **no
`<forward>`, no uplink, no NAT** — guests on it have no path to the LAN or
internet. It's left defined for future detonation work (a victim VM + an analysis
VM, statically addressed, INetSim faking the internet). Nothing uses it today. By
contrast `lan-br0` puts guests first-class on `192.168.1.0/24` — convenient, but
**never** for anything you actually detonate.

---

## Once a VM boots cleanly
- `virsh -c qemu:///system autostart <name>` to start it at host boot (only after
  it's verified — the host's `libvirtd` is `onBoot = "ignore"` by design).
- Commit any XML you tweaked here so the domain stays reproducible.
