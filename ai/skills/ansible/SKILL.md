---
name: ansible
description: Ansible (ansible-core 2.20+) playbook, role, collection, and inventory authoring. Use when editing files under `playbooks/`, `roles/`, `inventories/`, `group_vars/`, `molecule/`, `ansible.cfg`, or for prompts about `ansible-playbook`, `ansible-vault`, `ansible-lint`, Molecule. Enforces FQCN, modern syntax, and the `ansible-lint` production profile.
compatibility: opencode
---

# Ansible

Ansible is a YAML-driven, push-model orchestrator that ships Python modules over SSH and runs them on target hosts. The unit of work is an **idempotent module call** that converges a piece of system state — not a shell command. A play is a declaration ("these hosts should look like this"), not a script. Read every task you write through that lens: *if I run this twice, does the second run report zero changes?* If no, the task is wrong.

The most common AI failure mode is writing pre-2.16 Ansible: `with_items` loops, bare module names (`copy:`, `service:`), `yes`/`no` booleans, non-boolean `when:` expressions (now an error in 2.19+), `command: cat`/`command: systemctl status`, missing `changed_when`, `ignore_errors: true` as a band-aid, `become_user` without `become`, role inputs in `vars/main.yml`, hardcoded secrets, `include:` (removed in 2.16), mixing `roles:` and `tasks:` in the same play. Don't do any of that. The defaults below are non-negotiable for new code.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Write or fix a task, pick a module, set `when`/`loop`/`block`, get idempotency right, use `async`, handle errors | [tasks.md](tasks.md) |
| Author or restructure a role — layout, defaults vs vars, handlers, `argument_specs`, dependencies | [roles.md](roles.md) |
| Organize inventory, scope variables across hosts/groups, resolve a precedence question, use constructed inventory | [inventory.md](inventory.md) |
| Add a collection, pick the right FQCN, manage `requirements.yml`, pin versions | [collections.md](collections.md) |
| Configure `ansible-lint`, justify a skip, set up Molecule, build an execution environment with `ansible-builder`, run `ansible-navigator` | [lint.md](lint.md) |
| Encrypt a secret, switch to an external secret store (HashiCorp Vault, 1Password, AWS Secrets Manager), scrub logs | [vault.md](vault.md) |

For one-off edits, the cheat sheets below are usually enough. Reach for reference files when the task warrants depth.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Engine | **`ansible-core` 2.20+** | Current stable; 2.19 also active. Controller Python **3.12–3.14**, managed-node Python **3.9–3.14** |
| Distribution | **`ansible-core` + `requirements.yml`** | The `ansible` umbrella package (12.x) is still maintained; new projects prefer explicit core + pinned collections |
| Lint | **`ansible-lint` `production` profile** | Authoritative; CI must pass it. Bundled yamllint enforces lowercase `true`/`false` |
| Test | **Molecule** with the `podman` driver (rootless) or `delegated` for CI | One scenario per role, `default` minimum. `molecule lint` was removed in 6.x — run `ansible-lint` separately |
| Verifier | **`pytest-testinfra`** for post-converge state checks | `pytest-ansible` to drive Molecule scenarios from pytest |
| Execution | **`ansible-navigator` + execution environments built with `ansible-builder`** for prod | Direct `ansible-playbook` fine for dev |
| Inventory | File-based YAML under `inventories/<env>/`, plus dynamic plugins per cloud, plus a **constructed** plugin layered last | One dir per environment; never one giant `hosts.ini` |
| Variables | `group_vars/` and `host_vars/` per inventory; role inputs in `defaults/`; internal constants in `vars/` | Sensitive values never in either — see vault below |
| Secrets | External store (HashiCorp Vault via `community.hashi_vault`, 1Password, AWS Secrets Manager) for runtime; `ansible-vault` for in-repo | See [vault.md](vault.md) |
| Collections | Pinned in `requirements.yml`, installed via `ansible-galaxy collection install -r requirements.yml` | Never `pip install` modules |
| Role inputs | **Validated by `meta/argument_specs.yml`** (separate file, canonical since 2.11) | Not `assert:` at runtime |
| Strategy | `linear` (default) for most plays; `host_pinned` when you want speed with per-host ordering | Avoid `free` unless you know why |
| Naming | Every play, task, block, and handler has an imperative `name:` | "Ensure firewalld is running" |
| Role names | `snake_case` | Dashes break collection imports |

## Standard project layout

