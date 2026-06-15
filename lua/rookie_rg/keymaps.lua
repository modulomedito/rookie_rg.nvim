local M = {}

function M.setup()
  local core = require("rookie_rg.core")
  local opts = { silent = true }

  vim.keymap.set("n", "gg", core.global_grep, vim.tbl_extend("force", opts, {
    desc = "RookieRg: grep word under cursor",
  }))

  vim.keymap.set("x", "gg", core.visual_grep, vim.tbl_extend("force", opts, {
    desc = "RookieRg: grep visual selection",
  }))

  vim.keymap.set("n", "gf", core.live_grep, vim.tbl_extend("force", opts, {
    desc = "RookieRg: prompt for grep pattern",
  }))
end

return M
