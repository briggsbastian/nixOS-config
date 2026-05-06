{ config, pkgs, ... }:

{
  programs.waybar = { 
    enable = true;
    settings = {
      mainBar = {layer = "top"; position = "top"; height = 30; spacing = 4;};
    };
    
    modules-left=["hyprland/workspaces" "hyprland/window"];
    modules-center=["clock"];
    modules-right=["pulseaudio" "network" "tray"];

    "hyprland/workspaces" = {
      format = "{icon}";
      on-click = "activate";
    };

    "hyprland/window" = {
      format = "{}";
      max-length = 50;
    };

    clock = {format = "{:%H:%M}"; format-alt = "{:%Y-%m-%d %H:%M:%S}"; tooltip-format = "<tt><small>{calendar}</small></tt>"; };
    network = {format-ethernet = "{ifname}"; format-disconnected = "disconnected"; tooltip-format = "{ifname}: {ipaddr}"; };
    tray = {icon-size = 18; spacing = 8; };
  };
}
