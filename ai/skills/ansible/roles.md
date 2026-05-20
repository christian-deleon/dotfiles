# Roles — layout, variables, handlers, argument specs

A role is the unit of reuse. The discipline is rigid because the payoff is reuse: a well-shaped role can be dropped into any inventory and configured entirely through `defaults/`. Common failure modes: dumping inputs into `vars/`, naming variables without a role prefix, using `assert:` instead of `argument_specs`, doing `import_role` when you really wanted `include_role` (or vice versa).

## Canonical layout

```
roles/<role_name>/
├── defaults/
│   └── main.yml             # all role inputs (overridable). Document every var.
├── vars/
│   └── main.yml             # internal constants. High precedence, hard to override.
├── tasks/
│   ├── main.yml             # entrypoint — typically a list of import_tasks
│   ├── install.yml
│   ├── configure.yml
│   └── service.yml
├── handlers/
│   └── main.yml
├── templates/               # j2 templates; rendered with role + host vars
├── files/                   # static files; copied verbatim
├── meta/
│   ├── main.yml             # galaxy_info, dependencies
│   └── argument_specs.yml   # role input validation (canonical since 2.11)
├── molecule/
│   └── default/             # converge + verify scenario
└── README.md
```

Naming rules:

- Role directory: `snake_case`. Dashes break collection imports.
- Public role variables: prefixed with the role name. `k3s_disable_ipv6`, not `disable_ipv6`. Prevents collisions when roles run in the same play.
- Internal-only variables (computed mid-role, not for caller override): `__role_internal_state`. Double underscore is the convention.
- Boolean variables: `<role>_enabled`, `<role>_install`, `<role>_<feature>` — not `<feature>_enable`.

## `defaults/main.yml` vs `vars/main.yml`

| | `defaults/main.yml` | `vars/main.yml` |
|---|---|---|
| Precedence | Lowest (22 of 22) | High (7 of 22) |
| Purpose | Caller-overridable inputs | Role-internal constants |
| Documentation | Every variable gets a comment | Usually not |
| What goes in | `nginx_listen_port: 80`, `nginx_user: nginx` | `__nginx_pkg_name: "{{ 'nginx' if ansible_facts.os_family == 'RedHat' else 'nginx-light' }}"` |
| What does NOT go in | Secrets, host-specific values | Anything callers might want to override |

If a value should ever be overridable from the playbook, inventory, or `extra-vars`, it belongs in `defaults/`. If a value should NOT be overridable (because it's a fact about the role's implementation), it belongs in `vars/`.

Document `defaults/`:

```yaml
# defaults/main.yml
---
# Whether to enable IPv6 in the kernel module.
# Set to `false` if you're on an IPv4-only host.
k3s_disable_ipv6: false

# Extra args appended to the k3s server command line.
# Use a YAML list, not a single string.
k3s_server_extra_args: []
```

## `meta/argument_specs.yml` — validated role inputs

This is the canonical way to validate role inputs since ansible-core 2.11. Don't use runtime `assert:` for the same job.

```yaml
# meta/argument_specs.yml
---
argument_specs:
  main:
    short_description: Install and configure k3s.
    description:
      - Installs the k3s binary, manages the systemd unit, and bootstraps
        the cluster on the first server node.
    options:
      k3s_role:
        type: str
        required: true
        choices: [server, agent]
        description: Whether this host runs the control plane or as an agent.
      k3s_version:
        type: str
        default: v1.32.0+k3s1
        description: The k3s release tag to install.
      k3s_disable_ipv6:
        type: bool
        default: false
      k3s_server_extra_args:
        type: list
        elements: str
        default: []
      k3s_token:
        type: str
        required: true
        no_log: true
        description: Cluster join token. Pass via Vault or external secret store.

  uninstall:
    short_description: Remove k3s from this host (alternate entrypoint).
    options: {}
```

What you get:

- Validation runs automatically at role entry, tagged `always` (never accidentally skipped).
- Type coercion (`type: bool` rejects `"yes"`, expects `true`/`false`).
- Multiple entry points — each `argument_specs:` key maps to a corresponding `tasks/<name>.yml`.
- The schema doubles as documentation; `ansible-doc -t role <fqcn>` reads it.

Use this *instead of* `assert:` blocks at task time, and instead of relying on lint to catch missing inputs.

## `tasks/main.yml` shape

Keep `main.yml` short — an index of `import_tasks` for clarity:

```yaml
# tasks/main.yml
---
- name: Install
  ansible.builtin.import_tasks: install.yml
  tags: [install]

- name: Configure
  ansible.builtin.import_tasks: configure.yml
  tags: [configure]

- name: Service
  ansible.builtin.import_tasks: service.yml
  tags: [service]
```

`import_tasks` is **static** — it's expanded at parse time, so tags on the imported file work, and loops/conditionals on the import itself don't (they apply to every imported task).

`include_tasks` is **dynamic** — it's expanded at runtime, so loops and conditionals work, but tags on the included file don't filter the import itself.

