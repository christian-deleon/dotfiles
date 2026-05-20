# Secrets

Ansible has two valid answers to "how do I handle secrets": **`ansible-vault`** for secrets that live in the repo (encrypted), and **external secret stores** (HashiCorp Vault, 1Password, AWS Secrets Manager, etc.) for runtime fetching. Most production setups use both — vault for bootstrap credentials and pinned values, external store for everything else. The wrong answer is "I'll just put it in `defaults/main.yml` and remember to gitignore it." Don't.

The non-negotiables:

1. **Never commit plaintext secrets.** Not in `defaults/`, not in `vars/`, not in inventory, not in playbooks.
2. **`no_log: true` on any task that touches a secret.** Otherwise the task output prints it to logs.
3. **Vault password files / vault IDs live outside the repo.** Use `vault_password_file =` in `ansible.cfg` only when the path is gitignored (`~/.config/ansible/vault-pass`) or a script that fetches the password from a secret store.

## `ansible-vault`

### Encrypting whole files

```bash
ansible-vault encrypt vars/secrets.yml
ansible-vault decrypt vars/secrets.yml     # rarely; only for inspection
ansible-vault view vars/secrets.yml
ansible-vault edit vars/secrets.yml         # in-place edit, re-encrypts on save
ansible-vault rekey vars/secrets.yml        # change the password
```

A vaulted file looks like:

```
$ANSIBLE_VAULT;1.2;AES256;production
30313264363437363861333837356235646...
```

The trailing `;production` is the **vault ID** (see below).

### Encrypting single strings

When you only need to encrypt one or two values, drop them inline as encrypted strings instead of vaulting the whole file:

```bash
ansible-vault encrypt_string 'super-secret-password' \
  --name 'db_admin_password' \
  --vault-id production@~/.config/ansible/vault-pass
```

Outputs YAML you paste into a normal vars file:

```yaml
db_admin_password: !vault |
  $ANSIBLE_VAULT;1.2;AES256;production
  6638373061363539393134616462303663316662303530393939393738653634...
```

Mix encrypted strings and plaintext values in the same file. This is usually cleaner than vaulting an entire `secrets.yml`.

### Vault IDs (multi-vault)

A vault ID is a named label for a key. They let you have, say, a different password for prod and staging:

```bash
ansible-vault encrypt vars/prod/secrets.yml --vault-id prod@prompt
ansible-vault encrypt vars/staging/secrets.yml --vault-id staging@prompt
```

Configure in `ansible.cfg`:

```ini
[defaults]
vault_identity_list = prod@~/.config/ansible/vault-prod, staging@~/.config/ansible/vault-staging
```

`@prompt` asks at run time; `@<path>` reads from a file; `@<script>` runs an executable that prints the password (used for fetching from a secret store).

### Vault password from a secret store (the right pattern)

Don't commit the vault password — fetch it. A `vault-pass.sh` that asks 1Password / AWS / wherever:

```bash
#!/usr/bin/env bash
# ~/.config/ansible/vault-pass
set -euo pipefail
op read "op://Production/ansible-vault/password"
```

Then `ansible.cfg`:

```ini
[defaults]
vault_password_file = ~/.config/ansible/vault-pass
```

Or per-vault-id:

```ini
vault_identity_list = prod@~/.config/ansible/vault-pass-prod.sh,staging@~/.config/ansible/vault-pass-staging.sh
```

### Using vaulted values in plays

Same as any other variable. Ansible decrypts on read.

```yaml
- name: Bootstrap DB user
  community.postgresql.postgresql_user:
    name: app
    password: "{{ db_admin_password }}"
    state: present
  no_log: true
```

Run with the vault password available:

```bash
ansible-playbook site.yml --vault-id prod@~/.config/ansible/vault-pass-prod.sh
# or, if ansible.cfg has vault_password_file set:
ansible-playbook site.yml
```

## External secret stores (runtime lookup)

For dynamic secrets, short-lived credentials, or anything you don't want a copy of in your repo even encrypted, use a lookup plugin.

### HashiCorp Vault — `community.hashi_vault`

Now a standalone collection (was previously folded into `community.general`). AppRole is the recommended auth method for CI; token auth for interactive use.

```yaml
# requirements.yml
collections:
  - name: community.hashi_vault
    version: ">=7.0.0,<8.0.0"
```

```yaml
- name: Pull database password from Vault
  ansible.builtin.set_fact:
    db_password: "{{ lookup('community.hashi_vault.vault_kv2_get',
                            'apps/myapp/db',
                            engine_mount_point='secret').secret.password }}"
  no_log: true

- name: Use it
  community.postgresql.postgresql_user:
    name: app
    password: "{{ db_password }}"
    state: present
  no_log: true
```

Vault address and auth:

```yaml
# group_vars/all.yml (or environment-scoped)
ansible_hashi_vault_addr: https://vault.example.com:8200
ansible_hashi_vault_auth_method: approle
ansible_hashi_vault_role_id: "{{ lookup('env', 'VAULT_ROLE_ID') }}"
ansible_hashi_vault_secret_id: "{{ lookup('env', 'VAULT_SECRET_ID') }}"
```

