return {
  "HiPhish/rainbow-delimiters.nvim",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  config = function()
    require("config.rainbow-bracket")
    require("rainbow-delimiters").enable(0)
  end,
}
