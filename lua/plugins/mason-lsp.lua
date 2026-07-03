return {
	-- Mason
	{
		"williamboman/mason.nvim",
		config = true,
	},

	{
		"williamboman/mason-lspconfig.nvim",
		config = function()
			require("mason-lspconfig").setup({
				ensure_installed = {
					"lua_ls",
					"pyright",
					"ts_ls",
					"clangd",
				},
			})
		end,
	},

	-- LSP Config
	{
		"neovim/nvim-lspconfig",
		config = function()
			local lspconfig = require("lspconfig")
			local capabilities = require("cmp_nvim_lsp").default_capabilities()

			-- Lua
			lspconfig.lua_ls.setup({
				capabilities = capabilities,
				settings = {
					Lua = {
						diagnostics = {
							globals = { "vim" },
						},
					},
				},
			})

			-- Python
			lspconfig.pyright.setup({
				capabilities = capabilities,
			})

			-- TypeScript
			lspconfig.ts_ls.setup({
				capabilities = capabilities,
			})

			-- C/C++
			lspconfig.clangd.setup({
				capabilities = capabilities,
			})
			lspconfig.prisma.setup({
				capabilities = capabilities,
			})

			lspconfig.kotlin_lsp.setup({
				capabilities = capabilities,
			})

			-- Keymaps LSP
			vim.keymap.set("n", "gd", vim.lsp.buf.definition)
			vim.keymap.set("n", "K", vim.lsp.buf.hover)
			vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename)
			vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action)
		end,
	},
}
