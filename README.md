# Neovim Rainbow Brackets Setup

This config enables rainbow brackets via `rainbow-delimiters.nvim` and Tree-sitter.

## Quick Start

1. Open Neovim.
2. Run `:Lazy sync`.
3. Run `:TSUpdate` (or `:TSInstall <filetype>`).
4. Open a file with brackets, for example `{}` or `()`.

## How It Works

- Tree-sitter is enabled per filetype in [lua/config/treesitter.lua](lua/config/treesitter.lua).
- Rainbow brackets are configured and highlight groups are defined in [lua/config/rainbow-bracket.lua](lua/config/rainbow-bracket.lua).
- Plugins are declared in [lua/plugins/treesitter.lua](lua/plugins/treesitter.lua) and [lua/plugins/rainbow-bracket.lua](lua/plugins/rainbow-bracket.lua).

## Supported Filetypes

The default list is in [lua/config/treesitter.lua](lua/config/treesitter.lua). If your filetype is not listed, add it to the `languages` table and restart Neovim.

## Troubleshooting

- Check filetype: `:set filetype?`
- Check Tree-sitter health: `:checkhealth nvim-treesitter`
- Check rainbow-delimiters health: `:checkhealth rainbow-delimiters`
- Update parsers: `:TSUpdate`

If brackets still do not change color, make sure the filetype is in the `languages` list and Tree-sitter is running for that buffer.

## Generate a Log

To create a fresh log file:

```bash
rm -f ~/.config/nvim/nvim.log
nvim --headless -V3~/.config/nvim/nvim.log "+edit ~/.config/nvim/init.lua" "+qa"
```

Then inspect it with:

```bash
sed -n '1,200p' ~/.config/nvim/nvim.log
```
