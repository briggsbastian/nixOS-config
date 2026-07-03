# Git config (migrated from the hand-written ~/.gitconfig) + delta.
{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user.name = "briggsbastian";
      user.email = "briggsbastian@pm.me";

      # gh as the GitHub credential helper (was hand-set; now via pkgs.gh, no
      # hardcoded store path). The leading "" resets any prior helper.
      credential."https://github.com".helper = [
        ""
        "!${pkgs.gh}/bin/gh auth git-credential"
      ];
      credential."https://gist.github.com".helper = [
        ""
        "!${pkgs.gh}/bin/gh auth git-credential"
      ];

      init.defaultBranch = "main";
      pull.rebase = false; # merge on pull — simplest mental model
    };
  };

  # delta: readable, syntax-highlighted diffs in the terminal.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true; # n / N to jump between files in a diff
      line-numbers = true;
    };
  };
}
