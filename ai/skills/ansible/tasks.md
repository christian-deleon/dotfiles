# Tasks — module choice, control flow, idempotency

A task is one module invocation against the play's targeted hosts. Tasks aren't shell scripts; they're declarative converge steps. The discipline here — pick the right module, set `changed_when` honestly, control flow with `block`/`when`/`loop`, and respect `--check` — is what separates a playbook that works once from one that's safe to run on Tuesday at 3am.

## Picking the right module

Reach for `command`/`shell` only when nothing else will do. The reflexes:

| Task | Module | Notes |
|---|---|---|
| Install packages | `ansible.builtin.dnf` / `apt` / `pacman` / `homebrew` / `package` | `package` for cross-platform, but per-distro is more capable |
| Manage services | `ansible.builtin.systemd_service` | `systemd` is now an alias for `systemd_service` |
| Enumerate services without changing | `ansible.builtin.service_facts` | Sets `ansible_facts.services` |
| File contents | `ansible.builtin.copy` / `template` / `lineinfile` / `blockinfile` | `template` for j2; `lineinfile` only for single lines |
| File state | `ansible.builtin.file` | Mode, owner, group, type (file/dir/link/absent) |
| Read file from a host | `ansible.builtin.slurp` | Returns base64 — pipe through `\| b64decode` |
| Test path existence/attrs | `ansible.builtin.stat` | Then check `.stat.exists`, `.stat.isdir`, etc. |
| User / group | `ansible.builtin.user` / `group` | `password_lock`, `shell`, `groups`, `append: true` |
| Cron entries | `ansible.builtin.cron` | Don't shell out to `crontab` |
| Mounts | `ansible.posix.mount` | Idempotent fstab + mount in one step |
| Firewall (firewalld) | `ansible.posix.firewalld` | `state=enabled` + `permanent=true` + `immediate=true` |
| SELinux | `ansible.posix.selinux` / `seboolean` / `sefcontext` | Reboot via handler if mode change |
| Sysctl | `ansible.posix.sysctl` | Use it instead of editing `/etc/sysctl.d/*.conf` directly + reloading |
| Lookup name resolution | `ansible.builtin.getent` | `database: passwd` / `group` / `services` |
| HTTP | `ansible.builtin.uri` | `body_format: json`, `status_code: [200, 201]`, `return_content: true` |
| Get a URL into a file | `ansible.builtin.get_url` | Set `checksum:` whenever possible |
| Git checkout | `ansible.builtin.git` | `version:` pin; `force: true` only if you really mean it |
| Archive / unarchive | `ansible.builtin.unarchive` / `archive` | Idempotent via `creates:` |
| Docker / Podman | `community.docker.*` / `containers.podman.*` | Whole API surface — never `command: docker ...` |
| Kubernetes | `kubernetes.core.k8s` (apply YAML), `k8s_info`, `helm`, `helm_repository` | Server-side apply via `apply: true` |
| AWS / Azure / GCP | `amazon.aws.*` / `azure.azcollection.*` / `google.cloud.*` | Cloud-state — never the raw CLI |

When in doubt, run `ansible-doc -t module <name>` (or `ansible-doc -l` to list). Modules added in newer ansible-core versions (e.g. `systemd_service`) get cited in the porting guides.

## Escaping to `command` / `shell`

When you genuinely have to:

```yaml
- name: Reload sysctl
  ansible.builtin.command: sysctl -p /etc/sysctl.d/99-net.conf
  changed_when: false      # read-only-ish: always report unchanged
```

```yaml
- name: Rebuild the index if data changed
  ansible.builtin.command: /opt/app/bin/reindex
  register: reindex
  changed_when: "'rebuilt' in reindex.stdout"
  failed_when:
    - reindex.rc != 0
    - "'already up to date' not in reindex.stderr"
```

Rules:

- Set `changed_when:` explicitly. A bare `command:` always reports `changed`, which breaks change-detection and handler firing.
- Use `command`, not `shell`, unless you need shell features (pipes, globs, redirects, `&&`).
- When you do need `shell:`, force bash and pipefail:

