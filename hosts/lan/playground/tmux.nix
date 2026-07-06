# hosts/lan/playground/tmux.nix
#
# tmux is the backbone of how this box gets used - `kali`/`htb` land in a
# tmux-persistent SSH session (see the desktop's `kali` alias and `lab()`
# function), and `decep cli` is itself a tmux-driven launcher. Worth making it
# pleasant: vi keys (matches nvim), mouse mode, true color, instant escape
# (no lag leaving insert/copy mode), a bigger scrollback, a status bar themed
# red to match Starship's "you're on the lab box" cue, and:
#   - yank: copy to the CONNECTING CLIENT's clipboard over OSC52, so `y` in
#     copy-mode works even over plain SSH with no X forwarding.
#   - resurrect + continuum: session contents survive a host reboot -
#     genuinely useful mid-engagement, not just convenience.
#   - vim-tmux-navigator: Ctrl-hjkl moves between tmux panes AND nvim splits
#     seamlessly (paired with the same plugin on the nvim side, see neovim.nix).
{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    keyMode = "vi";
    customPaneNavigationAndResize = true;
    terminal = "tmux-256color";
    escapeTime = 0;
    baseIndex = 1;
    historyLimit = 50000;
    aggressiveResize = true;

    plugins = with pkgs.tmuxPlugins; [
      sensible
      yank
      resurrect
      continuum
      vim-tmux-navigator
    ];

    extraConfigBeforePlugins = ''
      set -ga terminal-overrides ",*256col*:Tc"
      set -g mouse on

      # continuum: auto-save every 15m, auto-restore the last session when
      # the tmux server (re)starts - e.g. after a host reboot.
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '15'
      set -g @resurrect-capture-pane-contents 'on'
    '';

    extraConfig = ''
      # status bar: red, matching the Starship prompt theme on this host
      set -g status-style "bg=black,fg=red"
      set -g status-left "#[bold,fg=red]#S #[fg=white]| "
      set -g status-right "#[fg=white]%Y-%m-%d %H:%M "
      setw -g window-status-current-style "bold,fg=black,bg=red"
      set -g pane-active-border-style "fg=red"
      set -g pane-border-style "fg=white"
    '';
  };
}
