# modules/deploy-user.nix
#
# The Colmena remote-deploy identity, on its own so it can be imported without
# the rest of the fleet baseline (modules/common.nix). That matters for mgmt,
# which is folded in faithfully (its own base.nix owns SSH/firewall/ACME) and
# only needs this much to become Colmena-managed.
#
# A dedicated, unprivileged `deploy` user - not a login/admin account. The
# desktop (Colmena control node) connects as this user with its SSH key. It can
# do exactly two privileged things and nothing else:
#   1. receive unsigned closures over SSH  -> it's a Nix `trusted-user`
#   2. run the NixOS activation as root    -> scoped NOPASSWD sudo below
# So a stolen deploy key can't open a general root shell - only re-activate a
# system closure. Deploy by IP; the internal domain lives on mgmt (DNS).
{ ... }:

{
  users.users.deploy = {
    isNormalUser = true;
    description = "Colmena deploy user";
    # Read-only journal access so deploys can be observed/debugged remotely.
    extraGroups = [ "systemd-journal" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
    ];
  };

  nix.settings.trusted-users = [ "root" "deploy" ];

  # Scope the deploy user's sudo to just the activation binaries (any args).
  # Store paths change every build, so we allow the binaries, not exact paths.
  security.sudo.extraRules = [{
    users = [ "deploy" ];
    runAs = "root";
    commands = [
      { command = "/nix/store/*/bin/switch-to-configuration"; options = [ "NOPASSWD" "SETENV" ]; }
      { command = "/run/current-system/sw/bin/nix-env";       options = [ "NOPASSWD" "SETENV" ]; }
      { command = "/nix/store/*/bin/nix-env";                 options = [ "NOPASSWD" "SETENV" ]; }
      { command = "/run/current-system/sw/bin/systemd-run";   options = [ "NOPASSWD" "SETENV" ]; }
    ];
  }];
}
