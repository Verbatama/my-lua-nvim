return {
	"romgrk/barbar.nvim",

	dependencies = {
		"nvim-tree/nvim-web-devicons",
	},

	init = function()
		vim.g.barbar_auto_setup = false
	end,

	config = function()
		require("barbar").setup({
			animation = true,
			auto_hide = false,

			icons = {
				filetype = {
					enabled = true,
				},

				separator = {
					left = "▎",
					right = "",
				},
			},

			maximum_padding = 1,
			minimum_padding = 1,

			maximum_length = 20,
		})

		-- keymaps
		vim.keymap.set("n", "<Tab>", "<Cmd>BufferNext<CR>")
		vim.keymap.set("n", "<S-Tab>", "<Cmd>BufferPrevious<CR>")

		vim.keymap.set("n", "<leader>x", "<Cmd>BufferClose<CR>")
		vim.keymap.set("n", "<leader>x", function()
			if vim.bo.buftype == "terminal" then
				vim.cmd("bd! %")
			else
				vim.cmd("BufferClose")
			end
		end)
	end,
}
