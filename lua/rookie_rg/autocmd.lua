local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup("RookieRg", { clear = true })

  vim.api.nvim_create_autocmd("QuickFixCmdPre", {
    group = group,
    pattern = "grep*",
    callback = function()
      require("rookie_rg.core").clear_highlight()
    end,
    desc = "Clear vim-highlighter matches before running grep",
  })
end

return M
