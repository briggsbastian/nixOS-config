# hosts/lan/playground/shell.nix
#
# Interactive shell polish for playground - unlike the rest of the fleet, people
# actually sit in this box over SSH (kali/htb/decep from the desktop all land
# here), so it's worth more than the bare `programs.zsh.enable` from
# modules/common.nix. Starship prompt (styled red to visually flag "you're on
# the lab box"), oh-my-zsh for its plugins only (theme disabled - starship owns
# the prompt), autosuggestions/syntax-highlighting, zoxide for `z`, lsd/bat for
# nicer ls/cat, and a fastfetch banner once per SSH login (loginShellInit, not
# interactiveShellInit, so it doesn't fire again for every tmux pane/window).
{ pkgs, ... }:
{
  users.users.playground.shell = pkgs.zsh;

  # zsh's new-user-install wizard nags on every login until ~/.zshrc exists;
  # `f` only creates it if missing, so this never clobbers real user content.
  systemd.tmpfiles.rules = [
    "f /home/playground/.zshrc 0644 playground users -"
  ];

  environment.systemPackages = with pkgs; [
    starship
    lsd
    bat
    zoxide
    fzf
    fastfetch
  ];

  programs.zsh = {
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    ohMyZsh = {
      enable = true;
      theme = ""; # starship owns the prompt
      plugins = [
        "git"
        "sudo"
        "command-not-found"
        "colored-man-pages"
      ];
    };

    shellAliases = {
      ls = "lsd";
      ll = "lsd -l";
      la = "lsd -la";
      cat = "bat";
    };

    interactiveShellInit = ''
      eval "$(${pkgs.zoxide}/bin/zoxide init zsh)"
      source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      source ${pkgs.fzf}/share/fzf/completion.zsh
    '';

    loginShellInit = ''
      ${pkgs.fastfetch}/bin/fastfetch
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      format = ''
        $username$hostname$directory$git_branch$git_status$cmd_duration
        $character'';

      add_newline = true;

      character = {
        success_symbol = "[➜](bold red)";
        error_symbol = "[➜](bold white)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold cyan";
      };

      git_branch = {
        symbol = " ";
        style = "bold yellow";
      };

      git_status.style = "bold yellow";

      cmd_duration = {
        min_time = 2000;
        style = "bold yellow";
        format = "took [$duration]($style) ";
      };

      # always on (not ssh_only) - this box is reached over SSH, console, and
      # Guacamole, so the prompt should always say where you are
      hostname = {
        ssh_only = false;
        style = "bold red";
        format = "[@$hostname]($style) ";
      };

      username = {
        show_always = true;
        style_user = "bold red";
        style_root = "bold white bg:red";
      };
    };
  };
}
