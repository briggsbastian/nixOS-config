{inputs, pkgs, ...}:
{ 
  imports = [inputs.nixvim.homeModules.nixvim];
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
      # NOTE: camouflage.nvim has no nixvim module, so it is NOT enabled here.
      # It is added via extraPlugins + setup() below instead.
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

