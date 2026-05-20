---
name: skaffold
description: Skaffold v2 for the Kubernetes inner-loop dev workflow — build, push, deploy, sync, log-tail, port-forward, debug — driven by a single `skaffold.yaml`. ALWAYS use when editing `skaffold.yaml`/`skaffold.yml`, files referencing `apiVersion: skaffold/v4beta*`, or for prompts mentioning Skaffold, `skaffold dev`/`debug`/`run`/`build`/`render`/`apply`/`init`/`diagnose`/`verify`/`inspect`, file sync, hot reload, dev loop, inner loop, profiles, taggers, monorepo with `requires:`, cross-arch builds, or 'rebuild on file change', 'port-forward this', 'debug in-cluster', 'wire up skaffold', 'add a profile', 'why is my image not updating', 'add a verify test'. Treats Skaffold as a **dev/CI build orchestrator**, NOT a production deployer — production is GitOps (see `flux` skill). Enforces v2 schema, render/apply split, file sync over rebuilds, inputDigest/gitCommit taggers, profile-based env variation, and `skaffold debug` for breakpoints.
compatibility: opencode
---

# Skaffold

Skaffold is a CLI that watches your source, picks the right builder per artifact, builds + (optionally) pushes images, renders Kubernetes manifests, applies them to a cluster, then tails logs and forwards ports — all driven by a single `skaffold.yaml`. The point is the **inner dev loop**: edit code, see it running in a real cluster in seconds, with port-forwards and log tailing already wired up. It is not Argo CD, Flux, Helmfile, or a release manager. Don't use it to deploy production. Use it to make the path from `vim main.go` to `curl localhost:8080` short.

The most common AI failure mode here is treating Skaffold like a generic Kubernetes deployer and writing it the way you'd write a Helmfile or an Argo CD `Application` — full rebuilds on every change instead of `sync`, `skaffold deploy` for everything instead of the render/apply split, `latest` tags, profiles used as a config-file-per-env replacement, and `skaffold/v2beta*` (pre-v2) syntax. Also: forgetting that **`skaffold debug` is a first-class command** — people port-forward and `kubectl logs` manually when Skaffold already does both, and they reach for `kubectl debug` ephemeral containers when `skaffold debug` would have rewritten the entrypoint to start a debug-server-compatible runtime on the right port.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Pick / configure a builder (ko, docker, buildpacks, kaniko, jib, bazel, custom); cross-arch; image dependencies | [builders.md](builders.md) |
| Set up file sync / hot-reload; lifecycle hooks (`before`/`after` build/sync/deploy); per-framework reload recipes | [sync.md](sync.md) |
| Use `skaffold debug` per-language; IDE attach configs; multi-container pods | [debug.md](debug.md) |
| Author profiles, activation rules, JSON Patch ops, templating field values | [profiles.md](profiles.md) |
| Wire Skaffold into CI / GitOps; render/apply split; `verify:` tests; monorepo with `requires:` | [ci.md](ci.md) |
| Build environments (`local`/`cluster`/`googleCloudBuild`), cache tuning, `skaffold inspect`, manifest transformers, LSP | [advanced.md](advanced.md) |

For one-off edits the cheat sheets below are usually enough. Reach for reference files when the task warrants depth.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Skaffold version | **v2.x** (v2.13+) | One static binary, no daemon |
| Schema apiVersion | **`skaffold/v4beta*`** | Highest `v4beta` your binary supports. Run `skaffold fix` to upgrade. Never `v2beta*` / `v1beta*` |
| Builder (Go) | **`ko`** | No Dockerfile, distroless static, reproducible |
| Builder (everything else) | **`docker`** with `useBuildkit: true` | `buildpacks` for polyglot/no-Dockerfile; `kaniko` for in-cluster; `jib` for JVM |
| Tagger | **`inputDigest`** (v2 default) or **`gitCommit`** for human-readable tags | Never `dateTime`, never `:latest` |
| Cluster target | **`kind`/`minikube`/`k3d`** local, remote context for shared dev | Skaffold auto side-loads images into local clusters — no registry needed |
| Push behavior | Auto-derived from kube context | Local cluster = no push. Override with `build.local.push:` only when needed |
| Registry namespace | **`--default-repo`** / `SKAFFOLD_DEFAULT_REPO` per environment | Never hardcode the registry in `skaffold.yaml` |
| Manifest renderer | **`helm`**, **`kustomize`**, or **`rawYaml`** under `manifests:` | Renderers and deployers are **separate** in v2 |
| Deployer | **`kubectl`** for almost everything | v2 idiom: render with helm/kustomize → apply with kubectl |
| Env variation | **Profiles** with `activation:` on `kubeContext`/`env`/`command` | One yaml + N profiles. Never `skaffold.<env>.yaml` files |
| File sync | **`sync.manual:`** with explicit `src`/`dest`/`strip` | The single biggest dev-loop accelerator |
| Logs | **Auto-tailed** in `dev`/`debug`/`run --tail` | No `kubectl logs -f` |
| Port forwarding | **`portForward:`** at top level | Auto-applies in `dev`/`debug` |
| Status checks | **On by default** — waits for Deployments/Pods Ready before tailing | Tune with `deploy.statusCheckDeadlineSeconds` |
| Cleanup | `--cleanup=true` (default for `run`) tears down on exit | `dev` cleans up on Ctrl-C |

