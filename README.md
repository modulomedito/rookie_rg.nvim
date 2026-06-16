# rookie_rg.nvim

Quickfix-first search helpers for Neovim with floating prompts for grep and file search.

## Default Keymaps

Normal mode:

- `<leader>gg`: grep word under cursor
- `<leader>gf`: open live grep prompt
- `<leader>b`: show existing buffers in quickfix
- `<C-p>`: open fuzzy file search prompt
- `<F8>`: toggle quickfix window
- `<F9>`: preview previous quickfix item
- `<F10>`: preview next quickfix item
- `<F11>`: close quickfix window

Visual mode:

- `<leader>gg`: grep visual selection
- `<leader>gf`: open live grep prompt prefilled from visual selection

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
- `Up` / `Down`: move the quickfix selection
- `Ctrl-P` / `Ctrl-N`: move the quickfix selection
- `Enter`: confirm and open the currently selected quickfix item
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
- `j` / `k`: move selection and refresh the floating preview
- `<C-d>` / `<C-u>`: page through quickfix and refresh the floating preview
- `gg` / `G`: jump to the first or last quickfix item and refresh the floating preview
- `s`: open selected item in a horizontal split
- `v`: open selected item in a vertical split
- `t`: open selected item in a new tab
- `q`: close quickfix

Extra behavior:

- file-search quickfix closes after opening with `Enter`
- buffer quickfix refreshes after switching buffers
- existing buffer quickfix skips quickfix buffers
- existing buffer quickfix skips unnamed, unmodified buffers
- `<F9>` / `<F10>` move the quickfix selection and show a floating preview without opening the file
- use `Enter` after previewing to open the currently selected quickfix item

## Notes

- buffer quickfix entries preserve the last known cursor position
- live grep prioritizes the current-line match when possible
- file search keeps results in quickfix so you can continue using quickfix navigation
