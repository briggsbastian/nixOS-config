# modules/internal-ca.nix
#
# Trust the homelab's private step-ca (on mgmt) and consume its services: the
# root cert for TLS, the Harmonia binary cache, and step-ca's ACME endpoint as
# the default for any host that requests certs. All behind one mkEnableOption.
#
# Every value here is public (root cert, cache pubkey, URLs) - safe to commit.
# Internal names resolve via AdGuard on mgmt; the TLD is migrating
# *.mgmt.lan -> *.alcove, so flip these defaults at cutover.
{ config, lib, ... }:

let
  cfg = config.alcove.internalCa;
  # Hostname out of a URL: strip scheme, take the part before the first "/".
  hostOf =
    url:
    lib.elemAt (lib.splitString "/" (lib.removePrefix "http://" (lib.removePrefix "https://" url))) 0;
in
{
  options.alcove.internalCa = {
    enable = lib.mkEnableOption "trust mgmt's step-ca root + use its ACME endpoint and Nix binary cache";

    rootCertFile = lib.mkOption {
      type = lib.types.path;
      default = ./certs/mgmt-root.crt;
      description = "PEM of the step-ca root CA (public - safe to commit).";
    };

    acmeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "https://ca.mgmt.lan/acme/acme/directory";
      description = "step-ca ACME v2 directory URL.";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      default = "admin@mgmt.lan";
      description = "Contact email for ACME registrations.";
    };

    cacheUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://cache.mgmt.lan";
      description = "Harmonia binary cache URL.";
    };

    cachePublicKey = lib.mkOption {
      type = lib.types.str;
      default = "cache.mgmt.lan-1:QFQh2wr91EtDPQ0mMU4qjE5xOTQo+fW4xgoKyb5WBKE=";
      description = "Harmonia cache signing public key.";
    };

    mgmtIp = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.222";
      description = ''
        mgmt's LAN IP. The CA + cache hostnames are pinned to it in /etc/hosts so
        they resolve even when this host isn't using mgmt's AdGuard as its
        resolver - otherwise https://ca.mgmt.lan / https://cache.mgmt.lan don't
        resolve and the cache silently falls back to cache.nixos.org.
      '';
    };

    useCache = lib.mkEnableOption "add mgmt's Harmonia cache as a substituter (cache.mgmt.lan serves a real step-ca cert as of 2026-06-15)";
  };

  config = lib.mkIf cfg.enable {
    # 1. Trust the private root CA system-wide, so https://*.mgmt.lan verifies.
    security.pki.certificateFiles = [ cfg.rootCertFile ];

    # 1b. Resolve the CA + cache names locally. Consumers don't necessarily use
    #     mgmt's AdGuard as their resolver, so these names wouldn't resolve and
    #     the cache would silently fall back to cache.nixos.org. nginx on mgmt
    #     fronts both on :443. (Same /etc/hosts pattern step-ca.nix uses on mgmt.)
    networking.hosts."${cfg.mgmtIp}" = [
      (hostOf cfg.acmeDirectory)
      (hostOf cfg.cacheUrl)
    ];

    # 2. Add mgmt's binary cache (cfg.useCache). cache.mgmt.lan serves a real
    #    step-ca cert and the root is trusted via item 1, so nix can verify it.
    #    `extra-*` appends - cache.nixos.org stays as the fallback when a path
    #    isn't cached or harmonia is down.
    nix.settings = lib.mkIf cfg.useCache {
      extra-substituters = [ cfg.cacheUrl ];
      extra-trusted-public-keys = [ cfg.cachePublicKey ];
    };

    # 3. Default ACME to step-ca, so a host only needs `enableACME = true` to get
    #    a real, auto-renewing cert from the internal CA (used when we wire TLS
    #    onto media + other services).
    security.acme = {
      acceptTerms = true;
      defaults = {
        server = cfg.acmeDirectory;
        email = cfg.acmeEmail;
      };
    };
  };
}
