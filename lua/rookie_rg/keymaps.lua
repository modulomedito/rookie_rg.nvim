local M = {}

function M.setup()
  local core = require("rookie_rg.core")
  local opts = { silent = true }

  vim.keymap.set("n", "<leader>gg", core.global_grep, vim.tbl_extend("force", opts, {
    desc = "RookieRg: grep word under cursor",
  }))

  vim.keymap.set("x", "<leader>gg", core.visual_grep, vim.tbl_extend("force", opts, {
    desc = "RookieRg: grep visual selection",
  }))

  vim.keymap.set("n", "<leader>gf", core.live_grep, vim.tbl_extend("force", opts, {
    desc = "RookieRg: prompt for grep pattern",
  }))

  vim.keymap.set("x", "<leader>gf", core.visual_live_grep, vim.tbl_extend("force", opts, {
    desc = "RookieRg: prompt for grep pattern from visual selection",
  }))

  vim.keymap.set("n", "<leader>b", core.show_buffers, vim.tbl_extend("force", opts, {
    desc = "RookieRg: show listed buffers in quickfix",
  }))

  vim.keymap.set("n", "<C-p>", core.find_files, vim.tbl_extend("force", opts, {
    desc = "RookieRg: fuzzy find files in quickfix",
  }))

  vim.keymap.set("n", "<F9>", core.quickfix_prev, vim.tbl_extend("force", opts, {
    desc = "Previous quickfix item preview",
  }))

  vim.keymap.set("n", "<F10>", core.quickfix_next, vim.tbl_extend("force", opts, {
    desc = "Next quickfix item preview",
  }))

  vim.keymap.set("n", "<F11>", core.close_quickfix, vim.tbl_extend("force", opts, {
    desc = "Close quickfix list",
  }))

  vim.keymap.set("n", "<F8>", core.toggle_quickfix, vim.tbl_extend("force", opts, {
    desc = "Toggle quickfix list",
  }))
end

return M