```yaml
- name: Count failed units (pipefail required)
  ansible.builtin.shell: |
    set -o pipefail
    systemctl --failed --no-legend | wc -l
  args:
    executable: /bin/bash
  register: failed_units
  changed_when: false
```

- Skip `command` entirely for state-reading. `cat` → `slurp`. `systemctl status` → `service_facts`. `ls /path` → `stat`. `id user` → `getent`. `grep ... /etc/passwd` → `getent` or `user`.
- Use `creates:` / `removes:` to make a one-shot `command:` idempotent:

```yaml
- name: Bootstrap the cluster (only once)
  ansible.builtin.command: /opt/cluster/bin/init
  args:
    creates: /var/lib/cluster/initialized
```

## Conditionals (`when`)

`when` must evaluate to a real boolean. Non-boolean conditionals became hard errors in ansible-core 2.19.

```yaml
- name: Configure firewalld
  ansible.posix.firewalld:
    service: https
    state: enabled
    permanent: true
    immediate: true
  when: firewall_enabled | bool
```

| Pattern | Why |
|---|---|
| `when: enabled \| bool` | Coerces string/yes-no to bool |
| `when: result.rc == 0` | Comparison → boolean |
| `when: hostvar is defined` | Defined-ness tests are booleans |
| `when: foo is not none` | Explicit None check |
| `when: ansible_facts.os_family == 'RedHat'` | Use `ansible_facts.*` not bare `ansible_*` |
| AVOID: `when: somevar` (non-boolean) | Errors in 2.19+ |
| AVOID: `when: enabled == "true"` (stringly) | Always pipe through `\| bool` instead |

Multiple conditions: pass a YAML list — Ansible ANDs them:

```yaml
when:
  - install_thing | bool
  - ansible_facts.os_family == 'RedHat'
```

## Loops

`loop:` only. `with_*` still parses but fails `production` lint (`use-loop` rule).

```yaml
- name: Create app users
  ansible.builtin.user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    append: true
  loop: "{{ app_users }}"
  loop_control:
    label: "{{ item.name }}"        # cleaner stdout per iteration
```

Common conversions:

| Old `with_*` | Modern `loop` |
|---|---|
| `with_items: x` | `loop: x` |
| `with_dict: d` | `loop: "{{ d \| dict2items }}"` (each `item` has `.key` / `.value`) |
| `with_fileglob: 'foo/*'` | `loop: "{{ lookup('fileglob', 'foo/*') }}"` |
| `with_nested: [a, b]` | `loop: "{{ a \| product(b) \| list }}"` |
| `with_subelements: [list, sublist]` | `loop: "{{ list \| subelements('sublist') }}"` |
| `with_together: [a, b]` | `loop: "{{ a \| zip(b) \| list }}"` |
| `with_sequence: start=1 end=3` | `loop: "{{ range(1, 4) \| list }}"` |
| `with_first_found: [...]` | `vars: { found: "{{ lookup('first_found', ...) }}" }` then use `found` |

`loop_control` is your friend:

| Key | Use |
|---|---|
| `label:` | Override the per-iteration log label |
| `index_var:` | Capture the 0-based index |
| `loop_var:` | Rename `item` (required when nested loops) |
| `pause:` | Seconds between iterations |

`until` is the retry pattern, not a loop:

```yaml
- name: Wait for service to come up
  ansible.builtin.uri:
    url: http://{{ inventory_hostname }}/health
    status_code: 200
  register: health
  retries: 30
  delay: 2
  until: health.status == 200
```

## Blocks, rescue, always

`block` groups tasks for shared properties (`when`, `become`, `tags`, `no_log`) and gives you exception handling.

```yaml
- name: Manage the legacy app
  block:
    - name: Stop the service
      ansible.builtin.systemd_service:
        name: legacy
        state: stopped

    - name: Migrate data
      ansible.builtin.command: /opt/legacy/migrate.sh
      register: migrate
      changed_when: "'no changes' not in migrate.stdout"
  rescue:
    - name: Capture migration log on failure
      ansible.builtin.fetch:
        src: /var/log/legacy/migrate.log
        dest: ./logs/{{ inventory_hostname }}/
        flat: false
    - name: Re-raise
      ansible.builtin.fail:
        msg: "Migration failed on {{ inventory_hostname }}"
  always:
    - name: Start the service back up
      ansible.builtin.systemd_service:
        name: legacy
        state: started
  become: true
  tags: [legacy, migrate]
```

