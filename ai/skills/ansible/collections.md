# Collections and `requirements.yml`

Almost every module you'd use lives in a collection. `ansible-core` ships only `ansible.builtin`; everything else (`community.general`, `ansible.posix`, `kubernetes.core`, `amazon.aws`, etc.) is declared in `requirements.yml` and installed by `ansible-galaxy`. Never `pip install` a collection — that's the single most common "where did my module go in CI" bug.

## `requirements.yml`

Pin versions. Always.

```yaml
# requirements.yml
---
collections:
  - name: ansible.posix
    version: ">=2.0.0,<3.0.0"
  - name: community.general
    version: ">=12.0.0,<13.0.0"
  - name: community.docker
    version: ">=4.6.0,<5.0.0"
  - name: kubernetes.core
    version: ">=6.0.0,<7.0.0"
  - name: amazon.aws
    version: ">=10.0.0,<11.0.0"
  - name: community.hashi_vault
    version: ">=7.0.0,<8.0.0"

# Roles (legacy; prefer collection-shipped roles)
roles: []
```

Install:

```bash
ansible-galaxy collection install -r requirements.yml --force
```

In CI, install to a project-local path:

```bash
ansible-galaxy collection install -r requirements.yml \
  --collections-path ./collections
```

And point `ansible.cfg` at it:

```ini
[defaults]
collections_path = ./collections
```

Vendoring collections is a fine choice for reproducibility. The `--force-with-deps` flag re-resolves dependencies, which you usually want when bumping a version.

## Picking the right FQCN

The matrix of "which collection owns which module" shifts over time. When in doubt, check `ansible-doc -l | grep <thing>` or the official docs. As of mid-2026:

