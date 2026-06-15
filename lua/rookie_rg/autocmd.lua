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

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "qf",
    callback = function(args)
      vim.keymap.set("n", "<CR>", function()
        require("rookie_rg.core").quickfix_enter()
      end, {
        buffer = args.buf,
        silent = true,
        desc = "Open quickfix item",
      })
    end,
    desc = "Handle Enter in quickfix windows",
  })
end

return M
