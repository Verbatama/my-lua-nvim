return {
    {
        "rebelot/kanagawa.nvim",
        priority = 1000,

        config = function()
            require("config.kanagawa-theme")
        end,
    },

    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
    },
}
