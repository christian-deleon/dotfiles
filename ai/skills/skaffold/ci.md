# Skaffold in CI / CD

Skaffold's role in CI is **build images and render manifests**. Its role in CD is, usually, **nothing** — production deploys are GitOps (Flux/Argo CD reconcile from a git repo). The `render` / `apply` / `verify` split lets you cleanly hand off between the two without `skaffold deploy` blurring the line.

Two failure modes dominate here: (1) `skaffold dev`-style configs leak into CI, which then tries to watch and port-forward in a headless runner; and (2) `skaffold apply` is used to push to production from CI, bypassing the GitOps controller and creating drift. Don't do either.

## The pipeline shape

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   build      │ →  │   render     │ →  │   commit     │ →  │   reconcile  │
│ (Skaffold)   │    │ (Skaffold)   │    │ to GitOps    │    │ (Flux/Argo)  │
│              │    │              │    │ repo         │    │              │
│ skaffold     │    │ skaffold     │    │ git push     │    │ — out of CI  │
│ build        │    │ render       │    │              │    │   pipeline   │
│ --file-output│    │ --offline    │    │              │    │              │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

Each step is independently re-runnable. The build step produces image digests; the render step produces manifests with those digests baked in; the commit step delivers manifests to the GitOps repo; the GitOps controller does the actual cluster mutation.

## `skaffold build` in CI

```sh
skaffold build \
  --file-output=build.json \                          # dump resolved image tags
  --push=true \                                       # explicit, even though default for non-local contexts
  --default-repo=ghcr.io/myorg \                      # registry namespace per environment
  --tag="$(git rev-parse --short HEAD)"               # optional: override tag policy with a static tag
```

`--file-output=build.json` writes a JSON document:

```json
{
  "builds": [
    {
      "imageName": "ghcr.io/myorg/svc",
      "tag": "ghcr.io/myorg/svc:abc123@sha256:..."
    }
  ]
}
```

Pass it to `skaffold render --build-artifacts=build.json` to render with the just-built tags — that's how you avoid the render step rebuilding (or worse, re-resolving to a different tag).

## `skaffold render` in CI

```sh
skaffold render \
  --build-artifacts=build.json \                      # consume the build output
  --offline=true \                                    # hermetic: no cluster calls, no chart-repo fetches beyond pinned
  --output=manifests/rendered.yaml \                  # write to a file (default is stdout)
  --digest-source=tag                                 # or `local` / `remote` / `none`
```

