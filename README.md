# rookie_rg.nvim

Quickfix-first search helpers for Neovim with floating prompts for grep and file search.

## Default Keymaps

Normal mode:

- `<leader>gg`: grep word under cursor
- `<leader>gf`: open live grep prompt
- `<leader>b`: show existing buffers in quickfix
- `<C-p>`: open fuzzy file search prompt
- `<F8>`: toggle quickfix window
- `<F9>`: previous quickfix item
- `<F10>`: next quickfix item
- `<F11>`: close quickfix window

Visual mode:

- `<leader>gg`: grep visual selection

## Live Grep Prompt

Inside the floating live grep prompt:

- `Enter`: run grep and open quickfix results
- `Esc`: cancel
- `Ctrl-C`: toggle case-sensitive mode
- `Ctrl-W`: toggle whole-word mode
- `Ctrl-R`: toggle regex mode
- `Ctrl-U`: clear input
- `Backspace`: delete one character

The grep flags are preserved between prompt sessions.

## File Search Prompt

Inside the floating file search prompt:

- type to live-update quickfix file results
- `Enter`: finish file search and move focus to quickfix
- `Esc`: cancel and close the file search results
- `Ctrl-U`: clear input
- `Backspace`: delete one character

The file search uses `rg --files --hidden` and fuzzy-matches results in Lua.

Performance notes:

- live preview starts after `2` characters
- live preview reuses the previous match set when you keep typing
- live preview caps quickfix updates to the top `80` matches
- final `Enter` search still allows broader results

## Quickfix Actions

Inside the quickfix window:

- `Enter`: open selected item
- `s`: open selected item in a horizontal split
- `v`: open selected item in a vertical split
- `t`: open selected item in a new tab
- `q`: close quickfix

Extra behavior:

- file-search quickfix closes after opening with `Enter`
- buffer quickfix refreshes after switching buffers
- existing buffer quickfix skips quickfix buffers
- existing buffer quickfix skips unnamed, unmodified buffers

## Notes

- buffer quickfix entries preserve the last known cursor position
- live grep prioritizes the current-line match when possible
- file search keeps results in quickfix so you can continue using quickfix navigation
