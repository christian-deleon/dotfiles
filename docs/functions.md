# Shell Functions Reference

This document provides a reference for all custom shell functions available in this dotfiles repository.

## General

### `chromium-agent [args...]`

Open the dedicated agent Chromium (`~/.config/chromium-agent`). Full browser — install 1Password and other extensions here; Playwright MCP uses the same profile. Daily Chromium can stay open. Close this window before an agent drives the browser (profile lock). Also in Walker as **Chromium Agent**.

```bash
chromium-agent
chromium-agent https://start.1password.com
```

### `dot [args...]`

Runs the `dot` script, then after `dot update` re-sources `~/.aliases`, `~/.functions` and `completions.d/` in the current shell, so commands the update added work right away. It keeps `dot`'s exit status. Environment, prompt and history settings in `.commonrc` still need a new shell, and commands the update removed stay defined until then.

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

### `pk` \*

Pick processes from `ps` with fzf and kill them. Sorted by PID; type to fuzzy-match any column (user, %cpu, command, …). `TAB` to multi-select. `ENTER` sends `SIGTERM`; `Ctrl-K` sends `SIGKILL` for unresponsive processes.

```bash
pk       # picker — ENTER for TERM, Ctrl-K for KILL
```

### `hdf` \*

Delete entries from your shell history with fzf. Lists `history` (most recent first); type to fuzzy-match, `TAB` to multi-select, `ENTER` to forget the selected lines. Deletes highest-offset-first so removals don't renumber pending ones, then persists with `history -w`. bash only (uses `history -d`). For *searching* history, use fzf's `Ctrl-R`.

```bash
hdf      # picker — TAB to mark lines, ENTER to delete them
```

---

### `histdedup` \*

Collapse duplicate commands in your saved history, keeping the most recent copy of each (with its timestamp; trailing space is ignored) and drop lines that match `HISTIGNORE` (so existing ignored entries get purged, not just future ones). New shells already load a cleaned file automatically — `~/.commonrc` rewrites `~/.bash_history` at the end of rc, immediately before ble.sh/bash loads it — so this is only needed to clean a shell that was *already* open. A new shell skips the pass when the file has not changed since the last one (a stamp under `$XDG_STATE_HOME/dotfiles/hist-dedup/`); `histdedup` always runs it. The rewrite is abandoned if another shell appended to the file meanwhile, so a sibling's new lines are never lost. Live typing is also de-duped against the whole in-memory list (`HISTCONTROL=erasedups` plus ble.sh `history_erasedups_limit=` so re-running an older command moves it to the end instead of adding a second copy). It cleans the shared file for future shells **and** refreshes the current shell's recall, de-duping only the in-memory list so other terminals' commands are never imported (per-terminal recall is preserved). bash only; zsh handles this natively via `HIST_SAVE_NO_DUPS`.

```bash
histdedup
```

---

### `pkgup`

Full OS package update and cleanup for the current host. Detects the package manager inline (no dependency on `scripts/lib.sh`). On Omarchy this is `omarchy update`, not a raw `pacman`/`yay -Syu` — Omarchy's alpm hook aborts direct system upgrades.

| Host | What runs |
|------|-----------|
| Omarchy | `omarchy update` (pass `-y` for unattended) |
| macOS | `brew update && brew upgrade && brew cleanup && brew doctor` |
| Arch + `yay` (not Omarchy) | `yay -Syu --noconfirm` then `yay -Yc --noconfirm` |
| Arch + pacman only | `sudo pacman -Syu --noconfirm` |
| Debian/Ubuntu | `apt-get update && upgrade && autoremove && autoclean` |

Not part of `dot update` — that command only refreshes this repo (pull, submodules, profile, AI configs). Use both when you want a full maintenance pass: `dot update && pkgup`.

