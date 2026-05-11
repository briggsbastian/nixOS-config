{ pkgs, ... }:
{
  services.udev.extraRules = ''
    # Mayflash / Nintendo GameCube Adapter for Wii U (057e:0337)
    SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="0337", MODE="0666", TAG+="uaccess"

    # Wooting keyboards — grant hidraw access for Wootility and rgb.net
    KERNEL=="hidraw*", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="ff01", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="ff02", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="31e3", MODE="0660", TAG+="uaccess"
  '';

  # uinput is required by wii-u-gc-adapter to create virtual controllers
  boot.kernelModules = [ "uinput" ];

  # Run wii-u-gc-adapter as a system service so Steam/RetroArch see controllers
  systemd.services.wii-u-gc-adapter = {
    description = "Wii U GameCube Adapter userspace driver";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.wii-u-gc-adapter}/bin/wii-u-gc-adapter";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
