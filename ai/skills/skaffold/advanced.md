# Skaffold — Advanced

The genuinely-weird, edge-case, or "you should know this exists" patterns. Reach here when the default-stack tables and the per-topic reference files don't cover what you're trying to do.

## `skaffold inspect` — programmatic config introspection

A subcommand tree for querying the resolved config without rendering or running. Output is JSON by default — pipe it through `jq` for automation.

```sh
skaffold inspect modules list                        # configs Skaffold sees (top + required)
skaffold inspect profiles list                       # all profiles and their activation rules
skaffold inspect profiles list --module api
skaffold inspect build-env list                      # which build env each artifact uses
skaffold inspect tests list                          # registered test containers
skaffold inspect namespaces list                     # namespaces deployments target
skaffold inspect executionModes list                 # verify execution modes per test
skaffold inspect config-dependencies list            # the dep graph of `requires:`
```

Useful in CI for "did my change actually do what I expected" guardrails:

```sh
# Fail CI if anyone adds an artifact without inputDigest tagging
skaffold inspect build-env list --format=json | jq -e 'all(.builders[]; .tagPolicy.inputDigest)'
```

## Build environments — `local`, `cluster`, `googleCloudBuild`

You pick one per `Config`. Most users live in `local:` and never look elsewhere.

### `local:` (default)

Builds run on the host docker daemon. Push behavior auto-derived from kube context.

```yaml
build:
  local:
    push: false
    useBuildkit: true
    concurrency: 0                                   # 0 = unlimited; positive int = cap
    tryImportMissing: true                          # for missing base images, pull from registry instead of failing
```

### `cluster:` (kaniko)

Builds happen as kaniko Pods in a target cluster. The build cluster doesn't have to be the same as the deploy cluster.

```yaml
build:
  cluster:
    namespace: skaffold-builds
    pullSecretName: gcr-pull                         # for kaniko to pull the base image
    dockerConfig:
      secretName: docker-config-json                 # for kaniko to push the result
    resources:                                       # pod resource requests
      requests:
        cpu: "2"
        memory: "8Gi"
    timeout: 30m
    nodeSelector:
      kaniko.skaffold.dev: "true"                    # pin builds to dedicated nodes
    tolerations:
      - key: "build"
        operator: "Exists"
    serviceAccount: skaffold-builder
    annotations:                                     # propagated to build pods (sidecar.istio.io/inject: "false" is common)
      sidecar.istio.io/inject: "false"
```

When to use: CI environments without a docker socket (unprivileged GitHub Actions runners, OpenShift), or when build resources need to live in the cluster's autoscaling group, not on a separate build fleet.

### `googleCloudBuild:`

Submits builds to GCB. Useful when you want builds close to GCR/AR (no egress) or when local build resources are constrained.

```yaml
build:
  googleCloudBuild:
    projectId: my-gcp-project
    diskSizeGb: 100
    machineType: E2_HIGHCPU_8
    timeout: 1800s
    region: us-east1
    logging: CLOUD_LOGGING_ONLY
    logStreamingOption: STREAM_DEFAULT
    workerPool: projects/my-gcp-project/locations/us-east1/workerPools/private-pool
    dockerImage: gcr.io/cloud-builders/docker:24.0.6
    kanikoImage: gcr.io/kaniko-project/executor:v1.23.2
    packImage: gcr.io/k8s-skaffold/pack
```

GCB pulls the build context to a GCB worker, builds there, pushes to a registry, and writes structured logs. Skaffold reports progress as it goes. Slower per-build than `local:`, but no machine constraints.

## Cache strategies

Build cache is the difference between a 30s rebuild and a 5min rebuild. Each builder has its own mechanism:

### docker (BuildKit)

```yaml
build:
  local:
    useBuildkit: true
  artifacts:
    - image: ghcr.io/myorg/svc
      docker:
        buildArgs:
          BUILDKIT_INLINE_CACHE: "1"                # write cache metadata into the pushed image
        cacheFrom:
          - ghcr.io/myorg/svc:cache                 # pull this as a layer cache source
          - ghcr.io/myorg/svc:latest                # also try the previous build
```

For multi-arch buildx builds, use `--cache-to type=registry,ref=cache,mode=max` style — but that requires a `custom:` builder script since Skaffold's docker integration doesn't expose buildx-mode cache flags.

### ko

ko has its own layer cache, separate from docker:

```sh
export KO_CACHE=~/.cache/ko                          # persist between Skaffold invocations
```

For CI, mount `~/.cache/ko` as a workflow cache (actions/cache or equivalent). For remote build caches, ko's `--platform=all` builds benefit from `KO_DEFAULTBASEIMAGE` being a multi-arch image (manifest list).

### kaniko

```yaml
artifacts:
  - kaniko:
      cache:
        repo: ghcr.io/myorg/svc-kaniko-cache
        ttl: 168h
        hostPath: /cache                            # local cache on the build node (mostly for kaniko-in-docker)
```