CI exports `VAULT_ROLE_ID` and `VAULT_SECRET_ID` (themselves stored in the CI secret store). Local dev uses `vault login` and the resulting token.

### 1Password — `community.general.onepassword`

Multiple lookups for different shapes of secret:

```yaml
# Whole item (returns dict)
ansible.builtin.set_fact:
  db_creds: "{{ lookup('community.general.onepassword_doc',
                       'Database/prod-postgres') }}"

# One field
ansible.builtin.set_fact:
  api_token: "{{ lookup('community.general.onepassword',
                        'API/myapp',
                        field='credential') }}"

# SSH key
ansible.builtin.set_fact:
  deploy_key: "{{ lookup('community.general.onepassword_ssh_key',
                         'Deploy Keys/myapp') }}"
```

Auth via `op` CLI is the simplest: `op signin` once on the controller, the lookup uses the session.

### AWS Secrets Manager / SSM Parameter Store — `amazon.aws`

```yaml
- name: Fetch RDS password
  ansible.builtin.set_fact:
    rds_password: "{{ lookup('amazon.aws.secretsmanager_secret',
                             'prod/rds/admin',
                             region='us-east-1') }}"
  no_log: true

- name: Fetch a config value from SSM
  ansible.builtin.set_fact:
    feature_flag: "{{ lookup('amazon.aws.ssm_parameter',
                             '/myapp/feature_x/enabled',
                             region='us-east-1') }}"
```

AWS auth comes from the standard chain: env vars, instance profile, AWS_PROFILE, etc.

## `no_log: true` — when, where, why

`no_log: true` suppresses the task's output (stdout, stderr, registered result) from logs and stdout. Without it, Ansible prints decrypted secrets when a task fails or runs in `-v` mode.

Mandatory on:

- Any task that **reads** a secret (lookup, set_fact, slurp on a credentials file).
- Any task that **writes** a secret (template, copy of a credentials file, user/postgresql_user with password).
- Any task that **uses** a secret in a module call.

```yaml
- name: Set DB admin password
  community.postgresql.postgresql_user:
    name: postgres
    password: "{{ db_admin_password }}"
  no_log: true
```

Trade-off: `no_log: true` also hides **debugging output**. If a task fails and you can't see why, set `no_log: false` *temporarily* in a dev environment.

For loops, `no_log: true` is per-task; if you want to log everything but the secret, restructure the loop or use a `block:` with `no_log` only on the secret-touching task.

## `argument_specs` — `no_log` on role inputs

Mark secret inputs at the role boundary so the role itself doesn't leak them:

```yaml
# meta/argument_specs.yml
argument_specs:
  main:
    options:
      app_admin_password:
        type: str
        required: true
        no_log: true
        description: Admin password. Pass via Vault or external store.
```

This makes `ansible-lint`'s `no-log-password` rule happy and documents the contract.

## CI patterns

- **CI vault password** lives in the CI secret store, mounted as a file or env var at run time.
- **Never store the decrypted secret** in CI artifacts or logs. Mask outputs in your CI's settings.
- **Rotate vault passwords** with `ansible-vault rekey`. A rotation playbook in your repo (vault-encrypted with the *new* password) is a clean record.
- **One vault ID per environment**, not one shared vault password across all envs. Limits blast radius.

## Anti-patterns

| Don't | Do |
|---|---|
| Commit `vault-pass.txt` to the repo | Fetch from an external store (1Password / AWS) via a script |
| Use one vault password for all environments | Vault IDs per env: `prod`, `staging`, `dev` |
| Decrypt secrets with `ansible-vault decrypt`, then forget to re-encrypt | `ansible-vault edit` (re-encrypts on save) |
| `lookup('env', 'DB_PASSWORD')` with the password baked into a bash profile | External store lookup |
| `--extra-vars '@secrets.yml'` where `secrets.yml` is plaintext | Vault the file; or use `vars_files:` with a vault-encrypted file |
| Log `set_fact: { password: ... }` without `no_log: true` | Always set `no_log: true` |
| `assert:` with the secret in the failure message | Validate via `argument_specs` with `no_log: true`; failure messages don't leak |
| Inline secret in `command:` args | Modules that take a `password:` parameter handle redaction; if you must shell out, write the secret to a temp file with `mode: "0600"` and `no_log: true` |
| Long-lived static credentials in Vault | Short-lived dynamic credentials from HashiCorp Vault or AWS STS |
| Store the same secret in vault AND an external store | Pick one source of truth; reference it from the other if needed |

## When something leaks

If a secret hits your logs or git history:

1. **Rotate it now.** Don't wait to finish the rest.
2. Strip from logs (`grep`-and-redact your run artifacts).
3. Purge from git history with `git filter-repo` — and assume the secret was exposed even after purging (treat as still compromised).
4. Audit: how did it leak? Missing `no_log`? Wrong store? Fix the source, not just the symptom.

The fastest leak is a missing `no_log: true` on a `debug:` task added "just to see what's going on." Don't add those without `no_log: true` from the start.
