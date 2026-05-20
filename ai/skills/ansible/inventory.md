# Inventory and variables

Inventory is where Ansible learns about hosts: who they are, what groups they're in, and what variables apply. The discipline is twofold: layer your sources (static → dynamic → constructed) and put variables at the right level of the precedence ladder. Most "I don't know why this var has that value" bugs trace back to a precedence misunderstanding.

## Per-environment inventory layout

One directory per environment. Never one giant flat `hosts.ini`.

```
inventories/
├── prod/
│   ├── 01-source.aws_ec2.yml         # dynamic plugin source
│   ├── 02-static.yml                 # static hosts that aren't in cloud
│   ├── 99-constructed.yml            # constructed plugin — LAST, derives groups/vars
│   ├── group_vars/
│   │   ├── all.yml
│   │   ├── all/                      # OR a directory if it gets big
│   │   │   ├── network.yml
│   │   │   └── monitoring.yml
│   │   ├── webservers.yml
│   │   └── databases.yml
│   └── host_vars/
│       ├── web01.yml
│       └── db-primary.yml
└── staging/
    ├── ...
```

Run with `-i inventories/prod`. Ansible reads every file in the dir in **lexicographic order**, which is why files are numbered: dynamic plugins resolve first, constructed inventory layers groups on top last.

`group_vars/<group>.yml` and `host_vars/<host>.yml` work whether the group/host comes from a static or dynamic source — that's the whole reason this layout works.

## Static inventory (YAML, not INI)

INI parses, but YAML is what new code should use:

```yaml
# inventories/prod/02-static.yml
---
all:
  children:
    webservers:
      hosts:
        web01.example.com:
        web02.example.com:
      vars:
        nginx_listen_port: 443
    databases:
      hosts:
        db-primary.example.com:
          db_replica_of: ~
        db-replica.example.com:
          db_replica_of: db-primary.example.com
  vars:
    ansible_user: deploy
    ansible_python_interpreter: /usr/bin/python3
```

`children:` nests groups; a host can belong to many groups; `all` is the root. Don't inline a lot of `vars:` here — push them into `group_vars/` instead.

`inventory_hostname` is the name Ansible uses to refer to the host (the YAML key). `ansible_host` is the actual address used for SSH. They can differ:

```yaml
web01:
  ansible_host: 10.0.1.10
  ansible_user: deploy
```

## Dynamic inventory plugins

Modern cloud and platform inventories come from plugins, not custom scripts. Drop a YAML config under `inventories/<env>/`:

```yaml
# inventories/prod/01-source.aws_ec2.yml
---
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1
  - us-west-2
filters:
  tag:Environment:
    - production
keyed_groups:
  - key: tags.Role
    prefix: role
  - key: placement.region
    prefix: region
hostnames:
  - tag:Name
  - private-dns-name
compose:
  ansible_host: private_ip_address
```

Common plugins:

| Plugin | Source |
|---|---|
| `amazon.aws.aws_ec2` | AWS EC2 |
| `amazon.aws.aws_rds` | AWS RDS |
| `azure.azcollection.azure_rm` | Azure |
| `google.cloud.gcp_compute` | GCP Compute |
| `kubernetes.core.k8s` | Kubernetes (pods/services as inventory) |
| `community.general.proxmox` | Proxmox |
| `community.docker.docker_containers` | Local Docker |
| `community.vmware.vmware_vm_inventory` | vSphere |

Run with `ansible-inventory -i inventories/prod --list --yaml` to see what the plugin returns. Run with `--graph` to see group structure.

## Constructed inventory — the modern layering trick

The `ansible.builtin.constructed` plugin reads previously-resolved inventory and synthesizes new groups and vars from Jinja expressions. It must be the **last** source in the directory:

```yaml
# inventories/prod/99-constructed.yml
---
plugin: ansible.builtin.constructed
strict: false                  # don't fail if a referenced var is undefined
use_vars_plugins: true         # see group_vars/host_vars layered before this runs
groups:
  prod_webservers: "'webservers' in group_names and env == 'prod'"
  needs_reboot: "ansible_facts.kernel | default('') is version('6.0', '<')"
compose:
  ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new"
keyed_groups:
  - key: ansible_facts.distribution | default('unknown') | lower
    prefix: os
  - key: tags.Team | default('unowned')
    prefix: team
```

This is how you add an "all my prod EL9 web servers running an old kernel" group without modifying upstream metadata.

## The variable precedence ladder

There are 22 levels, lowest to highest. Memorize the top and bottom; reference this for the middle:

