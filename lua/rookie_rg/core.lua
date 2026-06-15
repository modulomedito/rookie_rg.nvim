local M = {}

local default_live_grep_flags = {
  case_sensitive = false,
  whole_word = false,
  regex = false,
}

local function get_live_grep_flags()
  local flags = vim.g.rookie_rg_live_grep_flags
  if type(flags) ~= "table" then
    flags = vim.deepcopy(default_live_grep_flags)
    vim.g.rookie_rg_live_grep_flags = flags
    return flags
  end

  flags.case_sensitive = flags.case_sensitive == true
  flags.whole_word = flags.whole_word == true
  flags.regex = flags.regex == true
  return flags
end

local function get_case_prefix(case_sensitive)
  if case_sensitive == nil then
    return ""
  end

  return case_sensitive and "\\C" or "\\c"
end

local function set_search_register(pattern, case_sensitive)
  vim.fn.setreg("/", get_case_prefix(case_sensitive) .. "\\V" .. pattern)
end

local function set_search_register_whole_word(pattern, case_sensitive)
  vim.fn.setreg("/", get_case_prefix(case_sensitive) .. "\\V\\<" .. vim.fn.escape(pattern, "\\") .. "\\>")
end

local function set_regex_search_register(pattern, case_sensitive, whole_word)
  local prefix = get_case_prefix(case_sensitive)
  if whole_word then
    vim.fn.setreg("/", prefix .. "\\<" .. pattern .. "\\>")
    return
  end

  vim.fn.setreg("/", prefix .. pattern)
end

local function set_live_grep_search_register(pattern, flags)
  if flags.regex then
    set_regex_search_register(pattern, flags.case_sensitive, flags.whole_word)
    return
  end

  if flags.whole_word then
    set_search_register_whole_word(pattern, flags.case_sensitive)
    return
  end

  set_search_register(pattern, flags.case_sensitive)
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

local function build_grep_args(pattern, opts)
  opts = opts or {}

  local args = {}
  local case_mode = opts.case_mode

  if case_mode == "sensitive" then
    table.insert(args, "-s")
  elseif case_mode == "insensitive" then
    table.insert(args, "-i")
  elseif case_mode == "smart" then
    table.insert(args, "-S")
  end

  if opts.whole_word then
    table.insert(args, "-w")
  end

  if opts.fixed_strings then
    table.insert(args, "-F")
  end

  table.insert(args, "--")
  table.insert(args, vim.fn.shellescape(pattern))
  table.insert(args, ".")

  return args
end

local function execute_grep(args)
  vim.cmd("silent! grep! " .. table.concat(args, " "))

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

local function format_live_grep_flags(flags)
  return table.concat({
    flags.case_sensitive and "[C]" or "C",
    flags.whole_word and "[W]" or "W",
    flags.regex and "[R]" or "R",
  })
end

local function open_live_grep_prompt()
  local prev_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    row = 1,
    col = 1,
    width = 40,
    height = 2,
    noautocmd = true,
  })

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].spell = false

  return {
    buf = buf,
    win = win,
    prev_win = prev_win,
  }
end

local function close_live_grep_prompt(prompt)
  if prompt == nil then
    return
  end

  if prompt.win and vim.api.nvim_win_is_valid(prompt.win) then
    vim.api.nvim_win_close(prompt.win, true)
  elseif prompt.buf and vim.api.nvim_buf_is_valid(prompt.buf) then
    vim.api.nvim_buf_delete(prompt.buf, { force = true })
  end

  if prompt.prev_win and vim.api.nvim_win_is_valid(prompt.prev_win) then
    pcall(vim.api.nvim_set_current_win, prompt.prev_win)
  end
end

