require("lualine").setup({
	options = {
		section_separators = "",
		component_separators = "",
	},

	sections = {
		lualine_c = {
			"filename",
		},

		lualine_x = {
			-- LSP STATUS (clean + anti empty)
			function()
				local clients = vim.lsp.get_clients({ bufnr = 0 })

				if #clients == 0 then
					return " LSP Off"
				end

				local names = {}
				for _, client in ipairs(clients) do
					table.insert(names, client.name)
				end

				return " " .. table.concat(names, ", ")
			end,

			-- ENCODING + FILEFORMAT
			function()
				local enc = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or vim.o.encoding
				local ff = vim.bo.fileformat

				return enc .. "[" .. ff .. "]"
			end,

			"filetype",

			-- OS INFO
			function()
				local uname = vim.loop.os_uname().sysname

				if uname == "Linux" then
					local file = io.open("/etc/os-release", "r")

					if file then
						local content = file:read("*a")
						file:close()

						local distro = content:match('PRETTY_NAME="([^"]+)"')

						if distro then
							local icon = ""

							if distro:match("Fedora") then
								icon = ""
							elseif distro:match("Arch") then
								icon = ""
							elseif distro:match("Ubuntu") then
								icon = ""
							elseif distro:match("Debian") then
								icon = ""
							end

							return icon .. " " .. distro
						end
					end

					return " Linux"
				elseif uname == "Darwin" then
					return " macOS"
				elseif uname == "Windows_NT" then
					return " Windows"
				end

				return uname
			end,
		},
	},
})