1. **command line values** (e.g. `-u` for user) — lowest
2. `role defaults` (`defaults/main.yml`)
3. inventory file or script `group_vars/all`
4. inventory `group_vars/all/*`
5. playbook `group_vars/all`
6. playbook `group_vars/all/*`
7. inventory `group_vars/<group>`
8. inventory `group_vars/<group>/*`
9. playbook `group_vars/<group>`
10. playbook `group_vars/<group>/*`
11. inventory `host_vars/<host>`
12. inventory `host_vars/<host>/*`
13. playbook `host_vars/<host>`
14. playbook `host_vars/<host>/*`
15. host facts / cached `set_fact`
16. play vars
17. play `vars_prompt`
18. play `vars_files`
19. role vars (`vars/main.yml`) — **inputs do NOT belong here**
20. block vars (in `block:`)
21. task vars (per task)
22. include_vars
23. set_facts / registered vars
24. role (and include_role) params
25. include params
26. **extra vars** (`-e`) — highest, always wins

Practical implications:

- `defaults/main.yml` is the floor. Anything else can override it.
- `vars/main.yml` is very high — once set, it's hard to override. That's exactly why role *inputs* go in `defaults/`, not `vars/`.
- `-e` always wins. Use it sparingly (CI overrides, one-off operator overrides). Never in normal playbook authoring.
- `set_fact` outranks `group_vars` and `host_vars`. Use it deliberately, not as a workaround for "I can't figure out where this var is coming from."

## Common conventions

- `group_vars/all.yml` — site-wide defaults.
- `group_vars/<env>.yml` — environment-specific (use a group named `prod`, `staging`).
- `group_vars/<role-group>.yml` — application/role specific.
- `host_vars/<host>.yml` — last resort. If you find a value in here that applies to more than one host, hoist it into a group.

When a directory grows past a few files:

```
group_vars/all/
├── 00-common.yml
├── 10-network.yml
├── 20-monitoring.yml
└── 99-secrets.yml      # vault-encrypted file
```

Ansible reads all files in lexicographic order and merges them. Use the `hash_behaviour` setting in `ansible.cfg` with care; the default (`replace`) is usually correct.

## `vars_files` and `vars_prompt`

`vars_files` is a play-level inclusion of variable files. Useful when you don't want to commit a file to `group_vars/` (e.g. operator-provided overrides):

```yaml
- hosts: all
  vars_files:
    - vars/main.yml
    - vars/{{ env }}.yml
```

`vars_prompt` asks the operator at run time. Avoid it in CI; use it for human-in-the-loop ad-hoc plays.

## Inventory parameters cheat sheet

| Parameter | Use |
|---|---|
| `ansible_host` | The actual hostname/IP for SSH (when different from `inventory_hostname`) |
| `ansible_port` | SSH port (default 22) |
| `ansible_user` | SSH user (default = current) |
| `ansible_ssh_private_key_file` | Path to key |
| `ansible_ssh_common_args` | Extra `ssh` args; e.g. ProxyCommand for bastions |
| `ansible_python_interpreter` | Path to python on the managed node (set this; don't rely on auto-discovery) |
| `ansible_become` / `ansible_become_method` / `ansible_become_user` | Privilege escalation |
| `ansible_connection` | `ssh` (default), `local`, `docker`, `kubectl`, `winrm`, `community.aws.aws_ssm` |
| `ansible_winrm_transport` | When `ansible_connection: winrm` |

Set `ansible_python_interpreter` explicitly per group — auto-discovery works but is one more thing that can break in odd environments:

```yaml
# group_vars/all.yml
ansible_python_interpreter: /usr/bin/python3
```

## Facts and `ansible_facts.*`

Facts are gathered automatically when a play has `gather_facts: true` (default). They're host-scoped variables under `ansible_facts.*`. The legacy bare-`ansible_*` form depends on the `INJECT_FACTS_AS_VARS` setting, which flips to `False` in 2.24. Write `ansible_facts.distribution`, not `ansible_distribution`.

Subsets help speed up plays that don't need everything:

```yaml
- hosts: webservers
  gather_facts: true
  gather_subset:
    - "!all"
    - "min"        # hostname, os family, distribution, kernel
    - "network"    # interfaces and IPs
```

`gather_facts: false` skips fact collection entirely. Use it on plays that don't need facts — it's a meaningful speed-up at scale.

`ansible.builtin.setup` runs fact collection on demand mid-play. Use it after a reboot or major state change.

## Caching facts

For long playbooks or many-host runs, enable fact caching in `ansible.cfg`:

```ini
[defaults]
fact_caching = jsonfile
fact_caching_connection = /var/lib/ansible/facts_cache
fact_caching_timeout = 86400
```

Redis and memcached backends exist too. Keep TTLs short enough that you notice when a host's facts go stale.

## Variable hygiene

- Don't `set_fact` to "save" something you could have just registered. `register:` is task-scoped already.
- Don't overload one variable name with different meanings in different scopes.
- Don't put environment-dependent values in `defaults/main.yml` of a role. Defaults are *defaults*; the environment-specific value lives in `group_vars/`.
- Variables that change between environments belong in `inventories/<env>/group_vars/`, not in the playbook.