| Flag | What |
|---|---|
| `--offline=true` | No cluster calls (no `lookup`, no live-state queries). Required for reproducible CI renders. |
| `--build-artifacts=<file>` | Use these pre-built image refs instead of building/resolving. |
| `--digest-source=tag` | Use the `:tag` from build artifacts (the tag itself includes a digest in `--tag=foo@sha256:...` form). |
| `--digest-source=local` | Look up digests from the local docker daemon (rarely useful in CI). |
| `--digest-source=remote` | Query the registry for the current digest of each tag (slow, but works when build wasn't done by Skaffold). |
| `--digest-source=none` | Skip digest resolution — leave tags as-is. |
| `--output=<file>` | Write rendered manifests to a file. |

The render output is plain Kubernetes YAML — one stream, all resources, server-applicable. Hand it to `kubectl apply -f` (for direct apply) or commit it to a GitOps repo (for reconcile).

### What `--offline=true` actually means

- No `helm dependency update` reaching out to chart repos.
- No `lookup` template calls (any Helm template that uses `lookup` fails or returns nil).
- No `postRenderer:` that reaches over the network.
- Chart deps in `charts/` must already be present (run `helm dep update` before invoking Skaffold, or commit `charts/`).

If a build fails with "chart not found" under `--offline=true`, the chart wasn't vendored. Fix it in the pre-build step, not by removing `--offline`.

## `skaffold apply` — when (and when not)

`skaffold apply <rendered-manifests-file>` is a thin wrapper over `kubectl apply` that also does Skaffold's status checks and log tailing. Use it for:

- **Ephemeral CI test environments** — PR preview namespaces that get torn down after tests.
- **Local one-shots** — when `skaffold run` is what you want but you've already rendered separately.

Don't use it for:

- **Production deploys** — let Flux/Argo CD reconcile from the GitOps repo.
- **Anything where you also want rollback semantics** — `kubectl apply` doesn't track releases; if you need rollback, use Helm directly or `kubectl rollout undo`.

```sh
skaffold apply \
  --status-check=true \                              # wait for resources to be Ready
  --tail=false \                                     # don't tail in CI (no stdin)
  manifests/rendered.yaml
```

## `verify:` — post-deploy integration tests

`verify:` declares test containers that Skaffold launches after the deploy is healthy. Tests are jobs that pass or fail; Skaffold reports the result and exits non-zero if any failed.

```yaml
verify:
  - name: smoke-http
    container:
      name: smoke
      image: curlimages/curl:8.10.1
      command: ["sh", "-c"]
      args:
        - |
          set -e
          curl -fsS http://my-service.default.svc.cluster.local:8080/healthz
    executionMode:
      kubernetesCluster:
        overrides:
          metadata:
            namespace: my-service-test
        jobManifestPath: tests/job-template.yaml      # optional override

  - name: contract-tests
    container:
      name: contract
      image: ghcr.io/myorg/contract-tests:latest
      env:
        - name: TARGET_URL
          value: http://my-service.default.svc.cluster.local:8080
    executionMode:
      kubernetesCluster: {}
```

```sh
skaffold verify                                      # run tests against current deploy
skaffold run --tail                                  # run then verify in one shot (verify runs if test phase succeeds)
```

`executionMode:` chooses where the test runs:

| Mode | What |
|---|---|
| `kubernetesCluster: {}` | Test runs as a Job in the target cluster |
| `local: {}` | Test runs as a docker container on the host |

Test containers are real containers — bake the test logic into an image with the right tools (curl, k6, pytest, etc.). Keep them fast (under a minute total) so they don't dominate CI time.

`verify:` is the right home for smoke tests and contract tests, not for full integration suites. Big test suites belong in dedicated CI jobs, not chained off Skaffold.

## Monorepo: `requires:` and multi-config

For a monorepo with N services, the cleanest pattern is one `skaffold.yaml` per service + a top-level orchestrator config that `requires:` them all:

```
my-monorepo/
├── skaffold.yaml                       # top-level orchestrator
└── services/
    ├── api/
    │   ├── skaffold.yaml               # api service config
    │   ├── Dockerfile
    │   └── ...
    ├── worker/
    │   ├── skaffold.yaml
    │   └── ...
    └── web/
        ├── skaffold.yaml
        └── ...
```

Top-level config:

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: monorepo

requires:
  - configs: [api]
    path: services/api
  - configs: [worker]
    path: services/worker
  - configs: [web]
    path: services/web
```

Per-service config (in `services/api/skaffold.yaml`):

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: api                             # matched by top-level `configs: [api]`

build:
  artifacts:
    - image: ghcr.io/myorg/api
      docker:
        dockerfile: Dockerfile

manifests:
  rawYaml:
    - manifests/*.yaml
```

Then:

```sh
# From repo root — builds + deploys all required configs
skaffold dev

# Just one service
skaffold dev --module api

# Mix and match
skaffold dev --module api --module worker
```

`--module <name>` scopes to the named config (matches `metadata.name`). Without it, all required configs run. Profiles activate per-required-config; use `requires[].activeProfiles:` to propagate profile activation across the boundary (see [profiles.md](profiles.md)).

### Multi-document configs

An alternative to `requires:` for simpler cases: multiple `Config` docs in one file separated by `---`:

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: api
build:
  artifacts:
    - image: ghcr.io/myorg/api
      docker: { dockerfile: api.Dockerfile }
---
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: worker
build:
  artifacts:
    - image: ghcr.io/myorg/worker
      docker: { dockerfile: worker.Dockerfile }
```

Two configs, one file, both run by default. `--module` works the same way. Prefer this when the services live in the same dir tree; prefer `requires:` when they're cleanly split into per-service dirs.

## GitHub Actions example

```yaml
# .github/workflows/build.yml
name: build
on: [push]

jobs:
  build-render:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-helm@v4
        with:
          version: v3.15.4
      - name: Install Skaffold
        run: |
          curl -fsSLo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
          chmod +x skaffold && sudo mv skaffold /usr/local/bin
      - name: Login to GHCR
        run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin
      - name: Build images
        run: skaffold build --file-output=build.json --default-repo=ghcr.io/${{ github.repository_owner }}
      - name: Render manifests
        run: |
          mkdir -p out
          skaffold render --offline=true --build-artifacts=build.json --output=out/manifests.yaml
      - name: Commit to GitOps repo
        run: ./scripts/push-to-gitops.sh out/manifests.yaml
```

Notice: no `skaffold dev`, no `skaffold apply`, no `--port-forward`. CI builds and renders; the GitOps controller picks up the commit and reconciles.

## Skaffold + Flux/Argo CD handoff

The GitOps repo stores **rendered manifests** (or chart references, depending on how the GitOps controller is configured):

- **Flux with `Kustomization`** pointing at a directory of rendered manifests: Skaffold's `render --output=path/to/dir/manifests.yaml` writes here, CI commits, Flux reconciles. Simple.
- **Flux with `HelmRelease`**: Skaffold isn't in the render path at all — Flux's helm-controller renders. Skaffold's job is just to `build` and push the new image; a separate step bumps the chart's `values.yaml` (often Renovate or image-update-automation).
- **Argo CD with App-of-Apps**: same shape — Skaffold builds, CI updates manifests in the GitOps repo, Argo CD syncs.

The throughline: **Skaffold builds, CI updates git, controller reconciles**. Skaffold never touches the cluster Flux/Argo controls.

## Don't / Do

| Don't | Do |
|---|---|
| `skaffold dev` in CI | `skaffold build` + `skaffold render` |
| `skaffold deploy` (legacy combined) | `skaffold render` → `skaffold apply` (or `kubectl apply`) for separate phases |
| `skaffold apply` to production | Commit rendered manifests to GitOps; controller reconciles |
| `skaffold render` without `--offline=true` in CI | `--offline=true` for hermetic, reproducible output |
| `skaffold render` without `--build-artifacts` after a separate build step | `--build-artifacts=build.json` to consume the build phase's tags |
| Skip `helm dep update` before `skaffold render --offline=true` | Vendor deps (run `helm dep update`) in the pre-build step |
| One `skaffold.yaml` with 12 services tangled together | Multi-config (`requires:`) — one config per service, top-level orchestrator |
| `verify:` containing a 30-minute integration suite | Keep `verify:` fast — smoke + contract; full suite in a dedicated CI job |
| `skaffold dev` against a Flux-managed namespace | Separate dev cluster, or a namespace Flux doesn't reconcile |
| Push images from `skaffold dev` runs to a shared dev registry | Per-user `--default-repo` namespacing (`ghcr.io/myorg-dev/$USER/...`) |
