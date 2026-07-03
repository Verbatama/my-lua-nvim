return {
  "Maan2003/lsp_lines.nvim",
  event = "VeryLazy",
  config = function()
    require("lsp_lines").setup()
    vim.diagnostic.config({
      virtual_lines = false,  -- <-- nyalain default
      virtual_text = true,  -- biar gak dobel
    })

    -- toggle
    vim.keymap.set("n", "<leader>l", function()
      local current = vim.diagnostic.config().virtual_lines
      vim.diagnostic.config({
        virtual_lines = not current,
        virtual_text = current, -- biar balik ke mode lama kalau off
      })
    end, { desc = "Toggle lsp_lines" })
  end,
}
