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
| playground (.217) | Incus lab | `--on playground` | Single NIC on a `br0` bridge; network changes need care. |
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

## Grafana

Grafana's DB encryption key comes from sops (`grafana_secret_key` in
`secrets/mgmt.yaml`), referenced with Grafana's `$__file{}` provider. It was
briefly pinned to upstream's old public default during the 26.05 upgrade; see the
comment in `hosts/lan/mgmt/modules/monitoring.nix` for why that is gone.

**Rotating `secret_key` makes every previously encrypted DB value unreadable.**
Grafana has no supported in-place rotation, so a rotation means resetting state.

Move the **whole state directory**, not just `grafana.db`. Grafana 13 keeps
unified-storage state in `/var/lib/grafana/data/` as well, and a fresh
`grafana.db` beside a stale `data/` leaves the two stores disagreeing — which
surfaces as `Datasource provisioning error: data source not found`, i.e. exactly
the failure you were trying to clear:

```sh
ssh mgmt
sudo systemctl stop grafana
sudo mv /var/lib/grafana /var/lib/grafana.bak-$(date +%F-%H%M)
sudo systemctl start grafana        # start it by hand first; faster to diagnose
                                    # than a 40s colmena round trip
```

If the unit dies with `status=200/CHDIR`, the state directory is simply missing:
recreate it and start again. `monitoring.nix` sets `StateDirectory=grafana` so
systemd does this itself, but a host still running an older generation will not
have that yet.

```sh
sudo install -d -o grafana -g grafana -m 0700 /var/lib/grafana
```

`grafana-pre-start` recreates the `conf` and `tools` symlinks, and `plugins`
re-downloads, so the directory rebuilds itself.

Nothing of value is lost by this: datasources, dashboards and alert rules are all
provisioned declaratively from the flake. What *is* lost is anything created
through the UI — ad-hoc dashboards, users beyond the provisioned admin, API keys.

