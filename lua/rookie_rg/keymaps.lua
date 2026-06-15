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

  vim.keymap.set("n", "<F9>", core.quickfix_prev, vim.tbl_extend("force", opts, {
    desc = "Previous quickfix item",
  }))

  vim.keymap.set("n", "<F10>", core.quickfix_next, vim.tbl_extend("force", opts, {
    desc = "Next quickfix item",
  }))

  vim.keymap.set("n", "<F11>", "<Cmd>cclose<CR>", vim.tbl_extend("force", opts, {
    desc = "Close quickfix list",
  }))

  vim.keymap.set("n", "<F8>", core.toggle_quickfix, vim.tbl_extend("force", opts, {
    desc = "Toggle quickfix list",
  }))
end

return M
