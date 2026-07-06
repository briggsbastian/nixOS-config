# hosts/lan/playground/htb.nix
#
# HackTheBox (and other lab-VPN) connectivity - split out from the former
# decepticon.nix when Decepticon itself was removed (upstream launcher crash,
# see git history) so this standalone, working capability wasn't lost with it.
#
# `htb` is a tiny convenience wrapper for the VPN toggle below - `htb up|down`
# (no password prompt, see the scoped sudo rule further down), plus `htb status`
# / `htb ip` to see the tunnel state. It's on every shell's PATH here, and the
# desktop aliases it over SSH (hosts/workstation/desktop/dotfiles/zsh.nix), so
# the same word works from the box, over SSH, or in Cockpit's terminal.
#
# The tunnel terminates on THIS host (no /dev/net/tun in any container/VM here),
# so anything else on playground that wants HTB-routed traffic - a Kali VM, a
# future tool - gets it for free once the tunnel is up: it's just a route out
# tun0, no per-consumer wiring needed.
#
# Manual-start on purpose (autoStart = false) - the tunnel should only be up
# while you're actually on a machine:
#   htb up      # or: sudo systemctl start openvpn-htb
#   htb down    # or: sudo systemctl stop  openvpn-htb
# HTB configs don't set redirect-gateway, so only the HTB lab subnets route
# over tun0 - the host's default route (updates, Colmena, DNS) is untouched.
#
# The .ovpn is sops-managed (secrets/playground.yaml -> key `htb_ovpn`), so it
# never lands in the Nix store or git in the clear; playground decrypts it at
# activation with its own SSH host key (see .sops.yaml + common.nix). It rotates
# per season and embeds your client key, so when HTB reissues it, refresh with:
#   sops secrets/playground.yaml     # paste the new .ovpn under `htb_ovpn`
# then redeploy. openvpn reads the decrypted file at /run/secrets/htb_ovpn.
{ config, pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "htb";
      runtimeInputs = with pkgs; [
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
  ];

  sops.secrets.htb_ovpn.sopsFile = ../../../secrets/playground.yaml;
  services.openvpn.servers.htb = {
    autoStart = false;
    config = "config ${config.sops.secrets.htb_ovpn.path}";
  };

  # Trust the VPN interface so the deny-by-default nftables firewall (common.nix)
  # doesn't drop replies from HTB targets.
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