If `grafana.service` fails with `Datasource provisioning error: data source not
found`, the on-disk DB is the problem, not the config — that exact failure kept
mgmt's Grafana down from 2026-07-17 and blocked every `colmena apply --on mgmt`,
because a failed unit makes activation fail. Reset the DB as above.

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
nix build .#checks.x86_64-linux.mgmt-backup # the backup writes an archive + its success metric
nix fmt                                     # nixfmt + statix + deadnix (also a check)
```

The VM tests are hermetic (no network, no real hosts). `nix fmt` formats and lints
the whole tree, and the same check (`checks.x86_64-linux.formatting`) gates CI.

## Backups

State that isn't in the repo and would be lost on a reinstall:

| What | Where | Notes |
|---|---|---|
| Media library | NAS 192.168.1.213:/srv/media | Back up the NAS. |
| mgmt service secrets | `mgmt:/var/lib/mgmt-secrets/` | NetBox/Snipe-IT/cache keys. Auto-backed-up — **verify, don't assume** (below). |
| step-ca root + intermediate | `mgmt:/var/lib/private/step-ca/` | Lose it and every device re-trusts. Auto-backed-up — **verify, don't assume** (below). |
| SSH host keys | `/etc/ssh/ssh_host_*` | The sops identity; keep across re-images. |
| sops secrets | `secrets/*.yaml` | Safe in git (encrypted). |
| ATMons world | `hacktop:/srv/minecraft/atmons` | Players' work, and the only griefing rollback on an open server. Daily 04:00 local, quiesced, auto-verified monthly. |

`backup.nix` runs daily at 03:30: it streams `/var/lib/private/step-ca`,
`/var/lib/mgmt-secrets` and — when NetBox is enabled — `/var/backup/postgresql`
through `age` to `192.168.1.213:/srv/media/_backups/mgmt/`, keeping the newest 14.
Restore on the desktop:

```sh
age -d -i ~/.config/sops/age/keys.txt mgmt-state-<ts>.tar.age | sudo tar -C / -xv
```

### Confirm the backup is real, not merely scheduled

On 2026-07-24 the table above said "Auto-backed-up" while `mgmt-backup.service`
had failed every night since it was written and had **never once succeeded**: an
optional source path (`/var/backup/postgresql`, produced by NetBox, whose import
is commented out) was handed to `tar` unconditionally, so the run aborted and
step-ca's only off-box copy was never written. A green timer is not a backup.

```sh
# did the last run actually produce an archive? this file is written only on success
ssh deploy@192.168.1.222 cat /var/lib/node-exporter-textfile/mgmt_backup.prom
ssh deploy@192.168.1.222 sudo ls -la /mnt/nas/_backups/mgmt/

# and can it be restored? worth doing occasionally, on the desktop:
age -d -i ~/.config/sops/age/keys.txt mgmt-state-<ts>.tar.age | tar -tv | head
```

`checks.x86_64-linux.mgmt-backup` covers the regression, and the `BackupStale`
alert reads the metric above. Note that a failed run of the old script still left
a plausible-looking `mgmt-state-*.tar.age` on the NAS built from a truncated tar
stream — treat any archive dated before 2026-07-24 as unverified until you have
listed it with the command above.

Loki's data (`mgmt:/var/lib/loki`) isn't backed up; it refills from the journals.

### The ATMons world

`hosts/lan/hacktop/minecraft-backup.nix` runs daily at 04:00 **local** time (not
UTC — `time.timeZone` is `America/Los_Angeles`, and systemd calendar specs use
the system timezone). It pauses saving, flushes the world, tars it through `age`
to the NAS, keeps the newest 14, then re-enables saving.

Unlike mgmt's backup, these archives carry **two** age recipients: the admin key
and hacktop's own SSH host key. That second one is what lets hacktop verify its
own backups — `minecraft-backup-verify.service` runs monthly, decrypts the newest
archive and walks every tar header. It also means a hacktop compromise can read
historical worlds, which was judged an acceptable price for verifiability.

```sh
# proof, not vibes: written only on a successful run
ssh deploy@192.168.1.26 cat /var/lib/node-exporter-textfile/minecraft_backup.prom
#   minecraft_backup_quiesced 0  means the archive may catch a partial save
ssh deploy@192.168.1.26 sudo systemctl start minecraft-backup-verify   # verify on demand

# restore, on the desktop (stop the server first):
age -d -i ~/.config/sops/age/keys.txt atmons-world-<ts>.tar.age | sudo tar -C /srv/minecraft -xv
```

Alerts: `MinecraftBackupStale`, `MinecraftBackupNotQuiesced`,
`MinecraftBackupShrank`, `MinecraftBackupUnverified`.

## The ATMons Minecraft server

**The console is not a terminal.** It is a systemd FIFO
(`/run/minecraft/atmons.stdin`), so `tmux attach` no longer exists:

```sh
journalctl -fu minecraft-server-atmons     # read the console
sudo mc-console send 'list'                # write to it
sudo mc-console up                         # is it writable at all?
```

**Never** write to that path with a shell redirect. If the socket unit happens to
be down, `echo x > /run/minecraft/atmons.stdin` creates a *regular file* there,
and the socket then refuses to start — the server never comes back until someone
removes it by hand. `mc-console` exists solely to make that impossible, and
`checks.x86_64-linux.minecraft-console` keeps it that way.

**Roles.** Policy lives in git (`hosts/lan/hacktop/atmons-ranks.nix`, generated
into `world/serverconfig/ftbranks/ranks.snbt`); membership lives on the server.
So `/ftbranks add <player> trusted` persists, but editing ranks in-game does not
— the file is re-copied from the store on every start. `trusted` grants nothing
in-world; it only unlocks `/color`.

**Ops are declarative**, so in-game `/op` and `/deop` are reverted at the nightly
restart — put operators in the `operators` attrset in `minecraft.nix` instead.

**Bans are not.** `nix-minecraft` only manages `banned-players.json` when
`bannedPlayers` is non-empty, and it is unset, so in-game `/ban` writes that file
directly and persists. Setting `bannedPlayers` would flip that behaviour. Either
way, ban the *username*: cloud1's masquerade makes every player `10.100.0.1`, so
`/ban-ip` is useless and the only place an address can be blocked is cloud1's
nftables.

The server restarts nightly at ~05:00 local with 15/5/1-minute in-game warnings,
because a 374-mod pack leaks — it was at 11.6 GB RSS after five days against the
old 8 GB heap cap. The heap is now 12 GB fixed (`Xms == Xmx`, pre-touched), so
expect ~15–16 GB RSS from startup rather than a climb to it; `minecraft.nix` has
the RAM arithmetic against the CI runner that shares this box.

### Updating the modpack

Everyone must update their CurseForge client in the same window — a client on
the old pack cannot join. So this is a coordinated change, not a quiet one.

Find the new server-pack file id (the *server* pack, not the client zip):

```sh
curl -s 'https://www.curseforge.com/api/v1/mods/1356598/files?pageSize=5&sort=dateCreated&sortDescending=true' | jq '.data[] | {id, displayName}'
curl -s 'https://www.curseforge.com/api/v1/mods/1356598/files/<clientFileId>/additional-files'
```

The CDN URL splits the id after 4 digits: `8572602` → `files/8572/602/`. Then
`nix-prefetch-url --type sha256 <url>` (≈1 GB, and it seeds the store so the
later build does not re-download), and `nix hash convert --to sri` for the hash.

Before editing, check the four things `minecraft.nix` assumes about the zip —
each is a comment there that goes stale silently:

```sh
unzip -Z1 <zip> | grep -i crashassistant            # the installPhase `rm` glob must still match
unzip -Z1 <zip> | grep '^kubejs/server_scripts/'    # nothing named atmons_color.js
unzip -p  <zip> kubejs/server_scripts/modpack/commands.js | grep -i literal   # nothing registering "color"
unzip -p  <zip> startserver.sh | grep NEOFORGE_VERSION
```

Then diff the mod list against the old zip. **Mod removals are the world risk** —
missing block/entity registries eat chunks; pure version bumps and additions do
not. 1.1.1 → 1.2.0 removed nothing, which is why it was a safe one.

**The NeoForge bump usually forces a `nix flake update nix-minecraft`, and that
input controls the JVM.** Upstream now derives the JDK from
`java_versions.getLatest`, so a routine bump moved the same NeoForge build from
`openjdk-headless-21` to `openjdk-25`. `minecraft.nix` pins `jre_headless` back
to `pkgs.jdk21_headless` for that reason — keep the pin, and check what actually
landed rather than trusting it:

```sh
nix derivation show -r "/etc/nixos#nixosConfigurations.hacktop.config.system.build.toplevel" \
  | grep -o 'openjdk-[a-z]*-\?[0-9][0-9.+]*' | sort -u     # expect only 21.x
```

Deploy takes the server down for a few minutes (12 GB of pre-touched heap plus
374 mods is a slow boot). Roll back with `colmena apply --on hacktop` from the
previous commit; the world is untouched by a downgrade only if no new mod wrote
into it, so take the backup seriously — `minecraft-backup.service` runs at 04:00,
or start it by hand first.

### Attributing an incident to a source address

The game server logs a **username**; cloud1 masquerades, so the address it sees
is always `10.100.0.1`. The real client address exists at exactly one place: the
`mc-conn` line cloud1's nftables writes as the connection crosses the forward
hook, before the masquerade. Grafana → **ATMons - Security & Attribution** puts
the two side by side for exactly this.

```sh
# 1. when did they join?  (Loki, or on the box)
{unit="minecraft-server-atmons.service"} |= `joined the game`

# 2. what connected around then?
{host="cloud1"} |= `mc-conn `        # SRC=<real address>
```

This is correlation by timestamp, not proof. With several people joining inside
the same few seconds it narrows the field rather than identifying someone — say
so out loud before acting on it.

To actually block an address, it has to be done on cloud1 (nftables); a
`/ban-ip` on the game server is meaningless behind the masquerade.

### Moderation

```sh
sudo mc-console send 'ban <player> <reason>'   # persists; see the note above
sudo mc-console send 'kick <player> <reason>'
sudo mc-console send 'pardon <player>'
sudo mc-console send 'banlist'
sudo mc-console send 'mute <player> 10m'       # FTB Essentials, chat only
```

The pack also ships its own KubeJS banlist (`server_banlist_config.json`, read by
`kubejs/server_scripts/banlist_script.js`) which bans *items*, replaces banned
block entities with signs, and blocks banned mob spawns — worth knowing before
reaching for a mod.

### Diagnosing lag

`spark` is already in the pack and works from the console. This is the response
to a `MinecraftTickLag` alert:

```sh
sudo mc-console send 'spark tps'
sudo mc-console send 'spark health'
sudo mc-console send 'spark profiler start'
# ... let it run through the bad period ...
sudo mc-console send 'spark profiler stop'
```

`observable` is also installed and reports lag by entity/block.

`spark` answers "what is slow *right now*". For a stall that already happened,
the JVM writes a GC + safepoint log to `/var/log/minecraft-atmons/gc.log`
(5 × 32 MB, rotated by the JVM, outside `/srv` so the nightly world backup does
not sweep it up):

The files are `0660 minecraft:minecraft` (the unit's `UMask=0007`), so reading
them needs `sudo` — and `deploy` has no passwordless sudo, so use `ssh -t` or
just run these on the box:

```sh
ssh -t deploy@192.168.1.26

# every stop-the-world pause over 1s, GC-caused or not. Total: is in NANOseconds
# — the legacy "application threads were stopped" line does not exist under
# unified logging, don't grep for it.
sudo awk -F'Total: ' '/Safepoint /{split($2,t," ");
  if (t[1]+0 > 1e9) printf "%8.2f s  %s\n", t[1]/1e9, $0}' /var/log/minecraft-atmons/gc.log

# heap occupancy either side of each collection — is it filling up over the day?
sudo grep -E 'Pause (Young|Full)' /var/log/minecraft-atmons/gc.log | tail -40
```

Rotation is the JVM's own (`gc.log`, then `gc.log.0`…`gc.log.4`), and it starts
a fresh file on every restart — so a nightly-restart cycle is roughly one file.

This distinguishes the two causes of a "Can't keep up!" line, which `spark`
after the fact cannot. Read the **safepoint name** on any multi-second pause:

- `G1CollectForAllocation` / `Pause Full` → a **collector pause**. The heap is
  the problem; the fix is more heap or less garbage, and the `Pause Young` lines
  will show occupancy climbing toward the cap through the day.
- anything else, or tick lag with **no** pause of comparable length → the tick
  did six seconds of honest work. The fix is less per-tick work (`spark
  profiler`, entity/chunk load), and more heap will do nothing.

They need opposite fixes, so check here before tuning anything.

Baseline as of 2026-08-02, worth knowing before reading this as an emergency:
the server produced ~16 `Can't keep up!` lines/day at 1–2 players, worst 14.1 s.
`MinecraftTickLag` only fires above 10 in 15m, so that drip does not alert.

### Surgical grief repair

Restoring the whole world costs everyone a day. A region file covers 512×512
blocks, so `region = floor(coord / 512)` — extract just the affected one:

```sh
# griefed around x=6500, z=-5300  ->  r.12.-11.mca
age -d -i /etc/ssh/ssh_host_ed25519_key atmons-world-<ts>.tar.age \
  | tar -xf - atmons/world/region/r.12.-11.mca
```

Stop the server, drop the file into `/srv/minecraft/atmons/world/region/`, start.

### Known blind spot: no command auditing

There is **no record of what commands anyone ran** — verified as zero
`issued server command` lines across 30h of journal, including for `/ftbranks`
commands that were definitely executed. Vanilla's `logAdminCommands` only covers
commands that emit feedback, and most mod commands do not. Closing this properly
needs a mod. Written down so it is a known gap rather than a false sense of
coverage.

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
