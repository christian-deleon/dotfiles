# Lint, Molecule, and execution environments

`ansible-lint` is authoritative — if it fails, the playbook is wrong. Molecule is how roles get tested in isolation. `ansible-builder` + `ansible-navigator` is how prod runs execute against a pinned, immutable execution environment. Skipping any of these is fine for throwaways; for anything that goes into CI, all three are non-negotiable.

## `ansible-lint`

Configure via `.ansible-lint` at repo root or a `[tool.ansible-lint]` section in `pyproject.toml`. Production projects should target the `production` profile.

```yaml
# .ansible-lint
---
profile: production
strict: true
use_default_rules: true

# What lint should look at
kinds:
  - playbook: "**/playbooks/*.yml"
  - tasks: "**/tasks/*.yml"
  - vars: "**/vars/*.yml"
  - meta: "**/meta/main.yml"
  - requirements: "requirements.yml"

exclude_paths:
  - .cache/
  - .github/
  - collections/

# Rare per-rule overrides (justify each)
skip_list: []          # don't put rules here without a recorded reason
warn_list: []
enable_list:
  - no-log-password    # explicit re-enable in case profile changes default
  - fqcn

# var name policy
var_naming_pattern: "^[a-z_][a-z0-9_]*$"
```

### Profiles

Lint profiles are cumulative (each adds rules to the previous):

| Profile | Adds | Use for |
|---|---|---|
| `min` | Syntax-only baseline | Quick smoke checks |
| `basic` | Naming, deprecations, truthy YAML | Day-1 of a new repo |
| `moderate` | Idempotency basics, `name` requirements | Most internal projects |
| `safety` | Risky patterns (avoid `command`, no_log on secrets) | Anything that touches prod |
| `shared` | Public-style rules (formatting, docs) | Roles you publish to Galaxy |
| `production` | `fqcn`, `use-loop`, all upstream rules | What CI should enforce |

Start at `moderate`, ratchet up to `production`. Adding rules incrementally beats a "fix 200 lint errors in one PR" rewrite.

### Common findings and the fix

| Rule | What it catches | Fix |
|---|---|---|
| `fqcn[action-core]` | Bare `copy:` etc. | `ansible.builtin.copy:` |
| `fqcn[action]` | Bare `docker_container:` etc. | `community.docker.docker_container:` |
| `name[missing]` | Unnamed play/task | Add `name:` in imperative voice |
| `name[casing]` | Lowercase first word | Capitalize first word ("Install nginx") |
| `yaml[truthy]` | `yes`/`no`/`True`/`False` | `true`/`false` lowercase |
| `no-changed-when` | `command:`/`shell:` without `changed_when` | Add `changed_when: false` (read-only) or a real condition |
| `risky-shell-pipe` | Pipe in `shell:` with no pipefail | Add `args.executable: /bin/bash` + `set -o pipefail;` |
| `command-instead-of-module` | `command: dnf install ...` etc. | Use the proper module |
| `command-instead-of-shell` | `shell:` when `command:` would do | Switch to `command:` |
| `risky-file-permissions` | `file:`/`copy:`/`template:` with no `mode:` | Always set `mode: "0644"` (or whatever) |
| `no-log-password` | A `password:`/`token:` field without `no_log: true` | Add `no_log: true` |
| `partial-become` | `become_user:` without `become: true` | Pair them |
| `use-loop` | `with_items` etc. | Switch to `loop:` |
| `var-naming` | CamelCase or dashed var | snake_case |
| `key-order` | YAML keys in surprising order | Reorder; `name` first, then module, then args |
| `jinja[spacing]` | `{{foo}}` | `{{ foo }}` |
| `package-latest` | `state: latest` | `state: present` (latest is non-deterministic) |
| `risky-octal` | `mode: 644` (number) | `mode: "0644"` (string) |
| `meta-no-info` | Missing `galaxy_info` in role | Add it |
| `args[module]` | Wrong arg types per module schema | Fix the args |

### Justifying skips

Don't blanket-`skip_list:`. If a rule legitimately doesn't apply to a single task, skip it inline with a comment:

```yaml
- name: Read /etc/os-release via raw command (no Python on target yet)
  ansible.builtin.raw: cat /etc/os-release
  changed_when: false
  # noqa: command-instead-of-module - target is pre-Python bootstrap
```

For a whole file, prefer adjusting the playbook to be lint-clean. If you really need to suppress a rule across the project, document **why** at the top of `.ansible-lint`.

### Running lint

```bash
ansible-lint                      # full project
ansible-lint roles/myrole         # one role
ansible-lint playbooks/site.yml   # one playbook
ansible-lint --offline            # skip network checks (galaxy)
ansible-lint --write              # auto-fix where possible (review the diff)
ansible-lint --profile production # one-off profile override
ansible-lint --list-rules         # show every rule
ansible-lint --list-tags          # show category tags
```

The `--write` (autofix) feature handles a chunk of mechanical findings (FQCN, truthy, key-order, `mode:` octal strings). Review the diff before committing.

## Molecule

Per-role test harness. One scenario per role minimum (`default`), plus extras for distro/strategy variations.

### Layout

```
roles/<role>/molecule/default/
├── molecule.yml          # scenario config
├── converge.yml          # playbook that applies the role
├── verify.yml            # OR use pytest-testinfra in tests/
└── prepare.yml           # optional pre-converge setup
```

