# Forgejo Actions runner (Project 5) — runs the fleet's CI on hacktop against the
# repos on git.mgmt.lan. Registered instance-wide, so it serves every repo.
#
# Setup once: mint a runner token in Forgejo (Settings → Actions → Runners), then
# `sops secrets/hacktop.yaml` and set forgejo_runner_token = "TOKEN=<token>".
{ config, pkgs, ... }:

{
  # Loaded as a systemd EnvironmentFile, so the value must be `TOKEN=<token>`.
  sops.secrets.forgejo_runner_token.sopsFile = ../../../secrets/hacktop.yaml;

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.hacktop = {
      enable = true;
      name = "hacktop";
      url = "https://git.mgmt.lan";
      tokenFile = config.sops.secrets.forgejo_runner_token.path;

      # Jobs run on the host (has Nix + KVM). Select with `runs-on: native` / `nix`.
      labels = [
        "native:host"
        "nix:host"
      ];

      # PATH for host jobs.
      hostPackages = with pkgs; [
        bash
        coreutils
        git
        gnused
        gnugrep
        gawk
        gnutar
        gzip
        nix
        nodejs
        cacert
        curl
        wget
        jq
      ];

      settings = {
        # A few jobs at once (e.g. the build-hosts matrix) + a cache for reruns.
        runner.capacity = 4;
        cache.enabled = true;
      };
    };
  };

  # Let the nix daemon run NixOS VM tests on this box.
  nix.settings.system-features = [
    "nixos-test"
    "kvm"
    "big-parallel"
    "benchmark"
  ];

  # Pin git.mgmt.lan so it resolves without depending on DHCP DNS; TLS still
  # matches the step-ca cert (root trusted via internal-ca.nix).
  networking.hosts."192.168.1.222" = [ "git.mgmt.lan" ];
}
