-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Grep including hidden files (dotfiles), excluding .git
vim.keymap.set("n", "<leader>sG", function()
  Snacks.picker.grep({ args = { "--hidden", "--glob=!.git" } })
end, { desc = "Grep (hidden files)" })
