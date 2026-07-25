# Rofi app launcher / clipboard menu, themed to match the rest of the rice.
{ pkgs, ... }:
let
  c = import ./colors.nix;
in
{
  home.packages = [ pkgs.rofi ];

  xdg.configFile."rofi/config.rasi".text = ''
    configuration {
      modi: "drun,run,window";
      show-icons: true;
      icon-theme: "Papirus-Dark";
      drun-display-format: "{name}";
      display-drun: "run";
      font: "JetBrainsMono Nerd Font 12";
    }

    @theme "theme"
  '';

  xdg.configFile."rofi/theme.rasi".text = ''
    * {
      void:    ${c.hex.void};
      panel:   ${c.hex.panel};
      magenta: ${c.hex.magenta};
      cyan:    ${c.hex.cyan};
      yellow:  ${c.hex.yellow};
      fg:      ${c.hex.fg};
      muted:   ${c.hex.muted};

      background-color: transparent;
      text-color: @fg;
    }

    window {
      background-color: rgba(6, 0, 8, 0.85);
      border: 2px;
      border-color: @magenta;
      border-radius: 14px;
      width: 640px;
      location: center;
    }

    mainbox {
      padding: 16px;
      children: [ "inputbar", "listview" ];
      spacing: 12px;
    }

    inputbar {
      background-color: @panel;
      border: 2px;
      border-color: @cyan;
      border-radius: 10px;
      padding: 10px 14px;
      children: [ "prompt", "entry" ];
    }

    prompt {
      text-color: @yellow;
      font: "Orbitron 12";
    }

    entry {
      placeholder: "run >";
      placeholder-color: @muted;
      margin: 0 0 0 10px;
    }

    listview {
      lines: 8;
      spacing: 4px;
      fixed-height: false;
      border: 0;
    }

    element {
      padding: 8px 10px;
      border-radius: 8px;
    }

    element selected {
      background-color: @panel;
      border: 1px;
      border-color: @magenta;
      text-color: @cyan;
    }

    element-text {
      vertical-align: 0.5;
    }

    element-icon {
      size: 22px;
    }
  '';
}
