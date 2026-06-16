local M = {}

local default_live_grep_flags = {
  case_sensitive = false,
  whole_word = false,
  regex = false,
}

local min_live_file_search_chars = 2
local max_live_file_search_results = 80
local max_file_search_results = 200
local quickfix_preview_context = 8
local quickfix_preview = {
  buf = nil,
  win = nil,
  ns = vim.api.nvim_create_namespace("RookieRgQuickfixPreview"),
}
local close_quickfix_preview
local get_quickfix_filename
local get_quickfix_window_id
local set_quickfix_selection

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

local function set_live_grep_flags(flags)
  vim.g.rookie_rg_live_grep_flags = {
    case_sensitive = flags.case_sensitive == true,
    whole_word = flags.whole_word == true,
    regex = flags.regex == true,
  }
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
  local mode = vim.fn.mode(1)
  local visual_mode = mode
  local start_pos
  local end_pos

  if mode == "v" or mode == "V" or mode == "\22" then
    start_pos = vim.fn.getpos("v")
    end_pos = vim.fn.getpos(".")
  else
    start_pos = vim.fn.getpos("'<")
    end_pos = vim.fn.getpos("'>")
    visual_mode = vim.fn.visualmode()
  end

  local start_row = start_pos[2]
  local start_col = start_pos[3]
  local end_row = end_pos[2]
  local end_col = end_pos[3]

  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  if visual_mode == "V" then
    local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
    if #lines == 0 then
      return ""
    end

    return table.concat(lines, "\n")
  end

  start_row = start_row - 1
  start_col = math.max(start_col - 1, 0)
  end_row = end_row - 1

  if vim.o.selection ~= "inclusive" then
    end_col = math.max(end_col - 1, 0)
  end

  local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  if #lines == 0 then
    return ""
  end

  return table.concat(lines, "\n")
end

local function normalize_prompt_text(text)
  if text == nil or text == "" then
    return ""
  end

  return (text:gsub("[\r\n]+", " "))
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
  close_quickfix_preview()

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

local function format_file_search_prompt()
  return "Find Files"
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