The same split applies to roles:

| Use | When |
|---|---|
| `roles:` keyword on a play | Static, runs in `pre_tasks` → `roles` → `tasks` → `post_tasks` order |
| `ansible.builtin.import_role:` (in `tasks:`) | Static, expanded at parse time — allows tags |
| `ansible.builtin.include_role:` (in `tasks:`) | Dynamic — allows `loop`, `when` per iteration |

Never use both `roles:` and `tasks:` in the same play. Pick `roles:` for clean stage ordering, or move everything into `tasks:` with `import_role`/`include_role`.

## Handlers

A handler is a task that runs only when notified, once per play, after all tasks finish (or at `meta: flush_handlers`).

```yaml
# handlers/main.yml
---
- name: Restart k3s
  ansible.builtin.systemd_service:
    name: k3s
    state: restarted

- name: Reload sysctl
  ansible.builtin.command: sysctl --system
  changed_when: false
```

Notify from a task by name:

```yaml
- name: Drop k3s sysctl tunables
  ansible.builtin.copy:
    src: 99-k3s-sysctl.conf
    dest: /etc/sysctl.d/99-k3s.conf
    mode: "0644"
  notify: Reload sysctl
```

`listen:` lets multiple handlers fire on the same event:

```yaml
- name: Restart k3s
  ansible.builtin.systemd_service:
    name: k3s
    state: restarted
  listen: k3s changed

- name: Drain workloads
  ansible.builtin.command: /usr/local/bin/k3s kubectl drain ...
  changed_when: false
  listen: k3s changed
```

Force handlers to run early with `meta: flush_handlers` when ordering matters (e.g. restart before next task depends on the restart).

## `meta/main.yml`

Galaxy metadata + role dependencies:

```yaml
# meta/main.yml
---
galaxy_info:
  role_name: k3s
  namespace: example_co
  author: Example Co Platform Team
  description: Install and manage k3s.
  license: Apache-2.0
  min_ansible_version: "2.20"
  platforms:
    - name: EL
      versions: ["9", "10"]
    - name: Ubuntu
      versions: [noble, oracular]
  galaxy_tags:
    - kubernetes
    - k3s

dependencies:
  - role: example_co.containerd
    vars:
      containerd_version: "1.7.20"
```

Notes:

- `dependencies:` runs each listed role once before this role's tasks. Use sparingly — explicit `include_role` from a playbook is usually clearer.
- `allow_duplicates: true` only if you have a real reason; most of the time you don't want this.
- For collection-shipped roles, the role name must match the directory exactly.

## Templates and files

- `templates/foo.conf.j2` — j2 template. Access role and host vars by name. Always `mode:` the destination explicitly.
- `files/<thing>` — static, copied verbatim. Use `copy:` not `template:` if there's nothing to interpolate.

When a template renders something sensitive (TLS keys, passwords), set `no_log: true` on the task that writes it.

## `import_role` vs `include_role` — when to use which

```yaml
# Static: one role, every host, every time. Tags work.
- ansible.builtin.import_role:
    name: monitoring
  tags: [monitor]

# Dynamic: parameterize per iteration.
- ansible.builtin.include_role:
    name: app_deploy
  vars:
    app_name: "{{ item.name }}"
    app_version: "{{ item.version }}"
  loop: "{{ apps }}"
  loop_control:
    label: "{{ item.name }}"
```

Prefer `import_role` for the common case. `include_role` only when you genuinely need per-iteration vars or a runtime conditional.

## Role tests with Molecule

A `default` scenario is the minimum bar (see [lint.md](lint.md) for full setup):

```
roles/k3s/molecule/default/
├── molecule.yml
├── converge.yml
└── verify.yml
```

- `converge.yml` is a playbook that just applies the role.
- `verify.yml` is a playbook that checks the converged state (or use `pytest-testinfra` for the verifier).
- `molecule test` runs the full lifecycle (dependency → lint → cleanup → destroy → syntax → create → prepare → converge → idempotence → side_effect → verify → cleanup → destroy).
- Don't expect `molecule lint` — it was removed in 6.x. Run `ansible-lint` separately.

## README — the missing piece

Every role gets a `README.md` with:

1. **One-paragraph what / why**.
2. **Requirements** — supported OSes, ansible-core version, collections needed.
3. **Role variables** — pulled from `argument_specs.yml` if possible; otherwise list every default with a sentence each.
4. **Dependencies** — from `meta/main.yml`.
5. **Example playbook** — minimal one-host invocation.
6. **License** — match what's in `meta/main.yml`.

The README is what other people read first. If `argument_specs.yml` is complete, you can have `ansible-doc -t role <fqcn>` generate the variable section for you.

## Role-naming reminders

- Snake case directory: `roles/my_role/`.
- Variables prefixed with role name: `my_role_<thing>`.
- Internal vars start with `__`: `__my_role_state`.
- One role per concern. If a role grows two purposes, split it.
