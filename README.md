# nixOS fleet

One flake for my homelab: a desktop plus five servers, all NixOS. Servers are
deployed over SSH with [Colmena](https://github.com/zhaofengli/colmena) from the
desktop. Secrets are [sops-nix](https://github.com/Mic92/sops-nix), and each host
decrypts its own with its SSH host key. The desktop runs nixpkgs unstable; the
servers stay on stable (nixos-25.11).

## Hosts

| Host | Role |
|------|------|
| desktop | KDE desktop, and the box I deploy from. |
| mgmt | The LAN's core: AdGuard DNS, an nginx + step-ca reverse proxy, Prometheus/Grafana, a Loki + Alloy log stack with Alertmanager/ntfy alerts, NetBox, Forgejo, a Harmonia cache, and PXE boot. It runs DNS and PKI for the house, so I deploy it carefully. [Details](hosts/lan/mgmt/README.md). |
| media | Jellyfin, the *arr stack, and Kavita, served off the NAS over NFS. |
| playground | A libvirt security lab with a Guacamole gateway and a Cockpit VM console. |
| hacktop | Staging, CI builds, and a Cobblemon Minecraft server. |
| cloud1 | A Linode VPS, installed with disko + nixos-anywhere. |

Internal services sit behind a private CA. They're reached at `*.mgmt.lan` (AdGuard
resolves the names) over TLS from step-ca, and hosts pull from mgmt's binary cache.
The shared baseline (key-only SSH, nftables, the `deploy` user, sops, the Alloy log
shipper, CA trust) lives in [modules/](modules).

## Layout

```
flake.nix             nixosConfigurations + Colmena hive + devShell
modules/              shared modules (common, internal-ca, siem-lite, ...)
hosts/<zone>/<host>/  per-host config, grouped by zone (lan / cloud / workstation)
pkgs/                 packages not in nixpkgs
secrets/              sops-encrypted per-host secrets
.sops.yaml            sops recipients (public keys only)
```

## Deploying

```sh
nix develop                  # colmena + the sops/age toolchain
colmena apply --on <host>    # one host
colmena apply --on @server   # all servers
```

Updates, GC, secrets, TLS, backups, and rollback are in [MAINTENANCE.md](MAINTENANCE.md).
