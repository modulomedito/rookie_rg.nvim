local M = {}

local function set_search_register(pattern)
  vim.fn.setreg("/", "\\V" .. pattern)
end

local function set_search_register_whole_word(pattern)
  vim.fn.setreg("/", "\\V\\<" .. vim.fn.escape(pattern, "\\") .. "\\>")
end

local function refresh_search_highlight()
  pcall(vim.cmd.normal, { args = { "nN" }, bang = true })
end

local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_row = start_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_row = end_pos[2] - 1
  local end_col = end_pos[3]

  if vim.o.selection ~= "inclusive" then
    end_col = math.max(end_col - 1, 0)
  end

  local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  if #lines == 0 then
    return ""
  end

  return table.concat(lines, "\n")
end

local function execute_grep(args)
  vim.cmd("silent! grep! " .. args .. " .")

  if #vim.fn.getqflist() > 0 then
    vim.cmd.copen()
    vim.cmd("wincmd p")
    vim.cmd.redraw()
    return true
  end

  vim.cmd.cclose()
  vim.cmd.redraw()
  vim.api.nvim_echo({ { "No matches found." } }, false, {})
  return false
end

function M.live_grep()
  local user_input = vim.fn.input("Grep Pattern: ")
  if user_input == "" then
    return
  end

  execute_grep(user_input)
  set_search_register(user_input)
end

function M.global_grep()
  local word = vim.fn.expand("<cword>")
  if word == "" then
    return
  end

  local curr_buf = vim.fn.bufnr("%")
  local curr_lnum = vim.fn.line(".")
  local curr_col = vim.fn.col(".")
  local line_text = vim.fn.getline(".")
  local word_pat = "\\V\\<" .. vim.fn.escape(word, "\\") .. "\\>"
  local match = vim.fn.matchstrpos(line_text, word_pat, curr_col - 1)

  if match[2] >= 0 then
    curr_col = match[2] + 1
  end

  execute_grep("-w " .. vim.fn.shellescape(word))
  set_search_register_whole_word(word)
  refresh_search_highlight()

  local qflist = vim.fn.getqflist()
  if vim.tbl_isempty(qflist) then
    return
  end

  local idx = nil
  local best_idx = nil
  local best_dist = nil

  for i, item in ipairs(qflist) do
    if item.bufnr == curr_buf and item.lnum == curr_lnum then
      if (item.col or -1) == curr_col then
        idx = i
        break
      end

      local dist = math.abs((item.col or 0) - curr_col)
      if best_dist == nil or dist < best_dist then
        best_dist = dist
        best_idx = i
      end
    end
  end

  idx = idx or best_idx
  if idx and idx > 1 then
    local item = table.remove(qflist, idx)
    table.insert(qflist, 1, item)
    vim.fn.setqflist({}, "r", { items = qflist })
  end
end

function M.visual_grep()
  local selection = get_visual_selection()
  if selection == "" then
    return
  end

  execute_grep("-F " .. vim.fn.shellescape(selection))
  set_search_register(selection)
  refresh_search_highlight()
end

function M.clear_highlight()
  if vim.g.loaded_vim_highlighter ~= nil then
    vim.cmd("Hi clear")
  end
end

local function get_quickfix_filename(item)
  if not item then
    return nil
  end

  if item.bufnr and item.bufnr > 0 then
    local bufname = vim.fn.bufname(item.bufnr)
    if bufname ~= "" then
      return bufname
    end
  end

  if item.filename and item.filename ~= "" then
    return item.filename
  end

  return nil
end

local function jump_quickfix(cmd, item)
  local ok, err = pcall(vim.cmd, cmd)
  if ok then
    return
  end

  if type(err) == "string" and err:find("E824:") then
    local filename = get_quickfix_filename(item)
    if filename then
      local undofile = vim.fn.undofile(filename)
      if vim.fn.filereadable(undofile) == 1 then
        vim.fn.delete(undofile)
        vim.cmd(cmd)
        return
      end
    end
  end

  error(err)
end

local function cycle_quickfix(step)
  local qf = vim.fn.getqflist({ idx = 0, items = 1, size = 0 })
  if qf.size == 0 then
    return
  end

  local cmd
  local target_idx

  if step > 0 then
    if qf.idx >= qf.size then
      cmd = "cfirst"
      target_idx = 1
    else
      cmd = "cnext"
      target_idx = qf.idx + 1
    end
  else
    if qf.idx <= 1 then
      cmd = "clast"
      target_idx = qf.size
    else
      cmd = "cprevious"
      target_idx = qf.idx - 1
    end
  end

  jump_quickfix(cmd, qf.items[target_idx])
end

function M.quickfix_prev()
  cycle_quickfix(-1)
end

function M.quickfix_next()
  cycle_quickfix(1)
end

return M
