# Prompt for Claude Design — Homelab Topology Graph

Create a single, maximally detailed **infrastructure topology diagram** of my NixOS homelab fleet (option namespace "alcove", flake at /etc/nixos, deployed with Colmena). Every fact below is accurate and extracted from the actual config — do not invent nodes or edges. Prioritize completeness and correctness over minimalism; this is a reference poster, not a marketing slide.

## Layout: five nested zones

Arrange the diagram as bounded zones (nested boxes), roughly left→right = public→private:

1. **Internet / Public** — external actors: Minecraft players, admin's phone (ntfy), public DNS (`play.briggsbastian.com` A record), Quad9/Cloudflare upstream DNS, cache.nixos.org, CurseForge CDN.
2. **Linode Cloud (us-sea)** — host `cloud1` only.
3. **WireGuard overlay `wg-mc` 10.100.0.0/24** — a thin tunnel zone bridging cloud1 and hacktop (draw as a pipe/corridor between the cloud and LAN zones, not a full box).
4. **Home LAN 192.168.1.0/24** — gateway/router (UniFi) at `192.168.1.1`; hosts `mgmt`, `media`, `hacktop`, `desktop`, plus a non-NixOS **NAS** at `192.168.1.213`.

Inside `mgmt`, draw its many services as sub-nodes within the host box (it's the hub — give it the most space).

## Node inventory

### desktop (hostname `nixos`) — workstation & control node, DHCP IP
- KDE Plasma 6 workstation, user `briggs`. Firewall disabled, SSH server on.
- **Colmena control node**: holds the deploy SSH key (`briggs@nixos`) and the sops admin age key. Deploys every server; rebuilds itself locally (`rebuild-kde`).
- DNS resolvers: 192.168.1.222 (AdGuard) then 9.9.9.9. Trusts the step-ca root. Jellyfin Media Player client (endpoint configured in-app).

### mgmt — 192.168.1.222 (eno1) — LAN core: DNS + PKI + observability + git
Pinned nixpkgs (`nixpkgs-mgmt`); Colmena tag `@gated`. "A bad deploy takes DNS and PKI down for the house." All web services bind 127.0.0.1 and are fronted by **nginx :80/:443** with per-vhost TLS certs from the local step-ca via ACME. Firewall: 22, 53 (TCP+UDP), 80, 443, 2222, 3100 (LAN-source-only), pixiecore UDP 67/69/4011 + TCP 8088/8089.

Services (listen → vhost):
- **AdGuard Home** DNS `0.0.0.0:53` (web 127.0.0.1:3000 → `adguard.mgmt.lan`). Rewrites: `mgmt.lan` & `*.mgmt.lan` → 192.168.1.222. Upstreams: Quad9 DoH, 9.9.9.9, 1.1.1.1. Whole LAN uses it via router DHCP.
- **step-ca** private ACME CA `127.0.0.1:8443` → `ca.mgmt.lan` (90-day certs for all `*.mgmt.lan` vhosts; root published at `ca.mgmt.lan/root.crt`).
- **nginx** reverse proxy — vhosts: `mgmt.lan`/`home.mgmt.lan` → Homepage dashboard (127.0.0.1:8082); `adguard` →:3000; `status` → Uptime Kuma :3001; `grafana` →:3002; `ntop` → ntopng :3003; `git` → Forgejo :3004; `news` → Newspaper :8377; `cache` → Harmonia :5000; `netbox` →:8001; `alerts` → Alertmanager :9093; `ntfy` →:2586; `ca` → step-ca :8443; `assets` → Snipe-IT (local MySQL).
- **Observability**: Prometheus 127.0.0.1:9090 (scrapes node_exporters + blackbox-TLS probes of every vhost); Loki `0.0.0.0:3100` (journal logs, 30-day retention, LAN-only firewall); Grafana :3002 (datasources: Prometheus default, Loki); Alertmanager :9093 → alertmanager-ntfy bridge :8000 → **ntfy :2586, topic `homelab-alerts`** → admin's phone. Alert rules: NodeDown, NodeDiskFull, NodeMemoryPressure, NodeSwapAlmostFull, SystemdUnitFailed, CertExpiringSoon (14d), TlsProbeDown, SSHBruteForce, SudoFailure. Uptime Kuma :3001. ntopng :3003 sniffing eno1.
- **Forgejo** git `git.mgmt.lan` (HTTP :3004, SSH :2222). Actions enabled; runner lives on hacktop. Also the source of the `newspaper` flake input.
- **Harmonia** Nix binary cache `cache.mgmt.lan` (:5000), signing key `cache.mgmt.lan-1`; fleet hosts use it as extra substituter (cache.nixos.org fallback).
- **NetBox** :8001 (own PostgreSQL + Redis), **Snipe-IT** `assets.mgmt.lan` (own MySQL), **Newspaper** :8377 (05:30 refresh), **pixiecore PXE/netboot.xyz** (:8088/:8089 + DHCP-proxy UDP), **Homepage dashboard** :8082 (tiles link to every service below, including off-box media apps and lab tools).
- **Backup timer 03:30 daily**: tar+age-encrypt `/var/lib/private/step-ca` + `/var/lib/mgmt-secrets` → NFS → NAS `192.168.1.213:/srv/media/_backups/mgmt` (keep 14).

### media — 192.168.1.189 — Jellyfin + *arr stack
- NFS client: mounts NAS `192.168.1.213:/srv/media` at `/mnt/media` (all services depend on this mount).
- Services (all LAN-open): Jellyfin :8096 (Intel QSV /dev/dri transcode), Sonarr :8989, Radarr :7878, Prowlarr :9696, Bazarr :6767, NZBGet :6789 (Usenet-only, no torrents/VPN), Kavita :5000. Internal chain: Prowlarr → Sonarr/Radarr → NZBGet → NAS storage → Jellyfin/Kavita serve it. systemd sandbox hardening on all six.

### hacktop — 192.168.1.26 (lan0 wired; Wi-Fi fallback .241) — staging / CI runner / game server
- **Forgejo Actions runner** (labels `native:host`, `nix:host`, capacity 4, KVM + nixos-test) → registers with `https://git.mgmt.lan`; builds fleet configs and runs VM tests.
- **Minecraft "All the Mons" (ATMons)** NeoForge 1.21.1, :25565 open, **whitelist OFF** — public reach only via cloud1 tunnel.
- **WireGuard `wg-mc` 10.100.0.2** — dials OUT to cloud1 `172.234.232.185:51820`, keepalive 25s (zero inbound ports at home).

### cloud1 — 172.234.232.185 (enp0s3) — Linode Nanode, public front door
- Terraform-managed; ephemeral IP. Linode Cloud Firewall: 22/tcp, 51820/udp, 25565/tcp.
- **WireGuard `wg-mc` 10.100.0.1:51820** (passive listener; sole peer = hacktop 10.100.0.2).
- **nftables NAT relay**: DNAT enp0s3:25565 → 10.100.0.2:25565 over the tunnel + masquerade (players all appear as 10.100.0.1 → username whitelist is the only gate). No HTTP proxy, no TLS.
- **Deliberately opted out**: no internal-CA trust, no node_exporter, no log shipping — unmonitored until the planned fleet mesh ("Project 4C", note as a dashed future element).

### NAS — 192.168.1.213 (not NixOS-managed)
- NFS exports `/srv/media`: media library for `media` host; encrypted-backup dropbox for `mgmt`.

## Edge categories — color-code and put port/protocol labels on every edge

1. **User/web traffic** (solid): LAN clients → AdGuard :53; LAN browsers → mgmt nginx :443 (`*.mgmt.lan`) → each backend; Jellyfin clients (desktop, TVs) → media :8096; Homepage links → media app ports.
2. **Game traffic** (solid, distinct color): players → `play.briggsbastian.com` → cloud1 :25565 → DNAT → wg-mc → hacktop :25565.
3. **DNS**: everything on LAN → AdGuard 192.168.1.222:53 → Quad9/1.1.1.1 upstream; AdGuard rewrites for `*.mgmt.lan`.
4. **PKI/ACME**: nginx (mgmt) + LAN hosts ← 90-day certs ← step-ca ACME `ca.mgmt.lan`; root CA trusted by media, hacktop, desktop (NOT cloud1); blackbox exporter probes every vhost cert.
5. **Metrics** (dashed): mgmt Prometheus ← scrapes node_exporter :9100 on hacktop/media (firewalled to mgmt's IP only) + its own via localhost; cloud1 excluded.
6. **Logs** (dashed): Alloy journal shippers on hacktop/media/mgmt → Loki 192.168.1.222:3100 (LAN-source-only).
7. **Alerts**: Prometheus & Loki-ruler → Alertmanager :9093 → ntfy bridge :8000 → ntfy :2586 → phone via `ntfy.mgmt.lan`.
8. **CI/CD**: desktop → git push → Forgejo :3004/:2222 → hacktop runner polls `git.mgmt.lan` → builds (KVM VM tests) ; fleet hosts pull store paths from Harmonia `cache.mgmt.lan` (fallback cache.nixos.org).
9. **Deploy/SSH** (bold): desktop → Colmena → `deploy@{192.168.1.222, .26, .189, 172.234.232.185}:22` (key-only, scoped sudo); sops secrets decrypted per-host with host SSH keys.
10. **Storage/backup**: media → NFS → NAS `/srv/media`; mgmt → age-encrypted tar 03:30 → NFS → NAS `_backups/mgmt`.
11. **Remote-desktop/console**: *(removed — Guacamole/Cockpit were on playground, now retired)*
12. **Disabled/future** (dashed grey): Project 4C WireGuard mesh (would let mgmt monitor cloud1).

## Style requirements
- Include a **legend** for the edge colors/styles and zone boundaries.
- Label every edge with port/protocol (e.g. "TCP 25565", "ACME HTTP-01", "NFS 4.2", "WG UDP 51820").
- Mark security boundaries prominently: the air-gapped `mal-isolated` net (red), the "no inbound home ports" property of the WG dial-out, the :9100/:3100 firewall source restrictions, and cloud1's untrusted/unmonitored status.
- Show mgmt's internal loopback services as small nodes inside the mgmt box with nginx as the single entry point.
- Dense is fine; overlapping edges are not. Prefer orthogonal routing and grouped/bundled edges per category where it helps readability.
