# Skaffold Profiles

Profiles overlay the base config to vary behavior per environment, command, or context. **One `skaffold.yaml` with N profiles** is the canonical pattern — never a `skaffold.dev.yaml` / `skaffold.prod.yaml` split. Profiles either *replace* whole blocks or *patch* specific fields via JSON Patch.

The activation system is what makes profiles ergonomic: a profile pinned to a kube context fires automatically whenever you target that context. No remembering `--profile=foo` for every command.

## Profile anatomy

```yaml
profiles:
  - name: staging
    activation:                         # auto-fire rules; OR-ed across entries
      - kubeContext: gke_myorg_us-east1_staging
      - env: ENV=staging                # AND-ed within a single entry
    patches: [...]                      # JSON Patch ops on the config tree
    # OR
    build: {...}                        # whole-block override (any top-level key)
    manifests: {...}
    deploy: {...}
    portForward: [...]
```

`activation:` entries are **OR**ed. A single activation entry's conditions are **AND**ed. So:

```yaml
activation:
  - kubeContext: foo                    # fires if context == foo
  - env: CI=true                        # ...OR if CI=true
  - kubeContext: bar
    env: REGION=us-east-1               # ...OR if context == bar AND REGION=us-east-1
```

## Activation rules

| Rule | Matches when | Notes |
|---|---|---|
| `kubeContext: <name>` | Current `kubectl` context equals `<name>` | Supports regex via `kubeContext: !!python/regex 'gke_.*_prod'` (YAML 1.1 tag) or just plain regex string — Skaffold treats it as a regex match |
| `env: NAME=VALUE` | Env var `NAME` is set to `VALUE` | `NAME=` (empty value) matches when set to empty; absence = no match |
| `command: <verb>` | Skaffold invoked with that command | One of `dev`, `debug`, `run`, `build`, `render`, `apply`, `deploy`, `delete`, `verify` |

Common patterns:

```yaml
profiles:
  # Auto-fires for any GKE prod context
  - name: prod-gke
    activation:
      - kubeContext: gke_myorg_.*_prod
    build:
      local:
        push: true

  # Fires only during render — useful for CI hermetic builds
  - name: ci-render
    activation:
      - command: render
    build:
      tagPolicy:
        inputDigest: {}

  # Fires when developer sets DEV_USER, used for namespacing
  - name: per-user
    activation:
      - env: DEV_USER=.+
    patches:
      - op: replace
        path: /deploy/kubectl/defaultNamespace
        value: "dev-{{.DEV_USER}}"
```

## `patches:` — JSON Patch operations

For small, surgical edits prefer `patches:` over re-declaring whole sections. Five operations matter (`copy` and `move` exist but are rarely useful):

| Op | What | Example |
|---|---|---|
| `add` | Insert a value at the path | `op: add, path: /build/artifacts/0/ko/flags, value: [-trimpath]` |
| `replace` | Replace the value at the path | `op: replace, path: /deploy/kubectl/defaultNamespace, value: my-ns` |
| `remove` | Delete the value at the path | `op: remove, path: /portForward/1` |
| `test` | Assert the current value matches before applying | `op: test, path: /build/local/push, value: false` — fails if mismatch |

### Path syntax (RFC 6901)

Paths are slash-delimited. Array indices are zero-based. `~` is escaped as `~0`, `/` as `~1`.

```
/build/local/push                          # build.local.push
/build/artifacts/0                         # build.artifacts[0]
/build/artifacts/0/dependencies/paths/0    # build.artifacts[0].dependencies.paths[0]
/manifests/helm/releases/0/valuesFiles/-   # append to manifests.helm.releases[0].valuesFiles (`-` = end of array)
```

The `/-` suffix on `add` appends to an array:

```yaml
patches:
  - op: add
    path: /manifests/helm/releases/0/valuesFiles/-
    value: charts/my-service/values-debug.yaml
```

### Combining patches

Patches apply in order. Use `test:` to guard against base-config drift breaking your patch:

```yaml
patches:
  - op: test
    path: /build/tagPolicy/inputDigest
    value: {}                              # ensure base is still using inputDigest
  - op: replace
    path: /build/tagPolicy
    value:
      gitCommit:
        variant: AbbrevCommitSha
```

Without the `test`, if someone changes the base tagger from `inputDigest` to `gitCommit`, your `replace` silently overwrites their change.

## Whole-block override

For larger changes, just declare the whole block. The profile's block replaces the base's:

```yaml
profiles:
  - name: minikube
    activation:
      - kubeContext: minikube
    build:
      local:
        push: false
        useBuildkit: true
        concurrency: 2
      tagPolicy:
        gitCommit:
          variant: AbbrevCommitSha
      artifacts:
        - image: ghcr.io/myorg/svc
          docker:
            dockerfile: Dockerfile.dev   # different Dockerfile for dev
```