## Canonical `skaffold.yaml` shape

Go service deployed via a Helm chart in a kind cluster, with file sync for templates:

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: my-service

build:
  local:
    push: false                                       # auto-true on non-local contexts
    useBuildkit: true
  tagPolicy:
    inputDigest: {}                                   # reproducible: tag = hash of build inputs
  artifacts:
    - image: ghcr.io/myorg/my-service                 # bare ref; --default-repo rewrites at runtime
      ko:
        main: ./cmd/server
        ldflags:
          - -s -w
          - -X main.version={{.GIT_COMMIT}}
        env:
          - CGO_ENABLED=0
        dependencies:
          paths:
            - "**/*.go"
            - go.mod
            - go.sum
      sync:
        manual:
          - src: "internal/templates/**/*.tmpl"
            dest: /app/templates
            strip: internal/

manifests:
  helm:
    releases:
      - name: my-service
        chartPath: ./charts/my-service
        valuesFiles:
          - charts/my-service/values.yaml

deploy:
  kubectl: {}

portForward:
  - resourceType: service
    resourceName: my-service
    namespace: default
    port: 8080
    localPort: 8080

profiles:
  - name: remote-dev
    activation:
      - kubeContext: dev-eks
    build:
      local:
        push: true
    deploy:
      kubectl:
        defaultNamespace: my-service-dev
```

Patterns at play: `apiVersion: skaffold/v4beta13` (or whatever's current — `skaffold fix` upgrades); `build.local.push` left unset so Skaffold derives from the kube context; bare image ref + `--default-repo` for per-user registry namespacing; `inputDigest` tagger for reproducibility; profile auto-activates on kube context match. See [builders.md](builders.md) for builder schemas, [sync.md](sync.md) for sync depth, [profiles.md](profiles.md) for the full profile/activation model.

## Inner-loop commands cheat sheet

```sh
skaffold dev                              # build + deploy + watch + sync + tail + port-forward — the main loop
skaffold dev --trigger=manual             # rebuild only when you press Enter
skaffold dev --no-prune                   # leave intermediate images on exit (faster restart)

skaffold debug                            # like dev, but rewrites entrypoints to launch the debugger:
                                          #   Go (dlv) :56268, Node :9229, Python (debugpy) :5678, Java :5005
                                          # IDE attaches via the auto-port-forward. See debug.md.

skaffold run                              # one-shot: build + deploy, no watch
skaffold run --tail                       # one-shot + log tail until Ctrl-C
skaffold delete                           # tear down what `run`/`dev` deployed

skaffold build                            # build artifacts only
skaffold build --file-output=tags.json    # dump image tags for downstream tooling

skaffold render                           # render manifests (stdout default)
skaffold render -o manifests.yaml --offline=true   # hermetic render for CI → file
skaffold apply manifests.yaml             # apply pre-rendered manifests (rarely needed; prefer GitOps)

skaffold init                             # bootstrap from existing Dockerfiles + manifests
skaffold init --generate-manifests        # also scaffold k8s manifests

