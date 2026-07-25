# Waybar, styled Y2K/Shibuya-punk: dark glass panel, magenta/cyan pill
# modules, Orbitron clock. Config is written as raw JSON/CSS (rather than
# through home-manager's programs.waybar module) so it's just standard
# waybar syntax if you ever want to hand-edit it outside Nix.
{ pkgs, ... }:
let
  c = import ./colors.nix;
in
{
  home.packages = [ pkgs.waybar ];

  xdg.configFile."waybar/config.jsonc".text = builtins.toJSON {
    layer = "top";
    position = "top";
    height = 34;
    margin-top = 8;
    margin-left = 14;
    margin-right = 14;
    spacing = 4;

    modules-left = [
      "hyprland/workspaces"
      "hyprland/window"
    ];
    modules-center = [ "clock" ];
    modules-right = [
      "cpu"
      "memory"
      "temperature"
      "pulseaudio"
      "network"
      "tray"
      "custom/power"
    ];

    "hyprland/workspaces" = {
      format = "{icon}";
      on-click = "activate";
      format-icons = {
        default = "";
        active = "";
        urgent = "";
      };
      persistent-workspaces = {
        "*" = 5;
      };
    };

    "hyprland/window" = {
      format = "{}";
      max-length = 60;
      separate-outputs = true;
    };

    clock = {
      format = "{:%H:%M}";
      format-alt = "{:%A, %Y-%m-%d}";
      tooltip-format = "<tt><small>{calendar}</small></tt>";
    };

    cpu = {
      format = " {usage}%";
      interval = 3;
    };

    memory = {
      format = " {percentage}%";
      interval = 5;
    };

    temperature = {
      critical-threshold = 85;
      format = "{icon} {temperatureC}°C";
      format-icons = [ "" "" "" ];
    };

    pulseaudio = {
      format = "{icon} {volume}%";
      format-muted = " muted";
      format-icons = {
        default = [ "" "" "" ];
      };
      on-click = "pavucontrol";
    };

    network = {
      format-ethernet = " {ifname}";
      format-wifi = " {essid} ({signalStrength}%)";
      format-disconnected = "⚠ offline";
      tooltip-format = "{ifname}: {ipaddr}/{cidr}";
    };

    tray = {
      icon-size = 16;
      spacing = 10;
    };

    "custom/power" = {
      format = "⏻";
      on-click = "wlogout";
      tooltip = false;
    };
  };

  xdg.configFile."waybar/style.css".text = ''
    * {
      font-family: "JetBrainsMono Nerd Font", "Orbitron", sans-serif;
      font-size: 13px;
      min-height: 0;
    }

    window#waybar {
      background: transparent;
    }

    #workspaces,
    #window,
    #clock,
    #cpu,
    #memory,
    #temperature,
    #pulseaudio,
    #network,
    #tray,
    #custom-power {
      background-color: ${c.hex.panel};
      color: ${c.hex.fg};
      border: 1px solid ${c.hex.muted};
      border-radius: 10px;
      margin: 4px 3px;
      padding: 0 12px;
    }

    #workspaces {
      padding: 0 6px;
    }

    #workspaces button {
      color: ${c.hex.muted};
      padding: 0 6px;
      background: transparent;
      border: none;
    }

    #workspaces button.active {
      color: ${c.hex.fg};
      border-bottom: 2px solid ${c.hex.magenta};
    }

    #workspaces button.urgent {
      color: ${c.hex.urgent};
    }

    #workspaces button:hover {
      color: ${c.hex.cyan};
      background: transparent;
    }

    #window {
      color: ${c.hex.muted};
      font-style: italic;
    }

    #clock {
      font-family: "Orbitron", "JetBrainsMono Nerd Font";
      color: ${c.hex.yellow};
      border-color: ${c.hex.magenta};
      font-weight: bold;
    }

    #cpu {
      border-color: ${c.hex.cyan};
    }

    #memory {
      border-color: ${c.hex.magenta};
    }

    #temperature.critical {
      color: ${c.hex.urgent};
      border-color: ${c.hex.urgent};
    }

    #pulseaudio {
      border-color: ${c.hex.cyan};
    }

    #network {
      border-color: ${c.hex.green};
    }

    #network.disconnected {
      color: ${c.hex.urgent};
    }

    #custom-power {
      color: ${c.hex.urgent};
      border-color: ${c.hex.urgent};
    }

    #tray > .passive {
      -gtk-icon-effect: dim;
    }
  '';
}
