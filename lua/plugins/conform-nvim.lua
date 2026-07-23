return {
	"stevearc/conform.nvim",
	opts = {
		formatters = {
			prisma = {
				command = "prisma",
				args = { "format" },
				stdin = false,
			},
		},
		formatters_by_ft = {
			python = { "black" },
			javascript = { "prettier" },
			typescript = { "prettier" },
			javascriptreact = { "prettier" },
			typescriptreact = { "prettier" },
			go = { "gofmt" },
			lua = { "stylua" },
			prisma = { "prisma" },
			kotlin = { "ktfmt" },
			php = { "pint" },
			blade = { "blade-formatter" },
			rust = { "rustfmt" },
		},

		format_on_save = {
			timeout_ms = 1000,
			lsp_fallback = true,
		},
	},
}
