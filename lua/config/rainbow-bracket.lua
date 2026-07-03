local rainbow_delimiters = require("rainbow-delimiters")

local function set_rainbow_hl()
  local colors = {
    "#ff5f56", -- red (soft but visible)
    "#ffbd2e", -- yellow
    "#27c93f", -- green
    "#2ea8ff", -- blue
    "#a277ff", -- purple
    "#ff6bd6", -- pink
    "#00d4ff", -- cyan
  }

  local groups = {
    "RainbowDelimiterRed",
    "RainbowDelimiterYellow",
    "RainbowDelimiterGreen",
    "RainbowDelimiterBlue",
    "RainbowDelimiterViolet",
    "RainbowDelimiterOrange",
    "RainbowDelimiterCyan",
  }

  for i, group in ipairs(groups) do
    vim.api.nvim_set_hl(0, group, {
      fg = colors[i],
      bold = true,
    })
  end
end

set_rainbow_hl()

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("RainbowDelimiterHighlights", { clear = true }),
  callback = set_rainbow_hl,
})

vim.g.rainbow_delimiters = {
  strategy = {
    [""] = rainbow_delimiters.strategy["global"],
  },
  query = {
    [""] = "rainbow-delimiters",
  },
  highlight = {
    "RainbowDelimiterRed",
    "RainbowDelimiterYellow",
    "RainbowDelimiterGreen",
    "RainbowDelimiterBlue",
    "RainbowDelimiterViolet",
    "RainbowDelimiterOrange",
    "RainbowDelimiterCyan",
  },
}