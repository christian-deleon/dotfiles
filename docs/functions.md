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

### `gcbare <repo-url>`

Clone a git repository as bare repo for worktree workflows. Configures remote fetch and updates refs.

```bash
gcbare git@github.com:user/repo.git
# Creates repo.git/ directory
```

### `gaw <branch-name> [base-branch] [-g|--group <group>]`

Create a git worktree from bare repo. Creates new branch and worktree directory. Default base branch is main.

```bash
gaw feature-123           # Create from main
gaw bugfix-456 develop    # Create from develop
gaw agent-042 -g myagent  # Create in group directory
```

### `grw`

Remove current git worktree and its branch. Requires confirmation via gum. Must be run from within a worktree. Checks for uncommitted changes and unpushed commits before deletion.

```bash
grw
```

### `gsync`

Sync bare repo: fetch latest, prune dead remote tracking branches, delete orphaned local branches that have no worktree.

```bash
gsync
```

### `gsyncall`

Sync all bare repos in the current directory.

```bash
gsyncall
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

## Notes

- Functions marked with \* use fzf for interactive selection
- Most Kubernetes functions respect the current namespace context
- Many functions provide both interactive (fzf) and direct argument modes
- Worktree functions expect bare repo naming: `repo.git`
