# Shell Aliases Reference

This document provides a reference for all custom shell aliases available in this dotfiles repository.

## File System

### ls Variations

- `la` - List all files in long format with human-readable sizes (`ls -lAh`)
- `ll` - List all files including hidden in long format (`ls -lah`)

### Directory Navigation

- `up` - Go up one directory (`cd ..`)
- `up2` - Go up two directories (`cd ../..`)
- `up3` - Go up three directories (`cd ../../..`)
- `up4` - Go up four directories (`cd ../../../..`)

---

## General Commands

- `diff` - Enable colored diff output (`diff --color=auto`)
- `mkdir` - Create directories with verbose parent creation (`mkdir -pv`)
- `vi` - Use vim instead of vi

---

## Tailscale

- `ts` - Tailscale command shortcut
- `tss` - Show Tailscale status (`tailscale status`)
- `tsssh` - SSH via Tailscale (`tailscale ssh`)

---

## Kubernetes

Basic kubectl shortcuts and resource viewing. See [functions.md](functions.md) for interactive fzf-enabled functions.

### Core

- `k` - kubectl shortcut
- `kapi` - List API resources (`kubectl api-resources`)
- `kcg` - Get contexts (`kubectl config get-contexts`)

### Deployments

- `kd` - Get deployments (`kubectl get deployments`)
- `kda` - Get deployments in all namespaces

### Events

- `kev` - Get events sorted by timestamp (`kubectl get events --sort-by='.lastTimestamp'`)
- `keva` - Get events in all namespaces sorted by timestamp

### Namespaces

- `kns` - Get namespaces (`kubectl get namespaces`)
- `knsw` - Watch namespaces (`kubectl get namespaces --watch`)

### Pods

- `kp` - Get pods (`kubectl get pods`)
- `kpad` - Get pods in all namespaces with detailed output (`-o wide`)
- `kpaw` - Watch pods in all namespaces
- `kpd` - Get pods with detailed output (`-o wide`)
- `kpw` - Watch pods

### ReplicaSets

- `krs` - Get replicasets (`kubectl get replicasets`)
- `krsa` - Get replicasets in all namespaces

### Secrets

- `kse` - Get secrets (`kubectl get secrets`)
- `ksea` - Get secrets in all namespaces

### StatefulSets

- `kss` - Get statefulsets (`kubectl get statefulsets`)
- `kssa` - Get statefulsets in all namespaces

### Services

- `ksv` - Get services (`kubectl get services`)
- `ksva` - Get services in all namespaces

---

## Flux CD

GitOps toolkit shortcuts for managing Flux resources.

### Events & Monitoring

- `fe` - Get Flux events (`flux events`)
- `fea` - Get Flux events in all namespaces
- `fs` - Show Flux statistics (`flux stats`)
- `fkw` - Watch kustomizations in all namespaces (`watch -n 1 flux get kustomizations --all-namespaces`)

### Sources

- `fgs` - Get git sources (`flux get sources git`)

### Kustomizations

- `fkls` - List kustomizations in all namespaces (`flux get kustomizations --all-namespaces`)
- `fkr` - Resume kustomization (`flux resume kustomization`)
- `fks` - Suspend kustomization (`flux suspend kustomization`)

### Reconciliation

- `frg` - Reconcile flux-system git source (`flux reconcile source git flux-system`)
- `frh` - Reconcile helmrelease with source (`flux reconcile helmrelease --with-source`)
- `frk` - Reconcile kustomization with source (`flux reconcile kustomization --with-source`)
- `fro` - Reconcile flux-system OCI source (`flux reconcile source oci flux-system`)

---

## GitHub Copilot CLI

- `cs` - GitHub Copilot shell suggestions (`ghcs`)
- `ce` - GitHub Copilot explain command (`ghce`)

---

## Telepresence

- `tp` - Telepresence command shortcut

---

## Ansible

- `ap` - Ansible playbook shortcut (`ansible-playbook`)

---

## Terraform

- `tf` - Terraform command shortcut

---

## Docker

- `d` - Docker command shortcut
- `dc` - Docker Compose shortcut (`docker compose`)

---

## Poetry

Python dependency management shortcuts.

- `pl` - Poetry lock (`poetry lock`)
- `pu` - Poetry update (`poetry update`)
- `pv` - Poetry version (`poetry version`)
- `plu` - Poetry lock and update (`poetry lock && poetry update`)

---

## Skaffold

Kubernetes development workflow tool shortcuts.

- `sk` - Skaffold command shortcut
- `skd` - Skaffold dev mode (`skaffold dev`)
- `skdel` - Skaffold delete (`skaffold delete`)
- `skdp` - Skaffold dev with profile (`skaffold dev --profile`)
- `skr` - Skaffold run (`skaffold run`)
- `skrp` - Skaffold run with profile (`skaffold run --profile`)

---

## Network Tools

- `ncc` - Netcat connection test (`nc -zv`)

---

## Applications

- `ffm` - Open Firefox Profile Manager (`/Applications/Firefox.app/Contents/MacOS/firefox -ProfileManager`)
- `oc` - OpenCode shortcut

---

## Notes

- Many Kubernetes operations have interactive fzf-enabled functions available - see [functions.md](functions.md)
- Aliases prefixed with `k` are Kubernetes-related
- Aliases prefixed with `f` are Flux CD-related
- Most aliases support standard command arguments after the alias
