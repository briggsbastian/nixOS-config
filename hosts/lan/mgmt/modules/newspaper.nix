# The morning newspaper — e-ink RSS reader, fronted by nginx at
# https://news.mgmt.lan (vhost in nginx.nix). The app listens on localhost;
# a systemd timer fetches the edition each morning. Source + package come
# from the `newspaper` flake input (git.mgmt.lan/briggs/newspaper); bump it
# with `nix flake update newspaper` then `colmena apply --on mgmt`.
{ inputs, ... }:

{
  imports = [ inputs.newspaper.nixosModules.default ];

  services.morning-newspaper = {
    enable = true;
    # Feeds are versioned in the repo (single source of truth). To change them:
    # edit feeds.toml, push, `nix flake update newspaper`, redeploy.
    feedsFile = inputs.newspaper + "/feeds.toml";
    address = "127.0.0.1"; # nginx terminates TLS and proxies; don't expose directly
    port = 8377;
    refreshTime = "05:30"; # build the morning edition before wake-up
    openFirewall = false; # reached only via the nginx vhost
  };
}
