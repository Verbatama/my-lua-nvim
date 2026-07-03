return {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
        local autopairs = require("nvim-autopairs")
        autopairs.setup({
            check_ts = true,
        })

        -- 🔥 INTEGRASI CMP HARUS DI DALAM config
        local ok, cmp = pcall(require, "cmp")
        if not ok then return end

        local cmp_autopairs = require("nvim-autopairs.completion.cmp")

        cmp.event:on(
            "confirm_done",
            cmp_autopairs.on_confirm_done()
        )
    end,
}
