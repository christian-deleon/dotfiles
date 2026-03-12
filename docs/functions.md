# Shell Functions Reference

This document provides a reference for all custom shell functions available in this dotfiles repository.

## General

### `mkd <directory>`

Create a new directory and immediately cd into it.

```bash
mkd ~/projects/new-app
```

### `cdr [subdirectory]`

Change to the root directory of the current git repository. Optionally cd into a subdirectory relative to the repo root.

```bash
cdr              # Go to repo root
cdr src/app      # Go to repo_root/src/app
```

### `clocg [args...]`

Run cloc (Count Lines of Code) with automatic git integration. If `.gitignore` exists in the current directory, automatically uses `--vcs=git` to respect gitignore rules. Always formats output with thousands delimiter and alignment.

```bash
clocg .                    # Count current directory (respects .gitignore if present)
clocg --exclude-dir=vendor # Additional options still work
clocg src/                 # Count specific directory
```

---

## Kubernetes

Functions marked with \* support fzf for interactive selection when no arguments are provided.

### `kcs [config]` \*

Set the current kubeconfig. If no argument provided, uses fzf to select from `~/.kube/` configs.

```bash
kcs              # Interactive selection
kcs prod-config  # Direct selection
```

### `kca`

Set all kubeconfigs by merging all files in `~/.kube/` directory.

```bash
kca
```

### `kcu`

Unset the current kubeconfig (clears KUBECONFIG environment variable).

```bash
kcu
```

### `kn [namespace]` \*

Set the namespace for the current context. If no argument provided, uses fzf to select.

```bash
kn               # Interactive selection
kn production    # Direct selection
```

### `kc [context]` \*

Switch kubectl context. If no argument provided, uses fzf to select.

```bash
kc               # Interactive selection
kc prod-cluster  # Direct selection
```

### `kpa [pattern]`

Get all pods in all namespaces except kube-system, flux-system, and metallb-system. Optionally filter by pattern.

```bash
kpa              # All pods
kpa nginx        # Filter for "nginx"
```

### `ktns [namespace]` \*

Get cumulative CPU and Memory usage of all pods in a namespace. If no namespace provided, uses fzf to select or uses current context.

```bash
ktns             # Interactive or current context
ktns production  # Specific namespace
```

### `ktnsa`

Get CPU and Memory usage for all namespaces.

```bash
ktnsa
```

### `kl [namespace]` \*

Get logs from a pod. Uses fzf to select pod. If pod has multiple containers, prompts for container selection.

```bash
kl               # Current namespace, select pod interactively
kl production    # Specific namespace, select pod interactively
```

### `ke [namespace]` \*

Execute command in a pod (opens /bin/sh). Uses fzf to select pod and container if needed.

```bash
ke               # Current namespace, select pod interactively
ke production    # Specific namespace, select pod interactively
```

### `kdp [namespace]` \*

Describe a pod. Uses fzf to select pod.

```bash
kdp              # Current namespace
kdp production   # Specific namespace
```

### `kdelp [namespace]` \*

Delete a pod with confirmation prompt. Uses fzf to select pod.

```bash
kdelp            # Current namespace
kdelp production # Specific namespace
```

### `kdd [namespace]` \*

Describe a deployment. Uses fzf to select deployment.

```bash
kdd              # Current namespace
kdd production   # Specific namespace
```

### `ks [namespace|replicas] [replicas]` \*

Scale a deployment. Uses fzf to select deployment. Prompts for replica count if not provided.

```bash
ks               # Interactive: select deployment, input replicas
ks 3             # Select deployment, scale to 3
ks production 5  # In production namespace, scale to 5
```

### `filter_kubectl_output <pattern> <command>`

Internal helper function to filter kubectl output by pattern.

---

## Git

### `gc <repo-url>`

Git clone and cd into the cloned directory.

```bash
gc git@github.com:user/repo.git
```

### `gcc <repo-url>`

Git clone, cd into directory, and open in Cursor editor.

```bash
gcc git@github.com:user/repo.git
```

