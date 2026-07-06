# hosts/lan/playground/devenv.nix
#
# Prework for per-project dev environments - languages TBD (go/python/rust/ruby
# are the likely candidates), so this just gets the tooling in place rather than
# guessing at project-specific configs. Workflow once a project exists:
#   cd ~/some-project && devenv init && direnv allow
#   # edit devenv.nix: languages.go.enable = true; (or python/rust/ruby)
# direnv then auto-loads/unloads that project's shell on `cd`; nix-direnv caches
# the build so re-entering is instant instead of re-evaluating every time.
{ pkgs, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  environment.systemPackages = [ pkgs.devenv ];
}