skaffold verify                           # run post-deploy verification tests (see ci.md)
skaffold diagnose                         # dump the fully-resolved config + build/deploy plan
skaffold inspect <subcommand>             # programmatic introspection (modules, profiles, build-env, etc.)
skaffold fix                              # auto-upgrade an old apiVersion to the latest schema
```

`skaffold dev` and `skaffold debug` are the two you live in. Everything else is CI plumbing or maintenance.

## Image side-loading into local clusters

Skaffold auto-detects local cluster types and skips the registry round-trip:

| Cluster | Mechanism |
|---|---|
| **kind** | `kind load docker-image <tag>` |
| **minikube** | `minikube image load <tag>` |
| **k3d** | `k3d image import <tag>` |
| **Docker Desktop K8s** | Uses the host's docker daemon directly |

When this works, no registry needed. When it doesn't (remote cluster), set `--default-repo` / `SKAFFOLD_DEFAULT_REPO` per-user — never hardcode the registry in `skaffold.yaml`. `default-repo` rewrites every image ref at build/render time, so the same config works for every developer with their own dev registry namespace.

## Skaffold + GitOps (don't conflate them)

Skaffold runs locally on the developer's laptop or in CI. Flux/Argo CD run in the cluster and reconcile from git. **They serve different parts of the lifecycle and should not overlap.**

- **Dev:** `skaffold dev` against a dev cluster. Don't go through git.
- **CI:** `skaffold build` + `skaffold render --offline=true` to produce manifests. Push manifests to the GitOps repo. **Don't `skaffold apply` to production from CI.**
- **CD:** Flux/Argo CD picks up the new manifests from git and reconciles. (See the `flux` skill.)

If a cluster is reconciled by Flux/Argo CD, `skaffold dev`/`run` against it will fight the reconciler. Either use a separate dev cluster, or scope Skaffold to a namespace Flux doesn't watch. Full handoff patterns: [ci.md](ci.md).

## Universal don't / do

| Don't | Do |
|---|---|
| `apiVersion: skaffold/v2beta*` or `v1beta*` | `skaffold/v4beta*` — and run `skaffold fix` on inherited configs |
| Hardcode `image: ghcr.io/myorg/...` registry in `skaffold.yaml` | Bare image ref + `--default-repo` / `SKAFFOLD_DEFAULT_REPO` per environment |
| `tagPolicy: { dateTime: {} }` or `:latest` | `inputDigest: {}` for reproducibility, or `gitCommit` for readability |
| Rebuild on every template/static file change | `sync.manual:` the files into the running container ([sync.md](sync.md)) |
| `kubectl logs -f` and `kubectl port-forward` by hand | Skaffold auto-tails and auto-forwards from `portForward:` |
| `kubectl debug` ephemeral containers for breakpoint debugging | `skaffold debug` ([debug.md](debug.md)) |
| `skaffold.dev.yaml` / `skaffold.prod.yaml` separately | One `skaffold.yaml` + `profiles:` ([profiles.md](profiles.md)) |
| Profile activated only by `--profile=foo` flag | `activation:` on `kubeContext`/`env`/`command` |
| `skaffold deploy` (legacy v1 combined render+apply) | `skaffold run` for local one-shot, `render` + `apply` for CI/CD ([ci.md](ci.md)) |
| `local.push: true` hardcoded everywhere | Let Skaffold derive from kube context |
| Skip `skaffold init` and hand-write the first config | `skaffold init` → sensible first draft → edit |
| `skaffold render --offline=false` in CI | `--offline=true` for hermetic, deterministic output |
| `skaffold apply` to push to production from CI | Render in CI, commit to GitOps repo, let Flux/Argo CD reconcile |
| `skaffold dev` against a Flux-reconciled cluster's namespace | Separate dev cluster, or a namespace Flux doesn't watch |
| Debug "why isn't this updating" by re-running things | `skaffold diagnose` first — dumps the fully-resolved plan |
| One `skaffold.yaml` with 12 services tangled together | Multi-config (`requires:`) — one config per service ([ci.md](ci.md)) |

## When Skaffold isn't the right tool

- **Production deploy / continuous delivery:** GitOps (Flux, Argo CD). Skaffold's job ends when the manifests are in git.
- **Pure manifest templating across many environments:** Helmfile or Kustomize directly — Skaffold's profiles handle a handful of variations well, not dozens.
- **Local-only dev with no cluster:** Tilt is a sibling tool with a more interactive UI and a richer DSL. Skaffold has more polish for the CI handoff; Tilt has more polish for "I live in this for 8 hours a day."
- **Multi-cluster fan-out from one config:** Skaffold's `requires:` helps for monorepos, but for fanning the same release to N clusters use the GitOps layer.

Skaffold is great at: the dev loop, the build step in CI, the render step in CI, and bridging "I have Dockerfiles + manifests" to "I can iterate on this in a real cluster in seconds."

## After you change anything in this skill

Run `dot install` to refresh the symlinks across all three tools. No restart needed.
