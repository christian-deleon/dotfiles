# Skaffold Builders

Skaffold supports a builder per artifact, declared under `build.artifacts[].<builder>:`. Two artifacts in the same `Config` can use different builders — a Go API with `ko`, a frontend with `docker`, a JVM job with `jib`, all under one `build.artifacts:` list.

This file is the per-builder deep dive. For decision trees and the default-pick table, see `SKILL.md`. For build *environment* selection (`local` vs in-cluster vs Google Cloud Build), see [advanced.md](advanced.md).

## Picking a builder

| Builder | Default for | Why |
|---|---|---|
| **`ko`** | Go services | No Dockerfile, distroless static, reproducible, fast. The right answer for Go in 2026. |
| **`docker`** | Anything with a meaningful Dockerfile | Lingua franca. `useBuildkit: true` is mandatory. |
| **`buildpacks`** | Polyglot / no-Dockerfile | Cloud-Native Buildpacks; slow first build, fast incremental. |
| **`kaniko`** | In-cluster, no docker daemon | Unprivileged CI runners; sandboxed build envs. |
| **`jib`** | JVM (Maven/Gradle) | Skips Dockerfile, layers JARs cleverly. Fast iteration for Spring/Quarkus. |
| **`bazel`** | Existing Bazel monorepo | Wires `bazel build //target:image` into Skaffold. |
| **`custom`** | Anything else | Shell script produces the image; you tell Skaffold what tag it landed at. |

Reach for the **least exotic builder that fits**. Custom is the escape hatch, not the default.

## `ko` — Go services

```yaml
artifacts:
  - image: ghcr.io/myorg/my-service
    ko:
      fromImage: cgr.dev/chainguard/static:latest    # base; default is distroless-static
      main: ./cmd/server                              # path to the main package
      dir: .                                          # module dir; defaults to artifact context
      ldflags:
        - -s -w                                       # strip debug info (production)
        - -X main.version={{.GIT_COMMIT}}             # inject build-time vars
      flags:
        - -trimpath                                   # reproducible paths in stack traces
      env:
        - CGO_ENABLED=0
        - GOFLAGS=-mod=readonly
      labels:
        org.opencontainers.image.source: https://github.com/myorg/my-service
      platforms:                                      # cross-arch — see "Cross-architecture" below
        - linux/amd64
        - linux/arm64
      dependencies:
        paths:
          - "**/*.go"
          - go.mod
          - go.sum
        ignore:
          - "**/*_test.go"
```

**Gotchas:**

- `main:` is a Go *package path*, not a file. `./cmd/server`, not `./cmd/server/main.go`.
- `KO_DOCKER_REPO` env var lets `ko` push to a registry directly; Skaffold sets this for you from `--default-repo`. Don't set it manually inside the config.
- `ldflags` use Go template syntax — `{{.GIT_COMMIT}}` resolves via Skaffold's tagger context.
- For debug builds (Delve breakpoints landing on correct lines): drop `-s -w` and add `flags: [-gcflags=all=-N -l]`. Do this in a `debug` profile.
- `fromImage:` accepts any base — Chainguard `static`, distroless static, scratch. Don't pull from random `alpine:latest` unless you have a reason.

## `docker` — Dockerfile-based

```yaml
artifacts:
  - image: ghcr.io/myorg/my-api
    docker:
      dockerfile: Dockerfile                          # default
      target: production                              # multi-stage target
      buildArgs:
        VERSION: "{{.GIT_COMMIT}}"
        BUILDKIT_INLINE_CACHE: "1"                    # writes cache metadata into the image
      cacheFrom:
        - ghcr.io/myorg/my-api:cache                  # pull this as a cache source
      secrets:
        - id: npmrc
          src: ~/.npmrc                               # mount at build time without leaking into layers
      ssh:
        - id: default
          src: ~/.ssh/id_ed25519                      # for `git clone` from private repos in RUN steps
      network: host                                   # rarely needed; default is bridge
      noCache: false
      pullParent: true                                # always re-pull base image
    dependencies:
      paths:
        - "src/**"
        - package.json
        - package-lock.json
        - Dockerfile
      ignore:
        - "**/*.test.ts"
```

`build.local.useBuildkit: true` is required for `secrets:`, `ssh:`, `cacheFrom:` and inline cache to actually work. Set it once at the `build.local` level, not per-artifact.

## `buildpacks` — Cloud-Native Buildpacks