Note: with whole-block, the **whole** `build:` is replaced. Artifacts not listed in the profile's `build.artifacts:` are dropped. Use `patches:` if you only want to swap a tag policy.

## Templating in field values

Field values can use Go template syntax with access to env vars and a few Skaffold context vars:

```yaml
deploy:
  kubectl:
    defaultNamespace: "dev-{{.USER}}-{{cmd \"git rev-parse --abbrev-ref HEAD\"}}"
```

Available template vars:

| Var | What |
|---|---|
| `{{.ENV_VAR}}` | Any env var (Skaffold injects every env var as a template var) |
| `{{.IMAGE_FULLY_QUALIFIED}}` | Resolved image ref (in artifact-scoped contexts) |
| `{{.IMAGE_REPO_<sanitized>}}` | Per-image repo (when referenced from `setValueTemplates`) |
| `{{.IMAGE_TAG_<sanitized>}}` | Per-image tag |
| `{{.IMAGE_DIGEST_<sanitized>}}` | Per-image digest |
| `{{.GIT_COMMIT}}` | Resolved git commit SHA (when running inside a git tree) |
| `{{cmd "shell command"}}` | Execute and substitute the stdout. Use sparingly — slow and side-effecty |

Sanitization rule: in `IMAGE_*` template vars, the image ref is sanitized by replacing every non-alphanumeric character with `_`. So `ghcr.io/myorg/my-service` becomes `ghcr_io_myorg_my_service`:

```yaml
manifests:
  helm:
    releases:
      - name: my-svc
        chartPath: ./chart
        setValueTemplates:
          image.repository: "{{.IMAGE_REPO_ghcr_io_myorg_my_service}}"
          image.tag: "{{.IMAGE_TAG_ghcr_io_myorg_my_service}}@{{.IMAGE_DIGEST_ghcr_io_myorg_my_service}}"
```

This is how you wire Skaffold's resolved image refs into Helm chart values when chart-side auto-detection isn't working.

## Profile composition

Profiles **don't inherit** from each other. Stack them on the CLI:

```sh
skaffold dev --profile=minikube --profile=debug
```

Later profiles override earlier ones — they're applied left-to-right against the base. `--profile=minikube` patches base; `--profile=debug` then patches the (already-minikube-patched) result.

This is the idiom for composable profiles: keep each profile single-purpose (one switches the cluster type, one switches build flags for debugging, one switches namespace), then stack them.

## Multi-config monorepos

When a repo has multiple Skaffold configs (one per service), use `requires:` at the top level to reference them. Profiles can be scoped per-required-config or scoped globally:

```yaml
# Top-level skaffold.yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: monorepo

requires:
  - configs: [api]
    path: services/api
    activeProfiles:
      - name: dev                       # auto-activate `dev` profile in services/api when this config runs
        activatedBy: [monorepo-dev]     # ...but only if our profile `monorepo-dev` is active
  - configs: [worker]
    path: services/worker

profiles:
  - name: monorepo-dev
    activation:
      - command: dev
```

`activeProfiles:` propagates profile activation across `requires:` boundaries. Without it, each required config's profiles activate independently based on their own activation rules. See [ci.md](ci.md) for the full monorepo pattern.

## Inspecting resolved profiles

```sh
skaffold inspect profiles list                        # all profiles, with activation rules
skaffold inspect profiles list --module svc-a         # scoped to one config in a multi-config repo
skaffold config list -p staging                       # see what the `staging` profile resolves to
skaffold diagnose -p staging                          # dump the fully-resolved config under staging
```

`skaffold diagnose` is the answer to "what is my config actually doing right now." Always run it when a profile isn't behaving as expected.

## Don't / Do

| Don't | Do |
|---|---|
| `skaffold.dev.yaml` and `skaffold.prod.yaml` separately | One `skaffold.yaml` + `profiles:` |
| Profile activated only by `--profile=foo` | `activation:` on `kubeContext`/`env`/`command` so it auto-fires |
| `replaces:` whole `build:` block for a one-field change | `patches:` with `op: replace` on the specific path |
| Bare `setValueTemplates: image.tag: "{{.TAG}}"` | Use the sanitized `IMAGE_TAG_<sanitized>` var per-image |
| Assume profiles inherit | Stack with `--profile=a --profile=b` for composition |
| `{{cmd "long-running-script"}}` in templates | Pre-resolve in a hook or env var; cmd runs on every template eval |
| Edit YAML manually to "debug" why a profile didn't fire | `skaffold diagnose -p <name>` — dumps resolved config |
| `kubeContext: my-cluster` exact match when you have N clusters with shared suffix | Regex: `kubeContext: gke_.*_prod` |
