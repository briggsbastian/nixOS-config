{ config, pkgs, ... }:

{
  programs.starship = {  
    enable = true;
    enableZshIntegration = true;
    settings = { 
    # Overall prompt format — controls order of modules
    format = ''
      $username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration
      $character'';

    # Two-line prompt: info on top, just the prompt symbol on the second line
    # This keeps your typing area uncluttered

    add_newline = true;

    character = {
      success_symbol = "[➜](bold green)";
      error_symbol = "[➜](bold red)";
      vimcmd_symbol = "[](bold green)";
    };

    directory = {
      truncation_length = 3;
      truncate_to_repo = true;
      style = "bold cyan";
    };

    git_branch = {
      symbol = " ";
      style = "bold purple";
    };

    git_status = {
      style = "bold yellow";
      conflicted = "=";
      ahead = "⇡\${count}";
      behind = "⇣\${count}";
      diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
      modified = "!";
      staged = "+";
      untracked = "?";
      stashed = "\$";
    };

    cmd_duration = {
      min_time = 2000;  # only show if command took >2s
      style = "bold yellow";
      format = "took [$duration]($style) ";
    };

    nix_shell = {
      symbol = " ";
      format = "via [$symbol$state]($style) ";
      style = "bold blue";
    };

    # Hostname only shows in SSH sessions — clean for local, useful remote
    hostname = {
      ssh_only = true;
      style = "bold green";
      format = "[@$hostname]($style) ";
    };

    # Username only shows when relevant (root, SSH, different user)
    username = {
      show_always = false;
      style_user = "bold blue";
      style_root = "bold red";
    };

    };
  };
}
