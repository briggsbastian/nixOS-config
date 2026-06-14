{ config, pkgs, ... }:

{
  programs.waybar = { 
    enable = true;
    settings = {
      mainBar = {layer = "top"; position = "top"; height = 30; spacing = 4;   
        modules-left=["hyprland/workspaces" "hyprland/window"];
        modules-center=["clock"];
        modules-right=["pulseaudio" "network" "group/tray-group"];

        "hyprland/workspaces" = {
          format = "{icon}";
          on-click = "activate";
        };

        "hyprland/window" = {
          format = "{}";
          max-length = 50;
        };
        
        "group/tray-group" = {
          orientation = "horizontal";
          drawer = {
            transition-duration = 300;
            children-class = "tray-child";
            transition-left-to-right = false;
          };
          modules = ["custom/tray-icon" "tray"];
        };

        "custom/tray-icon" = {
          format = "";
          tooltip = false;
        };

        clock = {format = "{:%H:%M}"; format-alt = "{:%Y-%m-%d %H:%M:%S}"; tooltip-format = "<tt><small>{calendar}</small></tt>"; };
        network = {format-ethernet = "{ifname}"; format-disconnected = "disconnected"; tooltip-format = "{ifname}: {ipaddr}"; };
        tray = {icon-size = 18; spacing = 8; };
        pulseaudio = {format = "{icon} {volume}%"; format-muted = " muted"; format-icons = {default = ["" "" ""];}; on-click = "pavucontrol";};
        
      };
    };
    style = ''
      *  
      {font-family: "JetBrainsMono Nerd Font", sans-serif; font-size: 13px; min-height: 0;}
      
      window#waybar { background-color: transparent }
      #workspaces button {padding: 0 8px; background-color: transparent; color: #cdd6f4;}
      #workspaces button.active {color: #89b4fa; border-bottom: 2px solid #89b4fa;}
      #workspaces button.urgent {color: #f38ba8;}
      #clock,
      #network,
      #pulseaudio,
      #tray {background-color: #3c3836; color: #ebdbb2; padding: 2px 12px; margin: 4px 4px; border-radius: 10px} 
      #window {padding: 0 10px; margin: 0 4px; color: #cdd6f4;}
      #tray-group {background-color: #3c3836; padding: 2px 12px; margin: 4px 4px}
      #custom-tray-icon {padding: 0 4px;}
      #.tray-child {margin-left: 6px;}
    '';
  };
}
