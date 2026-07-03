local ts = require("nvim-treesitter")

local languages = {
	"lua",
	"python",
	"javascript",
	"c",
	"cpp",
	"prisma",
}

ts.install(languages)

vim.api.nvim_create_autocmd("FileType", {
	pattern = languages,
	callback = function()
		vim.treesitter.start()
		vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end,
})
