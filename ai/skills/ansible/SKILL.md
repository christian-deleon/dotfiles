---
name: ansible
description: Modern Ansible playbook, role, and inventory authoring. Activate when working in a directory containing ansible.cfg, playbooks/, roles/, inventories/, requirements.yml, or when editing YAML that is clearly Ansible (plays, tasks, handlers, role vars). Enforces current syntax (FQCN, loop, true/false), prefers modules over command/shell, and follows the standard role layout.
compatibility: opencode
---

# Ansible Authoring

Ansible has accumulated a lot of legacy syntax that still parses but is deprecated. Never emit dated forms — produce code that passes `ansible-lint` on the `production` profile.

## Project layout

```
ansible/
├── ansible.cfg
├── requirements.yml         # collections (and roles, if any)
├── inventories/<env>/       # one dir per environment
├── playbooks/*.yml
└── roles/<role_name>/
    ├── defaults/main.yml    # all role inputs (overridable), documented
    ├── vars/main.yml        # internal constants only — never role inputs
    ├── tasks/main.yml
    ├── handlers/main.yml
    ├── templates/
    └── files/
```

Role names are `snake_case`; dashes break collection imports. Public role variables are prefixed with the role name (`k3s_disable_ipv6`); internal-only variables use double-underscore (`__k3s_state`).

## Always use FQCN

Always write the fully qualified module name. Bare short names (`copy:`, `service:`) are the single biggest tell of dated Ansible code.

```yaml
# WRONG
- copy: { src: x, dest: /etc/x }

# RIGHT
- name: Install x config
  ansible.builtin.copy:
    src: x
    dest: /etc/x
    mode: "0644"
```

Common namespaces: `ansible.builtin.*`, `ansible.posix.*`, `community.general.*`, `community.docker.*`, `kubernetes.core.*`, `amazon.aws.*`. Add new collections to `requirements.yml` — never `pip install` or ad-hoc-install them.

## Modern syntax

| Don't | Do |
|---|---|
| `with_items`, `with_dict`, `with_fileglob`, etc. | `loop:` (combine with `lookup()` if needed) |
| `yes` / `no` | `true` / `false` |
| `when: somevar` (bare) | `when: somevar \| bool` |
| `become_user: x` alone | always pair with `become: true` |
| `module: key=value key=value` | YAML mapping form |
| `roles:` AND `tasks:` in the same play | pick one; or use `ansible.builtin.import_role` inside `tasks:` |

Every play, task, and block gets a `name:` in imperative voice ("Ensure firewalld is running"). No unnamed tasks.

## Use modules, not shell

If a module exists for the operation, use it. `command` and `shell` are last resorts. When unavoidable:

- Set `changed_when:` explicitly (and `failed_when:` if needed). A bare `command:` always reports changed and breaks idempotency.
- Prefer `command` over `shell` unless you actually need shell features (pipes, globs, redirects).
- Read files with `ansible.builtin.slurp`, not `command: cat`. Inspect services with `ansible.builtin.service_facts`, not `systemctl`.

```yaml
- name: Reload sysctl
  ansible.builtin.command: sysctl -p /etc/sysctl.d/99-x.conf
  changed_when: false
```

## Variables: defaults vs vars

- `defaults/main.yml` — anything a caller might override. Lowest precedence, easiest to override. Document each variable with a comment.
- `vars/main.yml` — internal constants the role itself uses. High precedence, hard to override.

If a value is meant to be configurable, it belongs in `defaults/`. Sensitive values go in Ansible Vault or an external secret store, never in `vars/` or `defaults/`.

## Handlers

Use handlers for actions that should only run when something changed (restart, reload, reboot). Notify by name; handler runs once per play after all tasks.

```yaml
tasks:
  - name: Configure SELinux
    ansible.posix.selinux:
      state: enforcing
      policy: targeted
    notify: Reboot servers

handlers:
  - name: Reboot servers
    ansible.builtin.reboot:
      reboot_timeout: 600
```

## Idempotency and check mode

Every task must be safe to run twice with the same inputs. Don't write tasks that always report `changed`. Support `--check` where possible: gate destructive logic on registered `stat` results, use read-only modules (`slurp`, `stat`, `getent`, `service_facts`) for inspection, and never invoke `command:` just to read state.

## Lint

`ansible-lint` is authoritative. If the repo has a config (`.ansible-lint` or `[tool.ansible-lint]` in `pyproject.toml`), follow it. If not, default to the `production` profile. Run lint after non-trivial edits and fix or justify every finding — don't blanket-skip rules.
