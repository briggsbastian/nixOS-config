{inputs, ...}:
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
      lsp = { 
        enable = true;
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
    '';
  };
}
