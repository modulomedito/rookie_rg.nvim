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
      local function map_preview_motion(lhs, rhs, desc)
        vim.keymap.set("n", lhs, function()
          vim.cmd.normal({ args = { rhs }, bang = true })
          require("rookie_rg.core").preview_selected_quickfix_item()
        end, {
          buffer = args.buf,
          silent = true,
          desc = desc,
        })
      end

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

      map_preview_motion("j", "j", "Move down and preview quickfix item")
      map_preview_motion("k", "k", "Move up and preview quickfix item")
      map_preview_motion("<C-d>", "<C-d>", "Page down and preview quickfix item")
      map_preview_motion("<C-u>", "<C-u>", "Page up and preview quickfix item")
      map_preview_motion("gg", "gg", "Jump to first quickfix item and preview")
      map_preview_motion("G", "G", "Jump to last quickfix item and preview")
    end,
    desc = "Handle Enter in quickfix windows",
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    pattern = "*",
    callback = function(args)
      if vim.bo[args.buf].buftype == "quickfix" then
        require("rookie_rg.core").close_quickfix_preview()
      end
    end,
    desc = "Close quickfix preview when quickfix window closes",
  })
end

return M