```
ansible/
├── ansible.cfg
├── requirements.yml                 # collections (pinned versions)
├── inventories/
│   ├── prod/
│   │   ├── 01-source.aws_ec2.yml    # dynamic source (numeric prefix = inventory merge order)
│   │   ├── 99-constructed.yml       # constructed plugin, layered LAST
│   │   ├── group_vars/
│   │   │   ├── all.yml
│   │   │   └── webservers.yml
│   │   └── host_vars/
│   │       └── web01.yml
│   └── staging/...
├── playbooks/
│   ├── site.yml                    # entry point; imports topic playbooks
│   ├── webservers.yml
│   └── ...
├── roles/
│   └── <role_name>/
│       ├── defaults/main.yml       # all role inputs (overridable), documented
│       ├── vars/main.yml           # internal constants only — never role inputs
│       ├── tasks/main.yml
│       ├── handlers/main.yml
│       ├── templates/
│       ├── files/
│       ├── meta/
│       │   ├── main.yml            # galaxy_info, dependencies
│       │   └── argument_specs.yml  # validated at role entry
│       └── molecule/default/
├── collections/                    # `ansible.cfg: collections_path` if vendored
├── execution-environment.yml       # ansible-builder definition
└── .ansible-lint                   # or [tool.ansible-lint] in pyproject.toml
```

Role names are `snake_case`. Public role variables are prefixed with the role name (`k3s_disable_ipv6`); internal-only variables use double underscore (`__k3s_state`). Details in [roles.md](roles.md).

## Modern syntax cheat sheet

| Don't | Do |
|---|---|
| `copy:`, `service:`, `command:` (bare names) | `ansible.builtin.copy:`, etc. — always FQCN |
| `ansible.builtin.systemd:` | `ansible.builtin.systemd_service:` (the new canonical name; `systemd` is now an alias) |
| `with_items: [...]` | `loop: [...]` |
| `with_dict: somedict` | `loop: "{{ somedict \| dict2items }}"` |
| `with_fileglob: 'conf/*'` | `loop: "{{ lookup('fileglob', 'conf/*') }}"` |
| `with_nested: [a, b]` | `loop: "{{ a \| product(b) \| list }}"` |
| `yes` / `no` / `True` / `False` | `true` / `false` (lowercase) |
| `when: somevar` (non-boolean) | `when: somevar \| bool` — non-boolean conditionals now ERROR in 2.19+ |
| `when: result.rc == 0` is fine | use boolean expressions; never rely on truthy strings |
| `module: key=value key=value` (inline string) | YAML mapping form |
| `become_user: foo` alone | `become: true` + `become_user: foo` |
| `tasks:` AND `roles:` in the same play | pick one; or `ansible.builtin.import_role` inside `tasks:` |
| `include: foo.yml` | `ansible.builtin.import_tasks: foo.yml` (static) or `include_tasks` (dynamic) — `include:` removed in 2.16 |
| `command: cat /etc/foo` | `ansible.builtin.slurp:` |
| `command: systemctl is-active foo` | `ansible.builtin.service_facts:` then check `ansible_facts.services` |
| `command: ls /etc/foo.d` for existence | `ansible.builtin.stat:` + `register:` + `.stat.exists` |
| `command: ...` with no `changed_when` | always set `changed_when:` (often `false` for read-only) |
| `ignore_errors: true` | `failed_when:` with the real condition, or `block:`/`rescue:`/`always:` |
| `assert:` to validate role inputs at runtime | `meta/argument_specs.yml` (validated at role entry, tagged `always`) |
| Bare `ansible_distribution` (relying on `INJECT_FACTS_AS_VARS=True`) | `ansible_facts.distribution` — the inject flag flips off in 2.24 |
| `async_status` `.started` / `.finished` used as booleans | use the `started` / `finished` test plugins (`is started`, `is finished`) — int-as-bool removed in 2.19 |
| Role inputs in `vars/main.yml` | `defaults/main.yml` — `vars/` is for internal-only constants |
| Bare `register: result` you never use | drop the `register`, or actually use `result` |
| `shell: foo \| bar` with no `pipefail` | use modules; if you must, `shell:` with `args.executable: /bin/bash` and `set -o pipefail;` prefix |

## Universal rules

These apply across plays, roles, and ad-hoc usage:

