# Harmonia - nix binary cache serving this host's /nix/store at
# https://cache.mgmt.lan. Clients add (public key published at
# https://cache.mgmt.lan/pubkey):
#   nix.settings.substituters = [ "https://cache.mgmt.lan" ];
#   nix.settings.trusted-public-keys = [ "<contents of pubkey>" ];
{ pkgs, ... }:

{
  # harmonia 3.x (nixos-26.05) moved the module to services.harmonia.cache.*
  services.harmonia.cache = {
    enable = true;
    signKeyPaths = [ "/var/lib/mgmt-secrets/harmonia.secret" ];
    settings.bind = "127.0.0.1:5000";
  };

  systemd.services.harmonia-key = {
    description = "Generate harmonia binary cache signing key";
    wantedBy = [ "multi-user.target" ];
    before = [ "harmonia.service" ];
    requiredBy = [ "harmonia.service" ];
    path = [ pkgs.nix ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/mgmt-secrets
      chmod 711 /var/lib/mgmt-secrets
      f=/var/lib/mgmt-secrets/harmonia.secret
      if [ ! -f "$f" ]; then
        umask 077
        nix-store --generate-binary-cache-key cache.mgmt.lan-1 "$f" "$f.pub"
      fi
      mkdir -p /var/lib/mgmt-public
      chmod 755 /var/lib/mgmt-public
      install -m 644 "$f.pub" /var/lib/mgmt-public/harmonia.pub
    '';
  };
}
