# Fleet maintenance

How to run the fleet day to day. Everything is deployed with Colmena from the
desktop; you rarely touch a server directly. See [README.md](README.md) for the
layout and [hosts/lan/mgmt/README.md](hosts/lan/mgmt/README.md) for mgmt's services.

Rule of thumb: change the config in this repo, then `colmena apply`. Don't hand-edit
a server, the next deploy reverts it. The only on-box state is under [Backups](#backups).

## Hosts

| Host | Role | Deploy | Notes |
|---|---|---|---|
| mgmt (.222) | DNS / PKI / monitoring | `--on mgmt` | Critical: runs the LAN's DNS and PKI. Pinned nixpkgs, deploy deliberately. |
| media (.189) | Jellyfin + *arr + Kavita | `--on media` | Needs the NAS NFS mount (192.168.1.213). |
| playground (.217) | libvirt lab + Guacamole | `--on playground` | Single NIC on a `br0` bridge; network changes need care. |
| hacktop (.26) | staging / CI / Minecraft | `--on hacktop` | Wired (`lan0`, USB-C dongle @1G); Wi-Fi stays connected as fallback on .241. |
| desktop | desktop + control node | `rebuild-kde` | Not a Colmena target; rebuilds itself. |

`@server` is all four servers, `@gated` is mgmt.

## Deploys

```sh
nix develop                              # colmena + sops/age
colmena apply --on <host>                # build, push, activate
colmena apply --on @server               # all servers
colmena apply dry-activate --on <host>   # show what would change
colmena exec --on @server -- uptime      # run a command everywhere
```

The desktop has its own aliases (in `hosts/workstation/desktop/dotfiles/zsh.nix`):
`rebuild-kde`, `rebuild-test-kde` (trial, reverts on reboot), `rebuild-boot-kde`.

mgmt is gated: a bad deploy takes DNS and PKI down for the house. Always
`dry-activate` first and have a rollback ready. It's pinned to its own nixpkgs, so
a normal apply should show no service restarts.

## Updates

Three nixpkgs inputs, on purpose: `nixpkgs` (unstable) for the desktop,
`nixpkgs-stable` (nixos-26.05) for the servers, `nixpkgs-mgmt` (pinned) for mgmt.

```sh
nix flake update nixpkgs-stable   # bump the servers' channel
colmena apply --on @server
rebuild-kde                        # or `upgrade`: bump, build, diff, confirm, switch
```

Review the closure diff before switching, especially the kernel. mgmt is frozen on
purpose; bump `nixpkgs-mgmt` on its own, diff, and apply in a window.

A scheduled Forgejo workflow (`.forgejo/workflows/lock-bump.yml`, weekly +
`workflow_dispatch`) does the routine bump for you: it updates every input *except*
the pinned `nixpkgs-mgmt`, builds all hosts, and opens a PR — no auto-merge. Review
the diff and merge, then deploy as above.

## Garbage collection

```sh
colmena exec --on @server -- 'df -h /'
sudo nix-collect-garbage --delete-older-than 30d
sudo nix store optimise
```

hacktop auto-GCs weekly (`nix.gc`). List generations with
`nix-env --list-generations --profile /nix/var/nix/profiles/system`.

## Secrets (sops-nix)

Each host decrypts its own secrets at activation with its SSH host key. The admin
age key on the desktop edits everything.

```sh
sops secrets/<host>.yaml                            # edit
sops set secrets/<host>.yaml '["key"]' '"value"'    # set one value
```

Add a host: get its recipient with
`ssh <host> cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age`, add it to
`.sops.yaml` (key + creation_rule), then `sops updatekeys secrets/<host>.yaml`.

A host's age identity is its `/etc/ssh/ssh_host_ed25519_key`, so re-imaging a box
loses access to its secrets unless you keep that key or re-key the files.

## TLS

step-ca issues 90-day certs for `*.mgmt.lan`; nginx renews them via lego timers.
The root lives 10 years in `/var/lib/private/step-ca`. Hosts trust it through
`alcove.internalCa.enable`.

```sh
# what is a service actually serving (from a host that resolves *.mgmt.lan):
echo | openssl s_client -connect 192.168.1.222:443 -servername ca.mgmt.lan 2>/dev/null \
  | openssl x509 -noout -issuer -enddate
# want issuer=CN=mgmt.lan Intermediate CA; "minica" means ACME fell back (see below)
```

ACME validation needs each box to resolve `*.mgmt.lan` itself, so `step-ca.nix` /
`internal-ca.nix` pin the ACME and cache hostnames to 192.168.1.222 in `/etc/hosts`.
Don't remove those pins or certs fall back to the untrusted minica self-signed cert.

## Health

```sh
colmena exec --on @server -- systemctl is-system-running
colmena exec --on @server -- 'systemctl --failed --no-legend'
```

Logs and alerts: every host runs Alloy shipping its journal to Loki on `mgmt:3100`.
Explore in Grafana (Explore -> Loki); the ruler alerts through Alertmanager to ntfy
(`ntfy.mgmt.lan/homelab-alerts`). Check which hosts report with
`curl -s http://127.0.0.1:3100/loki/api/v1/label/host/values` on mgmt.

Metrics and alerts: every LAN server runs a node_exporter (`:9100`, firewalled to
mgmt only); mgmt's Prometheus scrapes them — targets derived from `fleet-hosts.nix`,
the same map Colmena uses — and fires through the same Alertmanager -> ntfy path.
The rules (`hosts/lan/mgmt/modules/monitoring.nix`) are `NodeDown`, `NodeDiskFull`
(>85% on a real local fs), `NodeMemoryPressure`, `NodeSwapAlmostFull`,
`SystemdUnitFailed`, and `CertExpiringSoon` — a blackbox probe of every
`*.mgmt.lan` cert that fires 14 days before expiry, catching a silently-failed
step-ca/lego renewal. cloud1 isn't scraped yet (public VPS, no private path to
mgmt). See active alerts at `alerts.mgmt.lan`.

