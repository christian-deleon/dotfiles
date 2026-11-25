# tmux cheat sheet

Quick reference for the tmux setup in `tmux/.config/tmux/`. The prefix is
**Ctrl+Space** (Ctrl+B also works). "prefix, X" means press the prefix, let
go, then press X. Full details on the shell commands are in
[functions.md](functions.md#tmux).

## Sessions

| Keys | Does |
|------|------|
| prefix, C | Pick a project under `~/projects` and open its session (a worktree project gets a window per worktree) |
| prefix, s | Fuzzy-pick another session and switch to it, most recently used first |
| prefix, P / prefix, N | Previous / next session |
| Alt+Up / Alt+Down | Previous / next session, no prefix |
| prefix, R | Rename the session |
| prefix, K | Kill the session (asks first; moves you to the next one) |
| prefix, d | Detach (stock tmux) |

## Windows

| Keys | Does |
|------|------|
| prefix, c | New window in the current pane's folder |
| prefix, W | New agent session in a new worktree (`wtc`); asks for a branch, blank gives a codename |
| Alt+1 … Alt+9 | Go to window 1–9 |
| Alt+Left / Alt+Right | Previous / next window |
| Alt+Shift+Left / Right | Move the window left / right |
| prefix, r | Rename the window |
| prefix, k | Kill the window (asks first) |

Window names follow the git branch of the pane's folder (the folder name
outside git). Numbering starts at 1 and closes gaps when a window goes away.

## Panes

| Keys | Does |
|------|------|
| Alt+Enter, or prefix, h | Split, new pane below (in Grok, Alt+Enter is a newline instead) |
| Alt+Shift+Enter, or prefix, v | Split, new pane to the right |
| Ctrl+Alt+Arrow | Move to the pane in that direction |
| Ctrl+Alt+Shift+Arrow | Resize the pane by 5 cells |
| prefix, z | Zoom the pane to fill the window and back (stock tmux) |
| prefix, x | Kill the pane, **no confirmation** |

## Copy mode

| Keys | Does |
|------|------|
| prefix, [ | Enter copy mode (stock tmux); move with vi keys |
| v | Start a selection |
| y | Copy the selection and leave copy mode (also reaches the system clipboard) |

## Mouse

| Action | Does |
|--------|------|
| Click a window or session name | Switch to it |
| Right-click a session name | Session menu: switch, rename, new session, new window there, detach |
| Right-click a window name | tmux's window menu: swap, kill, respawn, mark, rename, new window |
| Ctrl+drag a pane border | Resize; a plain drag does nothing, so borders don't move by accident |
| Scroll | Scroll the pane's history (enters copy mode) |

## Status bar

At the top, on one line:

- **Left:** the current session's windows; the current one is blue. A yellow
  **●** after a window name means an agent there finished its turn and is
  waiting on you. It clears when you go to that window.
- **Right:** every session, the current one highlighted in blue, then
  `COPY`, `PREFIX` or `ZOOM` when one applies, then the host name.

## Shell commands

| Command | Does |
|---------|------|
| `tp` | Project picker, same as prefix, C; use it in a fresh terminal instead of `tmux` |
| `ts` | Session picker: Enter switches, Ctrl+X kills (Tab marks several), Ctrl+R renames |
| `tw` | Jump to any window in any session |
| `tav` / `tavk` | Lay out the window: agent, shell and Neovim (`tavk` adds k9s) |
| `wtc [branch]` | New agent session in a new worktree window |
| `wta [branch]` | Reopen a worktree's window and continue its conversation |
| `wtaa` | Reopen every worktree in the project (after a reboot) |
| `wtx` | Close finished worktree sessions |
| `ta` `tl` `tn` `tk` `tka` | `tmux` attach, list, new, kill session, kill server |

## Config

| Keys | Does |
|------|------|
| prefix, q | Reload `tmux.conf` |
| prefix, ? | List every key binding (stock tmux) |

A reload only applies what the file sets. An option removed from the file
keeps its old value until tmux restarts or you unset it with `tmux set -gu <option>`.
