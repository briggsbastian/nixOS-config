#!/usr/bin/env bash
#
# upgrade.sh — friendlier flake upgrade + nix-store maintenance
#
# Usage:
#   upgrade.sh                     # update + build + diff + switch (current DE)
#   upgrade.sh kde | hypr          # ... but target a specific config
#   upgrade.sh boot [kde|hypr]     # apply on next reboot instead of now
#                                  # (use this for kernel/driver bumps)
#   upgrade.sh diff                # show closure diff: running vs latest built
#   upgrade.sh gens                # list system generations
#   upgrade.sh gc                  # delete generations older than 14 days
#   upgrade.sh optimise            # dedupe the nix store
#   upgrade.sh rollback            # switch back to previous generation
#
# Flags (for upgrade/boot):
#   --no-update     skip `nix flake update` (rebuild from current lockfile)
#   --yes, -y       don't prompt before switching
#
# What this gives you over plain nixos-rebuild:
#   1. Bumps flake.lock, builds, then prints the *closure diff* — you see
#      exactly which packages (and kernel) change before you commit.
#   2. Asks for confirmation between "here's what's changing" and the switch.
#   3. Uses a /tmp result symlink, so it never litters /etc/nixos with `result`.
#   4. Reuses scripts/rebuild.sh for the actual switch — so error extraction,
#      logging, and rollback hints come along for free.

set -uo pipefail

# ---- paths ---------------------------------------------------------------

FLAKE_DIR="/etc/nixos"
REBUILD="${FLAKE_DIR}/scripts/rebuild.sh"
BUILD_LINK="/tmp/nixos-upgrade-result"

# ---- pretty printing -----------------------------------------------------

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
    GREEN=$'\033[32m'; CYAN=$'\033[36m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    BOLD=""; RED=""; YELLOW=""; GREEN=""; CYAN=""; DIM=""; RESET=""
fi

info()    { echo "${BOLD}==>${RESET} $*"; }
step()    { echo "${CYAN}${BOLD}::${RESET} $*"; }
warn()    { echo "${YELLOW}${BOLD}!!${RESET} $*" >&2; }
fail()    { echo "${RED}${BOLD}xx${RESET} $*" >&2; }
ok()      { echo "${GREEN}${BOLD}✓${RESET} $*"; }

usage() { sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ---- host detection ------------------------------------------------------
#
# Two flake outputs exist: nixos-kde and nixos-hyprland. The actual machine
# hostname is "nixos" for both, so we can't read it from hostname(1). Instead
# we let the user pass `kde` or `hypr`, and fall back to $XDG_CURRENT_DESKTOP
# when nothing was given (works inside a graphical session).

resolve_host() {
    case "${1:-}" in
        kde|nixos-kde)       echo "nixos-kde" ;;
        hypr|hyprland|nixos-hyprland) echo "nixos-hyprland" ;;
        "")
            # No arg — try to guess from the running session.
            case "${XDG_CURRENT_DESKTOP:-}${XDG_SESSION_DESKTOP:-}" in
                *KDE*|*kde*|*plasma*|*Plasma*) echo "nixos-kde" ;;
                *Hyprland*|*hyprland*)         echo "nixos-hyprland" ;;
                *)
                    fail "Can't tell which config to use."
                    fail "Pass 'kde' or 'hypr' explicitly: upgrade.sh kde"
                    exit 2
                    ;;
            esac
            ;;
        *)
            fail "Unknown host '$1'. Expected: kde | hypr"
            exit 2
            ;;
    esac
}

# ---- subcommand dispatch -------------------------------------------------

ACTION="${1:-upgrade}"

case "$ACTION" in
    -h|--help|help) usage 0 ;;

    diff)
        # Compare what's running against the most recent built profile.
        # If they're identical, nothing's pending — we say so explicitly
        # rather than printing an empty diff that looks like a no-op bug.
        if [[ "$(readlink -f /run/current-system)" == \
              "$(readlink -f /nix/var/nix/profiles/system)" ]]; then
            ok "Running system matches the latest built profile — nothing pending."
            exit 0
        fi
        info "Closure diff: running system → latest built profile"
        nix store diff-closures /run/current-system /nix/var/nix/profiles/system
        exit 0
        ;;

    gens)
        sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
        exit 0
        ;;

    gc)
        info "Deleting system + user generations older than 14 days…"
        sudo nix-collect-garbage --delete-older-than 14d
        ok "Done. Run 'upgrade.sh optimise' to also dedupe the store."
        exit 0
        ;;

    optimise|optimize)
        info "Optimising /nix/store (deduplicates identical files via hardlinks)…"
        sudo nix store optimise
        ok "Store optimised."
        exit 0
        ;;

    rollback)
        info "Rolling back to the previous system generation…"
        sudo nixos-rebuild switch --rollback
        exit $?
        ;;
esac

# ---- upgrade / boot flow -------------------------------------------------

# Decide between switch (apply now) and boot (apply on next reboot).
MODE="switch"
if [[ "$ACTION" == "boot" ]]; then
    MODE="boot"
    shift   # consume "boot"; the rest of the args follow the same shape
fi

# Anything else than `upgrade`/`boot`/known subcommands is treated as the
# host arg to an upgrade (so `upgrade.sh kde` Just Works).
if [[ "$ACTION" != "upgrade" && "$ACTION" != "boot" ]]; then
    set -- "$ACTION" "$@"
