local M = {}
local did_setup = false

M.core = require("rookie_rg.core")

M.live_grep = M.core.live_grep
M.global_grep = M.core.global_grep
M.visual_grep = M.core.visual_grep
M.clear_highlight = M.core.clear_highlight

function M.setup()
  if did_setup then
    return true
  end

  if vim.fn.executable("rg") ~= 1 then
    vim.notify("rookie_rg.nvim: `rg` is not executable", vim.log.levels.WARN)
    return false
  end

  -- Keep grepprg neutral; each search passes its own case mode flags.
  vim.opt.grepprg = "rg --vimgrep --no-heading --hidden"
  vim.opt.grepformat = "%f:%l:%c:%m"

  require("rookie_rg.keymaps").setup()
  require("rookie_rg.autocmd").setup()

  did_setup = true
  return true
end

return M