local function render_file_search_prompt(prompt, pattern)
  local lines = {
    format_file_search_prompt(),
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

local function starts_with(text, prefix)
  return prefix == "" or text:sub(1, #prefix) == prefix
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

  if translated_key == "<Down>" or translated_key == "^N" or translated_key == "<C-N>" then
    return "select_next"
  end

  if translated_key == "<Up>" or translated_key == "^P" or translated_key == "<C-P>" then
    return "select_prev"
  end

  if translated_key:match("^<.*>$") or translated_key:match("^%^[A-Z]$") then
    return nil
  end

  return "append"
end

local get_project_files
local open_file_quickfix
local find_files

local function prompt_live_grep(initial_pattern)
  local flags = vim.deepcopy(get_live_grep_flags())
  local pattern = normalize_prompt_text(initial_pattern or "")
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
        set_live_grep_flags(flags)
        return {
          pattern = pattern,
          flags = vim.deepcopy(flags),
        }
      end

      if action == "cancel" then
        return nil
      end

      if action == "toggle_case" then
        flags.case_sensitive = not flags.case_sensitive
        set_live_grep_flags(flags)
      elseif action == "toggle_whole_word" then
        flags.whole_word = not flags.whole_word
        set_live_grep_flags(flags)
      elseif action == "toggle_regex" then
        flags.regex = not flags.regex
        set_live_grep_flags(flags)
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

local function prompt_file_search()
  local pattern = ""
  local prompt = open_live_grep_prompt()
  local project_files = get_project_files()
  local previous_pattern = ""
  local previous_matches = project_files

  if project_files == nil then
    close_live_grep_prompt(prompt)
    vim.api.nvim_echo({ { "Failed to list project files." } }, false, {})
    return nil
  end

  table.sort(project_files)

  local ok, result = pcall(function()
    render_file_search_prompt(prompt, pattern)

    while true do
      local key = read_prompt_key()
      if key == "" then
        break
      end

      local action = get_prompt_key_action(key)
      local pattern_changed = false
      if action == "submit" then
        if M.quickfix_enter() then
          return {
            confirmed = true,
          }
        end

        return {
          pattern = pattern,
          project_files = project_files,
        }
      end

      if action == "cancel" then
        vim.cmd.cclose()
        return nil
      end

      if action == "backspace" then
        pattern = trim_last_char(pattern)
        pattern_changed = true
      elseif action == "clear" then
        pattern = ""
        pattern_changed = true
      elseif action == "append" then
        pattern = pattern .. key
        pattern_changed = true
      elseif action == "select_next" then
        M.quickfix_select_next()
      elseif action == "select_prev" then
        M.quickfix_select_prev()
      end

      if pattern_changed and vim.fn.strchars(pattern) < min_live_file_search_chars then
        previous_pattern = ""
        previous_matches = project_files
        vim.cmd.cclose()
      elseif pattern_changed then
        local source_files = project_files
        if starts_with(pattern, previous_pattern) and previous_matches ~= nil then
          source_files = previous_matches
        end

        local _, matches = find_files(pattern, {
          project_files = source_files,
          focus_quickfix = false,
          restore_win = prompt.win,
          notify_on_empty = false,
          max_results = max_live_file_search_results,
          return_all_matches = true,
        })

        previous_pattern = pattern
        previous_matches = matches or project_files
      end
      render_file_search_prompt(prompt, pattern)
    end
  end)

  close_live_grep_prompt(prompt)

  if not ok then
    error(result)
  end

  return result
end

local function fuzzy_score(candidate, query)
  if query == "" then
    return 0
  end

  local candidate_lower = candidate:lower()
  local query_lower = query:lower()
  local query_len = #query_lower
  local candidate_len = #candidate_lower
  local basename = candidate:match("[^/\\]+$") or candidate
  local basename_lower = basename:lower()
  local score = 0
  local start_idx = nil
  local last_match_idx = nil
  local search_from = 1

  if basename_lower:find(query_lower, 1, true) == 1 then
    score = score + 150
  else
    local basename_match = basename_lower:find(query_lower, 1, true)
    if basename_match ~= nil then
      score = score + math.max(0, 110 - basename_match)
    end
  end

  for i = 1, query_len do
    local ch = query_lower:sub(i, i)
    local found = candidate_lower:find(ch, search_from, true)
    if found == nil then
      return nil
    end

    if start_idx == nil then
      start_idx = found
      score = score + math.max(0, 100 - found)
    end

    if last_match_idx ~= nil then
      if found == last_match_idx + 1 then
        score = score + 15
      else
        score = score - (found - last_match_idx - 1)
      end
    end

    local prev = found > 1 and candidate_lower:sub(found - 1, found - 1) or ""
    if prev == "/" or prev == "\\" or prev == "_" or prev == "-" or prev == " " then
      score = score + 10
    end

    local curr = candidate:sub(found, found)
    if curr:match("%u") then
      score = score + 3
    end

    last_match_idx = found
    search_from = found + 1
  end

  score = score - (candidate_len - query_len)
  return score
end

get_project_files = function()
  local files = vim.fn.systemlist({ "rg", "--files", "--hidden" })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  return files
end

local function build_file_quickfix_items(files)
  local items = {}

  for _, file in ipairs(files) do
    local bufnr = vim.fn.bufnr(file)
    if bufnr > 0 then
      table.insert(items, {
        bufnr = bufnr,
        filename = file,
        lnum = 1,
        col = 1,
        text = file,
      })
    else
      table.insert(items, {
        filename = file,
        lnum = 1,
        col = 1,
        text = file,
      })
    end
  end

  return items
end

close_quickfix_preview = function()
  if quickfix_preview.win and vim.api.nvim_win_is_valid(quickfix_preview.win) then
    vim.api.nvim_win_close(quickfix_preview.win, true)
  elseif quickfix_preview.buf and vim.api.nvim_buf_is_valid(quickfix_preview.buf) then
    vim.api.nvim_buf_delete(quickfix_preview.buf, { force = true })
  end

  quickfix_preview.buf = nil
  quickfix_preview.win = nil
end

local function ensure_quickfix_preview_buffer()
  if quickfix_preview.buf and vim.api.nvim_buf_is_valid(quickfix_preview.buf) then
    return quickfix_preview.buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  quickfix_preview.buf = buf
  return buf
end

local function get_preview_source(item)
  local lnum = math.max(1, item.lnum or 1)
  local filename = get_quickfix_filename(item)
  local source_ft = ""
  local source_name = filename
  local lines = nil
  local start_lnum = 1
  local end_lnum = 1

  if item.bufnr
    and item.bufnr > 0
    and vim.api.nvim_buf_is_valid(item.bufnr)
    and vim.api.nvim_buf_is_loaded(item.bufnr)
  then
    local total_lines = vim.api.nvim_buf_line_count(item.bufnr)
    start_lnum = math.max(1, lnum - quickfix_preview_context)
    end_lnum = math.min(total_lines, lnum + quickfix_preview_context)
    lines = vim.api.nvim_buf_get_lines(item.bufnr, start_lnum - 1, end_lnum, false)
    source_ft = vim.bo[item.bufnr].filetype or ""
    if source_name == nil or source_name == "" then
      source_name = vim.fn.bufname(item.bufnr)
    end
  elseif filename and filename ~= "" then
    local ok, file_lines = pcall(vim.fn.readfile, filename)
    if not ok then
      return nil
    end

    start_lnum = math.max(1, lnum - quickfix_preview_context)
    end_lnum = math.min(#file_lines, lnum + quickfix_preview_context)
    lines = {}
    for line_nr = start_lnum, end_lnum do
      table.insert(lines, file_lines[line_nr] or "")
    end
    source_ft = vim.filetype.match({ filename = filename }) or ""
  else
    return nil
  end

  if lines == nil or vim.tbl_isempty(lines) then
    lines = { "" }
    start_lnum = lnum
    end_lnum = lnum
  end

  local number_width = math.max(2, #tostring(end_lnum))
  local preview_lines = {}
  for idx, line in ipairs(lines) do
    local absolute_lnum = start_lnum + idx - 1
    table.insert(preview_lines, string.format("%" .. number_width .. "d %s", absolute_lnum, line))
  end

  return {
    title = source_name ~= nil and source_name ~= "" and vim.fn.fnamemodify(source_name, ":.") or "[No Name]",
    lines = preview_lines,
    target_lnum = math.min(#preview_lines, math.max(1, lnum - start_lnum + 1)),
    filetype = source_ft,
  }
end

local function preview_quickfix_item(item)
  local preview = get_preview_source(item)
  if preview == nil then
    close_quickfix_preview()
    return false
  end

  local buf = ensure_quickfix_preview_buffer()
  local content_width = 36
  for _, line in ipairs(preview.lines) do
    content_width = math.max(content_width, vim.fn.strdisplaywidth(line) + 2)
  end

  local width = math.min(content_width, math.max(40, math.floor(vim.o.columns * 0.55)))
  local height = math.min(#preview.lines, math.max(6, math.floor(vim.o.lines * 0.45)))
  local row = math.max(1, math.floor((vim.o.lines - height) * 0.18))
  local col = math.max(0, vim.o.columns - width - 3)

  if quickfix_preview.win and vim.api.nvim_win_is_valid(quickfix_preview.win) then
    vim.api.nvim_win_set_config(quickfix_preview.win, {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      row = row,
      col = col,
      width = width,
      height = height,
      title = " Preview: " .. preview.title .. " ",
      title_pos = "center",
    })
  else
    quickfix_preview.win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      row = row,
      col = col,
      width = width,
      height = height,
      noautocmd = true,
      title = " Preview: " .. preview.title .. " ",
      title_pos = "center",
    })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview.lines)
  vim.api.nvim_buf_clear_namespace(buf, quickfix_preview.ns, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, quickfix_preview.ns, "Visual", preview.target_lnum - 1, 0, -1)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = preview.filetype

  vim.wo[quickfix_preview.win].wrap = false
  vim.wo[quickfix_preview.win].number = false
  vim.wo[quickfix_preview.win].relativenumber = false
  vim.wo[quickfix_preview.win].signcolumn = "no"
  vim.wo[quickfix_preview.win].foldcolumn = "0"
  vim.wo[quickfix_preview.win].cursorline = false
  vim.api.nvim_win_set_cursor(quickfix_preview.win, { preview.target_lnum, 0 })
  vim.cmd.redraw()
  return true
end

open_file_quickfix = function(files, query, opts)
  opts = opts or {}
  close_quickfix_preview()
  local items = build_file_quickfix_items(files)
  local title = query == "" and "Files" or ("Files: " .. query)
  local quickfix_open = false

  for _, wininfo in ipairs(vim.fn.getwininfo()) do
    if wininfo.quickfix == 1 and wininfo.loclist ~= 1 then
      quickfix_open = true
      break
    end
  end

  if vim.tbl_isempty(items) then
    vim.fn.setqflist({}, "r", {
      title = title,
      items = {},
    })
    vim.cmd.cclose()
    if opts.notify_on_empty ~= false then
      vim.api.nvim_echo({ { "No files found." } }, false, {})
    end
    return false
  end

  vim.fn.setqflist({}, "r", {
    title = title,
    items = items,
  })
  if not quickfix_open then
    vim.cmd.copen()
  end
  if opts.focus_quickfix == false and opts.restore_win and vim.api.nvim_win_is_valid(opts.restore_win) then
    pcall(vim.api.nvim_set_current_win, opts.restore_win)
  end
  vim.cmd.redraw()
  return true
end

find_files = function(query, opts)
  opts = opts or {}
  local files = opts.project_files or get_project_files()
  if files == nil then
    vim.api.nvim_echo({ { "Failed to list project files." } }, false, {})
    return false
  end

  if query == "" then
    local success = open_file_quickfix(files, query, opts)
    return success, files
  end

  local matches = {}
  for _, file in ipairs(files) do
    local score = fuzzy_score(file, query)
    if score ~= nil then
      table.insert(matches, {
        file = file,
        score = score,
      })
    end
  end

  table.sort(matches, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end

    if #a.file ~= #b.file then
      return #a.file < #b.file
    end

    return a.file < b.file
  end)

  local all_matches = {}
  local files_only = {}
  local max_results = opts.max_results or max_file_search_results
  for i, match in ipairs(matches) do
    table.insert(all_matches, match.file)
    if i > max_results then
      goto continue
    end
    table.insert(files_only, match.file)
    ::continue::
  end

  local success = open_file_quickfix(files_only, query, opts)
  if opts.return_all_matches then
    return success, all_matches
  end

  return success, all_matches
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
  return M.live_grep_with_input("")
end

function M.live_grep_with_input(initial_pattern)
  local curr_win = vim.api.nvim_get_current_win()
  local prompt_result = prompt_live_grep(initial_pattern)
  if prompt_result == nil or prompt_result.pattern == "" then
    return
  end

  local user_input = prompt_result.pattern
  local flags = prompt_result.flags

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

function M.visual_live_grep()
  local selection = get_visual_selection()
  if selection == "" then
    return
  end

  M.live_grep_with_input(selection)
end

function M.find_files()
  local prompt_result = prompt_file_search()
  if prompt_result == nil then
    return
  end

  if prompt_result.confirmed then
    return
  end

  find_files(prompt_result.pattern, {
    project_files = prompt_result.project_files,
    focus_quickfix = true,
    notify_on_empty = true,
  })
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

get_quickfix_filename = function(item)
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

  local target_idx
  local qf_win = get_quickfix_window_id()
  if qf_win and vim.api.nvim_win_is_valid(qf_win) then
    local cursor = vim.api.nvim_win_get_cursor(qf_win)
    if cursor and cursor[1] ~= nil then
      qf.idx = cursor[1]
    end
  end

  if step > 0 then
    if qf.idx >= qf.size then
      target_idx = 1
    else
      target_idx = qf.idx + 1
    end
  else
    if qf.idx <= 1 then
      target_idx = qf.size
    else
      target_idx = qf.idx - 1
    end
  end

  if not set_quickfix_selection(target_idx, { focus_quickfix = true }) then
    return
  end

  preview_quickfix_item(qf.items[target_idx])
end

local function is_file_search_quickfix(title)
  return type(title) == "string" and title:match("^Files")
end

local function is_buffer_quickfix(title)
  return title == "Buffers"
end

local function should_show_buffer(bufinfo)
  if vim.bo[bufinfo.bufnr].buftype == "quickfix" then
    return false
  end

  if (bufinfo.name == nil or bufinfo.name == "") and bufinfo.changed ~= 1 then
    return false
  end

  return true
end

local function is_quickfix_open()
  for _, wininfo in ipairs(vim.fn.getwininfo()) do
    if wininfo.quickfix == 1 and wininfo.loclist ~= 1 then
      return true
    end
  end

  return false
end

local function find_non_quickfix_window()
  local alternate_winnr = vim.fn.winnr("#")
  if alternate_winnr > 0 then
    local alternate_win = vim.fn.win_getid(alternate_winnr)
    if alternate_win > 0 and vim.api.nvim_win_is_valid(alternate_win) then
      local wininfo = vim.fn.getwininfo(alternate_win)[1]
      if wininfo and wininfo.quickfix ~= 1 then
        return alternate_win
      end
    end
  end

  local current_win = vim.api.nvim_get_current_win()
  for _, wininfo in ipairs(vim.fn.getwininfo()) do
    if wininfo.winid ~= current_win and wininfo.quickfix ~= 1 and wininfo.loclist ~= 1 then
      return wininfo.winid
    end
  end

  return nil
end

get_quickfix_window_id = function()
  for _, wininfo in ipairs(vim.fn.getwininfo()) do
    if wininfo.quickfix == 1 and wininfo.loclist ~= 1 then
      return wininfo.winid
    end
  end

  return nil
end

local function get_selected_quickfix_entry()
  local qf = vim.fn.getqflist({ idx = 0, items = 1, size = 0, title = 1 })
  local qf_win = get_quickfix_window_id()

  if qf_win == nil or not vim.api.nvim_win_is_valid(qf_win) then
    return nil, nil, nil, nil
  end

  local selected_idx = vim.api.nvim_win_get_cursor(qf_win)[1]

  if qf.size == 0 or selected_idx < 1 or selected_idx > #qf.items then
    return nil, nil, nil, nil
  end

  return qf, selected_idx, qf.items[selected_idx], qf_win
end

set_quickfix_selection = function(target_idx, opts)
  opts = opts or {}
  local qf = vim.fn.getqflist({ items = 1, size = 0 })
  local qf_win = get_quickfix_window_id()

  if qf.size == 0 or qf_win == nil or not vim.api.nvim_win_is_valid(qf_win) then
    return false
  end

  if target_idx < 1 then
    target_idx = qf.size
  elseif target_idx > qf.size then
    target_idx = 1
  end

  pcall(vim.fn.setqflist, {}, "a", { idx = target_idx })
  pcall(vim.api.nvim_win_set_cursor, qf_win, { target_idx, 0 })
  if opts.focus_quickfix and vim.api.nvim_win_is_valid(qf_win) then
    pcall(vim.api.nvim_set_current_win, qf_win)
  end
  vim.cmd.redraw()
  return true
end

local function post_quickfix_open(qf_title, qf_win)
  close_quickfix_preview()
  if is_file_search_quickfix(qf_title) then
    if qf_win and vim.api.nvim_win_is_valid(qf_win) then
      pcall(vim.api.nvim_win_close, qf_win, true)
    else
      vim.cmd.cclose()
    end
  elseif is_buffer_quickfix(qf_title) then
    M.show_buffers()
  end
end

local function open_selected_quickfix_item(mode)
  local qf, selected_idx, item, qf_win = get_selected_quickfix_entry()
  if qf == nil then
    return false
  end

  if mode == "tabedit" then
    vim.cmd.tabnew()
  else
    local target_win = find_non_quickfix_window()
    if target_win and vim.api.nvim_win_is_valid(target_win) then
      pcall(vim.api.nvim_set_current_win, target_win)
    end

    if mode == "split" then
      vim.cmd.split()
    elseif mode == "vsplit" then
      vim.cmd.vsplit()
    end
  end

  jump_quickfix("cc " .. selected_idx, item)
  post_quickfix_open(qf.title, qf_win)
  return true
end

local function get_buffer_display_name(bufinfo)
  if bufinfo.name ~= nil and bufinfo.name ~= "" then
    return vim.fn.fnamemodify(bufinfo.name, ":.")
  end

  return "[No Name]"
end

local function get_buffer_position(bufinfo)
  local lnum = bufinfo.lnum and bufinfo.lnum > 0 and bufinfo.lnum or 1
  local col = 1

  for _, winid in ipairs(bufinfo.windows or {}) do
    if vim.api.nvim_win_is_valid(winid) then
      local cursor = vim.api.nvim_win_get_cursor(winid)
      return cursor[1], cursor[2] + 1
    end
  end

  local ok, mark = pcall(vim.api.nvim_buf_get_mark, bufinfo.bufnr, '"')
  if ok and type(mark) == "table" then
    if mark[1] ~= nil and mark[1] > 0 then
      lnum = mark[1]
    end

    if mark[2] ~= nil and mark[2] >= 0 then
      col = mark[2] + 1
    end
  end

  return lnum, col
end

function M.show_buffers()
  local prev_win = vim.api.nvim_get_current_win()
  local buffers = vim.fn.getbufinfo({ buflisted = 1 })
  close_quickfix_preview()

  table.sort(buffers, function(a, b)
    if a.lastused ~= b.lastused then
      return a.lastused > b.lastused
    end

    return a.bufnr < b.bufnr
  end)

  local items = {}
  for _, bufinfo in ipairs(buffers) do
    if should_show_buffer(bufinfo) then
      local lnum, col = get_buffer_position(bufinfo)

      table.insert(items, {
        bufnr = bufinfo.bufnr,
        lnum = lnum,
        col = col,
        text = string.format(
          "%s %s",
          bufinfo.changed == 1 and "[+]" or "[ ]",
          get_buffer_display_name(bufinfo)
        ),
      })
    end
  end

  if vim.tbl_isempty(items) then
    vim.api.nvim_echo({ { "No listed buffers found." } }, false, {})
    return
  end

  vim.fn.setqflist({}, "r", {
    title = "Buffers",
    items = items,
  })

  vim.cmd.copen()
  if prev_win and vim.api.nvim_win_is_valid(prev_win) then
    pcall(vim.api.nvim_set_current_win, prev_win)
  end
  vim.cmd.redraw()
end

function M.toggle_quickfix()
  if is_quickfix_open() then
    close_quickfix_preview()
    vim.cmd.cclose()
    return
  end

  vim.cmd.copen()
end

function M.quickfix_enter()
  return open_selected_quickfix_item("edit")
end

function M.quickfix_split()
  return open_selected_quickfix_item("split")
end

function M.quickfix_vsplit()
  return open_selected_quickfix_item("vsplit")
end

function M.quickfix_tabedit()
  return open_selected_quickfix_item("tabedit")
end

function M.quickfix_select_next()
  local _, selected_idx = get_selected_quickfix_entry()
  if selected_idx == nil then
    return false
  end

  return set_quickfix_selection(selected_idx + 1)
end

function M.quickfix_select_prev()
  local _, selected_idx = get_selected_quickfix_entry()
  if selected_idx == nil then
    return false
  end

  return set_quickfix_selection(selected_idx - 1)
end

function M.close_quickfix()
  close_quickfix_preview()
  vim.cmd.cclose()
end

function M.close_quickfix_preview()
  close_quickfix_preview()
end

function M.preview_selected_quickfix_item()
  local _, _, item = get_selected_quickfix_entry()
  if item == nil then
    return false
  end

  return preview_quickfix_item(item)
end

function M.quickfix_prev()
  cycle_quickfix(-1)
end

function M.quickfix_next()
  cycle_quickfix(1)
end

return M