fi

# Flag parsing — only --no-update and --yes are meaningful here. Anything
# else that isn't a flag we treat as the host arg.
DO_UPDATE=1
ASSUME_YES=0
HOST_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-update) DO_UPDATE=0 ;;
        -y|--yes)    ASSUME_YES=1 ;;
        -h|--help)   usage 0 ;;
        -*)
            fail "Unknown flag: $1"
            usage 2
            ;;
        *)
            HOST_ARG="$1"
            ;;
    esac
    shift
done

HOST="$(resolve_host "$HOST_ARG")"

info "Flake:  ${FLAKE_DIR}#${HOST}"
info "Action: nixos-rebuild ${MODE}"
echo

# ---- step 1: bump flake.lock --------------------------------------------

if (( DO_UPDATE )); then
    step "Updating flake inputs…"
    # We capture the lockfile before/after so we can print a tidy summary of
    # which inputs actually moved (nix's own output is noisy).
    PRE_LOCK="$(mktemp)"
    cp "${FLAKE_DIR}/flake.lock" "$PRE_LOCK"

    if ! sudo nix flake update --flake "$FLAKE_DIR"; then
        fail "nix flake update failed."
        rm -f "$PRE_LOCK"
        exit 1
    fi

    if cmp -s "$PRE_LOCK" "${FLAKE_DIR}/flake.lock"; then
        ok "All flake inputs already at latest pinned revs — nothing to update."
    else
        ok "flake.lock updated. Changed inputs:"
        # `diff` on the lockfile is noisy; grep for "lastModified" lines as a
        # cheap proxy for which inputs moved.
        diff "$PRE_LOCK" "${FLAKE_DIR}/flake.lock" \
            | grep -E '"(lastModified|rev)"' \
            | sed 's/^/    /' \
            | head -n 20
    fi
    rm -f "$PRE_LOCK"
    echo
else
    step "Skipping flake update (--no-update)."
    echo
fi

# ---- step 2: build (no activation yet) -----------------------------------

step "Building ${HOST}…"
# We use `nix build` (not `nixos-rebuild build`) because only `nix build`
# accepts --out-link; nixos-rebuild always writes ./result in cwd, which
# would dirty /etc/nixos. The attribute we ask for here is exactly the one
# nixos-rebuild itself builds internally: config.system.build.toplevel.
# No sudo: build only creates a store path and a symlink under /tmp.
if ! nix build \
        "${FLAKE_DIR}#nixosConfigurations.${HOST}.config.system.build.toplevel" \
        --out-link "$BUILD_LINK"; then
    fail "Build failed. Lockfile has been updated but no activation happened."
    fail "Inspect the error above, or run 'upgrade.sh --no-update' to retry"
    fail "without re-bumping inputs."
    exit 1
fi
echo

# ---- step 3: show the diff ----------------------------------------------

step "Closure diff: running system → newly built system"
nix store diff-closures /run/current-system "$BUILD_LINK" || true
echo

# Surface kernel version bump separately — it's the single change most likely
# to make you want to reboot rather than switch live.
CUR_KERNEL="$(readlink -f /run/current-system/kernel 2>/dev/null || true)"
NEW_KERNEL="$(readlink -f "$BUILD_LINK/kernel" 2>/dev/null || true)"
if [[ -n "$CUR_KERNEL" && -n "$NEW_KERNEL" && "$CUR_KERNEL" != "$NEW_KERNEL" ]]; then
    warn "Kernel is changing. A live 'switch' won't load the new kernel —"
    warn "you'll keep running the old one until you reboot."
    warn "Consider 'upgrade.sh boot' instead so the new kernel takes effect"
    warn "cleanly on the next boot."
    echo
fi

# ---- step 4: confirm -----------------------------------------------------

if (( ! ASSUME_YES )); then
    read -r -p "${BOLD}Apply this with 'nixos-rebuild ${MODE}'? [y/N] ${RESET}" ans
    case "${ans:-}" in
        y|Y|yes) ;;
        *)
            warn "Aborted before activation. Built system is at: $BUILD_LINK"
            warn "(It'll be garbage-collected next time 'upgrade.sh gc' runs.)"
            exit 0
            ;;
    esac
fi

# ---- step 5: activate ---------------------------------------------------
#
# Hand off to rebuild.sh so the error extraction / log capture / rollback
# hint in that script applies here too. If rebuild.sh isn't present for
# some reason, fall back to calling nixos-rebuild directly.

step "Activating (${MODE})…"
if [[ -x "$REBUILD" ]]; then
    sudo "$REBUILD" "$MODE" --flake "${FLAKE_DIR}#${HOST}"
    RC=$?
else
    warn "scripts/rebuild.sh not found or not executable — using nixos-rebuild directly."
    sudo nixos-rebuild "$MODE" --flake "${FLAKE_DIR}#${HOST}"
    RC=$?
fi

# Clean up the build symlink only on success; on failure leave it so the
# user can inspect what was about to be activated.
if [[ $RC -eq 0 ]]; then
    rm -f "$BUILD_LINK"
    echo
    if [[ "$MODE" == "boot" ]]; then
        ok "Staged for next boot. Reboot to apply."
    else
        ok "Upgrade complete."
    fi
fi

exit "$RC"