Dashboards: Grafana, Uptime Kuma (`status.mgmt.lan`), ntopng (`ntop.mgmt.lan`),
landing page (`mgmt.lan`).

## Checks

`nix flake check` evaluates every host + flake output, runs the fmt/lint gate, and
runs the NixOS VM tests. CI (`.forgejo/workflows/ci.yml`) runs the same on every
push; the hacktop runner advertises `kvm` + `nixos-test`, so it can build them.

```sh
nix flake check --show-trace               # everything (eval + lint + VM tests)
nix build .#checks.x86_64-linux.mgmt-ca    # step-ca issues a cert + nginx serves TLS
nix build .#checks.x86_64-linux.log-path   # Alloy ships a journal line into Loki
nix fmt                                     # nixfmt + statix + deadnix (also a check)
```

The VM tests are hermetic (no network, no real hosts). `nix fmt` formats and lints
the whole tree, and the same check (`checks.x86_64-linux.formatting`) gates CI.

## Backups

State that isn't in the repo and would be lost on a reinstall:

| What | Where | Notes |
|---|---|---|
| Media library | NAS 192.168.1.213:/srv/media | Back up the NAS. |
| mgmt service secrets | `mgmt:/var/lib/mgmt-secrets/` | NetBox/Snipe-IT/cache keys. Auto-backed-up. |
| step-ca root + intermediate | `mgmt:/var/lib/private/step-ca/` | Lose it and every device re-trusts. Auto-backed-up. |
| SSH host keys | `/etc/ssh/ssh_host_*` | The sops identity; keep across re-images. |
| sops secrets | `secrets/*.yaml` | Safe in git (encrypted). |

`backup.nix` runs daily at 03:30: it streams `/var/lib/{private/step-ca,mgmt-secrets}`
through `age` to `192.168.1.213:/srv/media/_backups/mgmt/`, keeping the newest 14.
Restore on the desktop:

```sh
age -d -i ~/.config/sops/age/keys.txt mgmt-state-<ts>.tar.age | sudo tar -C / -xv
```

Loki's data (`mgmt:/var/lib/loki`) isn't backed up; it refills from the journals.

## Rollback

```sh
sudo nixos-rebuild switch --rollback   # on the host (needs root/console)
```

Or pick the previous generation at the boot menu. A `test` activation never changes
the boot default, so a power-cycle reverts it; that's the safe way to trial risky
changes on hacktop/playground, which are hard to recover remotely.

## Adding a host

1. `hosts/<zone>/<name>/{configuration,hardware-configuration}.nix`.
2. One line in the `servers` map in `flake.nix`.
3. Add its recipient to `.sops.yaml` + a creation_rule; create `secrets/<name>.yaml`.
4. Bootstrap the `deploy` user once (`sudo nixos-rebuild switch` on the box), then
   it's Colmena-managed. Run `nix flake check` before deploying.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `*.mgmt.lan` cert warning / `minica` issuer | `/etc/hosts` ACME pin missing or step-ca down | check the pins; `systemctl restart step-ca`; restart the `acme-order-renew-*` units |
| Cache falls back to cache.nixos.org | can't resolve/trust `cache.mgmt.lan` | `getent hosts cache.mgmt.lan` should be .222, and `internal-ca.enable` on |
| Host unreachable after a deploy | NetworkManager restart dropped Wi-Fi (hacktop) | console + reboot to last-good generation, redeploy |
| Host missing from Loki | Alloy not shipping | `systemctl status alloy`; check the `systemd-journal` group and that `:3100` is open |
| media *arr not starting | NFS mount down | check the NAS / `systemctl status mnt-media.automount` |
| `nix copy` rejects unsigned paths | deploy user isn't a trusted-user for manual copies | use `colmena apply`, which handles the push |