1. **FQCN always.** `ansible.builtin.copy`, never `copy`. Bare names break collection isolation and fail `ansible-lint` `fqcn` checks. See [collections.md](collections.md) for the namespace map.
2. **Every play, task, block, and handler has a `name:`** in imperative voice ("Install nginx", "Reload sysctl"). No unnamed work — lint will fail and humans can't read the run log.
3. **Modules over `command`/`shell`.** If a module exists, use it. When escape-hatching to `command`/`shell`, set `changed_when:` (and `failed_when:` where needed) — and prefer `command` over `shell` unless you actually need shell features (pipes, globs, redirects).
4. **Idempotency is non-negotiable.** Second consecutive run must report zero `changed`. Test it. If a task always reports changed, it's wrong.
5. **`defaults/main.yml` is the only place for role inputs.** `vars/main.yml` is for internal constants the role itself uses. Sensitive values go in neither — Vault or external store. See [roles.md](roles.md) and [vault.md](vault.md).
6. **Validate role inputs with `meta/argument_specs.yml`**, not runtime `assert:`. Argument specs cover types, required-ness, choices, and multi-entrypoint roles in one file. See [roles.md](roles.md).
7. **Handlers for actions that respond to change** (restart, reload, reboot). Notify by handler name; the handler runs once per play after all tasks. Listen with `listen:` for fan-out.
8. **Never `pip install` collections.** Declare them in `requirements.yml` and install with `ansible-galaxy collection install -r requirements.yml`. See [collections.md](collections.md).
9. **One play per concern.** A play targets one set of hosts with one goal. Long plays split into roles or get broken up with `import_playbook`.
10. **`true` / `false`**, never `yes` / `no` / `True` / `False`. YAML 1.2 cleanliness; `ansible-lint`'s `yaml[truthy]` rule enforces lowercase.
11. **Conditionals must be boolean.** `when: enabled | bool`, not `when: enabled`. Non-boolean conditionals became hard errors in 2.19.
12. **Prefer `ansible_facts.<thing>`** over the bare `ansible_<thing>` shortcut — `INJECT_FACTS_AS_VARS` flips to `False` in 2.24, breaking the latter.
13. **Respect `--check`.** Use registered `stat` results, read-only modules (`slurp`, `stat`, `getent`, `service_facts`) for inspection, and never invoke `command:` just to read state. Tasks that *must* perform side effects during a dry run get `check_mode: false` with a comment explaining why.
14. **No secrets in `defaults/`, `vars/`, inventory, or playbook source.** Vault them inline (`ansible-vault encrypt_string`), vault the whole file, or fetch from an external store at run time. Tag any task that handles secrets with `no_log: true`. See [vault.md](vault.md).

## Don't / Do

| Don't | Do |
|---|---|
| `- copy: { src: x, dest: /etc/x }` (bare + inline) | `- name: …` + `ansible.builtin.copy:` (mapping) |
| `with_items: "{{ users }}"` | `loop: "{{ users }}"` |
| `when: enable_thing` (bare, non-boolean) | `when: enable_thing \| bool` |
| `when: somevar == "true"` (string compare) | `when: somevar \| bool` |
| `command: cat /etc/release` + `register: r` | `ansible.builtin.slurp: src=/etc/release` then `.content \| b64decode` |
| `command: systemctl restart foo` | `ansible.builtin.systemd_service: name=foo state=restarted` (or notify a handler) |
| `command: useradd alice` | `ansible.builtin.user: name=alice state=present` |
| `command: dnf install -y foo` | `ansible.builtin.dnf: name=foo state=present` |
| `command: ...` with no `changed_when` | `changed_when: false` (read-only) or a real condition |
| `ignore_errors: true` swallowing failures | `failed_when:` with the real condition, or `block:`/`rescue:`/`always:` |
| `become_user: foo` only | `become: true` + `become_user: foo` |
| Role inputs in `vars/main.yml` | `defaults/main.yml` |
| `assert: { that: required_thing is defined }` at task time | declare `required: true` in `meta/argument_specs.yml` |
| Hardcoded secrets in `defaults/` or playbook | external store lookup (e.g. `community.hashi_vault.vault_kv2_get`) or `ansible-vault encrypt_string` |
| `no_log: false` on a task that prints a token | `no_log: true` on anything touching secrets |
| `roles:` AND `tasks:` in same play | one or the other; or `import_role`/`include_role` inside `tasks:` |
| `include: tasks/foo.yml` | `ansible.builtin.import_tasks` (static) or `include_tasks` (dynamic) |
| `set_fact` to capture `command` stdout | use the right module; or `register:` directly |
| `register: out` then never reference `out` | drop the register, or actually use it |
| `shell: cmd1 \| cmd2` (no pipefail) | use modules; or `shell:` with `args.executable: /bin/bash` + `set -o pipefail;` prefix |
| `pip install ansible-collection-foo` | add to `requirements.yml`, `ansible-galaxy collection install -r requirements.yml` |
| `Ansible 2.9` syntax in new code | target `ansible-core` 2.20+ |
| `ansible-playbook --extra-vars '@secret.yml'` (plaintext) | `ansible-vault encrypt secret.yml`, commit encrypted |
| `gather_facts: true` everywhere | `gather_facts: false` when you don't need facts (faster runs) |
| `delegate_to: localhost` for everything | `connection: local` on the play, or a `hosts: localhost` play |
| `ansible_distribution` (bare) | `ansible_facts.distribution` |
| `transport: smart` in `ansible.cfg` | `transport: ssh` (smart was removed in 2.20) |
| `roles/foo-bar/` (dashes) | `roles/foo_bar/` (snake_case) |
| `strategy: free` "for speed" | `strategy: host_pinned` |
| Custom Python scripts to read state from hosts | `ansible.builtin.service_facts`, `setup`, `stat`, `slurp`, `getent` |
