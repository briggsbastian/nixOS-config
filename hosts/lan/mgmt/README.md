# mgmt server (192.168.1.222)

The LAN's management box: AdGuard, nginx, step-ca, Prometheus/Grafana,
Loki/Alloy logs with Alertmanager + ntfy, Uptime Kuma, NetBox, Forgejo, ntopng,
Snipe-IT, a Harmonia cache, PXE boot, the morning newspaper, and the Homepage
landing page.

Web UIs all listen on localhost and are fronted by nginx under `*.mgmt.lan`, which
AdGuard resolves to this host. Certs come from step-ca over ACME and renew on their
own; devices just need to trust the root once.

## URLs

| Service | URL | Login |
|---|---|---|
| Homepage | https://mgmt.lan | none |
| AdGuard | https://adguard.mgmt.lan | `briggs` / sops `adguard_password` |
| Grafana | https://grafana.mgmt.lan | `admin` / sops `grafana_admin_password` |
| Alertmanager | https://alerts.mgmt.lan | none (LAN-only) |
| ntfy | https://ntfy.mgmt.lan | none, subscribe to `homelab-alerts` |
| Uptime Kuma | https://status.mgmt.lan | set on first visit |
| ntopng | https://ntop.mgmt.lan | `admin` / `admin` (forces change) |
| NetBox | https://netbox.mgmt.lan | `sudo -u netbox netbox-manage createsuperuser` |
| Forgejo | https://git.mgmt.lan | see modules/forgejo.nix |
| Snipe-IT | https://assets.mgmt.lan | setup wizard |
| step-ca root | https://ca.mgmt.lan/root.crt | - |
| Nix cache | https://cache.mgmt.lan (pubkey at /pubkey) | - |
| Newspaper | https://news.mgmt.lan | none (LAN-only) |

## First-time setup

1. Pin 192.168.1.222 in the router's DHCP, and set it as the DHCP DNS server so
   clients use AdGuard and can resolve `*.mgmt.lan`.
2. Trust the CA: install https://ca.mgmt.lan/root.crt as a root (the committed
   `modules/certs/mgmt-root.crt` is the same cert). Firefox needs
   `ImportEnterpriseRoots`.
3. Create the remaining admin accounts: Uptime Kuma (first visit), NetBox
   (`createsuperuser`), Forgejo (CLI), Snipe-IT (wizard).

Logs and alerting come up on their own: Alloy on every host ships its journal to
Loki here, and the ruler fires alerts through Alertmanager to ntfy. Browse logs in
Grafana under Explore. Grafana's admin password is re-applied from sops on each
start.

## Notes

- Everything is a native service: `systemctl status adguardhome nginx step-ca
  netbox forgejo ntopng harmonia pixiecore grafana prometheus uptime-kuma loki
  alloy alertmanager ntfy-sh morning-newspaper`.
- Runtime secrets (NetBox/Snipe-IT keys, cache signing key) are generated on first
  boot into `/var/lib/mgmt-secrets/`; public material (root cert, cache pubkey) in
  `/var/lib/mgmt-public/`.
- Certs are 90-day leases, renewed by lego timers. The CA root/intermediate live
  10 years in `/var/lib/private/step-ca`.
- Binary cache clients need the substituter + pubkey from /pubkey, plus the root CA.
- Forgejo SSH is on port 2222. PXE-boot any LAN machine for the netboot.xyz menu.
- RAM: roughly 5G of 15G in use; zram swap covers spikes.
