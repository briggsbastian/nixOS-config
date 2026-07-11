# hosts/lan/playground/decepticon.nix
#
# Decepticon - PurpleAILAB's autonomous red-team agent (https://github.com/PurpleAILAB/Decepticon).
# Apache-2.0. It is a Docker Compose v2 orchestrator: a Python/LangGraph CLI that
# stands up its own management-plane + sandbox stack (LiteLLM proxy, PostgreSQL,
# Neo4j, LangGraph, and an isolated target/C2 sandbox) and pulls its images at
# runtime. There is no nixpkgs package, and the tool manages its own Compose
# lifecycle via a Go launcher binary with an interactive onboarding wizard - so
# Nixifying the whole stack into virtualisation.oci-containers would fight the
# CLI and rot on every upstream bump.
#
# So this module declares only the *substrate* - Docker + Compose + the build
# toolchain - and Decepticon runs from a source checkout on top of it, the same
# way upstream's `make dogfood` flow expects. Lives on playground because that is
# the fleet's security-lab host (Kali lab + Guacamole; see ./configuration.nix
# and Project 1). Baseline is in ../../../modules/common.nix. HTB VPN connectivity
# lives separately in ./htb.nix.
#
# RUN IT IN THE FOREGROUND - NOT TMUX. Earlier revisions of this module wrapped
# the launcher in a detached tmux session for attach/detach convenience. That
# wrapping is what was actually causing a deterministic crash in the onboarding
# wizard and in engagement selection (`panic: interface conversion: tea.Model is
# nil, not compat.ViewModel`, from `runtime error: makeslice: len out of range`
# in charm.land/bubbles/v2's textinput rendering) - confirmed by running the
# exact same binary directly in a real, attached terminal with no tmux involved
# at all, which worked cleanly every time. Bumping bubbles/v2, matching tmux's
# pty size to the real terminal, and flooring the size all failed to fix it,
# because the tmux layer itself was the problem, not its sizing. `decep up`
# below therefore just `exec`s `make dogfood` directly - no session to manage,
# no attach step, no crash. The trade-off: the process ends if your SSH session
# drops. Acceptable for now; revisit only if that becomes a real problem.
#
# ONE-TIME SETUP (imperative, done as the `playground` user after this deploys;
# the docker-group membership below needs a fresh login/session to take effect):
#
#   git clone https://github.com/PurpleAILAB/Decepticon.git ~/Decepticon
#   decep up      # == `make dogfood` in your foreground terminal: builds the Go
#                 # launcher (clients/launcher, needs the `go` toolchain below),
#                 # then runs it - onboards (API keys + model tiers) inline on
#                 # first run, then engagement picker -> compose build/up -> CLI.
#
# KNOWN PORT CONFLICTS on THIS host (playground already runs Guacamole's own
# Postgres, the fleet's node_exporter, and Cockpit) - Decepticon's compose reads
# these from `.env`/`.dogfood/.env` as overrides, defaults in parens:
#   POSTGRES_PORT=15432       (default 5432  - collides with Guacamole's DB)
#   LANGGRAPH_PORT=12024      (default 2024  - collides with a host listener)
#   LITELLM_PORT=14000        (default 4000  - collides with a host listener)
#   SKILLOGY_REST_PORT=19100  (default 9100  - collides with node_exporter)
# Set these in the `.env`/`.dogfood/.env` the onboard wizard writes (uncomment
# the existing lines for the first three; SKILLOGY_REST_PORT has no placeholder,
# just append it) BEFORE compose tries to bind them, or `make dogfood` fails with
# "address already in use" partway through bringing containers up. This is
# ordinary Compose port-collision handling, not a Decepticon bug - re-check with
# `ss -tln` if a future upstream version adds/renames a host-bound port.
#
# There is no separate manual onboarding step - `decep onboard` exists only to
# RE-run the wizard later (change keys/tiers) via the already-built local
# launcher binary (clients/launcher/bin/decepticon). The upstream top-level
# README's `decepticon onboard` (bare, no path) refers to the PACKAGED CLI
# (`pipx install decepticon`), a from-scratch alternative to this source-checkout
# flow - don't mix the two: a bare `decepticon` is never installed here.
#
# The onboard wizard writes its own credential/config state under the checkout
# (or ~/.decepticon); that mutable state is intentionally NOT Nix-managed. If you
# later want the LLM API keys sops-managed, add them to secrets/playground.yaml
# (playground already decrypts its own secrets - see .sops.yaml) and source the
# rendered file into the environment before `decep up`.
#
# NETWORKING: the stack binds its service/UI ports itself via Compose. They are
# deliberately left OFF the host firewall here - reach them from your workstation
# over an SSH tunnel (`ssh -L ...`) or via the existing Guacamole gateway, rather
# than exposing Postgres/Neo4j/LiteLLM to the LAN. Open a specific port in
# ./configuration.nix's networking.firewall.allowedTCPPorts only if you need it.
{ pkgs, ... }:

