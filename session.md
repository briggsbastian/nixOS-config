# Session: Fleet Cleanup + Landing Page

## What the user wants
- Clean up stale branches, merge what's valuable, abandon what isn't
- Replace Homepage + Launchpad with a single pane of glass at `mgmt.lan`
- Landing page: fleet health bars, active alerts, uptime summary with slideout, service tiles, clock
- Budget tracker stays as its own app at `budget.mgmt.lan`, gets a tile under Infrastructure
- All servers in health bar (mgmt, media, hacktop, cloud1)
- Uptime bars from Prometheus blackbox probes, 30s poll
- Slideout shows ALL services; probed ones get uptime bars, non-probed show "—"
- Homepage tile layout (no orbit animation)

## What was done before this session
- Steps 1-7 already completed in interactive chat:
  1. Dropped Hyprland session (flake target, system config, home-hypr.nix, dotfiles/hypr/)
  2. Disabled Flatpak auto-updates
  3. Dropped AppImage binfmt
  4. Removed Claude Desktop (flake input + package)
  5. Moved deploy tools (sops, ssh-to-age) from system packages to devShell only
  6. Dropped NAS mount (nas.nix)
  7. Retired playground (host, secrets, DNS, monitoring, docs, CI matrices, zsh aliases)

## Phase 1: Branch cleanup

### To commit
- All the changes from steps 1-7 above (currently uncommitted in working tree)
- Branch: `feat/desktop-cleanup`

### To merge into main
- `chore/retire-playground` — moves playground to `attic/` (cleaner than our manual delete)
- `feat/fleet-users` — unified `briggs` at uid 1000
- `feat/atmons-roles` — Minecraft: roles, /color, console-to-journal, heap sizing, backups, VM tests, monitoring, proxy metrics
- `fix/mc-backup-retention` — NAS monitoring at 94%, backup pruning
- `feat/budget-tracker` — budget tracker at `budget.mgmt.lan`

### To abandon
- `feat/sso-authelia` — just CA trust prep for unfinished SSO

### To keep (HOLD)
- `fix/hacktop-ci-oom-priority` — marked "HOLD until measured"

### To delete (merged branches)
- Local: `feat/loki-crashloop-rule`, `feat/siem-auditd`, `feat/siem-drop-log-noise`, `fix/alloy-eve-log-tail`, `fix/recyclarr-v8-config`, `fix/suricata-alert-actionable-only`, `fix/suricata-ics-rules`, `fix/suricata-restart-on-ruleset-change`, `fix/suricata-trim-sources`, `migrate/wazuh-to-loki`
- Remote: `origin/feat/isc-audit-schedule`, `origin/feat/isc-state-and-alerts`, `origin/fix/mgmt-ssh-password-auth`, `origin/fix/newspaper-https`, `origin/isc-state`, `origin/automated/flake-lock-bump`

### Worktrees to delete
- `worktree-agent-a323dcd65704bdeaf`
- `worktree-agent-a4badb684cb3a502a`

## Phase 2: Landing page (single pane of glass)

### New files
- `hosts/lan/mgmt/modules/landing-page.nix` — nginx vhost + static site
- `hosts/lan/mgmt/modules/landing-page/site/index.html` — the page
- `hosts/lan/mgmt/modules/landing-page/site/style.css` — styles
- `hosts/lan/mgmt/modules/landing-page/site/app.js` — JS logic

### Page sections (top to bottom)
1. **Fleet health** — 4 hosts (mgmt, media, hacktop, cloud1), CPU/mem/disk bars, green/yellow/red
2. **Active alerts** — count badge + list of firing alerts from Alertmanager API
3. **Uptime summary** — "All services healthy" or "N degraded" with slideout
   - Slideout: ALL services, probed ones get uptime bars from `avg_over_time(probe_success{job="blackbox-tls"}[30d])`, non-probed show "—"
   - Red dot on services with issues (probe failing, active alert, or uptime < 95%)
4. **Service tiles** — hardcoded DATA array, categories: Security, Observability, Infrastructure (includes Budget), Media, Games
5. **Clock** — top-right

### API access
- nginx proxy locations: `/api/prometheus/` → `http://127.0.0.1:9090/`, `/api/alertmanager/` → `http://127.0.0.1:9093/`
- JS fetches `/api/prometheus/api/v1/query` and `/api/alertmanager/api/v2/alerts`
- Poll every 30s
- Graceful degradation: show "—" if API unreachable

### Files to modify
- `hosts/lan/mgmt/modules/nginx.nix` — change `mgmt.lan` from proxy to static root, remove `home.mgmt.lan`, remove `launchpad.mgmt.lan`
- `hosts/lan/mgmt/modules/monitoring.nix` — remove `services.homepage-dashboard` block (~200 lines), remove "Lab" section from Homepage services
- `hosts/lan/mgmt/modules/launchpad.nix` — DELETE
- `hosts/lan/mgmt/modules/launchpad/` — DELETE
- `MAINTENANCE.md` — update references
- `README.md` — update references

### Prometheus queries
- Fleet CPU: `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
- Fleet memory: `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100`
- Fleet disk: `(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100`
- Uptime per target: `avg_over_time(probe_success{job="blackbox-tls"}[30d]) * 100`
- Current probe status: `probe_success{job="blackbox-tls"}`

### Service list for slideout
**Probed (have blackbox-tls targets):**
AdGuard, Grafana, Alertmanager, ntfy, Git, Cache, CA, Status, ntopng, Snipe-IT, Newspaper, Budget
(NetBox commented out — no probe until re-enabled)

**Not probed (direct IP:port):**
Jellyfin, Radarr, Sonarr, Prowlarr, Bazarr, NZBGet, Kavita, All the Mons

### Verification
- `nix flake check` passes
- `colmena apply --on mgmt` deploys
- Page loads at `https://mgmt.lan` with all sections working

## What's next after this session
- Deploy to mgmt: `colmena apply --on mgmt`
- Verify landing page at `https://mgmt.lan`
- Check fleet health bars show correct data
- Check active alerts widget
- Check uptime slideout
- If any API proxy issues, debug nginx config
- Consider iterating on the landing page design based on usage
