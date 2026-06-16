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

      vim.keymap.set("n", "s", function()
        require("rookie_rg.core").quickfix_split()
      end, {
        buffer = args.buf,
        silent = true,
        desc = "Open quickfix item in split",
      })

      vim.keymap.set("n", "v", function()
        require("rookie_rg.core").quickfix_vsplit()
      end, {
        buffer = args.buf,
        silent = true,
        desc = "Open quickfix item in vertical split",
      })

      vim.keymap.set("n", "t", function()
        require("rookie_rg.core").quickfix_tabedit()
      end, {
        buffer = args.buf,
        silent = true,
        desc = "Open quickfix item in new tab",
      })

      vim.keymap.set("n", "q", function()
        require("rookie_rg.core").close_quickfix()
      end, {
        buffer = args.buf,
        silent = true,
        desc = "Close quickfix window",
      })
    end,
    desc = "Handle Enter in quickfix windows",
  })
end

return M
