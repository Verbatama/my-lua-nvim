require("kanagawa").setup({

	--theme = wave , dragon, lotus
	compile = false,
	undercurl = true,

	theme = "dragon",

	commentStyle = {
		italic = true,
	},

	keywordStyle = {
		italic = true,
	},

	transparent = true,
	dimInactive = true,
	terminalColors = true,
})

vim.cmd.colorscheme("kanagawa")
