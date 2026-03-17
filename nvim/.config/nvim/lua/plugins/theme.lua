-- On Omarchy, ~/.config/omarchy/current/theme/neovim.lua is managed by the
-- theme switcher. Load it dynamically if present, otherwise fall back to
-- tokyonight for non-Omarchy machines.
local omarchy_theme = vim.fn.expand("~/.config/omarchy/current/theme/neovim.lua")

if vim.fn.filereadable(omarchy_theme) == 1 then
	local ok, spec = pcall(dofile, omarchy_theme)
	if ok and spec then
		return spec
	end
end

return {
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "tokyonight",
		},
	},
}
