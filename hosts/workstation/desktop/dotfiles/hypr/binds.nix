# Keybindings, split out from ./hyprland.nix for readability.
_: {
  wayland.windowManager.hyprland.settings = {
    bind = [
      # core
      "$mod, RETURN, exec, $terminal"
      "$mod, B, exec, $browser"
      "$mod, E, exec, $fileManager"
      "$mod, D, exec, $menu"
      "$mod, Q, killactive"
      "$mod SHIFT, M, exit"
      "$mod, V, togglefloating"
      "$mod, F, fullscreen"
      "$mod, L, exec, hyprlock"
      "$mod SHIFT, E, exec, wlogout"

      # clipboard history (cliphist, backed by wl-paste --watch in exec-once)
      "$mod, C, exec, cliphist list | rofi -dmenu -p clipboard | cliphist decode | wl-copy"

      # screenshots
      ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
      "$mod, Print, exec, grim - | wl-copy"

      # focus movement
      "$mod, left, movefocus, l"
      "$mod, right, movefocus, r"
      "$mod, up, movefocus, u"
      "$mod, down, movefocus, d"

      # workspaces 1-10
      "$mod, 1, workspace, 1"
      "$mod, 2, workspace, 2"
      "$mod, 3, workspace, 3"
      "$mod, 4, workspace, 4"
      "$mod, 5, workspace, 5"
      "$mod, 6, workspace, 6"
      "$mod, 7, workspace, 7"
      "$mod, 8, workspace, 8"
      "$mod, 9, workspace, 9"
      "$mod, 0, workspace, 10"
      "$mod SHIFT, 1, movetoworkspace, 1"
      "$mod SHIFT, 2, movetoworkspace, 2"
      "$mod SHIFT, 3, movetoworkspace, 3"
      "$mod SHIFT, 4, movetoworkspace, 4"
      "$mod SHIFT, 5, movetoworkspace, 5"
      "$mod SHIFT, 6, movetoworkspace, 6"
      "$mod SHIFT, 7, movetoworkspace, 7"
      "$mod SHIFT, 8, movetoworkspace, 8"
      "$mod SHIFT, 9, movetoworkspace, 9"
      "$mod SHIFT, 0, movetoworkspace, 10"

      # cycle workspaces with the scroll wheel over the desktop
      "$mod, mouse_down, workspace, e+1"
      "$mod, mouse_up, workspace, e-1"
    ];

    bindm = [
      "$mod, mouse:272, movewindow"
      "$mod, mouse:273, resizewindow"
    ];

    binde = [
      # media / volume (repeats while held)
      ", XF86AudioRaiseVolume, exec, pamixer -i 5"
      ", XF86AudioLowerVolume, exec, pamixer -d 5"
      ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
      ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
    ];

    bindl = [
      # media keys that make sense as single triggers, not repeats
      ", XF86AudioMute, exec, pamixer -t"
      ", XF86AudioPlay, exec, playerctl play-pause"
      ", XF86AudioNext, exec, playerctl next"
      ", XF86AudioPrev, exec, playerctl previous"
    ];
  };
}
