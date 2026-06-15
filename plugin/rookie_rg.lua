if vim.g.loaded_rookie_rg_nvim == 1 then
  return
end

vim.g.loaded_rookie_rg_nvim = 1

require("rookie_rg").setup()
