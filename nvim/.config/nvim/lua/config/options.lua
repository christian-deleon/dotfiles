-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.relativenumber = false
vim.opt.spell = false

-- AI completion mode:
--   false = ghost text (inline suggestion, Tab to accept) — Copilot-native UX
--   true  = suggestions appear in the blink.cmp dropdown alongside LSP results
vim.g.ai_cmp = false
