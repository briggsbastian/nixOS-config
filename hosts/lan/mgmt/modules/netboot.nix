# PXE/netboot: pixiecore in ProxyDHCP mode serving netboot.xyz - boot any
# LAN machine into installers/rescue images without touching the router's
# DHCP. Network-boot a machine and pick an OS from the menu.
{ ... }:

{
  services.pixiecore = {
    enable = true;
    openFirewall = true; # UDP 67/69/4011 + the TCP ports below
    mode = "quick";
    quick = "xyz";
    dhcpNoBind = true; # coexist with the router's DHCP server
    port = 8088;
    statusPort = 8089;
  };
}
