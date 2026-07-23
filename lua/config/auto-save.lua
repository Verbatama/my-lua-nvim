local group = vim.api.nvim_create_augroup("UserAutoSave", { clear = true })

local function should_save(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	if vim.bo[bufnr].buftype ~= "" then
		return false
	end

	if not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly then
		return false
	end

	if not vim.bo[bufnr].modified then
		return false
	end

	if vim.api.nvim_buf_get_name(bufnr) == "" then
		return false
	end

	return true
end

local function autosave_current_buffer()
	local bufnr = vim.api.nvim_get_current_buf()

	if should_save(bufnr) then
		vim.cmd("silent! update")
	end
end

vim.api.nvim_create_autocmd("InsertLeave", {
	group = group,
	callback = function()
		vim.schedule(autosave_current_buffer)
	end,
})