```yaml
artifacts:
  - image: ghcr.io/myorg/web
    buildpacks:
      builder: paketobuildpacks/builder-jammy-base:latest
      buildpacks:
        - paketo-buildpacks/nodejs
        - paketo-buildpacks/npm-start
      env:
        - BP_NODE_VERSION=20.*
        - NODE_ENV=production
      trustBuilder: true                              # required for unverified third-party builders
      projectDescriptor: project.toml                 # CNB project descriptor; defaults to `project.toml`
    sync:
      auto: true                                      # buildpacks know what to sync — use it
```

`buildpacks` + `sync.auto: true` is the killer combo for inner-loop on Node/Python/Ruby/Go. The builder declares which paths can be synced; Skaffold just does it. No `manual:` rules to maintain.

## `kaniko` — in-cluster Docker-less builds

Only meaningful when `build.cluster:` is set (kaniko runs as a pod). Common for CI runners that can't grant a docker socket.

```yaml
build:
  cluster:
    namespace: skaffold-builds
    pullSecretName: gcr-pull
    dockerConfig:
      secretName: docker-config-json                  # for push auth
  artifacts:
    - image: ghcr.io/myorg/svc
      kaniko:
        dockerfile: Dockerfile
        cache:
          repo: ghcr.io/myorg/svc-kaniko-cache       # remote layer cache
          ttl: 168h
        buildArgs:
          VERSION: "{{.GIT_COMMIT}}"
        env:
          - name: AWS_REGION
            value: us-east-1
        contextSubPath: services/svc                  # for monorepos
        flags:
          - --snapshot-mode=redo                      # faster snapshots on big trees
          - --use-new-run
```

Three things that bite people:

- Push auth is **`build.cluster.dockerConfig.secretName`**, not per-artifact. The secret must contain a `config.json` key with standard docker-style auth.
- `cache.repo:` is critical for any non-trivial Dockerfile. Without it, kaniko rebuilds everything every time.
- `kaniko` doesn't side-load into kind/minikube — it pushes. Use it for remote clusters or CI.

## `jib` — JVM (Maven/Gradle)

```yaml
artifacts:
  - image: ghcr.io/myorg/spring-svc
    jib:
      project: spring-svc                             # Gradle subproject or Maven module
      type: gradle                                    # `gradle` or `maven`; defaults from build files present
      args:
        - --offline
        - -PdebugPort=5005
      baseImage: gcr.io/distroless/java17-debian12
```

Jib's superpower is JAR layering — your fat-jar's dependency layers cache separately from your application classes, so a one-character change to your code only rebuilds the top layer. Faster than `docker build` for any non-trivial JVM app.

## `bazel`

```yaml
artifacts:
  - image: ghcr.io/myorg/api
    bazel:
      target: //services/api:image.tar               # must be a tarball-producing rule
      args:
        - --platforms=@io_bazel_rules_go//go/toolchain:linux_amd64
```

Bazel artifacts produce a tarball that Skaffold then loads/pushes. The `target:` must end in `.tar` (or be a `container_image` rule that produces one).

## `custom` — escape hatch

```yaml
artifacts:
  - image: ghcr.io/myorg/weird
    custom:
      buildCommand: ./scripts/build.sh
      dependencies:
        paths:
          - "src/**"
          - scripts/build.sh
```

Skaffold sets these env vars in the script's environment:

| Env var | What |
|---|---|
| `IMAGE` | The fully-qualified image ref Skaffold expects you to produce |
| `PUSH_IMAGE` | `true` if Skaffold wants you to push, `false` if it'll side-load |
| `BUILD_CONTEXT` | Absolute path to the artifact context |
| `PLATFORMS` | Comma-separated platform list (when cross-building) |
| `SKAFFOLD_RUN_ID` | The current Skaffold invocation ID; useful for tagging caches |

Your script must produce an image at `$IMAGE` (and push it if `$PUSH_IMAGE=true`). Exit non-zero on failure. This is the right place to wire Nix builds, scratch OCI builds, or anything Skaffold doesn't natively support — but don't reach for `custom` just because `docker`/`ko`/`buildpacks` feels foreign.

## Cross-architecture builds

The standard case: M-series Mac → amd64 cluster (or vice versa). Without explicit platform, you build for the host arch and pods crash-loop on the wrong arch with no clear error.

