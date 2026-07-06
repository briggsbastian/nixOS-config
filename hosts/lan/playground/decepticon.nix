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
# lives separately in ./htb.nix (kept standalone even when this module was briefly
# removed and re-added - see git history).
#
# KNOWN UPSTREAM BUG (as of commit 4a8c953, 2026-07-04): the onboarding wizard's
# "LangSmith API Key" field (a masked/password text input, only rendered if you
# answer "Yes" to "Enable LangSmith?") deterministically crashes the launcher -
# `panic: interface conversion: tea.Model is nil, not compat.ViewModel`, itself
# triggered by `runtime error: makeslice: len out of range` inside
# charm.land/bubbles/v2's textinput.Model.placeholderView. Confirmed NOT a
# terminal-size/tmux artifact (reproduces identically with correctly-sized ptys)
# and NOT fixed by bumping bubbles/v2 to the latest release. A similar crash also
# hits when RE-SELECTING an already-created engagement (internal/engagement/
# picker.go's Select() incorrectly falls into promptNewSlug()). Neither is
# reported upstream yet. Workaround: answer "No" to "Enable LangSmith?" during
# onboarding (skips the buggy field entirely - this is why the very first
# onboarding attempt worked and a later one didn't), and avoid detaching and
# re-selecting an existing engagement until upstream fixes the Select() bug.
#
# ONE-TIME SETUP (imperative, done as the `playground` user after this deploys;
# the docker-group membership below needs a fresh login/session to take effect):
#
#   git clone https://github.com/PurpleAILAB/Decepticon.git ~/Decepticon
#   decep up                # == `make dogfood`: builds the Go launcher (clients/
#                            # launcher, needs the `go` toolchain below), then runs
#                            # it - it onboards (API keys + model tiers) INLINE on
#                            # first run, then engagement picker -> compose up -> CLI
#                            # Answer "No" to "Enable LangSmith?" - see the bug note above.
#
# There is no separate manual onboarding step for this flow - `decep onboard`
# exists only to RE-run the wizard later (change keys/tiers) via the already-built
# local launcher binary (clients/launcher/bin/decepticon). The upstream top-level
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
  # Rootful Docker + Compose. Mirrors mgmt's block (hosts/lan/mgmt/modules/base.nix):
  # docker_29 because the default docker 28.x is flagged insecure on nixos-25.11,
  # and autoPrune so the sandbox's throwaway images/containers don't fill the NVMe.
  virtualisation.docker = {
    enable = true;
    package = pkgs.docker_29;
    autoPrune.enable = true;
  };

  # Let the lab user drive Docker without sudo. extraGroups is a merged list
  # option, so this adds to the `wheel` set defined in ./configuration.nix rather
  # than replacing it. (The `docker` group is created by enabling docker above.)
  users.users.playground.extraGroups = [ "docker" ];

  # Build/run toolchain for the source checkout + optional packaged CLI.
  # git/curl are already in common.nix; gnumake drives upstream's `make dogfood`;
  # go builds the Go launcher binary that `make dogfood`/`make launcher` produces
  # at clients/launcher/bin/decepticon (go.mod pins 1.25.8 - pkgs.go on 25.11 is
  # newer, which satisfies it); gcc because the launcher pulls in a cgo dependency
  # (clipboard access) and fails to link without a C compiler on PATH; docker-compose
  # is the v2 CLI Decepticon shells out to; python3 + pipx cover `pipx install
  # decepticon` if you prefer the published CLI over source.
  #
  # `decep` is the one-word driver for the whole lab: `decep up` brings the HTB
  # VPN up (via htb, see ./htb.nix) AND the Decepticon stack up in a detached tmux
  # session running `make dogfood` (upstream's interactive launcher - Decepticon is
  # tmux-native, so we keep it attachable rather than daemonising it). `decep cli`
  # attaches that session; `decep status` shows VPN + containers + session;
  # `decep down` stops the stack (WITHOUT wiping volumes) + VPN; `decep web`
  # prints the tunnel one-liner (the desktop's `decep` function actually opens
  # it - see zsh.nix). The stack runs as the playground user (docker group), so
  # decep needs no sudo of its own; the only privileged step is delegated to htb.
  environment.systemPackages = with pkgs; [
    gnumake
    go
    gcc
    docker-compose
    python3
    pipx
    (writeShellApplication {
      name = "decep";
      # tmux only; `docker`/`make`/`go`/`htb` come from the system PATH (the host
      # runs docker_29 - pulling pkgs.docker here would drag in the insecure
      # default docker 28.x and refuse to build). The Decepticon launcher binary
      # itself is never on PATH - it's built locally by `make`/`make launcher`
      # into the checkout, and referenced here by its full path ($launcher).
      runtimeInputs = [
        tmux
        iproute2
      ];
      text = ''
        dir=/home/playground/Decepticon
        launcher="$dir/clients/launcher/bin/decepticon"
        session=decepticon
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
            if tmux has-session -t "$session" 2>/dev/null; then
              echo "Decepticon: already running (tmux '$session'). 'decep cli' to attach."
            else
              # Decepticon's launcher is a bubbletea/huh TUI that computes
              # layout (incl. text-input widths) from the pty size at first
              # render. A session created with plain `-d` gets tmux's internal
              # default (80x24) for that very first frame, regardless of your
              # actual terminal - and at some sizes that miscomputes a
              # negative slice length and panics before you ever attach. Pass
              # -x/-y from THIS terminal (the one running 'decep up') so the
              # detached session's initial pty matches reality from frame one.
              # (Confirmed this alone does NOT fix the known LangSmith-field
              # crash above - kept anyway since it's still correct hygiene.)
              cols=$(tput cols 2>/dev/null || echo 80)
              lines=$(tput lines 2>/dev/null || echo 24)
              # 'make dogfood' is the pane's only command, so if the launcher
              # crashes or exits, tmux kills the session and takes the crash
              # output with it. Tee to a log so a post-mortem doesn't need a
              # live pty - 'decep logs-launcher' (or a plain cat) reads it back.
              tmux new-session -d -s "$session" -x "$cols" -y "$lines" -c "$dir" \
                'make dogfood 2>&1 | tee -a ~/decep-launcher.log'
              echo "Decepticon: starting in tmux '$session' (first run builds images - be patient)."
              echo "Attach with 'decep cli'; open the web UI with 'decep web'."
            fi ;;
          cli|attach)
            if tmux has-session -t "$session" 2>/dev/null; then
              exec tmux attach -t "$session"
            else
              echo "Decepticon isn't running. Start it with 'decep up'."; exit 1
            fi ;;
          status)
            htb status || true
            echo
            if tmux has-session -t "$session" 2>/dev/null; then
              echo "session: up (tmux '$session')"
            else
              echo "session: none"
            fi
            if ss -tln 2>/dev/null | grep -q 127.0.0.1:3000; then
              echo "web: listening on :3000 (reach it with 'decep web')"
            else
              echo "web: not up (bring the stack up in 'decep cli', then spawn it with '/web')"
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
            echo "listens after you bring the stack up in 'decep cli' and spawn it with '/web'." ;;
          logs)
            need_checkout
            ( cd "$dir" && docker compose logs -f ) ;;
          logs-launcher)
            # The launcher's own output (onboarding, engagement picker, its
            # startup orchestration) - NOT container logs. See 'up' above for
            # why this is teed to a file instead of only living in the pane.
            tail -100 ~/decep-launcher.log 2>/dev/null || echo "No launcher log yet - run 'decep up' first." ;;
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
            tmux kill-session -t "$session" 2>/dev/null || true
            htb down || true
            echo "Decepticon: stopped (data volumes preserved), VPN down." ;;
          *)
            echo "usage: decep {up|cli|status|web|logs|logs-launcher|onboard|down}"; exit 1 ;;
        esac
      '';
    })
  ];
}