The `cache.repo:` is a registry namespace for layer cache — separate from your image registry, often `<image>-cache`. Without it, kaniko has no cache.

### buildpacks

```yaml
artifacts:
  - buildpacks:
      builder: paketobuildpacks/builder-jammy-base
      env:
        - BP_NODE_RUN_SCRIPTS=build                 # speeds up incremental builds
```

Buildpacks cache layers in an OCI image. The cache lives at `<image>-cache` in the same registry by default. First build is slow; subsequent builds for unchanged layers (deps, base) skip.

## Custom builders deep

`custom.buildCommand` lets you run any script. Skaffold sets env vars and expects an image at the named tag.

```yaml
artifacts:
  - image: ghcr.io/myorg/nix-svc
    custom:
      buildCommand: ./scripts/nix-build.sh
      dependencies:
        paths:
          - "src/**"
          - flake.nix
          - flake.lock
```

```bash
#!/usr/bin/env bash
# scripts/nix-build.sh
set -euo pipefail

# Skaffold-provided env vars
: "${IMAGE:?missing IMAGE from Skaffold}"
: "${PUSH_IMAGE:?missing PUSH_IMAGE from Skaffold}"
: "${BUILD_CONTEXT:?missing BUILD_CONTEXT from Skaffold}"

cd "$BUILD_CONTEXT"

# Build via nix
nix build .#dockerImage -o result

# Load the resulting tarball
docker load < result | tee /tmp/load.log
LOADED_TAG=$(awk '/Loaded image:/ {print $NF}' /tmp/load.log)

# Retag to what Skaffold expects
docker tag "$LOADED_TAG" "$IMAGE"

# Push if Skaffold asked
if [[ "$PUSH_IMAGE" == "true" ]]; then
  docker push "$IMAGE"
fi
```

Full env-var contract Skaffold exposes to custom builders:

| Var | What |
|---|---|
| `IMAGE` | Target image tag |
| `PUSH_IMAGE` | `true`/`false` |
| `BUILD_CONTEXT` | Absolute path to artifact context |
| `PLATFORMS` | Comma-separated platforms when cross-building |
| `SKAFFOLD_RUN_ID` | Per-invocation UUID — useful as a cache key |
| `SKAFFOLD_GO_GCFLAGS` | Set by `--gcflags` for Go (debug mode) |

## Manifest transformation pipelines

Render-time mutation, for cases where neither the source manifests nor the chart can express what you need:

```yaml
manifests:
  rawYaml:
    - manifests/*.yaml
  transform:
    - name: add-istio-annotations
      configMap:
        - sidecar.istio.io/proxyCPU=100m
        - sidecar.istio.io/proxyMemory=128Mi
    - name: set-namespace
      configMap:
        - namespace=my-app
  validate:
    - name: kubeval
```

Built-in transformers: `add-labels`, `add-annotations`, `set-namespace`, `set-image`. For custom transforms, wire a `kpt fn` pipeline:

```yaml
manifests:
  kpt:
    dir: manifests/
  transform:
    - name: kpt-fn
      configMap:
        - "image=gcr.io/kpt-fn/apply-setters:v0.2"
```

These run after rendering, before applying. If you find yourself reaching for transforms a lot, push the logic into the source manifests / chart instead — transforms are opaque to anyone reading the YAML.

## Manifest validation

```yaml
manifests:
  rawYaml:
    - manifests/*.yaml
  validate:
    - name: kubeval                                  # built-in: kubeval against k8s schemas
    - name: kubeconform                              # built-in: kubeconform (faster)
```

Built-in validators run after rendering, before deploying. CI-friendly — if rendering produces invalid manifests, the build fails before anything hits the cluster.

External validators (OPA, conftest, kyverno) aren't built-in; run them as a CI step after `skaffold render --output=manifests.yaml`.

## Custom status checks (`statusCheckResourceTypes`)

By default Skaffold waits for Deployments, StatefulSets, DaemonSets, Pods, ConfigMaps, and a few others to be Ready. For custom resources (CRDs from operators), tell Skaffold what "Ready" means:

```yaml
deploy:
  kubectl: {}
  statusCheck: true
  statusCheckDeadlineSeconds: 600
  tolerateFailuresUntilDeadline: false              # default: fail fast on first error
```

For CRD readiness, Skaffold v2 has limited extensibility — usually you let the CRD's controller do its thing and use a `verify:` test for post-deploy validation rather than blocking on CRD status.

## LSP integration

```sh
skaffold lsp                                         # starts the LSP server on stdin/stdout
```

Wire it into your editor for `skaffold.yaml` autocomplete, schema validation, and hover docs. VS Code: install the official Skaffold extension. Neovim:

```lua
-- nvim-lspconfig
lspconfig.skaffold.setup({
  cmd = { "skaffold", "lsp" },
  filetypes = { "yaml" },
  root_dir = lspconfig.util.root_pattern("skaffold.yaml"),
})
```

