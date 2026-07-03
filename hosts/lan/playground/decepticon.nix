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
  environment.systemPackages = with pkgs; [
    gnumake
    docker-compose
    python3
    pipx
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
}