| Concern | FQCN |
|---|---|
| File copy / template / line / file state | `ansible.builtin.copy`, `template`, `lineinfile`, `file` |
| Service management | `ansible.builtin.systemd_service` (alias: `systemd`), `service` |
| Package installs | `ansible.builtin.dnf`, `apt`, `pacman`, `homebrew`, `package` |
| User / group | `ansible.builtin.user`, `group` |
| Cron | `ansible.builtin.cron` |
| Sysctl | `ansible.posix.sysctl` |
| Mount | `ansible.posix.mount` |
| Firewalld | `ansible.posix.firewalld` |
| iptables / nftables | `ansible.posix.iptables`, `community.general.nftables` |
| SELinux | `ansible.posix.selinux`, `seboolean`, `sefcontext` |
| Reboot | `ansible.builtin.reboot` |
| Pip | `ansible.builtin.pip` |
| Pacman / Homebrew / Snap | `community.general.pacman`, `community.general.homebrew`, `community.general.snap` |
| Docker | `community.docker.docker_container`, `docker_image`, `docker_compose_v2` |
| Podman | `containers.podman.podman_container`, `podman_image` |
| Kubernetes apply | `kubernetes.core.k8s`, `k8s_info`, `k8s_scale` |
| Helm | `kubernetes.core.helm`, `helm_repository` |
| AWS EC2 | `amazon.aws.ec2_instance` |
| AWS S3 | `amazon.aws.s3_object`, `s3_bucket` |
| AWS Secrets Manager (lookup) | `amazon.aws.secretsmanager_secret` |
| AWS SSM Parameter Store (lookup) | `amazon.aws.ssm_parameter` |
| Azure RM | `azure.azcollection.azure_rm_<resource>` |
| GCP Compute | `google.cloud.gcp_compute_instance` |
| HashiCorp Vault | `community.hashi_vault.vault_kv2_get` (lookup), `vault_write` |
| 1Password | `community.general.onepassword` (lookup), `onepassword_raw`, `onepassword_doc`, `onepassword_ssh_key` |
| HTTP | `ansible.builtin.uri`, `get_url` |
| Git | `ansible.builtin.git` |
| Crypto / cert management | `community.crypto.openssl_certificate_complete_chain`, `acme_certificate`, `x509_certificate`, `openssl_privatekey` |
| MySQL / Postgres | `community.mysql.*`, `community.postgresql.*` |
| Redis | `community.general.redis_data` (and friends) |
| Slack / Discord / chat | `community.general.slack`, etc. |
| Generic shell escape | `ansible.builtin.command`, `shell`, `raw` (only when Python isn't on the target) |

When a collection is part of the `community.general` mega-collection, it's often migrating to a dedicated home (e.g. `community.docker`, `community.hashi_vault`, `community.crypto`). Check the latest porting guide if you find a module isn't where you expected.

## `ansible.cfg` essentials

```ini
[defaults]
inventory = ./inventories/prod
collections_path = ./collections
roles_path = ./roles
host_key_checking = false                # true in real environments; false for ephemeral CI hosts
forks = 25
gathering = smart                         # cache facts opportunistically
fact_caching = jsonfile
fact_caching_connection = ~/.ansible/facts_cache
fact_caching_timeout = 7200
stdout_callback = yaml                    # or `community.general.diy` / `community.general.unixy`
callbacks_enabled = profile_tasks
retry_files_enabled = false

[inventory]
enable_plugins = ansible.builtin.host_list, ansible.builtin.script, ansible.builtin.auto, ansible.builtin.yaml, ansible.builtin.ini, ansible.builtin.toml, amazon.aws.aws_ec2, ansible.builtin.constructed

[ssh_connection]
pipelining = true
ssh_args = -C -o ControlMaster=auto -o ControlPersist=300s
control_path = ~/.ssh/cm-%%h-%%p-%%r

[privilege_escalation]
become = false
become_method = sudo
become_user = root
become_ask_pass = false
```

Notes:

- `transport: smart` was removed in 2.20. If you set `transport:` at all, set `ssh` or `paramiko` explicitly.
- `host_key_checking = false` only in CI/ephemeral hosts. Real environments should run `ssh-keyscan` or use `accept-new` via `ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new"`.
- `stdout_callback = yaml` (or `community.general.unixy`) makes failures readable. Default is unfriendly.
- `callbacks_enabled = profile_tasks` shows per-task timing — invaluable for finding slow tasks.
- `pipelining = true` is a 2-3x speedup with no real downside except an old `requiretty` sudoers gotcha.

## Pinning and updates

When a collection version bump shows up in your dependency tree:

1. Read the collection's CHANGELOG before bumping.
2. Bump in `requirements.yml`, install with `--force-with-deps`.
3. Run `ansible-lint` — it'll flag breaking syntax changes.
4. Run `molecule test` for affected roles.

Don't pin to exact versions (`==`) unless you have to. `>=X,<Y` (next major) is usually the right range for a long-lived project.

## Authoring a private collection

When you've got more than a few shared roles, package them as a collection rather than copying directories around:

```
my_namespace/
└── my_collection/
    ├── galaxy.yml
    ├── meta/runtime.yml
    ├── plugins/
    │   ├── modules/
    │   ├── lookup/
    │   └── filter/
    ├── roles/
    │   └── my_role/
    └── tests/
```

```yaml
# galaxy.yml
---
namespace: my_namespace
name: my_collection
version: 1.0.0
readme: README.md
authors:
  - Platform Team
description: Internal platform automation.
license: [MIT]
tags: [internal]
dependencies:
  community.general: ">=12.0.0,<13.0.0"
```

Publish:

```bash
ansible-galaxy collection build .
ansible-galaxy collection publish my_namespace-my_collection-1.0.0.tar.gz \
  --server https://galaxy.internal.example.com/api/
```

Consume in another project:

```yaml
# requirements.yml
collections:
  - name: my_namespace.my_collection
    version: "1.0.0"
    source: https://galaxy.internal.example.com/api/
```

Or pull straight from git:

```yaml
collections:
  - name: https://github.com/myorg/my_collection.git
    type: git
    version: v1.0.0
```

## Common mistakes

- **`pip install ansible-collection-foo`** — this *almost* works (the upstream package exists for a few collections) but breaks reproducibility. Always use `requirements.yml`.
- **Forgetting to install collections in CI.** Add `ansible-galaxy collection install -r requirements.yml --force` to the CI prelude.
- **Mixing global and project-local collections paths.** Pick one (project-local for reproducibility) and stick to it.
- **Pinning to a specific patch version.** You'll miss security fixes. Pin to the next major.
- **Using a bare module name and relying on `collections:` keyword resolution.** This still works but is brittle and `production` lint catches it. Just write the FQCN.
