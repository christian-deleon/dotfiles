# ~/.config/blesh/init.sh — ble.sh user config, auto-sourced by ble.sh on load.
# Managed via omadot/Stow (symlinked from ~/.dotfiles/blesh/.config/blesh/).
# Docs: https://github.com/akinomyoga/ble.sh/wiki

# Autosuggestion ghost text. ble.sh's default `auto_complete` face is
# `bg=254,fg=238` — a near-white *background* that renders as a distracting gray
# box around the inline suggestion. Drop the background for clean, fish/zsh-style
# dim foreground ghost text instead. (Add `,italic` if you want fish's slant.)
ble-face auto_complete='fg=242'

# Alt+Backspace → delete the previous word. ble.sh's default emacs keymap binds
# every Alt+Backspace variant (M-C-? / M-DEL / M-C-h / M-BS) to
# `copy-backward-sword`, which *copies* the word rather than deleting it — unlike
# readline's `backward-kill-word`. Rebind the whole family to a kill widget so
# the familiar "hold Alt to rub out the last word" works again. `cword` is
# shell-token aware (matching ble.sh's own Alt+h / Alt+d); swap to
# `kill-backward-uword` for whitespace-only word boundaries.
ble-bind -f 'M-C-?' 'kill-backward-cword'
ble-bind -f 'M-DEL' 'kill-backward-cword'
ble-bind -f 'M-C-h' 'kill-backward-cword'
ble-bind -f 'M-BS'  'kill-backward-cword'

# Suppress the `[ble: elapsed 16.808s (CPU 223.8%)]` line ble.sh prints after a
# command crosses its CPU/wall-clock threshold. The timing report is noise here;
# emptying `exec_elapsed_enabled` clears every trigger so the line never shows.
bleopt exec_elapsed_enabled=