### `molecule.yml`

```yaml
---
dependency:
  name: galaxy
  options:
    requirements-file: requirements.yml

driver:
  name: podman                # default is `delegated`; podman is the modern container choice
  options:
    managed: true

platforms:
  - name: rocky-9
    image: docker.io/rockylinux/rockylinux:9
    pre_build_image: true
    privileged: true
    command: /usr/sbin/init
    systemd: always
    capabilities:
      - SYS_ADMIN
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
  - name: ubuntu-2404
    image: docker.io/library/ubuntu:24.04
    pre_build_image: true
    command: /lib/systemd/systemd
    systemd: always
    privileged: true
    capabilities:
      - SYS_ADMIN

provisioner:
  name: ansible
  config_options:
    defaults:
      stdout_callback: yaml
      callbacks_enabled: profile_tasks
  inventory:
    group_vars:
      all:
        my_role_enable_extra_thing: true

verifier:
  name: ansible             # or `testinfra` for pytest-testinfra
```

### Lifecycle commands

```bash
molecule test               # full sequence: dep → cleanup → destroy → syntax → create → prepare → converge → idempotence → side_effect → verify → cleanup → destroy
molecule converge           # apply the role (idempotent re-run friendly)
molecule verify             # run just the verifier
molecule login              # SSH/exec into a converged instance
molecule destroy            # tear down
molecule --debug test       # show every command, useful for CI failures
```

The `idempotence` step is what catches the most bugs: it runs `converge.yml` twice and fails if the second run reports any `changed` tasks. This is the test that proves your role is honestly idempotent.

### Verifier — `testinfra` vs `ansible`

- `verifier: ansible` + a `verify.yml` playbook — easy, no extra deps, less expressive.
- `verifier: testinfra` (via `pytest-testinfra`) — Python assertions about the host (`host.service('nginx').is_running`, `host.file('/etc/nginx.conf').contains('worker_processes')`). Stronger, recommended for real testing.

```python
# molecule/default/tests/test_default.py
def test_nginx_running(host):
    s = host.service("nginx")
    assert s.is_enabled
    assert s.is_running

def test_listening(host):
    s = host.socket("tcp://0.0.0.0:80")
    assert s.is_listening
```

### Removed: `molecule lint`

`molecule lint` was removed in Molecule 6.x and has not returned. Run `ansible-lint` separately (in CI: as a step, not as part of `molecule test`).

### `pytest-ansible`

For driving Molecule scenarios from `pytest` — useful when you want one test runner across the repo:

```bash
pip install pytest-ansible
pytest tests/                # discovers molecule scenarios automatically
```

## Execution environments (`ansible-builder` + `ansible-navigator`)

For prod, you want the playbook to run inside a pinned, immutable container image — same versions, every time. `ansible-builder` builds the image; `ansible-navigator` runs your playbook inside it.

### `execution-environment.yml`

```yaml
# execution-environment.yml
---
version: 3

images:
  base_image:
    name: quay.io/ansible/awx-ee:latest

dependencies:
  ansible_core:
    package_pip: ansible-core==2.20.6
  ansible_runner:
    package_pip: ansible-runner
  python:
    - boto3
    - botocore
    - kubernetes
    - hvac                       # for community.hashi_vault
  system:
    - openssh-clients [platform:rpm]
    - git-core [platform:rpm]
  galaxy: requirements.yml

additional_build_steps:
  append_final:
    - RUN useradd -m -s /bin/bash runner
    - USER runner
```

Build it:

```bash
ansible-builder build \
  --tag ee-myproject:1.0.0 \
  --file execution-environment.yml \
  --container-runtime podman
```

### `ansible-navigator`

```yaml
# ansible-navigator.yml
---
ansible-navigator:
  execution-environment:
    image: ee-myproject:1.0.0
    container-engine: podman
    enabled: true
    pull:
      policy: missing
  logging:
    level: info
  mode: stdout
  playbook-artifact:
    enable: true
    save-as: ./logs/{playbook_name}-artifact-{time_stamp}.json
```

Run:

```bash
ansible-navigator run playbooks/site.yml -i inventories/prod
```

The navigator drops you into a TUI by default (`mode: interactive`); `mode: stdout` makes it behave like `ansible-playbook`. CI should use `stdout`.

## Pre-commit hooks

`pre-commit` makes lint enforcement automatic locally:

```yaml
# .pre-commit-config.yaml
---
repos:
  - repo: https://github.com/ansible/ansible-lint
    rev: v25.0.0
    hooks:
      - id: ansible-lint
        files: ^(playbooks|roles|inventories)/.*\.ya?ml$
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.35.0
    hooks:
      - id: yamllint
        args: [-c=.yamllint]
```

`ansible-lint` runs yamllint internally, so a separate yamllint hook is optional. Adding it explicitly gives you faster YAML-only feedback on non-Ansible files.

## CI shape

A minimum CI pipeline for an Ansible repo:

1. Install `ansible-core` and collections (`ansible-galaxy collection install -r requirements.yml --force`).
2. `ansible-lint --profile production`.
3. `ansible-playbook --syntax-check` on every playbook.
4. `molecule test` for each role with a scenario.
5. Optional: build the EE with `ansible-builder` and publish on tag.

Don't conflate steps 2 and 4 — Molecule's testing doesn't replace lint; they catch different things.
