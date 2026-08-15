# modules/users.nix
#
# The human admin identity, declared once with a pinned UID so `briggs` means the
# same numeric identity everywhere. Before this, every host had its own
# differently-named admin (mgmt, hacktop, cloud1, media) and all of them landed on
# uid 1000 by auto-allocation - so `auid=1000` in an audit record identified a
# host, not a person, and correlating a login across two boxes was guesswork.
#
# Why 1000 specifically, and why it must not move: the NAS at 192.168.1.213 serves
# /srv/media over NFSv4 to the LAN with no identity mapping - uid/gid pass through
# raw, and the library is owned uid=1000 gid=1000 mode=775. That number is dictated
# by an appliance outside this flake. The desktop's briggs is already 1000 and
# mounts the same export (hosts/workstation/desktop/nas.nix), so writes land by
# *owner* match on the uid. Renumbering briggs would silently orphan ~916G.
#
# Deliberately no `users.groups.briggs`: isNormalUser defaults the primary group to
# `users` (gid 100), which is what every existing admin already uses. Creating a
# per-user group at gid 1000 would collide with the NAS group on the media host.
#
# Not yet fleet-wide. media still runs the *arr stack as a `media` service account
# sitting on uid 1000, so it opts out until that moves to its own account (Phase B,
# needs a chown of /var/lib/{sonarr,radarr,...} and a quiet window - nzbget mid-
# download is how you corrupt a queue). Grep `fleetUsers.enable = false`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.alcove.fleetUsers;
in
{
  options.alcove.fleetUsers = {
    enable = lib.mkEnableOption "the pinned-UID `briggs` admin account" // {
      default = true;
    };

    passwordSopsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Per-host sops file holding `briggs_hashed_password`. Required rather than
        defaulted: mgmt sets no `sops.defaultSopsFile` (it declares sopsFile per
        secret), so a default that silently resolved to the wrong host's file
        would fail at activation with the secret simply absent. Set it and it
        fails at eval instead.

        Generate the hash with `mkpasswd -m yescrypt`, then
        `sops secrets/<host>.yaml` and add it under `briggs_hashed_password`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Declarative passwords: with mutableUsers = true NixOS will not apply
    # hashedPasswordFile to a user that already exists on the box, and every host
    # here has had its admin password set by hand with `passwd` at some point.
    # false is what makes the sops hash actually take effect - and it matches the
    # estate's rule that on-box edits do not survive the next deploy.
    #
    # The consequence, stated plainly: any account or password created by hand on
    # these hosts is gone after this deploys.
    users.mutableUsers = false;

    users.users.briggs = {
      isNormalUser = true;
      uid = 1000;
      description = "briggs";
      shell = pkgs.zsh;
      extraGroups = [
        "wheel"
        # Read the journal without sudo - the whole point of this change is
        # making logs easier to chase across hosts.
        "systemd-journal"
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOdyXoksJm43MuCM6ZSKowV5N3tP94bMcjcyONvb3fzL briggs@nixos"
      ];
      # sudo/console password from sops. neededForUsers decrypts it before the
      # users module runs; without it the account activates with no password and
      # sudo is unusable. Change it via the secret + redeploy, not `passwd`.
      hashedPasswordFile = config.sops.secrets.briggs_hashed_password.path;
    };

    sops.secrets.briggs_hashed_password = {
      sopsFile = cfg.passwordSopsFile;
      neededForUsers = true;
    };

    # briggs' login shell. common.nix already enables zsh fleet-wide, but mgmt
    # skips common.nix - without this its shell would not exist.
    programs.zsh.enable = lib.mkDefault true;
  };
}
