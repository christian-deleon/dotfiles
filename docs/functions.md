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

### `kpaw`

Watch all pods in all namespaces (excluding system namespaces).

```bash
kpaw
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

Get logs from a pod. Uses fzf to select pod. If pod has multiple containers, prompts for container selection. Follows logs (-f).

```bash
kl               # Current namespace, select pod interactively
kl production    # Specific namespace, select pod interactively
```

**Examples:**

```bash
# View logs from a pod in current namespace
$ kl
# Opens fzf to select pod -> shows logs with tail -f

# View logs from a pod in production namespace
$ kl production
# Opens fzf filtered to production -> select pod -> if multiple containers, select container -> logs
```

### `ke [namespace]` \*

Execute command in a pod (opens /bin/sh). Uses fzf to select pod and container if needed.

```bash
ke               # Current namespace, select pod interactively
ke production    # Specific namespace, select pod interactively
```

**Examples:**

```bash
# Exec into a pod in current namespace
$ ke
# Opens fzf -> select pod -> opens shell in pod

# Exec into a pod in staging namespace
$ ke staging
# Opens fzf filtered to staging -> select nginx pod -> select nginx container -> /bin/sh session
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

**Examples:**

```bash
# Scale a deployment interactively
$ ks
# Opens fzf -> select "api-server" -> prompts "Number of replicas: " -> enter "3"
# Result: api-server scaled to 3 replicas

# Scale deployment to 5 replicas (current namespace)
$ ks 5
# Opens fzf -> select "web-frontend" -> scales to 5 replicas immediately

# Scale deployment in specific namespace
$ ks production 10
# Opens fzf filtered to production -> select "worker" -> scales to 10 replicas
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

**Examples:**

```bash
# Create .gitignore for a Python project
$ gi python
# Creates .gitignore with: python, vim, macos, visualstudiocode patterns

# Create .gitignore for a Node + TypeScript project
$ gi node,typescript
# Creates .gitignore with: node, typescript, vim, macos, visualstudiocode patterns

# If .gitignore exists, prompts for confirmation
$ gi go
# Output: "A .gitignore file already exists in the current directory"
#         "Do you want to overwrite it? (y/n): "
```

### `gcbare <repo-url>`

Clone a git repository as bare repo for worktree workflows. Configures remote fetch and updates refs. This is the recommended approach for AI agent workflows.

```bash
gcbare git@github.com:user/repo.git
# Creates repo.git/ directory
```

**Examples:**

```bash
# Clone a repository as bare for worktree workflow
$ gcbare git@github.com:myorg/api-server.git
# Cloning into bare repository 'api-server.git'...
# Bare repo ready at: /Users/you/api-server.git
# Create worktrees with: gaw <branch-name> [base-branch]

# Now cd'd into api-server.git, ready to create worktrees
$ gaw feature-auth
# Creates ../api-server-feature-auth/ worktree
```

### `gaw <branch-name> [base-branch]`

Create a git worktree from bare or normal repo. Creates new branch and worktree directory. Default base branch is main. Auto-detects if running from bare repo.

```bash
gaw feature-123           # Create from main
gaw bugfix-456 develop    # Create from develop
```

**Examples:**

```bash
# From inside api-server.git bare repo
$ gaw feature-user-auth
# Creating worktree: ../api-server-feature-user-auth @ feature-user-auth (from main)
# Switched to a new branch 'feature-user-auth'
# Now in: /Users/you/api-server-feature-user-auth

# Create worktree from develop branch
$ cd api-server.git
$ gaw hotfix-login develop
# Creating worktree: ../api-server-hotfix-login @ hotfix-login (from develop)
# Creates branch from develop, cd's into new worktree
```

### `grw`

Remove current git worktree and its branch. Requires confirmation via gum. Must be run from within a worktree. Automatically returns to bare repo directory.

```bash
grw
```

**Examples:**

```bash
# From inside api-server-feature-auth/ worktree
$ pwd
/Users/you/api-server-feature-auth

$ grw
# Really delete worktree + branch 'feature-auth' ? (y/N)
# Press y
# ✓ Worktree and branch removed
# Now in: /Users/you/api-server.git

# If you cancel
$ grw
# Really delete worktree + branch 'feature-old' ? (y/N)
# Press n
# Cancelled.
```

### `gfb`

Quick fetch and prune. Works with both bare and normal repos.

```bash
gfb
```

### `gawf <branch-name> [base-branch]`

Fetch and create worktree in one command. Combines gfb and gaw. Ensures you have latest refs before creating worktree.

```bash
gawf feature-789
```

**Examples:**

```bash
# Fetch latest and create worktree in one command
$ cd api-server.git
$ gawf feature-dashboard
# Bare repo updated ✓
# Creating worktree: ../api-server-feature-dashboard @ feature-dashboard (from main)
# Switched to a new branch 'feature-dashboard'

# Useful when team has pushed new commits to base branch
$ gawf hotfix-security main
# Fetches latest main, then creates worktree with up-to-date base
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

## Nix

### `nixp <packages...>`

Enter a nix-shell with the given packages.

```bash
nixp python3 nodejs
```

---

## kubectl-ai

### `kai [args...]`

Run kubectl-ai in interactive mode with grok-3 model.

```bash
kai "find pods using high memory"
```

### `kaiq [args...]`

Run kubectl-ai in quiet mode (non-interactive) with grok-3 model.

```bash
kaiq "scale deployment nginx to 5 replicas"
```

---

## Notes

- Functions marked with \* use fzf for interactive selection
- Most Kubernetes functions respect the current namespace context
- Many functions provide both interactive (fzf) and direct argument modes
- Worktree functions expect specific directory naming: `repo-branch`