### `gcv <repo-url>`

Git clone, cd into directory, and open in VS Code.

```bash
gcv git@github.com:user/repo.git
```

### `gs`

Git status with short output.

```bash
gs
```

### `gi [templates...]`

Generate .gitignore file using gitignore.io API. Automatically includes vim, macos, and visualstudiocode templates. Accepts comma-separated templates. Prompts before overwriting existing .gitignore.

```bash
gi                    # Just defaults (vim, macos, visualstudiocode)
gi python,node        # Python + Node + defaults
gi "go, docker"       # Go + Docker + defaults
```

### `gcb <repo-url>`

Clone a git repository as a bare repo for worktree workflows. Clones into `<repo>/.git`, configures remote fetch, and cds into the repo directory.

```bash
gcb git@github.com:user/repo.git
# Creates repo/.git, cds into repo/
```

---

## Starship

### `sk`

Toggle Kubernetes module visibility in Starship prompt.

```bash
sk
```

---

## 1Password

### `opl`

Login to 1Password CLI.

```bash
opl
```

---

## Tmux

### `ts` \*

Interactive tmux session switcher with fzf preview. Shows a live snapshot of each session's active pane as you navigate. Switches client if already inside tmux, otherwise attaches.

```bash
ts    # fzf picker with live pane preview
```

---

## Worktrunk

Functions for git worktree management with fzf interactive selection and tmux integration.

### `wf [query]` \*

Interactive worktree switcher using fzf. Filters out the main worktree.

```bash
wf               # fzf picker from all worktrees
wf auth          # pre-filter fzf for "auth"
```

### `wrf` \*

Interactive multi-select worktree remover using fzf. Select multiple worktrees with Tab, confirm with Enter.

```bash
wrf              # fzf multi-select, removes selected worktrees and their branches
```

### `wts [branch] [cmd...]` \*

Attach to a worktree's tmux session. Sessions are created automatically by worktrunk's `post-create` hook; this function creates one on-the-fly for worktrees that predate the hook. Optionally sends a command to the session.

```bash
wts              # fzf picker, attach to selected worktree's tmux session
wts feature/auth # Attach to feature/auth's tmux session
```

### `wcl <branch> [prompt]`

Attach to a worktree's tmux session and launch Claude Code. Creates the worktree if it doesn't exist (the `post-create` hook auto-creates the tmux session).

```bash
wcl feature/auth                   # Launch claude in worktree
wcl feature/auth "fix login bug"   # Launch claude with a starting prompt
```

### `woc <branch> [prompt]`

Attach to a worktree's tmux session and launch OpenCode. Creates the worktree if it doesn't exist (the `post-create` hook auto-creates the tmux session).

```bash
woc feature/auth                   # Launch opencode in worktree
woc feature/auth "fix login bug"   # Launch opencode with a starting prompt
```

### `wclean` \*

Interactive multi-select worktree cleanup using fzf. Shows merged/stale worktrees and removes selected ones along with their branches.

```bash
wclean           # fzf multi-select merged/stale worktrees for removal
```

---

## Dotfiles

### `dothelp [query]` \*

Interactive fzf explorer for all shell functions and aliases defined in `.functions` and `.aliases`. Shows type, name, category, and description in the list; the preview pane shows the full function body or alias expansion.

```bash
dothelp          # Browse everything interactively
dothelp kube     # Pre-filter to Kubernetes shortcuts
dh               # Short alias
dh git           # Pre-filter to git shortcuts
```

**Controls:**
- Type to fuzzy-search across name, category, and description
- `ENTER` — print the selected name to stdout
- `Ctrl-H` — toggle the preview pane

---

## Notes

- Functions marked with \* use fzf for interactive selection
- Most Kubernetes functions respect the current namespace context
- Many functions provide both interactive (fzf) and direct argument modes
- Worktrunk functions require a bare repo clone (use `gcb` to set up)
- `wcl` and `woc` create tmux sessions — use `tls` to list and `tka` to kill all