| Builder | How |
|---|---|
| `ko` | `ko.platforms: [linux/amd64, linux/arm64]` — produces a multi-arch manifest list |
| `docker` | Requires buildx; set `platforms: [linux/amd64, linux/arm64]` at the artifact level. Skaffold uses buildx under the hood when multiple platforms are specified |
| `buildpacks` | `platforms:` — but most paketo builders are still amd64-only as of 2026; check before relying on it |
| `kaniko` | Single-platform per build; run multiple kaniko builds, then `docker manifest create` |
| `jib` | `jib.platforms:` — JVM is arch-agnostic, this mostly affects the base image manifest |

For local dev against a remote arm64 cluster from an amd64 laptop (or the reverse), pin the single target platform — multi-arch is for production CI builds, not the inner loop.

```yaml
profiles:
  - name: arm-cluster
    activation:
      - kubeContext: gke_myorg_us-east1_arm-cluster
    patches:
      - op: add
        path: /build/artifacts/0/ko/platforms
        value: [linux/arm64]
```

## Image dependencies (artifact ordering)

When one artifact builds *on top of* another (a shared base image consumed by N services), declare the dependency so Skaffold builds them in order:

```yaml
artifacts:
  - image: ghcr.io/myorg/base
    docker:
      dockerfile: base.Dockerfile

  - image: ghcr.io/myorg/service-a
    requires:
      - image: ghcr.io/myorg/base
        alias: BASE                                   # available as ARG BASE in the Dockerfile
    docker:
      dockerfile: Dockerfile                          # uses ARG BASE; ARG BASE then `FROM $BASE`
      buildArgs:
        BASE: "{{.BASE}}"                             # injected by Skaffold from the resolved tag
```

Without `requires:`, Skaffold builds the artifacts in parallel and `service-a` references a stale (or missing) base tag. With `requires:`, `base` is built first, its tag is bound to the `BASE` template var, and `service-a` builds against the just-produced base.

This is also the way to share a built base across builders — `base` could be `ko`, `service-a` could be `docker`.

## `dependencies.paths` — narrow the trigger surface

The default ("rebuild this artifact if anything under its context changes") is wrong almost always. Always narrow:

| Stack | Reasonable `paths:` |
|---|---|
| Go | `**/*.go`, `go.mod`, `go.sum` |
| Node | `src/**`, `package.json`, `package-lock.json`, `tsconfig.json` |
| Python | `src/**/*.py`, `pyproject.toml`, `uv.lock` (or `poetry.lock`) |
| Java (Maven) | `src/**/*.java`, `pom.xml` |
| Rust | `src/**/*.rs`, `Cargo.toml`, `Cargo.lock` |

Pair with `ignore:` to skip generated files, test files (if tests don't need to rebuild the image), and editor swap files.

## Build environment selection

`build.local:` (default) builds on the host docker daemon. Two alternatives:

- `build.cluster:` — runs kaniko pods in a target cluster. Required when no docker daemon is available.
- `build.googleCloudBuild:` — submits builds to GCB. Useful when you want the build to happen close to a GCP-hosted registry, or when local resources are constrained.

Pick one; you can't mix. For details (auth, network, machine types, cache buckets), see [advanced.md](advanced.md).

## Don't / Do

| Don't | Do |
|---|---|
| `docker` builder for a Go service | `ko` — no Dockerfile, distroless, faster |
| Single-platform image deployed to wrong-arch cluster | Pin `platforms:` per builder; profile per cluster arch |
| `cacheFrom` without `useBuildkit: true` | Enable buildkit globally (`build.local.useBuildkit: true`) |
| Hardcode `KO_DOCKER_REPO` in `skaffold.yaml` | Let `--default-repo` / `SKAFFOLD_DEFAULT_REPO` set it per user |
| `kaniko` without `cache.repo:` on a non-trivial Dockerfile | Always configure a remote layer cache |
| `custom` builder for things `docker`/`ko` can do | Use the native builder; reserve `custom` for genuinely off-piste |
| Build base + dependent services in parallel | `requires:` on the dependent → Skaffold orders the builds |
| `sync.infer:` against a multi-stage Dockerfile | `sync.manual:` (see [sync.md](sync.md)) |
| Default `dependencies` (whole context) | Narrow `paths:` + `ignore:` so edits don't over-rebuild |
| `:latest` tag in `buildArgs` | Resolved digest (`{{.IMAGE_DIGEST_*}}`) or explicit version |
