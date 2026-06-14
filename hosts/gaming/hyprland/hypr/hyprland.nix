{ config, pkgs, ... }:
{

  home.packages = with pkgs; [
    wofi
    waybar
    slurp
    wl-clipboard
    brightnessctl
    playerctl
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      "$mod" = "SUPER";
      "$terminal" = "alacritty";
      "$browser" = "firefox";
      "$file" = "dolphin";
      "$menu" = "wofi --show drun";

      monitor = [ ",preffered,auto,1" ];
      exec-once = [ "noctalia-shell"];
      env = ["XCURSOR_SIZE,24"];

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        layout = "dwindle";
        "col.active_border" = "rgba(fabd2faa) rgba(b8bb26aa) 45deg";
        "col.inactive_border" = "rgba(595959aa)";
      };

      decoration = {
        rounding = 20; rounding-power = 2;
        shadow = {enabled = true; range = 4; render_power = 3; color = "rgba(1a1a1aee)";};
        blur = {enabled = true; size = 3; passes = 2; vibrancy = 0.169;}; 
      };

      layerrule = [
        "ignore_alpha 0.5, noctalia-background-.*"
        "blur, noctalia-background-.*"
        "blurpopups, noctalia-background-.*"
      ];

      animations = {
        enabled = true;
        bezier = ["myBezier, 0.05, 0.9, 0.1, 1.05"];
        animation = [
          "windows, 1, 7, myBezier" "windowsOut, 1, 7, default, popin 80%" "border, 1, 10, default" "fade, 1, 7, default" "workspaces, 1, 6, default"
        ];
      };

      dwindle = { pseudotile = true; preserve_split = true; };

    };
  };
}
