#!/usr/bin/env bash
#
# rebuild.sh — a friendlier wrapper around nixos-rebuild
#
# Usage:
#   ./rebuild.sh                  # equivalent to: nixos-rebuild switch
#   ./rebuild.sh test             # nixos-rebuild test (no bootloader change)
#   ./rebuild.sh boot             # apply on next boot only
#   ./rebuild.sh -- --flake .#foo # pass extra args after --
#
# What it does that plain nixos-rebuild doesn't:
#   1. Captures full output to a log file you can grep later
#   2. Extracts and highlights the actual error (not 500 lines of trace)
#   3. Tells you exactly which package/module failed
#   4. Reminds you of `nixos-rebuild --rollback` if a switch succeeds-but-breaks
#   5. Exits with the real exit code so you can chain it in other scripts

set -uo pipefail   # NOTE: deliberately NOT using `set -e` — we want to handle
                   # the failure ourselves rather than dying on the first error.

# ---- config ---------------------------------------------------------------

ACTION="${1:-switch}"           # switch | boot | test | build | dry-activate
shift || true

LOG_DIR="${LOG_DIR:-/tmp/nixos-rebuild-logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/rebuild-$(date +%Y%m%d-%H%M%S).log"

# ---- pretty printing ------------------------------------------------------

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; RED=$'\033[31m'; YELLOW=$'\033[33m'
    GREEN=$'\033[32m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    BOLD=""; RED=""; YELLOW=""; GREEN=""; DIM=""; RESET=""
fi

info()  { echo "${BOLD}==>${RESET} $*"; }
warn()  { echo "${YELLOW}${BOLD}!!${RESET} $*" >&2; }
fail()  { echo "${RED}${BOLD}xx${RESET} $*" >&2; }
ok()    { echo "${GREEN}${BOLD}✓${RESET} $*"; }

# ---- pre-flight checks ----------------------------------------------------

if [[ $EUID -ne 0 ]] && [[ "$ACTION" != "build" ]] && [[ "$ACTION" != "dry-activate" ]]; then
    fail "This action ($ACTION) needs root. Re-run with sudo."
    exit 1
fi

if ! command -v nixos-rebuild >/dev/null 2>&1; then
    fail "nixos-rebuild not found on PATH. Are you on NixOS?"
    exit 127
fi

# ---- run the build --------------------------------------------------------

info "Running: nixos-rebuild $ACTION $*"
info "Logging to: $LOG_FILE"
echo

# Run nixos-rebuild, mirroring output to the terminal AND saving to the log.
# `tee` would normally swallow the exit code, so we use PIPESTATUS to recover it.
nixos-rebuild "$ACTION" "$@" 2>&1 | tee "$LOG_FILE"
RC=${PIPESTATUS[0]}

echo

# ---- success path ---------------------------------------------------------

if [[ $RC -eq 0 ]]; then
    ok "nixos-rebuild $ACTION succeeded."
    if [[ "$ACTION" == "switch" || "$ACTION" == "boot" ]]; then
        info "If something feels broken, you can roll back with:"
        echo "    sudo nixos-rebuild switch --rollback"
    fi
    exit 0
fi

# ---- failure path: extract the real error --------------------------------

fail "nixos-rebuild $ACTION exited with code $RC"
echo

# These regexes match the most common signal lines Nix prints when it fails.
# We pull a few lines of context around them so the error is readable.
PATTERNS=(
    "error:"                        # generic Nix evaluation/build error
    "builder for .* failed"         # a derivation failed to build
    "hash mismatch"                 # fetched source doesn't match expected hash
    "infinite recursion"            # config evaluation loop
    "attribute .* missing"          # typo'd option name
    "is not of type"                # wrong type in module option
    "undefined variable"            # typo'd variable in config
    "collision between"             # two packages providing the same file
)

# Build one big grep pattern.
PATTERN_RE=$(IFS='|'; echo "${PATTERNS[*]}")

echo "${BOLD}--- likely cause(s) ---${RESET}"
# -B 1 -A 5 = one line before, five after — usually enough to show the message
#             and the file:line that caused it, without dumping the whole trace.
if grep -E -B 1 -A 5 "$PATTERN_RE" "$LOG_FILE" | head -n 60; then
    :
else
    warn "Couldn't auto-detect the error. Showing the last 40 lines instead:"
    tail -n 40 "$LOG_FILE"
fi
echo "${BOLD}-----------------------${RESET}"
echo

# ---- failure-type-specific hints -----------------------------------------

if grep -q "hash mismatch" "$LOG_FILE"; then
    warn "Hash mismatch detected. The source you're fetching changed."
    warn "  → Update the hash in your config to the 'got:' value shown above."
fi

if grep -q "attribute .* missing" "$LOG_FILE"; then
    warn "Missing attribute. Check for typos in option names, or run:"
    warn "  → man configuration.nix   (to look up the correct option)"
fi

if grep -q "collision between" "$LOG_FILE"; then
    warn "Two packages want to install the same file."
    warn "  → Remove one, or set nixpkgs.config.allowUnfree / priority."
fi

if grep -q "builder for .* failed" "$LOG_FILE"; then
    warn "A package failed to build (not just a config error)."
    warn "  → Full builder log is in: $LOG_FILE"
    warn "  → Try: nix log /nix/store/<the-failed-drv>"
fi

echo
fail "Full log: $LOG_FILE"
exit "$RC"