local function render_live_grep_prompt(prompt, pattern, flags)
  local lines = {
    "Grep Pattern " .. format_live_grep_flags(flags),
    pattern,
  }
  local width = 36

  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
  end

  width = math.min(width, math.max(vim.o.columns - 4, 20))

  local config = {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = #lines,
    row = math.max(1, math.floor((vim.o.lines - #lines) * 0.2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  }

  vim.api.nvim_win_set_config(prompt.win, config)
  vim.bo[prompt.buf].modifiable = true
  vim.api.nvim_buf_set_lines(prompt.buf, 0, -1, false, lines)
  vim.bo[prompt.buf].modifiable = false
  vim.api.nvim_win_set_cursor(prompt.win, { 2, #pattern })
  vim.cmd.redraw()
end

local function trim_last_char(text)
  local char_count = vim.fn.strchars(text)
  if char_count == 0 then
    return ""
  end

  return vim.fn.strcharpart(text, 0, char_count - 1)
end

local function read_prompt_key()
  local ok, key = pcall(vim.fn.getcharstr)
  if ok then
    return key
  end

  local err = tostring(key)
  if err:find("Keyboard interrupt", 1, true) or err:find("Interrupted", 1, true) then
    return "^C"
  end

  error(key)
end

local function get_prompt_key_action(key)
  local translated_key = vim.fn.keytrans(key)

  if key == " " or translated_key == "<Space>" then
    return "append"
  end

  if translated_key == "^M" or translated_key == "<CR>" or translated_key == "<Enter>" then
    return "submit"
  end

  if translated_key == "<Esc>" then
    return "cancel"
  end

  if translated_key == "<C-C>" or translated_key == "^C" then
    return "toggle_case"
  end

  if translated_key == "<C-W>" or translated_key == "^W" then
    return "toggle_whole_word"
  end

  if translated_key == "<C-R>" or translated_key == "^R" then
    return "toggle_regex"
  end

  if translated_key == "<BS>" or translated_key == "^H" or translated_key == "<Backspace>" then
    return "backspace"
  end

  if translated_key == "^U" or translated_key == "<C-U>" then
    return "clear"
  end

  if translated_key:match("^<.*>$") or translated_key:match("^%^[A-Z]$") then
    return nil
  end

  return "append"
end

local function prompt_live_grep()
  local flags = get_live_grep_flags()
  local pattern = ""
  local prompt = open_live_grep_prompt()

  local ok, result = pcall(function()
    render_live_grep_prompt(prompt, pattern, flags)

    while true do
      local key = read_prompt_key()
      if key == "" then
        -- This shouldn't happen with getcharstr(), but just in case to avoid infinite loop
        break
      end
      local action = get_prompt_key_action(key)

      if action == "submit" then
        return pattern
      end

      if action == "cancel" then
        return nil
      end

      if action == "toggle_case" then
        flags.case_sensitive = not flags.case_sensitive
      elseif action == "toggle_whole_word" then
        flags.whole_word = not flags.whole_word
      elseif action == "toggle_regex" then
        flags.regex = not flags.regex
      elseif action == "backspace" then
        pattern = trim_last_char(pattern)
      elseif action == "clear" then
        pattern = ""
      elseif action == "append" then
        pattern = pattern .. key
      end

      render_live_grep_prompt(prompt, pattern, flags)
    end
  end)

  close_live_grep_prompt(prompt)

  if not ok then
    error(result)
  end

  return result
end

local function prioritize_current_line(pattern, flags)
  local curr_buf = vim.fn.bufnr("%")
  local curr_lnum = vim.fn.line(".")
  local curr_col = vim.fn.col(".")
  local line_text = vim.fn.getline(".")

  local qflist = vim.fn.getqflist()
  if vim.tbl_isempty(qflist) then
    return
  end

  local search_pat
  if flags.regex then
    search_pat = pattern
  else
    search_pat = "\\V" .. vim.fn.escape(pattern, "\\")
  end

  if flags.whole_word then
    search_pat = "\\<" .. search_pat .. "\\>"
  end

  local case_prefix = get_case_prefix(flags.case_sensitive)
  search_pat = case_prefix .. search_pat

  local match = vim.fn.matchstrpos(line_text, search_pat, curr_col - 1)
  if match[2] < 0 then
    -- Try matching from start of line if not found at cursor
    match = vim.fn.matchstrpos(line_text, search_pat, 0)
  end

  local target_col = match[2] >= 0 and (match[2] + 1) or nil
  local idx = nil
  local best_idx = nil
  local best_dist = nil

  for i, item in ipairs(qflist) do
    if item.bufnr == curr_buf and item.lnum == curr_lnum then
      if target_col and (item.col or -1) == target_col then
        idx = i
        break
      end

      local dist = target_col and math.abs((item.col or 0) - target_col) or 0
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
    vim.cmd.crewind() -- Move to the first item
  end
end

function M.live_grep()
  local curr_win = vim.api.nvim_get_current_win()
  local user_input = prompt_live_grep()
  if user_input == nil or user_input == "" then
    return
  end

  local flags = vim.deepcopy(get_live_grep_flags())

  if execute_grep(build_grep_args(user_input, {
    case_mode = flags.case_sensitive and "sensitive" or "insensitive",
    whole_word = flags.whole_word,
    fixed_strings = not flags.regex,
  })) then
    -- If matches found, prioritize current line
    vim.api.nvim_win_call(curr_win, function()
      prioritize_current_line(user_input, flags)
    end)
  end

  set_live_grep_search_register(user_input, flags)
  refresh_search_highlight()
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

  execute_grep(build_grep_args(word, {
    case_mode = "smart",
    whole_word = true,
    fixed_strings = true,
  }))
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

  execute_grep(build_grep_args(selection, {
    case_mode = "smart",
    fixed_strings = true,
  }))
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

local function is_quickfix_open()
  for _, wininfo in ipairs(vim.fn.getwininfo()) do
    if wininfo.quickfix == 1 and wininfo.loclist ~= 1 then
      return true
    end
  end

  return false
end

function M.toggle_quickfix()
  if is_quickfix_open() then
    vim.cmd.cclose()
    return
  end

  vim.cmd.copen()
end

function M.quickfix_prev()
  cycle_quickfix(-1)
end

function M.quickfix_next()
  cycle_quickfix(1)
end

return M
