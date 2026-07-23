return {
	--------------------------------------------------------------------------
	-- Mason
	--------------------------------------------------------------------------
	{
		"mason-org/mason.nvim",
		opts = {},
	},

	--------------------------------------------------------------------------
	-- Mason LSP Config
	--------------------------------------------------------------------------
	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = {
			"mason-org/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		config = function()
			local lspconfig = require("lspconfig")
			local util = require("lspconfig.util")
			local capabilities = require("cmp_nvim_lsp").default_capabilities()
			local vue_language_server_path = vim.fs.joinpath(
				vim.fn.stdpath("data"),
				"mason",
				"packages",
				"vue-language-server",
				"node_modules",
				"@vue",
				"language-server"
			)

			require("mason-lspconfig").setup({
				ensure_installed = {
					"lua_ls",
					"pyright",
					"clangd",
					"cssls",
					"emmet_ls",
					"prismals",
					"kotlin_language_server",
					"vtsls",
					"pint",
					"intelephense",
					"blade-formater",
					"rust_analyzer",
				},
				automatic_installation = true,
				handlers = {
					function(server_name)
						lspconfig[server_name].setup({
							capabilities = capabilities,
						})
					end,
					rust_analyzer = function()
						lspconfig.rust_analyzer.setup({
							capabilities = capabilities,
							on_attach = function(client, bufnr)
								-- Enable additional features
								if client.server_capabilities.semanticTokensProvider then
									vim.lsp.semantic_tokens.start(bufnr, client.id)
								end
							end,
							settings = {
								["rust-analyzer"] = {
									checkOnSave = {
										command = "clippy",
										extraArgs = { "--all-targets", "--all-features" },
									},
									assist = {
										emitMustUse = true,
										expressionFillDefaultTraits = true,
									},
									cargo = {
										allFeatures = true,
										loadOutDirsFromCheck = true,
										runBuildScripts = true,
									},
									completion = {
										autoself = {
											enable = true,
										},
										autoimport = {
											enable = true,
										},
										callable = {
											snippets = "fill_arguments",
										},
									},
									diagnostics = {
										enable = true,
										disabled = { "unresolved-proc-macro" },
									},
									hover = {
										actions = {
											enable = true,
										},
										documentation = {
											enable = true,
										},
									},
									inlayHints = {
										bindingModeHints = {
											enable = false,
										},
										chainingHints = {
											enable = true,
										},
										closingBraceHints = {
											minLines = 25,
										},
										closureReturnTypeHints = {
											enable = "never",
										},
										lifetimeElisionHints = {
											enable = "never",
										},
										maxLength = 25,
										parameterHints = {
											enable = true,
										},
										reborrowHints = {
											enable = "never",
										},
										renderColons = true,
										typeHints = {
											enable = true,
											hideClosureInitialization = false,
										},
									},
									procMacro = {
										enable = true,
									},
									runnables = {
										command = "cargo",
										extraArgs = {},
									},
									server = {
										extraEnv = {},
									},
								},
							},
						})
					end,
					lua_ls = function()
						lspconfig.lua_ls.setup({
							capabilities = capabilities,
							settings = {
								Lua = {
									diagnostics = { globals = { "vim" } },
								},
							},
						})
					end,
					pyright = function()
						lspconfig.pyright.setup({
							capabilities = capabilities,
							root_dir = util.root_pattern("pyproject.toml", "setup.py", ".git"),
						})
					end,
					intelephense = function()
						lspconfig.intelephense.setup({
							capabilities = capabilities,
							filetypes = {
								"php",
								"blade.php",
							},
						})
					end,
					emmet_ls = function()
						lspconfig.emmet_ls.setup({
							capabilities = capabilities,
							filetypes = {
								"html",
								"css",
								"scss",
								"sass",
								"javascriptreact",
								"typescriptreact",
							},
						})
					end,
					vtsls = function()
						lspconfig.vtsls.setup({
							capabilities = capabilities,
							init_options = {
								hostInfo = "neovim",
							},
							settings = {
								vtsls = {
									tsserver = {
										globalPlugins = {
											{
												name = "@vue/typescript-plugin",
												location = vue_language_server_path,
												languages = { "vue" },
												configNamespace = "typescript",
											},
										},
									},
								},
							},
							filetypes = {
								"javascript",
								"javascriptreact",
								"typescript",
								"typescriptreact",
								"vue",
							},
							root_dir = util.root_pattern("package.json", "tsconfig.json", "jsconfig.json", ".git"),
						})
					end,
					vue_ls = function()
						lspconfig.vue_ls.setup({
							capabilities = capabilities,
							filetypes = { "vue" },
							init_options = {
								vue = {
									hybridMode = true,
								},
							},
						})
					end,
				},
			})

			-- LSP Keymaps
			vim.keymap.set("n", "gd", vim.lsp.buf.definition)
			vim.keymap.set("n", "gr", vim.lsp.buf.references)
			vim.keymap.set("n", "K", vim.lsp.buf.hover)
			vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename)
			vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action)
		end,
	},

	--------------------------------------------------------------------------
	-- LSP CONFIG (Removed - now handled by mason-lspconfig handlers)
	--------------------------------------------------------------------------

}
