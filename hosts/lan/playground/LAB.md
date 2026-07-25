# playground lab runbook (Incus)

The lab stack is Incus (see `./incus.nix`): web UI + API on
<https://192.168.1.217:8443>, CLI as the `playground` user (`incus-admin` group,
no sudo needed). Guests attach to the LAN via the systemd-networkd `br0` bridge
(default profile) or to the air-gapped `malbr0` net (`isolated` profile,
10.13.37.0/24, no uplink/NAT/DHCP).

## First connect (web UI / remote CLI)

Auth is mutual TLS — a client certificate, not a password. This is also why
there is no `*.mgmt.lan` reverse proxy for it: nginx can't forward the
browser's client cert.

1. Browse <https://192.168.1.217:8443>, accept the self-signed server cert.
   The UI walks through creating a client certificate.
2. On playground, trust it — token flow is easiest:

   ```sh
   incus config trust add ui-desktop     # prints a one-time token, paste in the UI
   # or trust an existing cert directly:
   incus config trust add-certificate <client.crt>
   ```

3. Import the generated client cert into the browser
   (Settings → Certificates → Your Certificates), reload.
4. Remote CLI from the desktop: `incus remote add playground https://192.168.1.217:8443`
   (same token flow).

## Kali VM (fresh build)

Kali must be a **VM**, not a container — HTB tooling wants a real kernel.
Check whether the public image server ships a VM variant first:

```sh
incus image list images: kali    # look for TYPE virtual-machine
incus launch images:kali/current lab-kali --vm -c limits.memory=4GiB -c limits.cpu=4
```

If it's container-only (likely), install from the ISO:

```sh
wget https://cdimage.kali.org/current/kali-linux-<ver>-installer-amd64.iso
incus storage volume import default kali-linux-*-installer-amd64.iso kali-iso --type=iso
incus init lab-kali --vm -c limits.memory=4GiB -c limits.cpu=4 -c security.secureboot=false
incus config device override lab-kali root size=60GiB
incus config device add lab-kali installer disk pool=default source=kali-iso boot.priority=10
incus start lab-kali
```

- `security.secureboot=false`: Kali's kernel isn't signed for the default OVMF
  secure-boot keys.
- Console: the UI's graphical console, or `incus console lab-kali --type=vga`
  (plain `incus console` for serial).
- After install: `apt install openssh-server`, note the VM's LAN IP/MAC (real
  DHCP lease via br0), set the router reservation, and re-point the desktop's
  `ssh kali` mapping — the `kali`/`lab` zsh aliases depend on it.
- Detach the installer when done: `incus config device remove lab-kali installer`.
- RAM budget: 12 GB total on this box — don't run a fat Kali and the full
  Decepticon docker stack at once.

## Test / detonation guests

```sh
incus launch images:debian/12 t1                    # throwaway LAN container
incus init victim --vm --profile isolated           # air-gapped VM on malbr0
```

`isolated` guests have no DHCP — static-address inside the guest (10.13.37.x,
gw/none; the host is 10.13.37.1 but routes nowhere).

## One-time migration cleanup (old libvirt/Guacamole state)

Run on playground with sudo, only after Incus is verified working:

```sh
# old libvirt domains + networks
virsh -c qemu:///system list --all        # destroy + undefine each (--nvram for UEFI ones)
virsh -c qemu:///system net-destroy lan-br0;      virsh -c qemu:///system net-undefine lan-br0
virsh -c qemu:///system net-destroy mal-isolated; virsh -c qemu:///system net-undefine mal-isolated
sudo rm -rf /var/lib/libvirt              # includes the old kali.qcow2 (discarded on purpose)
# guacamole leftovers (services already removed from the config)
sudo rm -rf /var/lib/postgresql /var/lib/guacamole /var/lib/tomcat
```

Then drop the dead secret: `sops secrets/playground.yaml` → delete
`guacamole_db_password`.
