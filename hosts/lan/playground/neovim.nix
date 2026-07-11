# hosts/lan/playground/neovim.nix
#
# Same nixvim setup as the desktop (hosts/workstation/desktop/dotfiles/neovim.nix),
# ported system-wide via nixvim's NixOS module instead of the home-manager one -
# playground has no home-manager, and this box only has the one interactive user
# anyway. Config is duplicated rather than shared: desktop runs unstable nixpkgs,
# playground runs nixpkgs-stable, and home-manager vs NixOS module wrappers
# aren't quite the same option surface, so a cross-cutting shared module would
# couple two things that are fine to drift independently.
#
# Uses `inputs.nixvim-stable` (nixvim's release branch matching nixpkgs-stable,
# see flake.nix), NOT the plain `nixvim` input the desktop uses - nixvim's main
# branch tracks unstable nixpkgs and errors against stable.
{ pkgs, inputs, ... }:
{
  imports = [ inputs.nixvim-stable.nixosModules.nixvim ];
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    colorschemes.gruvbox.enable = true;
    opts = {
      number = true;
      relativenumber = true;
      shiftwidth = 2;
      expandtab = true;
    };
    plugins = {
      lualine.enable = true;
      telescope.enable = true;
      treesitter.enable = true;
      colorizer.enable = true;

      # Git tooling.
      gitsigns.enable = true; # gutter hunks: stage/reset/preview, blame, hunk nav
      lazygit.enable = true; # full visual Git TUI (:LazyGit)
      neogit.enable = true; # Magit-style menu UI (:Neogit)
      diffview.enable = true; # side-by-side diffs, file history, conflict resolver
      fugitive.enable = true; # classic :Git / :Git blame

      # camouflage.nvim has no nixvim module; added via extraPlugins below instead.
      lsp = {
        enable = true;
        servers.ols.enable = true;
      };
    };
    keymaps = [
      {
        mode = "n";
        key = "<leader>ff";
        action = "<cmd>Telescope find_files<cr>";
      }

      # Git UIs
      {
        mode = "n";
        key = "<leader>gg";
        action = "<cmd>LazyGit<cr>";
        options.desc = "LazyGit";
      }
      {
        mode = "n";
        key = "<leader>gn";
        action = "<cmd>Neogit<cr>";
        options.desc = "Neogit";
      }
      {
        mode = "n";
        key = "<leader>gd";
        action = "<cmd>DiffviewOpen<cr>";
        options.desc = "Diff: open";
      }
      {
        mode = "n";
        key = "<leader>gq";
        action = "<cmd>DiffviewClose<cr>";
        options.desc = "Diff: close";
      }
      {
        mode = "n";
        key = "<leader>gh";
        action = "<cmd>DiffviewFileHistory %<cr>";
        options.desc = "Diff: file history";
      }
      {
        mode = "n";
        key = "<leader>gs";
        action = "<cmd>Git<cr>";
        options.desc = "Fugitive status";
      }

      # Hunks (gitsigns)
      {
        mode = "n";
        key = "<leader>hs";
        action = "<cmd>Gitsigns stage_hunk<cr>";
        options.desc = "Stage hunk";
      }
      {
        mode = "n";
        key = "<leader>hr";
        action = "<cmd>Gitsigns reset_hunk<cr>";
        options.desc = "Reset hunk";
      }
      {
        mode = "n";
        key = "<leader>hp";
        action = "<cmd>Gitsigns preview_hunk<cr>";
        options.desc = "Preview hunk";
      }
      {
        mode = "n";
        key = "<leader>hb";
        action = "<cmd>Gitsigns blame_line<cr>";
        options.desc = "Blame line";
      }
      {
        mode = "n";
        key = "]c";
        action = "<cmd>Gitsigns next_hunk<cr>";
        options.desc = "Next hunk";
      }
      {
        mode = "n";
        key = "[c";
        action = "<cmd>Gitsigns prev_hunk<cr>";
        options.desc = "Prev hunk";
      }
    ];
    extraConfigLua = ''
      vim.api.nvim_set_hl(0, "Normal", {bg = "none"})
      local _99 = require("99")
      _99.setup({
        tmp_dir = "./tmp",
        md_files = { "AGENT.md" },
      })
      vim.keymap.set("v", "<leader>9v", function() _99.visual() end)
      vim.keymap.set("n", "<leader>9s", function() _99.search() end)
      vim.keymap.set("n", "<leader>9x", function() _99.stop_all_requests() end)

      -- camouflage.nvim: mask secret values in config files (no nixvim module, configured here)
      require("camouflage").setup({
        -- options go here; an empty table uses defaults
      })
    '';

    extraPackages = [ pkgs.opencode ];
    extraPlugins = [
      # pairs with tmuxPlugins.vim-tmux-navigator in tmux.nix: Ctrl-hjkl moves
      # seamlessly between tmux panes and nvim splits. Sets its own <C-h/j/k/l>
      # mappings by default, nothing else to wire up.
      pkgs.vimPlugins.vim-tmux-navigator
      (pkgs.vimUtils.buildVimPlugin {
        pname = "99";
        version = "2026-06-11";
        src = pkgs.fetchFromGitHub {
          owner = "ThePrimeagen";
          repo = "99";
          rev = "c17422457027c913c76c75a921fca1e623d2678e";
          hash = "sha256-iilpiG81kHIv7Y0qvPzZOanNA0lsPotlB18cvtmTy0o=";
        };
        doCheck = false;
      })
      (pkgs.vimUtils.buildVimPlugin {
        pname = "camouflage.nvim";
        version = "0.10.0";
        src = pkgs.fetchFromGitHub {
          owner = "zeybek";
          repo = "camouflage.nvim";
          rev = "v0.10.0"; # latest release; resolves to commit 44669ba
          hash = "sha256-rl1/T0YxugkMEYoriDfLd7ynbNk5LivKsUVR3qRQZGs=";
        };
      })
    ];
  };
}
