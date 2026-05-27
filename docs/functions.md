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

### `fkill` \*

Pick processes from `ps` with fzf and kill them. Sorted by PID; type to fuzzy-match any column (user, %cpu, command, …). `TAB` to multi-select. `ENTER` sends `SIGTERM`; `Ctrl-K` sends `SIGKILL` for unresponsive processes.

```bash
fkill    # picker — ENTER for TERM, Ctrl-K for KILL
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

### `kl [namespace] [pod] [container]` \*

Get logs from a pod. Any positional you omit is picked via fzf; any you pass skips its picker. Pass `""` to skip namespace (use current context) while still specifying pod/container.

```bash
kl                          # fzf everything in current namespace
kl production               # fzf pod + container in 'production'
kl production api-7d9c      # that pod, fzf container if multi
kl production api-7d9c app  # fully specified, no picker
kl "" api-7d9c              # current ns, that pod
```

### `ke [namespace] [pod] [container]` \*

Exec into a pod (opens `/bin/sh`). Same positional/fzf semantics as [`kl`](#kl-namespace-pod-container-).

```bash
ke                          # fzf everything in current namespace
ke production api-7d9c app  # fully specified, no picker
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

## Flux

### `fx` \*

Unified picker over every reconcilable Flux resource in the cluster — Kustomizations, HelmReleases, and Sources (Git, Helm, OCI, Bucket) — with `kubectl describe` preview. One picker, four actions via keybinds:

- **`ENTER`** — `flux reconcile` the highlighted resource
- **`Ctrl-S`** — `flux suspend` (pause reconciliation)
- **`Ctrl-R`** — `flux resume`
- **`Ctrl-E`** — `flux events --for=Kind/name` (recent events for the resource)

```bash
fx    # picker — ENTER reconcile / Ctrl-S suspend / Ctrl-R resume / Ctrl-E events
```

### `fpush [git-push-args...]`

Push the current branch, then reconcile any Flux `GitRepository` whose `.spec.url` matches the local repo's `origin`, and cascade to every Kustomization that references that source. Matches by normalized URL (strips scheme, user, `.git`, trailing `/`; converts `git@host:owner/repo` ↔ `https://host/owner/repo`); falls back to repo basename when no exact URL match. Operates against the current kubeconfig context. Requires `kubectl`, `flux`, and `jq`.

```bash
fpush                  # git push, then source + kustomization reconcile
fpush -u origin feat   # arguments forward to git push
```

---

## Skaffold

### `sk` \*

Picker over **every** Skaffold config reachable from cwd, paired with each config's profiles (plus a `(no profile)` row per config). Discovery is content-based — any YAML containing `apiVersion: skaffold/` qualifies, so it catches configs that aren't literally named `skaffold.yaml` (e.g. `infra/skaffold/athenis-engine.yaml`). Uses `git ls-files` inside a repo (fast + gitignore-aware), falls back to `find` otherwise. Preview shows the selected profile's patch — or the base config with `.profiles` stripped for `(no profile)`.

One picker, five actions via keybinds:

- **`ENTER`** — `skaffold dev` (main inner loop)
- **`Ctrl-D`** — `skaffold debug`
- **`Ctrl-R`** — `skaffold run` (one-shot build + deploy)
- **`Ctrl-B`** — `skaffold build`
- **`Ctrl-X`** — `skaffold delete`

Selection runs `skaffold <verb> -f <path> [-p <profile>]`, so it works from anywhere within the project. Configs imported by another via `requires:` still appear in the picker — target them when you want to iterate on a single module standalone.

```bash
sk    # picker — fuzzy-search by path or profile
```

---

## AWS

All `ssm*` functions auto-pick an instance via fzf when the first positional argument isn't an instance ID (matched against `^i-[0-9a-f]+$`). `-p` overrides `AWS_PROFILE`; `-r` overrides `AWS_REGION`. Instances need the SSM agent running and an IAM role with `AmazonSSMManagedInstanceCore`. Requires the `aws` CLI plus the Session Manager plugin.

### `ssm [-p profile] [-r region] [instance-id]`

Open an SSM Session Manager shell on an EC2 instance. Uses IAM auth (no SSH key, no public IP, no open port 22 required).

```bash
ssm                                              # fzf-pick → session
ssm i-0abc123def456789a                          # explicit instance
ssm -p myprofile -r us-west-2                    # fzf-pick in a specific profile/region
AWS_PROFILE=myprofile ssm                        # env var instead of flag
```

### `ssmpf [-p profile] [-r region] [instance-id] <local-port> [remote-port]`

Forward `localhost:<local-port>` to a port *on the SSM instance itself*. Use this when something is listening on the EC2 (e.g. a process bound to `127.0.0.1:8080` on the instance). If `<remote-port>` is omitted, it defaults to `<local-port>`.

```bash
ssmpf 80                                        # fzf-pick → localhost:80 → instance:80
ssmpf 9000 3000                                 # fzf-pick → localhost:9000 → instance:3000
ssmpf i-0abc123def456789a 80                    # explicit
```

### `ssmpfh [-p profile] [-r region] [instance-id] <remote-host> <remote-port> [local-port]`