```bash
pkgup      # omarchy update on Omarchy; brew/yay/apt elsewhere
pkgup -y   # omarchy update -y (ignored on other hosts)
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

### `k9 [-c context] [-n namespace]` \*

Launch k9s against a context. Without `-c`, uses fzf to select a context. Without `-n`, uses fzf to select a namespace against the chosen context (ESC to skip / all namespaces). Runs `k9s --context <name> [-n <namespace>]`.

```bash
k9                          # Pick context, then namespace
k9 -c prod-cluster          # Direct context, pick namespace (ESC for all)
k9 -c prod-cluster -n kube-system  # Direct context and namespace
```

Tab completion: see [Tab completion](#tab-completion).

### `kcd` \*

Delete one or more kubectl contexts and their now-orphaned cluster/user entries. Opens fzf in multi-select mode (TAB to mark, ENTER to confirm), then prompts before deleting. After removing the selected contexts, it deletes each associated cluster and user **only if no remaining context still references it** (shared entries are kept). Requires `jq`.

```bash
kcd              # Mark contexts with TAB, confirm, delete contexts + orphans
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

Needs `yq` (Python yq or mikefarah's Go yq) and `jq`. Selection runs `skaffold <verb> -f <path> [-p <profile>]`, so it works from anywhere within the project. Configs imported by another via `requires:` still appear in the picker — target them when you want to iterate on a single module standalone.

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

### `eksc [-p profile] [-r region] [-a alias] [cluster-name]` \*

Update your kubeconfig for an EKS cluster (`aws eks update-kubeconfig`). If no cluster name is given, fzf-picks from `aws eks list-clusters`. The config is merged into your default `~/.kube/config`; `--alias` sets the context name (switch to it later with `kc`). If `-a` isn't passed, you're prompted for an alias defaulting to the cluster name. `-p` overrides `AWS_PROFILE` (only sent when passed); `-r` overrides `AWS_REGION`.

```bash
eksc                                             # fzf-pick → prompt alias → merge
eksc -a prod                                     # fzf-pick, context alias "prod"
eksc -p myprofile -r us-west-2 my-cluster        # explicit cluster + profile/region
kc prod                                          # switch to it afterwards
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

### `tav [-t|--tool <ai-cmd>] [-f|--prompt-file <path>] [prompt...]`

Open a 3-pane tmux layout in the current window: AI tool in the top-left (70% tall, focused), bash in the bottom-left (30% tall), and `nvim` (LazyVim) on the right (full height, 70% wide). The Neovim pane opens on the project dir and drops straight into the LazyGit view (same as `<leader>gg` / the `nvg` alias); quitting LazyGit leaves you in the project explorer. Must be run from inside tmux. `tav` is a wrapper over [`wto layout`](#wto-command), which refuses to lay out a pane an agent is running in (it would end that agent).

The AI pane is **respawned** with a non-interactive launcher (the harness shortcuts `cl`, `cca`, `gr`, `gra`, `oc`, `oca` expanded from `wto`'s own table, since the launcher runs outside an interactive shell; pending DA/OSC replies drained). Grok is started under `bin/tty-filter-da`, which drops Device Attributes / cursor-position replies (`0;2600;1c`, `84;0;0c`) before they reach the TUI — those keystrokes dismiss Grok’s welcome card permanently (not a session resume) and `C-u` can only clear the leftover prompt text. Neovim (and k9s in `tavk`) start ~2.5s later. For Grok only, a prompt scrub polls briefly and `C-u`s any DA body that slips through (in another harness, `C-u` would wipe text you typed). When the AI tool exits, that pane drops into a normal interactive `$SHELL`. The AI pane is tagged with tmux pane options for [`wto`](#wto-command): `@ai_tool` (`claude`, `grok`, `opencode`), `@ai_wt` (the worktree root), and `@ai_state` / `@ai_state_at` (`starting`, then whatever the hooks in `ai/hooks/session_state.sh` report; `exited` once the AI tool returns). Claude Code sessions get `--name <project>/<branch or folder>` so other sessions can address them, and the model and effort that [`wtc`](#agent-sessions) saved for the worktree. The current dir is pre-trusted for Grok and Claude Code (same grants `wta`/`wtc` write), so neither stops on a trust prompt.

Bare positional arguments are the **initial prompt** — the AI tool launches straight into it (joined into a single argument, so quoting is optional; OpenCode gets it as `--prompt=`, since its positional argument is a directory). `-f`/`--prompt-file` reads the prompt from a file and leaves the file alone. The prompt reaches the agent through a private temp file that the launcher reads once and deletes, so any size and any quoting arrive intact. The tool defaults to `$AI_TOOL` (set from the profile's `ai.default` or via `dot ai-tool`; `tav` errors when it is unset); use `-t`/`--tool` to override it for one call. The override accepts a full command including flags (e.g. `-t "gra -c"`). Use `--` before a prompt that begins with a dash.

```bash
tav                            # just the layout, uses $AI_TOOL
tav "add a contact me page"    # launch $AI_TOOL with that prompt
tav -t "gra -c" "fix the bug"  # resume Grok, with a prompt
tav -t oc "make it blue"       # override the AI tool for this call
tav -f /tmp/handoff.md         # initial prompt from a file
```

---

### `tavk [-t|--tool <ai-cmd>] [-f|--prompt-file <path>] [prompt...]`

Same as [`tav`](#tav--t--tool-ai-cmd--f--prompt-file-path-prompt) but with a 4th pane: bottom-right (30% tall, 70% wide) runs `k9s`. Takes the same `-t`/`--tool` / `-f`/`--prompt-file` flags and prompt arguments.

```bash
tavk                            # 4-pane variant with k9s in the bottom-right
tavk "fix the k8s deploy"       # 4-pane variant with an initial prompt
tavk -t "gra -c" "..."          # 4-pane variant resuming Grok
tavk -f /tmp/handoff.md         # 4-pane variant with a file-based prompt
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

### `tp` \*

Pick a project under `~/Projects` with fzf and land in a tmux session named after it, in that project's folder. Use it instead of `tmux` in a fresh terminal: it starts the server if none is running, attaches to the project's session if one is already open, and switches the client when run inside tmux. Same picker as `prefix` + `C`.

```bash
tp    # pick a project, then you're in its session
```

---

### `tw` \*

Switch to any tmux window across **all** sessions with fzf and a live preview of the highlighted window's active pane. Useful after `wto open --all` restores 10+ windows and you want to jump straight to one without first picking a session.

```bash
tw    # fzf picker over every window in every session
```

---

## Agent sessions

One agent session per git worktree, each in its own tmux window with the `tav` layout. Worktrees live beside a bare repository (`<project>/.git`, set up by [`gcb`](#gcb-repo-url)); every new session gets its own folder with a generated two-word name (`brisk-otter`), and the window shows the branch checked out there. `wtc`, `wta`, `wtx`, `tav` and `tavk` are thin wrappers over [`wto`](#wto-command).

### `wtc [-p|--prompt <text>] [-n|--no-switch] [-j|--job <job>] [-m|--model <model>] [-e|--effort <level>] [branch [base]]`

Start a session. `wto new` fetches `origin` (20-second limit; set `WTO_NO_FETCH=1` to skip), fast-forwards the local default branch to `origin`'s (a local branch that has diverged from `origin` is left alone with a warning, and the session starts from `origin`'s), makes a new codename folder, links the project's agent files there (`dot agent link`), and opens its window. **By default it then jumps to that window.**

- **No branch:** the folder starts on a detached HEAD at the latest default branch. Talk to the agent; once the work is clear it names the branch in place (`git switch -c fix/142-retry-backoff`) before its first commit, and the window label follows. The folder name never changes.
- **A branch:** a new one is created from `base` (default: the latest default branch) without upstream tracking; an existing local branch is fast-forwarded to `origin` if it is strictly behind; a branch only on `origin` gets a tracking branch. A branch that is already checked out in a folder just opens that folder's window.

Pass `-p`/`--prompt` (or `-f`/`--prompt-file`) to start the agent on a prompt. Pass `-n`/`--no-switch` to stay on the current window; agents spawn this way so focus is not stolen. Run without `-n` from a plain shell at the project root that is the only window in its tmux session, `wtc` builds the session in that window instead of opening a second one. Other windows are built from outside (created detached, split, agent started), and per-directory trust prompts are pre-accepted (Grok: `--trust` and a grant for the folder; Claude Code: `hasTrustDialogAccepted` in `~/.claude.json`), so an unattended agent starts without anyone pressing **y**.

Pass `-j`/`--job` to use a job's model and effort from `ai/models.yaml` (`plan`, `implement`, `review`, `small`) for the harness in `$AI_TOOL`; `-m`/`--model` and `-e`/`--effort` override it. The choice is saved in the worktree's git directory (`ai-launch`), so every later launch there (`wta`, `tav`, a continued conversation) keeps it. OpenCode has no per-session flag and starts on its configured default. A job spawn refuses the default branch itself.

The project must be bare; a normal clone with its own checkout is refused (`wto ls` still works there). Requires `$AI_TOOL` / `$AI_TOOL_RESUME` — run `dot ai-tool` first.

```bash
wtc                                         # detached session on the latest default branch, jump to it
wtc feature/auth -p "add a contact page"    # new branch, start the agent on a prompt
wtc hotfix/login production                 # new branch off an explicit base
wtc -n -j implement -f /tmp/handoff.md fix/retry   # agent-style spawn, focus stays put
```

---

### `wta [-p|--prompt <text>] [branch|folder]` \*

Go back to a session: open its window, or switch to it if it is open. Takes a branch or a folder name; with none, the only worktree, or an fzf picker showing branch and folder. The target tmux session is the one you are in when your pane sits inside the project, else one named after the project. A reopened session continues its conversation: Grok is pinned with `-r <session-id>` (the last session with real messages, not an empty one), Claude Code resumes with `-c` when it has a transcript for that folder, OpenCode starts fresh. `wta`, `wtc`, `tav` and `tavk` launch every harness without permission prompts (`cca`, `gra`, `oca`); the plain `cl`, `gr`, `oc` aliases still prompt when you type them. `wta` is a wrapper over `wto open --switch`.

```bash
wta                          # picker (or the only worktree)
wta feature/auth             # by branch
wta brisk-otter -p "rebase onto main and rerun the tests"   # by folder, with a prompt
```

---

### `wtaa`

Open a window for every worktree in the project, continuing each conversation the same way `wta` does, and switch to the first. Worktrees that already have a window are left alone. A worktree whose folder is gone is skipped too: tmux would otherwise open that window in the home directory. `git worktree prune` drops it. Use `wtaa` to restore a project after a reboot. `wtaa` is a wrapper over `wto open --all --switch`.

---

### `wtx [-y] [--park|--discard|--merged] [branch|folder...]` \*

Close sessions. In a session folder inside tmux, with no names, it runs `wto close --here` (with any flags). Otherwise it passes its arguments to `wto close`: names close those worktrees, and none opens the fzf picker. See [`wto close`](#wto-command).

```bash
wtx                 # close this session: its work is merged, in another branch, or pushed
wtx --park          # push this branch to origin, then close; wtc <branch> brings it back
wtx --discard       # close and drop commits that exist nowhere else (asks first)
```

---

### `wto <command>`

An executable in `bin/` (linked to `~/.local/bin/wto` by the installer and `dot update`), so agents and scripts can call it from shells that never load `functions.d/`. Run it anywhere inside the project, including the project root. It reads `$AI_TOOL` / `$AI_TOOL_RESUME`, or `~/.localrc` when they are unset. Needs git 2.38 or newer. A `<name>` below is a branch or a worktree folder name.

| Command | Does |
|---|---|
| `wto ls [--json] [--files]` | Roster of every worktree: branch and folder, git state against the default branch (ahead, behind, dirty, whether a rebase would conflict, `integrated` including squash merges), its agent session (harness, state and how long, tmux window), and the model and effort saved for it. `fresh` is true for a session that has not committed yet. Warns about a detached folder holding commits on no branch. `--files` names the files a rebase would conflict on. |
| `wto default [--refresh]` | Print the default branch. `--refresh` fetches `origin` first and fast-forwards the local default branch to it (left alone, with a warning, when a folder has it checked out). |
| `wto new …` | What `wtc` runs; stays put unless `--switch`. |
| `wto open [-p text \| -f file] [--switch] [<name>]` | What `wta` runs. |
| `wto open --all [--switch]` | Open a window for every worktree, continuing each conversation; skips ones that have a window, and a worktree whose folder is gone (tmux would start that window in the home directory). `git worktree prune` drops a gone folder. Used to restore a project after a reboot. |
| `wto layout [--k9s] [-t tool] [-p text \| -f file \| prompt...]` | What [`tav`](#tav--t--tool-ai-cmd--f--prompt-file-path-prompt) and `tavk` run: lay out the calling pane. Refuses a pane an agent runs in. |
| `wto close [-y] [--merged\|--park\|--discard] [<name>...]` | Close finished sessions: kills their tmux windows, removes the worktree with git, deletes the branch (printing the old tip), and hands its claims on. With no name, an fzf picker (Tab marks several; refused worktrees are dimmed with the reason). Each target gets a report first (`ok` with where the work lives, or the reasons), then one confirmation for a picked or multiple set (`-y` skips it). Closes only when the commits also live somewhere else: the local or `origin` default branch, another local branch, or any branch on `origin` (including the branch's own pushed copy); a squash merge into the default branch, another local branch, or its `origin` copy counts. `--merged` accepts only the default branch (what the orchestrator uses). `--park` pushes the branch to `origin` with an upstream first (never the default branch; a failed push closes nothing). `--discard` closes even when the commits exist nowhere else, after listing them, and always asks, even with `-y`. Every mode refuses uncommitted changes (untracked files count; the first ones are named), an operation in progress, a locked worktree, and the orchestrator's; without `--discard` it also refuses a detached folder with commits on no branch. Run from another window. |
| `wto close --here [--merged\|--park\|--discard]` | Close the session this shell is in. The checks, the `--park` push and the `--discard` confirmation run in the foreground and refuse with their reasons; then focus moves to another window and a detached tmux job removes the worktree and branch and then the window, writes its result to `close-<folder>.log` in the project's state dir (`wto dir`) and shows it as a tmux message. The window is killed last, once the removal succeeded; if it was the session's only window, a shell window in the project folder opens first, so the tmux session stays alive. A failed removal leaves the window open. |
| `wto here` | Print the project's live orchestrator marker; exit 1 if none. |
| `wto here --orchestrator` | Record the calling pane as the orchestrator; exits 3 if another live pane holds it. |
| `wto here --clear [--force]` | Remove the marker. |
| `wto dir` | Print the project's state directory, `<git-common-dir>/orchestrate/` (never committed, shared by every worktree). |
| `wto profile [--path]` | Print the project profile `/onboard` wrote (`.agents/profile.md`, `profile.md` beside an overlay `AGENTS.md`, or `agent-files/projects/<project>/profile.md`); exit 1 if there is none. A profile still kept as a `## Project profile` section of `AGENTS.md` is printed too, with a note. `--path` prints where the file is. |
| `wto send <name\|--orchestrator\|--all> [--relay] [--force] [-f file \| message...]` | Deliver a message to another session (stdin works too), prefixed with the origin header. OpenCode sessions get it through the OpenCode server (queued behind a running turn); others get a bracketed paste plus Enter. Refuses, with nothing typed, a session blocked on a question (exit 6), exited (5), in unknown state (6, unless `--force`), or launched under 15 seconds ago (7); exit 4 means no session. |
| `wto header [--relay]` | Print `[session message · from <project>/<branch or folder> (<orchestrator\|session>) · agent notice]` (or `relaying the user's words`), for a message sent through a harness's own session messaging. |
| `wto claim define [<resource>...]` | Set the names claims may use (or print them); a misspelled name is then rejected. |
| `wto claim take <resource>... [--note text]` | Take every named resource at once, or join the queue (exit 2). A request queues behind any earlier waiter that wants one of the same resources, so a request for several cannot starve. |
| `wto claim free [<resource>...\|--all] [--force]` | Free claims and hand them to the next waiter whose whole request is now free; prints who was granted. `--all` also leaves the queue. Freeing another worktree's claim needs `--force` and is logged. |
| `wto claim check <resource>...` | Exit 0 only if this worktree holds all of them; reads without the lock, so a deploy entry point can gate on it. Also acknowledges a pending grant. |
| `wto claim wait [--timeout secs]` | Wait (default 60s) for this worktree's queued request; exit 2 if still waiting. |
| `wto claim status [--json]`, `wto claim gc` | Show holders and the queue; drop claims of removed worktrees and hand over. |
| `wto claim bump <name>` | Move that session's waiting requests to the front of the queue, then hand over. |

Claims belong to a worktree path, not a process or a branch name, so they survive a restart and a branch rename. All changes happen under a lock file (`flock`, or perl's `flock()` on macOS); a lock busy for 5 seconds exits 75. Waiters without a live agent session keep their place but are skipped. `claim take`, `free`, `check` and `wait` need a session folder, not the project root.

Windows are found by the `@ai_wt` tag on the window and its agent pane, not by name, since the name follows the branch. Sessions are found by the pane tags `tav` sets; a session opened before those tags existed shows state `unknown`. Close its window and run `wta` to reopen it tagged. Claude Code sessions are named `<project>/<branch or folder>` at launch (`--name`); the name does not change when the session later names its branch.

```bash
wto ls                  # who is working, idle, blocked on a question, or exited
wto ls --json | jq -r '.[] | select(.behind > 0) | .branch // .name'
wto send --all 'main moved: v1.4.0 is released; rebase when you reach a stopping point'
wto claim take deploy/api --note 'testing the login fix'   # then: wto claim free --all
```

---

## Dotfiles

### `dot help [query]` \*

Interactive fzf explorer for all shell functions and aliases defined in `.functions` and `.aliases`. Implemented as the `dot help` subcommand (`scripts/dot/help.sh`), not a standalone shell function. Shows type, name, category, and description in the list; the preview pane shows the full function body or alias expansion.

```bash
dot help          # Browse everything interactively
dot help kube     # Pre-filter to Kubernetes shortcuts
```

**Controls:**
- Type to fuzzy-search across name, category, and description
- `ENTER` — print the selected name to stdout
- `Ctrl-H` — toggle the preview pane

---

## Tab completion

Many of these commands tab-complete their arguments from a live source. Completions live in `completions.d/*.sh` (one topic fragment per file, mirroring `functions.d/`), written once in bash style and shared with zsh via `bashcompinit`.

| Command(s) | Completes |
|---|---|
| `cdr` | directories relative to the git repo root |
| `kc` | kubectl context names |
| `kn` `ktns` `kdp` `kdd` `kdelp` `ks` | namespaces (current context) |
| `kcs` | kubeconfig files in `~/.kube` |
| `kl` `ke` | namespace → pod → container (positional) |
| `k9` | `-c` contexts, `-n` namespaces (+ `all`, scoped to `-c`) |
| `eksc` `ssm` `ssmpf` `ssmpfh` `ssmrun` | `-p` AWS profiles, `-r` regions |
| `ta` `tk` | tmux session names |
| `frk` `fkr` `fks` | Flux Kustomization names |
| `frh` | Flux HelmRelease names |
| `wta` | worktree branch and folder names |
| `wto` | subcommands, then branch and folder names |
| `dot` | subcommands; `dot install <item>`; `dot profile use <name>` |

Notes:
- Remote sources are bounded (`--request-timeout=2s`) and fail silent — if the cluster is unreachable, completion just returns nothing and the function's fzf fallback still works.
- Slow AWS API lookups (SSM instance IDs, EKS cluster names) are intentionally **not** completed; use the function's fzf picker instead.
- Alias completions (`ta` `tk` `frk` `fkr` `fks` `frh`) are bash-only. On zsh the alias expands first, so the underlying tool's native completion (e.g. `_tmux`, `flux`) takes over.

---

## Notes

- Functions marked with \* use fzf for interactive selection
- Most Kubernetes functions respect the current namespace context
- Many functions provide both interactive (fzf) and direct argument modes
- `wtc` needs a bare repo clone (use `gcb` to set up)
- `wtc` / `wta` create tmux sessions — use `tl` to list and `tka` to kill all
