# hosts/lan/playground/cockpit.nix
#
# Cockpit web console (:9090) as a lightweight VM control panel ALONGSIDE Guacamole
# (:8080) — not a replacement. Guacamole stays the polished remote-desktop gateway;
# Cockpit adds start/stop/restart buttons, live host+guest RAM (it matters on this
# 12 GB box), and a noVNC console, all driven from libvirt.
#
# Why pull from unstable: the `cockpit-machines` plugin (the Virtual Machines page)
# is NOT in nixos-25.11 — only base `cockpit` is. Unstable has cockpit-363 +
# cockpit-machines-353, so we source both from inputs.nixpkgs for this one host.
# `inputs` is threaded in via specialArgs in flake.nix (mkServerSystem + the Colmena
# meta). The base cockpit module sets `environment.pathsToLink = [ "/share/cockpit" ]`,
# so any systemPackage's /share/cockpit (i.e. the plugin) auto-registers in the UI.
#
# Access: https://192.168.1.217:9090 (self-signed cert — expect a browser warning;
# it's a LAN-only admin tool, but auth is PAM so we keep TLS, not AllowUnencrypted).
# Log in as `playground` (the password sops sets). That user is already in the
# `libvirtd` group (see ./libvirt.nix), which is all cockpit-machines needs to drive
# the system libvirtd via virsh — no libvirt-dbus or extra polkit rules required.
{ pkgs, inputs, ... }:
let
  unstable = import inputs.nixpkgs { inherit (pkgs.stdenv.hostPlatform) system; };
in
{
  services.cockpit = {
    enable = true;
    package = unstable.cockpit;   # match the plugin's vintage (363 vs the plugin's 353)
    openFirewall = true;          # opens :9090 in the (nftables) firewall
    # Cockpit rejects the post-login WebSocket if the browser Origin isn't allowed.
    # The module defaults to localhost only, so hitting it by IP (as the launchpad
    # tile did) authenticates but then drops the session after ~16s. The primary URL
    # is now the mgmt-fronted https://cockpit.mgmt.lan (trusted step-ca cert — see
    # mgmt nginx.nix); the direct IP is kept for on-box debugging. (Both merge with
    # the module's localhost default.)
    allowed-origins = [ "https://cockpit.mgmt.lan" "https://192.168.1.217:9090" ];
  };

  # The Virtual Machines plugin. Discovered via the base module's
  # pathsToLink = [ "/share/cockpit" ]; needs libvirtd (./libvirt.nix) + the user in
  # the libvirtd group (set there) to manage qemu:///system guests.
  environment.systemPackages = [ unstable.cockpit-machines ];
}