{
  # Rootful Docker + Compose. Default docker on nixos-26.05 is 29.x (the 25.11
  # default 28.x was flagged insecure, which used to force a docker_29 pin here);
  # autoPrune so the sandbox's throwaway images/containers don't fill the NVMe.
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  # Let the lab user drive Docker without sudo. extraGroups is a merged list
  # option, so this adds to the `wheel` set defined in ./configuration.nix rather
  # than replacing it. (The `docker` group is created by enabling docker above.)
  users.users.playground.extraGroups = [ "docker" ];

  # Build/run toolchain for the source checkout + optional packaged CLI.
  # git/curl are already in common.nix; gnumake drives upstream's `make dogfood`;
  # go builds the Go launcher binary that `make dogfood`/`make launcher` produces
  # at clients/launcher/bin/decepticon (go.mod pins 1.25.8 - pkgs.go on stable is
  # newer, which satisfies it); gcc because the launcher pulls in a cgo dependency
  # (clipboard access) and fails to link without a C compiler on PATH; docker-compose
  # is the v2 CLI Decepticon shells out to; python3 + pipx cover `pipx install
  # decepticon` if you prefer the published CLI over source.
  #
  # `decep` is the one-word driver for the lab: `decep up` brings the HTB VPN up
  # (via htb, see ./htb.nix) then `exec`s `make dogfood` directly in your current
  # terminal (see the top-of-file note on why NOT tmux). `decep status`/`down`/
  # `web`/`logs`/`onboard` are simple, stateless helpers around the checkout - no
  # session to track. The stack runs as the playground user (docker group), so
  # decep needs no sudo of its own; the only privileged step is delegated to htb.
  environment.systemPackages = with pkgs; [
    gnumake
    go
    gcc
    docker-compose
    python3
    # pipx 1.8.0's test suite fails on nixos-26.05 (packaging-lib spacing change
    # breaks 7 specifier tests); the package itself is fine, so skip the tests.
    (pipx.overridePythonAttrs (o: { doCheck = false; }))
    (writeShellApplication {
      name = "decep";
      # `docker`/`make`/`go`/`htb` come from the system PATH. The Decepticon
      # launcher binary itself is never on PATH - it's built locally by
      # `make`/`make launcher` into the checkout, and referenced here by its
      # full path ($launcher).
      runtimeInputs = [ iproute2 ];
      text = ''
        dir=/home/playground/Decepticon
        launcher="$dir/clients/launcher/bin/decepticon"
        web_url="http://localhost:3000/web"

        need_checkout() {
          if [ ! -d "$dir" ]; then
            echo "Decepticon checkout not found at $dir."
            echo "Clone it first:  git clone https://github.com/PurpleAILAB/Decepticon.git $dir"
            echo "Then run 'decep up' - onboarding (API keys) happens inline on first run."
            exit 1
          fi
        }

        case "''${1:-status}" in
          up)
            htb up || true
            need_checkout
            cd "$dir"
            exec make dogfood ;;
          status)
            htb status || true
            echo
            if ss -tln 2>/dev/null | grep -q 127.0.0.1:3000; then
              echo "web: listening on :3000 (reach it with 'decep web')"
            else
              echo "web: not up (bring the stack up with 'decep up', then spawn it with '/web')"
            fi
            if [ -d "$dir" ]; then
              echo "--- containers ---"
              ( cd "$dir" && DECEPTICON_STACK_NAME="" docker compose ps ) 2>/dev/null || true
            else
              echo "checkout: missing ($dir)"
            fi ;;
          web)
            echo "Decepticon's web UI is localhost-only: page on :3000, terminal panel on"
            echo "ws://localhost:3003 - so reach it from a machine with a browser, with BOTH"
            echo "ports tunnelled to this VM's localhost. From your workstation:"
            echo "  ssh -fNT -L 3000:127.0.0.1:3000 -L 3003:127.0.0.1:3003 playground@192.168.1.217 && xdg-open $web_url"
            echo "(the desktop 'decep web' does this - and checks it's up first.) The UI only"
            echo "listens after you bring the stack up and spawn it with '/web'." ;;
          logs)
            need_checkout
            ( cd "$dir" && docker compose logs -f ) ;;
          onboard)
            # Re-runs the onboard wizard standalone (change API keys/model
            # tiers) via the LOCAL launcher binary make dogfood builds - there
            # is no global `decepticon` command in this setup (see the
            # top-of-file note). Builds it first if `decep up` hasn't yet.
            need_checkout
            if [ ! -x "$launcher" ]; then
              echo "Launcher not built yet - building it (make launcher)..."
              ( cd "$dir" && make launcher )
            fi
            ( cd "$dir" && "$launcher" onboard ) ;;
          down)
            if [ -d "$dir" ]; then
              ( cd "$dir" && docker compose down ) || true
            fi
            htb down || true
            echo "Decepticon: stopped (data volumes preserved), VPN down." ;;
          *)
            echo "usage: decep {up|status|web|logs|onboard|down}"; exit 1 ;;
        esac
      '';
    })
  ];
}