`rescue` runs on failure; `always` runs regardless. Use this instead of `ignore_errors: true`.

## `register`, `failed_when`, `changed_when`

- `register: foo` captures the task result into `foo` for downstream tasks.
- `changed_when:` redefines when a task counts as changed (handler notification, lint scoring).
- `failed_when:` redefines when a task counts as failed.

```yaml
- name: Check cluster health
  ansible.builtin.command: /opt/cluster/bin/healthcheck
  register: health
  changed_when: false
  failed_when:
    - health.rc != 0
    - "'WARN' not in health.stdout"
```

Don't `register` something you never use. Don't `ignore_errors: true` and then ignore the registered result either — that's the same anti-pattern in two lines.

## Idempotency and check mode

Every task must be safe to run twice:

- Use modules that natively check current state (`copy`, `file`, `user`, `dnf`, `systemd_service`).
- For `command:`, gate on `creates:` / `removes:` or registered `stat` results.
- For read-only `command:`, set `changed_when: false`.
- For tasks that *must* run side effects during `--check`, set `check_mode: false` and comment why.

Test it:

```bash
ansible-playbook site.yml          # converge
ansible-playbook site.yml          # second run: PLAY RECAP should show changed=0
ansible-playbook site.yml --check  # dry run: no changes anywhere
```

## Async tasks

For long-running operations you don't want to block on:

```yaml
- name: Kick off the import
  ansible.builtin.command: /opt/app/bin/import-large.sh
  async: 3600          # max seconds
  poll: 0              # fire and forget
  register: import_job

- name: Continue with other work
  ansible.builtin.debug: { msg: "import running in background" }

- name: Wait for the import
  ansible.builtin.async_status:
    jid: "{{ import_job.ansible_job_id }}"
  register: import_result
  until: import_result is finished      # use the test, not `import_result.finished`
  retries: 60
  delay: 60
```

Two gotchas:

- `async_status` `.started` / `.finished` **cannot be used as integers-acting-as-booleans** since 2.19. Use the `started` / `finished` test plugins (`is started`, `is finished`).
- `async` requires Python on the target node and won't work with `become_method: su`.

## `delegate_to`, `run_once`, `connection: local`

- `delegate_to: localhost` — run *this* task on the controller, with the current host's vars. Useful for cloud API calls per host.
- `delegate_to: somehost` — run this task on a specific other host (e.g. load balancer).
- `run_once: true` — execute once across the play's host batch (pairs well with `delegate_to`).
- `connection: local` (play-level) — the whole play runs on the controller. Different from `hosts: localhost`, which is a real host.

```yaml
- name: Remove host from LB before upgrade
  community.general.haproxy:
    state: disabled
    host: "{{ inventory_hostname }}"
  delegate_to: lb-01.example.com
```

## Tags

Tags are filters, not features. Use them sparingly:

- Use tags for "rerun just this part" workflows (`--tags`/`--skip-tags`).
- The reserved tag `always` runs unless explicitly skipped.
- The reserved tag `never` runs only when explicitly requested.
- Argument-spec validation tasks are auto-tagged `always`.

```yaml
- name: Reload TLS certificates
  ansible.builtin.command: /opt/app/bin/reload-tls
  changed_when: false
  tags:
    - tls
    - never        # only fires with -t tls
```

## What never belongs in a task

- `print()`-style debugging that ships to prod. `debug:` is for development; use `verbosity:` to silence in normal runs:
  ```yaml
  - ansible.builtin.debug: { var: result, verbosity: 2 }
  ```
- Comments inside the YAML explaining what the module does. The `name:` is the comment.
- `become: false` to "fix" a permissions issue you don't understand. Investigate.
- `ignore_errors: true`. Use `failed_when:` or `block`/`rescue:`.
- Hardcoded secrets. See [vault.md](vault.md).
