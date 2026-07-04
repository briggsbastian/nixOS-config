# hosts/lan/playground/decepticon.nix
#
# Decepticon - PurpleAILAB's autonomous red-team agent (https://github.com/PurpleAILAB/Decepticon).
# Apache-2.0. It is a Docker Compose v2 orchestrator: a Python/LangGraph CLI that
# stands up its own management-plane + sandbox stack (LiteLLM proxy, PostgreSQL,
# Neo4j, LangGraph, and an isolated target/C2 sandbox) and pulls its images at
# runtime. There is no nixpkgs package, and the tool manages its own Compose
# lifecycle + an interactive `decepticon onboard` wizard - so Nixifying the whole
# stack into virtualisation.oci-containers would fight the CLI and rot on every
# upstream bump.
#
# So this module declares only the *substrate* - Docker + Compose + the build
# toolchain - and Decepticon runs from a source checkout on top of it, the same
# way upstream's `make dogfood` flow expects. Lives on playground because that is
# the fleet's security-lab host (Kali/Parrot/REMnux libvirt lab + Guacamole; see
# ./configuration.nix and Project 1). Baseline is in ../../../modules/common.nix.
#
# ONE-TIME SETUP (imperative, done as the `playground` user after this deploys;
# the docker-group membership below needs a fresh login/session to take effect):
#
#   git clone https://github.com/PurpleAILAB/Decepticon.git ~/Decepticon
#   cd ~/Decepticon
#   make dogfood            # bring up the full OSS stack against local code
#   # or, for the packaged CLI instead of a source checkout:
#   #   pipx install decepticon           # + `pipx install 'decepticon[neo4j]'`
#   decepticon onboard      # interactive wizard: API keys + model/provider tiers
#
# The onboard wizard writes its own credential/config state under the checkout
# (or ~/.decepticon); that mutable state is intentionally NOT Nix-managed. If you
# later want the LLM API keys sops-managed, add them to secrets/playground.yaml
# (playground already decrypts its own secrets - see .sops.yaml) and source the
# rendered file into the environment before `make dogfood` / `decepticon`.
#
# NETWORKING: the stack binds its service/UI ports itself via Compose. They are
# deliberately left OFF the host firewall here - reach them from your workstation
# over an SSH tunnel (`ssh -L ...`) or via the existing Guacamole gateway, rather
# than exposing Postgres/Neo4j/LiteLLM to the LAN. Open a specific port in
# ./configuration.nix's networking.firewall.allowedTCPPorts only if you need it.
{ config, pkgs, ... }:

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
  # git/curl are already in common.nix; gnumake drives upstream's `make dogfood`,
  # docker-compose is the v2 CLI Decepticon shells out to, and python3 + pipx
  # cover `pipx install decepticon` if you prefer the published CLI over source.
  #
  # `htb` is a tiny convenience wrapper for the VPN toggle below - `htb up|down`
  # (no password prompt, see the scoped sudo rule further down), plus `htb status`
  # / `htb ip` to see the tunnel state. It's on every shell's PATH here, and the
  # desktop aliases it over SSH (hosts/workstation/desktop/dotfiles/zsh.nix), so
  # the same word works from the box, over SSH, or in Cockpit's terminal.
  #
  # `decep` is the one-word driver for the whole lab: `decep up` brings the HTB
  # VPN up (via htb) AND the Decepticon stack up in a detached tmux session
  # running `make dogfood` (upstream's interactive launcher - Decepticon is
  # tmux-native, so we keep it attachable rather than daemonising it). `decep cli`
  # attaches that session; `decep status` shows VPN + containers + session;
  # `decep down` stops the stack (WITHOUT wiping volumes) + VPN; `decep web`
  # prints the tunnel one-liner (the desktop's `decep` function actually opens
  # it - see zsh.nix). The stack runs as the playground user (docker group), so
  # decep needs no sudo of its own; the only privileged step is delegated to htb.
  environment.systemPackages = with pkgs; [
    gnumake
    docker-compose
    python3
    pipx
    (writeShellApplication {
      name = "htb";
      runtimeInputs = [
        iproute2
        gawk
      ];
      text = ''
        sudo=/run/wrappers/bin/sudo
        sc=/run/current-system/sw/bin/systemctl
        unit=openvpn-htb.service
        case "''${1:-status}" in
          up)
            if "$sudo" "$sc" start "$unit"; then
              echo "HTB VPN: up. See 'htb status' / 'htb ip'."
            else
              echo "HTB VPN: start failed - is a real .ovpn set in the htb_ovpn secret? ('htb status' for details)"
            fi ;;
          down)    "$sudo" "$sc" stop "$unit";    echo "HTB VPN: stopped." ;;
          restart) "$sudo" "$sc" restart "$unit"; echo "HTB VPN: restarted." ;;
          status)
            "$sc" --no-pager --lines=0 status "$unit" || true
            if ip -4 -brief addr show tun0 >/dev/null 2>&1; then
              echo "tun0: $(ip -4 -brief addr show tun0 | awk '{print $3}')"
            else
              echo "tun0: down (no HTB tunnel)"
            fi ;;
          ip)
            if ip -4 -brief addr show tun0 >/dev/null 2>&1; then
              ip -4 -brief addr show tun0 | awk '{print $3}'
            else
              echo "tun0 down"
            fi ;;
          *) echo "usage: htb {up|down|restart|status|ip}"; exit 1 ;;
        esac
      '';
    })
    (writeShellApplication {
      name = "decep";
      # tmux only; `docker`/`make`/`htb`/`decepticon` come from the system PATH
      # (the host runs docker_29 - pulling pkgs.docker here would drag in the
      # insecure default docker 28.x and refuse to build).
      runtimeInputs = [ tmux ];
      text = ''
        dir=/home/playground/Decepticon
        session=decepticon
        web_url="http://localhost:3000/web"

        need_checkout() {
          if [ ! -d "$dir" ]; then
            echo "Decepticon checkout not found at $dir."
            echo "Clone it first:  git clone https://github.com/PurpleAILAB/Decepticon.git $dir"
            echo "Then run 'decep onboard' once (API keys), and 'decep up'."
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
              tmux new-session -d -s "$session" -c "$dir" 'make dogfood'
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
            if [ -d "$dir" ]; then
              echo "--- containers ---"
              ( cd "$dir" && docker compose ps ) || true
            else
              echo "checkout: missing ($dir)"
            fi ;;
          web)
            echo "Web dashboard is localhost-only on playground. From your workstation:"
            echo "  ssh -fNT -L 3000:127.0.0.1:3000 playground@192.168.1.217 && xdg-open $web_url"
            echo "(the desktop 'decep web' does this for you.)" ;;
          logs)
            need_checkout
            ( cd "$dir" && docker compose logs -f ) ;;
          onboard)
            need_checkout
            ( cd "$dir" && decepticon onboard ) ;;
          down)
            if [ -d "$dir" ]; then
              ( cd "$dir" && docker compose down ) || true
            fi
            tmux kill-session -t "$session" 2>/dev/null || true
            htb down || true
            echo "Decepticon: stopped (data volumes preserved), VPN down." ;;
          *)
            echo "usage: decep {up|cli|status|web|logs|onboard|down}"; exit 1 ;;
        esac
      '';
    })
  ];

  # --- HackTheBox (and other lab-VPN) connectivity -------------------------
  # Decepticon has no built-in VPN: its Kali `sandbox` container gets NET_ADMIN
  # but no /dev/net/tun, so the tunnel terminates HERE, on the host. HTB targets
  # then become reachable to the sandbox for free: the container's gateway is the
  # host, Docker MASQUERADEs sandbox-net's outbound, and the host routes the HTB
  # subnets over tun0. No edits to Decepticon's compose required.
  #
  # Manual-start on purpose (autoStart = false) - this box is the security lab
  # host, but the tunnel should only be up while you're actually on a machine:
  #   sudo systemctl start openvpn-htb    # before a session
  #   sudo systemctl stop  openvpn-htb    # after
  # HTB configs don't set redirect-gateway, so only the HTB lab subnets route
  # over tun0 - the host's default route (updates, Colmena, DNS) is untouched.
  #
  # The .ovpn is sops-managed (secrets/playground.yaml -> key `htb_ovpn`), so it
  # never lands in the Nix store or git in the clear; playground decrypts it at
  # activation with its own SSH host key (see .sops.yaml + common.nix). It rotates
  # per season and embeds your client key, so when HTB reissues it, refresh with:
  #   sops secrets/playground.yaml     # paste the new .ovpn under `htb_ovpn`
  # then redeploy. openvpn reads the decrypted file at /run/secrets/htb_ovpn.
  sops.secrets.htb_ovpn.sopsFile = ../../../secrets/playground.yaml;
  services.openvpn.servers.htb = {
    autoStart = false;
    config = "config ${config.sops.secrets.htb_ovpn.path}";
  };

  # Trust the VPN interface so the deny-by-default nftables firewall (common.nix)
  # doesn't drop replies from HTB targets or the container->tun0 forward path.
  networking.firewall.trustedInterfaces = [ "tun0" ];

  # Scoped NOPASSWD sudo so `htb up/down/restart` (and Cockpit's Services page)
  # toggle the VPN without a password prompt - convenience only. Same tight
  # pattern as modules/deploy-user.nix: exact stable binary path + exact args, so
  # this grants toggling THIS one unit and nothing else (not general systemctl).
  # Merges with the deploy user's rules (extraRules is a list).
  security.sudo.extraRules = [
    {
      users = [ "playground" ];
      runAs = "root";
      commands =
        map
          (verb: {
            command = "/run/current-system/sw/bin/systemctl ${verb} openvpn-htb.service";
            options = [ "NOPASSWD" ];
          })
          [
            "start"
            "stop"
            "restart"
          ];
    }
  ];
}
