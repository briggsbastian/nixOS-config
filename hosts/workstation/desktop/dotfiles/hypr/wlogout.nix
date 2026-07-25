# wlogout: the power menu behind waybar's power button and $mod+SHIFT+E.
{ pkgs, ... }:
let
  c = import ./colors.nix;
in
{
  home.packages = [ pkgs.wlogout ];

  xdg.configFile."wlogout/layout".text = builtins.toJSON [
    {
      label = "lock";
      action = "hyprlock";
      text = "Lock";
      keybind = "l";
    }
    {
      label = "logout";
      action = "hyprctl dispatch exit";
      text = "Logout";
      keybind = "e";
    }
    {
      label = "suspend";
      action = "systemctl suspend";
      text = "Suspend";
      keybind = "s";
    }
    {
      label = "reboot";
      action = "systemctl reboot";
      text = "Reboot";
      keybind = "r";
    }
    {
      label = "shutdown";
      action = "systemctl poweroff";
      text = "Shutdown";
      keybind = "p";
    }
  ];

  xdg.configFile."wlogout/style.css".text = ''
    * {
      font-family: "Orbitron", "JetBrainsMono Nerd Font", sans-serif;
      font-size: 16px;
    }

    window {
      background-color: rgba(6, 0, 8, 0.75);
    }

    button {
      color: ${c.hex.fg};
      background-color: ${c.hex.panel};
      border: 2px solid ${c.hex.muted};
      border-radius: 14px;
      margin: 14px;
      background-repeat: no-repeat;
      background-position: center 30%;
      background-size: 28%;
    }

    button:focus,
    button:active,
    button:hover {
      border-color: ${c.hex.magenta};
      background-color: ${c.hex.void};
      color: ${c.hex.cyan};
    }
  '';
}
