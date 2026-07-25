# Core Hyprland WM config: monitor, look & feel, layout, animations, autostart.
# Keybinds live in ./binds.nix; everything else in this rice (waybar, rofi,
# mako, hyprlock, hypridle, wallpaper) is its own file/module.
{ pkgs, ... }:
let
  c = import ./colors.nix;
in
{
  home.packages = with pkgs; [
    hyprpolkitagent
    networkmanagerapplet
    grim
    slurp
    wl-clipboard
    cliphist
    brightnessctl
    playerctl
    pamixer
    pavucontrol
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      # DP-3 is the desktop's single monitor in use (5120x1440 ultrawide).
      # HDMI-A-1 is a second connected port (TV/receiver) that's explicitly
      # kept off so it never auto-joins the desktop as a second display.
      monitor = [
        "DP-3,preferred,auto,1"
        "HDMI-A-1,disable"
        ",preferred,auto,1"
      ];

      "$mod" = "SUPER"; # the super/meta key, referenced by every bind in ./binds.nix
      "$terminal" = "alacritty";
      "$browser" = "firefox";
      "$fileManager" = "dolphin";
      "$menu" = "rofi -show drun";

      exec-once = [
        "hyprpaper"
        "waybar"
        "mako"
        "hypridle"
        "hyprpolkitagent"
        "nm-applet --indicator"
        "wl-paste --watch cliphist store"
      ];

      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "NIXOS_OZONE_WL,1"
        "QT_QPA_PLATFORM,wayland;xcb"
      ];

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
      };

      general = {
        gaps_in = 6;
        gaps_out = 14;
        border_size = 3;
        layout = "dwindle";
        # spray-paint gradient border: magenta -> cyan, the rice's signature.
        "col.active_border" = "rgb(${c.bare.magenta}) rgb(${c.bare.cyan}) 45deg";
        "col.inactive_border" = "rgba(${c.bare.muted}aa)";
        resize_on_border = true;
      };

      decoration = {
        rounding = 6;
        active_opacity = 1.0;
        inactive_opacity = 0.92;
        shadow = {
          enabled = true;
          range = 16;
          render_power = 3;
          color = "rgba(${c.bare.magenta}66)";
        };
        blur = {
          enabled = true;
          size = 4;
          passes = 2;
          vibrancy = 0.2;
        };
      };

      animations = {
        enabled = true;
        bezier = [
          "jsrPunch, 0.15, 0.9, 0.1, 1.05"
          "jsrSmooth, 0.05, 0.9, 0.1, 1.0"
        ];
        animation = [
          "windows, 1, 4, jsrPunch, popin 85%"
          "windowsOut, 1, 4, jsrSmooth, popin 85%"
          "border, 1, 8, jsrSmooth"
          "fade, 1, 4, jsrSmooth"
          "workspaces, 1, 5, jsrPunch, slide"
        ];
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        background_color = "rgb(${c.bare.void})";
      };

      # Keep Steam/game windows tiled sanely and route a couple of common
      # apps to dedicated workspaces so the single ultrawide stays organized.
      windowrule = [
        "workspace 2, class:^(steam)$"
        "workspace 2, class:^(steam_app_.*)$"
        "float, class:^(pavucontrol)$"
        "float, title:^(Picture-in-Picture)$"
        "immediate, class:^(steam_app_.*)$" # cut Hyprland's tearing-control latency for games
      ];
    };
  };

  imports = [
    ./binds.nix
  ];
}