Forward through the SSM instance to a *different* host the instance can reach (private RDS, internal ALB, etc.). The EC2 acts as a jump box but no SSH is required. If `<local-port>` is omitted, it defaults to `<remote-port>`.

```bash
# fzf-pick a bastion instance, then localhost:5432 → RDS endpoint:5432
ssmpfh mydb.cluster-xyz.us-east-1.rds.amazonaws.com 5432
# then: psql -h localhost -p 5432 ...

# explicit instance
ssmpfh i-0abc123def456789a mydb.cluster-xyz.us-east-1.rds.amazonaws.com 5432
```

### `ssmrun [-p profile] [-r region] [instance-id] '<command>'`

Run a shell command on an EC2 instance via SSM Run Command and print its stdout. Waits for completion before returning. Useful when you want a one-off command output without opening an interactive session.

```bash
ssmrun 'systemctl status nginx'                  # fzf-pick → run
ssmrun i-0abc123def456789a 'df -h'               # explicit
```

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

## 1Password

### `opl`

Login to 1Password CLI.

```bash
opl
```

---

## Sudo

Temporary passwordless sudo for agent/automation workflows. Grants `NOPASSWD: ALL` to the current user via a drop-in in `/etc/sudoers.d/`, with a systemd transient timer that auto-removes the grant and wipes the sudo timestamp cache when it fires. Linux + systemd only.

### `sudo-grant [duration]`

Grant temp NOPASSWD sudo with auto-expire. Duration defaults to `10m`; accepts `30s`, `10m`, `1h`, `2d`, or a bare integer (treated as minutes). Calling again replaces the pending revoke with a fresh timer. The grant itself requires entering your password once (it edits sudoers).

```bash
sudo-grant            # 10 minutes
sudo-grant 30         # 30 minutes
sudo-grant 1h         # 1 hour
```

### `sudo-revoke`

Revoke temp NOPASSWD sudo immediately. Removes the drop-in, cancels the pending timer, and wipes `/run/sudo/ts/$USER` so the timestamp cache can't keep sudo passwordless after the grant is gone.

```bash
sudo-revoke
```

---

## Tmux

### `tav [ai-cmd]`

Open a 3-pane tmux layout in the current window: AI tool in the top-left (70% tall, focused), bash in the bottom-left (30% tall), and `nvim` (LazyVim) on the right (full height, 70% wide). Must be run from inside tmux.

The top-left command defaults to `$AI_TOOL` (set in `.commonrc`, default `cld`). Pass a full command — including flags — to override.

```bash
tav                  # uses $AI_TOOL (default: cld)
tav "claude -c"      # resume most recent Claude session
tav "opencode"       # different AI tool
```

---

### `tavk [ai-cmd]`

Same as [`tav`](#tav-ai-cmd) but with a 4th pane: bottom-right (30% tall, 70% wide) runs `k9s`. Takes the same optional command argument.

```bash
tavk                 # 4-pane variant with k9s in the bottom-right
tavk "claude -c"     # 4-pane variant resuming Claude
```

---

### `ts` \*

Unified tmux session picker with fzf preview. One picker, three actions via keybinds:

- **`ENTER`** — switch to the highlighted session (switches client inside tmux, attaches otherwise)
- **`Ctrl-X`** — kill selected sessions (use `TAB` to multi-select). If your current attached session is among them, the client is auto-switched to a surviving session first so you're never detached. If the current session is the *only* one left, it's skipped with a warning.
- **`Ctrl-R`** — rename the highlighted session (prompts for the new name)

```bash
ts    # picker — pick an action with ENTER / Ctrl-X / Ctrl-R
```

---

### `tw` \*

Switch to any tmux window across **all** sessions with fzf and a live preview of the highlighted window's active pane. Useful after `wtaa` restores 10+ windows and you want to jump straight to one without first picking a session.

```bash
tw    # fzf picker over every window in every session
```

---

## Worktrunk

Functions for git worktree management with fzf interactive selection and tmux integration. (For the bare `wt switch` picker, use the `ws` alias.)

### `wrf` \*

Interactive multi-select worktree remover using fzf. Each row shows `clean`/`dirty` (modified, staged, or untracked files) so you don't nuke in-progress work by accident. Tab to multi-select, Enter to remove.

```bash
wrf              # fzf multi-select, removes selected worktrees and their branches
```

---

### `wta [branch]` \*

Open a single worktree in tmux with the `tav` layout. fzf picker if no branch is passed. Creates the project's tmux session if it doesn't exist (named after the worktrees' parent dir), then adds a window named after the sanitized branch and sends `tav "$cmd"`. If the window already exists, just attaches. Claude-aware resume: launches `$AI_TOOL_RESUME` when prior history exists at `~/.claude/projects/<slug>/*.jsonl`, otherwise `$AI_TOOL`.

Requires `$AI_TOOL` / `$AI_TOOL_RESUME` — run `dot ai-tool` first.

```bash
wta              # fzf picker
wta feature/auth # attach to (or create) feature/auth's window
```

---

### `wtaa`

Same per-worktree logic as [`wta`](#wta-branch--), but loops every worktree in the project (main first). Use to restore the full project as a single tmux session after a reboot.

```bash
wtaa             # one session, one window per worktree
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
- `wta` / `wtaa` create tmux sessions — use `tl` to list and `tka` to kill all
