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

## Phase 1: Branch cleanup — COMPLETE

### Committed and merged
- `feat/desktop-cleanup` — hyprland, flatpak auto-update, appimage, claude-desktop, nas mount, deploy tools, playground removal → merged into main
- `feat/fleet-users` — unified `briggs` at uid 1000 → already in main (subsumed)
- `feat/atmons-roles` — Minecraft features → merged into main
- `fix/mc-backup-retention` — NAS monitoring, backup pruning → merged into main
- `feat/budget-tracker` — budget tracker → already in main (subsumed by atmons-roles merge)

### Abandoned
- `feat/sso-authelia` — deleted (CA trust prep for unfinished SSO)

### Kept (HOLD)
- `fix/hacktop-ci-oom-priority` — marked "HOLD until measured"

### Deleted branches
- Local deleted: `feat/loki-crashloop-rule`, `feat/siem-auditd`, `feat/siem-drop-log-noise`, `fix/alloy-eve-log-tail`, `fix/recyclarr-v8-config`, `fix/suricata-alert-actionable-only`, `fix/suricata-ics-rules`, `fix/suricata-restart-on-ruleset-change`, `fix/suricata-trim-sources`, `migrate/wazuh-to-loki`, `feat/fleet-users`, `chore/retire-playground`, `feat/atmons-roles`, `feat/budget-tracker`, `feat/desktop-cleanup`, `fix/desktop-oom-swap`, `fix/mc-backup-retention`, `feat/sso-authelia`, `worktree-agent-*`
- Remote deleted: `automated/flake-lock-bump`, `feat/isc-audit-schedule`, `feat/isc-state-and-alerts`, `fix/mgmt-ssh-password-auth`, `fix/newspaper-https`, `isc-state`, `feat/loki-crashloop-rule`, `feat/siem-auditd`, `feat/siem-drop-log-noise`, `fix/alloy-eve-log-tail`, `fix/recyclarr-v8-config`, `fix/suricata-alert-actionable-only`, `fix/suricata-ics-rules`, `fix/suricata-restart-on-ruleset-change`, `fix/suricata-trim-sources`, `chore/retire-playground`, `feat/atmons-roles`, `feat/budget-tracker`, `fix/desktop-oom-swap`

### Worktrees deleted
- `worktree-agent-a323dcd65704bdeaf`
- `worktree-agent-a4badb684cb3a502a`

### Final branch state
- `main` (current, pushed to origin)
- `fix/hacktop-ci-oom-priority` (local only, HOLD)

### Commits on main
```
ea51f83 mgmt: single pane of glass landing page at mgmt.lan
a6c6a7c Merge branch 'fix/mc-backup-retention'
12daaff Merge branch 'feat/atmons-roles'
31a9c6e desktop: cleanup — drop hyprland, flatpak auto-update, appimage, claude-desktop, nas mount, deploy tools from system packages
9192564 monitoring: the NAS was watched by nobody, which is how it reached 94%
8428f6e atmons: 14 dailies is 180 GB of NAS, and the NAS has three weeks left
```

## Phase 2: Landing page — COMPLETE

### New files created
- `hosts/lan/mgmt/modules/landing-page.nix` — nginx vhost + static site + disables homepage-dashboard
- `hosts/lan/mgmt/modules/landing-page/site/index.html` — page structure
- `hosts/lan/mgmt/modules/landing-page/site/style.css` — dark theme styles
- `hosts/lan/mgmt/modules/landing-page/site/app.js` — JS logic (health, alerts, uptime, tiles, clock)

### Files modified
- `hosts/lan/mgmt/modules/nginx.nix` — removed `mgmt.lan` proxy, `home.mgmt.lan`, `launchpad.mgmt.lan` vhosts
- `hosts/lan/mgmt/modules/monitoring.nix` — removed `services.homepage-dashboard` block (~200 lines)
- `hosts/lan/mgmt/configuration.nix` — replaced `launchpad.nix` import with `landing-page.nix`

### Files deleted
- `hosts/lan/mgmt/modules/launchpad.nix`
- `hosts/lan/mgmt/modules/launchpad/` (directory with site/)

### Page layout
1. **Fleet health** — 4 hosts (mgmt, media, hacktop, cloud1), CPU/mem/disk bars, green(<70%)/yellow(70-85%)/red(>85%)
2. **Active alerts** — "All clear" or "N firing" with list from Alertmanager API
3. **Uptime summary** — "All services healthy" or "N services degraded" with click-to-expand slideout
   - Slideout: ALL services grouped by category, probed ones get uptime bars, non-probed show "—"
   - Red dot on services with issues (probe failing, active alert, or uptime < 95%)
4. **Service tiles** — hardcoded categories: Security, Observability, Infrastructure (includes Budget), Media, Games
5. **Clock** — top-right

### API access
- nginx proxies `/api/prometheus/` → `http://127.0.0.1:9090/`
- nginx proxies `/api/alertmanager/` → `http://127.0.0.1:9093/`
- JS fetches via same-origin (no CORS issues), polls every 30s
- Graceful degradation: shows "unavailable" or "—" if API unreachable

### Verification
- `nix flake check` — all checks passed
- Pushed to origin/main

## What's next after this session
- Deploy to mgmt: `colmena apply --on mgmt`
- Verify landing page at `https://mgmt.lan`
- Check fleet health bars show correct data for all 4 hosts
- Check active alerts widget shows firing alerts
- Check uptime slideout shows all services with bars/—
- If any API proxy issues, debug nginx config
- Consider iterating on the landing page design based on usage