The LSP validates against the resolved schema for whatever `apiVersion:` your file declares, which catches "wrong field name" issues before runtime.

## Templating `skaffold.yaml` itself

Field values support Go template substitution (see [profiles.md](profiles.md) for `{{.IMAGE_*}}` and template vars). For larger templating (templating chunks of the YAML structure, not just field values), wrap Skaffold in a Makefile/justfile that runs `envsubst` or `gomplate` over a `skaffold.yaml.tmpl` first:

```just
render-skaffold:
    gomplate -f skaffold.yaml.tmpl -o skaffold.yaml

dev: render-skaffold
    skaffold dev
```

Skaffold's own template substitution is powerful enough for 95% of cases — only reach for an outer templating layer when you need to vary the *structure* (conditionally include/exclude artifacts, generate N artifacts from a list, etc.).

## Image pull secrets at render time

For private registries, Skaffold doesn't auto-inject `imagePullSecrets`. Either:

1. Bake the secret reference into your chart/manifests.
2. Use a `transform:` step to add it post-render.
3. Use a cluster-default service account that already has the secret.

The cleanest is (1) — chart-side. The cluster default (3) is fine for shared-cluster dev. Avoid (2) unless options 1 and 3 are blocked.

## `--digest-source` for non-Skaffold-built images

When manifests reference images Skaffold didn't build (third-party charts, externally-built sidecars), `--digest-source` controls how Skaffold resolves them:

| Value | What |
|---|---|
| `tag` | Use the tag as-is from the manifest. No digest lookup. |
| `local` | Look up digest in the local docker daemon. Fails if image isn't pulled. |
| `remote` | Query the registry for the current digest. Network round trip per image. |
| `none` | Don't touch image refs at all. |

Default is `local` for `dev`/`run` and `tag` for `render`. For CI hermetic builds, `--digest-source=tag` (skip resolution) or `--digest-source=remote` (pin digests once at render time, then everything downstream is reproducible).

## Skipping artifacts / partial builds

```sh
skaffold build --only=ghcr.io/myorg/api,ghcr.io/myorg/worker     # build just these
skaffold build --except=ghcr.io/myorg/web                        # skip this one
```

Matches against `image:` (the artifact image name). Useful when iterating on one service in a multi-artifact `Config` and you don't want to wait for the others to rebuild.

`skaffold dev` doesn't have `--only` / `--except` — use `--module <name>` against a multi-config setup instead.

## Network policies and port-forwarding

`skaffold dev`/`debug` port-forwarding uses `kubectl port-forward` under the hood. NetworkPolicy denials affect *pod-to-pod* traffic, not `kubectl port-forward` (which goes through the API server). So `portForward:` works even on namespaces with strict NetworkPolicy, but in-cluster traffic from your other pods doesn't.

If your dev workflow needs in-cluster pod-to-pod traffic and NetworkPolicy is denying it, add a dev-only `NetworkPolicy` allowing same-namespace traffic, scoped via the `dev` profile.

## When `skaffold inspect` and `diagnose` aren't enough

For the truly baffling — "this config doesn't behave like it reads" — there's `--verbosity=trace` and the `--render-only` / `--build-only` short-circuits:

```sh
skaffold dev --verbosity=trace 2>&1 | tee /tmp/skaffold.log
skaffold render --output=/tmp/rendered.yaml --offline=true && less /tmp/rendered.yaml
skaffold diagnose -p myprofile > /tmp/resolved.yaml
diff <(skaffold diagnose) <(skaffold diagnose -p myprofile)    # what does my profile actually change?
```

The `diff <(skaffold diagnose) <(skaffold diagnose -p myprofile)` idiom is the answer to "what is my profile actually doing." Save the recipe.

## Don't / Do

| Don't | Do |
|---|---|
| `custom:` builder when `docker`/`ko`/`buildpacks` would work | Native builder first; `custom` is the escape hatch |
| `build.cluster:` kaniko without `cache.repo:` | Configure cache or accept slow builds |
| `googleCloudBuild:` without `workerPool:` for security-sensitive builds | Use a private worker pool to keep build traffic inside your VPC |
| `transform:` to fix what a chart should expose | Push the config into chart values, not a render-time mutation |
| `manifests.validate:` only in dev | Run validation in CI too — catches drift before deploy |
| `--digest-source=local` in CI | `--digest-source=tag` (with explicit tags) or `=remote` (one network round) |
| Skip `skaffold lsp` setup | Wire it up — catches schema errors at edit time |
| Templating skaffold.yaml structure with `envsubst` for trivial vars | Use built-in `{{.ENV_VAR}}` substitution; reach for outer templating only for structural changes |
| `kubectl port-forward` separately during dev | Declare in `portForward:` — auto-applies in `dev`/`debug` |
| Manual `--profile=foo --profile=bar` every command | `activation:` pinned to kubeContext/env so they auto-fire |
