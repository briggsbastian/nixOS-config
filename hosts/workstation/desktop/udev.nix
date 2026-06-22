{ pkgs, ... }:
{
  services.udev.extraRules = ''
    # Wooting keyboards - grant hidraw access for Wootility and rgb.net
    KERNEL=="hidraw*", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="ff01", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="ff02", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="31e3", MODE="0660", TAG+="uaccess"
  '';

  # uinput is required by wii-u-gc-adapter to create virtual controllers
  boot.kernelModules = [ "uinput" ];

}
