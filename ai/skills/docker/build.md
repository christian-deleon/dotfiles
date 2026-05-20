# Build — buildx, bake, multi-platform, cache

`docker build` has been a thin shim over `docker buildx` since Engine 23.0 — BuildKit is the only build backend, and buildx is the modern CLI. For one-off image builds, `docker buildx build` is enough. For anything multi-target (multiple images, matrix builds, complex cache wiring), the answer is **bake**: HCL config that drives BuildKit and runs targets in parallel with shared cache.

## buildx mental model

```
┌─ buildx (client CLI) ─┐         ┌────── builder instance ──────┐
│                       │  ──────►│  BuildKit daemon              │
│  docker buildx build  │         │   - Dockerfile interpreter    │
│  docker buildx bake   │         │   - Cache backends            │
│  docker buildx ls     │         │   - Multi-platform runners    │
└───────────────────────┘         └───────────────────────────────┘
```

`buildx` is the client. The **builder instance** is where BuildKit actually runs. There are several drivers — pick by use case.

## Builder drivers

| Driver | Where BuildKit runs | Multi-platform | Cache export | When |
|---|---|---|---|---|
| **`docker`** | The Docker daemon's bundled BuildKit | No | Inline only | Only for trivial local builds; auto-default |
| **`docker-container`** | A BuildKit container the daemon manages | Yes (via QEMU) | All backends | **The modern local default.** `docker buildx create --use --driver docker-container` |
| **`kubernetes`** | Pods (one StatefulSet per arch for native multi-arch) | Yes, native | All backends | CI clusters, shared build infrastructure, native arm64 without QEMU |
| **`remote`** | A BuildKit daemon you run separately | Yes | All backends | Self-hosted beefy build host shared by a team |
| **`cloud`** (Docker Build Cloud) | Docker-managed remote builders | Yes, native | Shared cache across team | When you can't run native arm64 and want a managed option |

Set up the modern local default once:

```bash
docker buildx create --name builder --driver docker-container --use --bootstrap
docker buildx ls
```

The legacy `docker` driver doesn't support multi-platform, advanced cache backends, or attestations — switch off it.

## `docker buildx build` — the single-image case

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag ghcr.io/acme/api:v1.2.3 \
  --tag ghcr.io/acme/api:latest \
  --build-arg VERSION=1.2.3 \
  --secret id=github_token,env=GITHUB_TOKEN \
  --ssh default \
  --cache-from type=registry,ref=ghcr.io/acme/api:buildcache \
  --cache-to   type=registry,ref=ghcr.io/acme/api:buildcache,mode=max \
  --attest type=sbom \
  --attest type=provenance,mode=max \
  --label org.opencontainers.image.source=https://github.com/acme/api \
  --push \
  .
```

Flags worth knowing:

| Flag | What |
|---|---|
| `--platform` | Comma-separated target platforms; `linux/amd64,linux/arm64` is the 2026 minimum |
| `--push` / `--load` / `--output` | Push to registry / load into local docker / write to filesystem |
| `--cache-from` / `--cache-to` | Cache import/export (see backends below) |
| `--attest type=sbom` | Attach an SPDX SBOM as an OCI referrer |
| `--attest type=provenance,mode=max` | Attach SLSA v1 provenance; `mode=min` is the default |
| `--secret id=…,src=…` / `--secret id=…,env=…` | Build secrets (matches Dockerfile `--mount=type=secret,id=…`) |
| `--ssh default` / `--ssh <key>=<path>` | Forward SSH agent for `--mount=type=ssh` |
| `--call=check` | Run BuildKit's Dockerfile checks; doesn't produce an image |
| `--call=outline` / `--call=targets` | List build args / stages without building |
| `--metadata-file out.json` | Write digest, descriptor, refs to a file (capture for downstream signing) |

`--load` only works for a single platform — multi-platform images must `--push` because the local image store has no native manifest-list support.

## Multi-platform strategy

`linux/amd64,linux/arm64` is the floor in 2026. Apple Silicon laptops, Graviton/Ampere cloud, Raspberry Pi 5 — arm64 is a first-class production target.

| Strategy | How | Trade-off |
|---|---|---|
| **Native multi-arch builders** | Kubernetes driver with arm64 nodes; or GitHub Actions `ubuntu-24.04-arm` runners; or a fleet of native builders behind a remote driver | Fastest; requires arm64 hardware |
| **Cross-compile in the Dockerfile** | `--platform=$BUILDPLATFORM` on the build stage; compiler emits target arch | Almost as fast as native; only works for languages that cross-compile cleanly (Go, Rust, C with the right toolchain) |
| **QEMU emulation** | The `docker-container` driver auto-registers `binfmt_misc` handlers for foreign arches | Zero Dockerfile changes; 5-10x slower for CPU-heavy builds |

Cross-compile pattern (Go example) — see [dockerfile.md](dockerfile.md) for the full skeleton:

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.26 AS build
ARG TARGETOS TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=bind,source=.,target=/src \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /out/app ./cmd/app
```

QEMU is "free" but slow. Cross-compile when the language supports it (Go, Rust); fall back to QEMU when it doesn't (Python, Node).

## Cache backends

BuildKit's `--cache-from`/`--cache-to` decouple build cache from build location. The major backends:

| Backend | Spec | Use |
|---|---|---|
| **`type=inline`** | `--cache-to type=inline` | Embeds cache in the pushed image. Free, no extra registry path. Only works with `--push`. |
| **`type=registry`** | `--cache-to type=registry,ref=ghcr.io/acme/api:buildcache,mode=max` | Cache as a separate registry tag. **Most teams' default.** `mode=max` exports cache for every stage; `mode=min` only exports the final stage. |
| **`type=gha`** | `--cache-to type=gha,mode=max --cache-from type=gha` | GitHub Actions cache (10 GB per repo). Best for GHA pipelines; requires `actions/cache`-style permissions. |
| **`type=s3`** | `--cache-to type=s3,region=us-east-1,bucket=acme-buildcache,mode=max` | S3-backed. Use for big monorepo builds where registry cache hits size limits. |
| **`type=local`** | `--cache-to type=local,dest=./cache,mode=max --cache-from type=local,src=./cache` | Filesystem cache. Use in CI runners that persist the cache dir across jobs. |

`mode=max` exports cache for every intermediate stage in a multi-stage build — required for the cache to be useful when the final stage is a tiny distroless image. `mode=min` (default) only exports the final stage's cache, which is almost never what you want.

GHA-specific gotcha: the GHA cache backend writes to the per-repo cache, which has a 10 GB cap and per-ref eviction rules. For monorepos, use registry cache with a shared tag instead.

## `docker buildx bake` — multi-target builds

Bake is the declarative front-end. One config file, multiple targets, parallel builds, shared cache, variables, inheritance. HCL is preferred (richer than JSON or YAML).

```hcl
# docker-bake.hcl

variable "REGISTRY" { default = "ghcr.io/acme" }
variable "TAG"      { default = "dev" }
variable "PLATFORMS" {
  default = "linux/amd64,linux/arm64"
}

# Common settings inherited by every target
target "_common" {
  context    = "."
  platforms  = split(",", PLATFORMS)
  cache-from = ["type=registry,ref=${REGISTRY}/buildcache"]
  cache-to   = ["type=registry,ref=${REGISTRY}/buildcache,mode=max"]
  attest = [
    "type=sbom",
    "type=provenance,mode=max",
  ]
  labels = {
    "org.opencontainers.image.source"  = "https://github.com/acme/services"
    "org.opencontainers.image.version" = "${TAG}"
  }
}

target "api" {
  inherits   = ["_common"]
  dockerfile = "api/Dockerfile"
  tags       = ["${REGISTRY}/api:${TAG}"]
}

target "worker" {
  inherits   = ["_common"]
  dockerfile = "worker/Dockerfile"
  tags       = ["${REGISTRY}/worker:${TAG}"]
}

# Default group — what `docker buildx bake` (no args) builds
group "default" {
  targets = ["api", "worker"]
}

# CI matrix expansion
target "release" {
  inherits = ["_common"]
  name     = "release-${svc}"
  matrix   = { svc = ["api", "worker"] }
  dockerfile = "${svc}/Dockerfile"
  tags     = ["${REGISTRY}/${svc}:${TAG}"]
}
```

Run:

```bash
docker buildx bake                              # build the default group
docker buildx bake api                          # build one target
docker buildx bake --print                      # resolved JSON plan (no build)
docker buildx bake --push api worker            # push after build
TAG=v1.2.3 docker buildx bake --push release    # variables via env
docker buildx bake --set api.platforms=linux/amd64    # override field
```

Key features:

- **`inherits`** — DRY common config into a base target.
- **`matrix`** — expand a target into N targets with one field varying.
- **`group`** — named bundles of targets; the default group runs when no args.
- **`--print`** — emit the resolved plan as JSON; never executes. Critical for debugging.
- **`--set`** — CLI overrides for any field; useful in CI.

## Bake + Compose interop

Bake can read `compose.yaml` and treat each `services.<name>.build` block as a target:

```bash
docker buildx bake --file compose.yaml api
```

Useful when the same image definition needs to run via both `docker compose up` (locally) and `bake` (CI). The `x-bake:` extension on a service injects bake-only fields:

```yaml
services:
  api:
    image: ghcr.io/acme/api:${TAG:-dev}
    build:
      context: ./api
      x-bake:
        platforms: [linux/amd64, linux/arm64]
        cache-from: [type=registry,ref=ghcr.io/acme/api:buildcache]
        cache-to:   [type=registry,ref=ghcr.io/acme/api:buildcache,mode=max]
        attest:
          - type=sbom
          - type=provenance,mode=max
        tags:
          - ghcr.io/acme/api:${TAG:-dev}
          - ghcr.io/acme/api:latest
```

Many teams describe images once in Compose and let bake drive CI.

## CI patterns — GitHub Actions

The canonical pipeline for multi-platform signed images with cache and attestations:

```yaml
name: build
on:
  push:
    tags: ["v*"]
  pull_request:

permissions:
  contents: read
  packages: write
  id-token: write          # required for keyless cosign signing

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up buildx
        uses: docker/setup-buildx-action@v3

      - name: Hadolint
        uses: hadolint/hadolint-action@v3

      - name: BuildKit checks
        run: docker buildx build --call=check .

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Bake
        uses: docker/bake-action@v5
        with:
          push: true
          set: |
            *.cache-from=type=gha
            *.cache-to=type=gha,mode=max
            *.tags=ghcr.io/${{ github.repository }}:${{ github.sha }}

      - name: Install cosign
        uses: sigstore/cosign-installer@v3

      - name: Sign images (keyless)
        env:
          DIGEST: ${{ steps.bake.outputs.metadata }}
        run: |
          # Pull digests from bake's metadata JSON and sign each
          for img in $(jq -r '.[] | select(."containerimage.digest") | "\(.["image.name"])@\(.["containerimage.digest"])"' <<<"$DIGEST"); do
            cosign sign --yes "$img"
          done
```

Notes:

- **Native arm64 runners** (`ubuntu-24.04-arm`) eliminate QEMU. Use them when available — multi-platform builds finish in minutes instead of hours.
- **`id-token: write`** is required for Sigstore keyless signing via OIDC.
- **`type=gha`** cache backend writes to the per-repo Actions cache.
- **`bake-action`** is the official Action; it understands `docker-bake.hcl` and Compose `build:` blocks.

## `imagetools` — manifest list manipulation

```bash
# Inspect a multi-arch image
docker buildx imagetools inspect ghcr.io/acme/api:v1.2.3
docker buildx imagetools inspect --format '{{ json . }}' ghcr.io/acme/api:v1.2.3
docker buildx imagetools inspect --format '{{ json .SBOM }}' ghcr.io/acme/api:v1.2.3
docker buildx imagetools inspect --format '{{ json .Provenance }}' ghcr.io/acme/api:v1.2.3

# Stitch existing single-arch images into a new manifest list
docker buildx imagetools create \
  --tag ghcr.io/acme/api:v1.2.3 \
  ghcr.io/acme/api-build-amd64:v1.2.3 \
  ghcr.io/acme/api-build-arm64:v1.2.3

# Re-tag without re-pulling layers
docker buildx imagetools create \
  --tag ghcr.io/acme/api:latest \
  ghcr.io/acme/api:v1.2.3
```

`imagetools create` operates entirely on the registry — no pull, no rebuild. Useful for promotion pipelines that build once and re-tag through environments.

## BuildKit checks at build time

```bash
docker buildx build --call=check .
docker buildx bake --call=check
```

Runs the in-tree Dockerfile linter (rules: `JSONArgsRecommended`, `SecretsUsedInArgOrEnv`, `LegacyKeyValueFormat`, `WorkdirRelativePath`, `FromAsCasing`, …). Fast, no extra tool. **Run this in CI before the actual build.**

Pair with **hadolint** for the broader `DL****` ruleset plus embedded ShellCheck on `RUN` blocks. The two overlap but each catches things the other misses — run both.

## Don't / Do — build

| Don't | Do |
|---|---|
| `docker build .` (legacy builder) | `docker buildx build .` (modern, BuildKit) |
| `DOCKER_BUILDKIT=1 docker build .` | `docker buildx build .` — the env var is for the legacy CLI |
| `docker` driver for serious work | `docker buildx create --driver docker-container --use` |
| `--platform linux/amd64` only | `--platform linux/amd64,linux/arm64` minimum |
| `mode=min` cache export (default) | `mode=max` — export every stage's cache |
| `--cache-from` without `--cache-to` | Both — cache import without export gets stale fast |
| Building each image with a separate `buildx build` invocation in CI | `docker buildx bake` — parallel, shared cache, one config |
| Hand-maintained matrix shell loops | `target { matrix = { svc = [...] } }` |
| Multi-arch builds without an attestation step | `--attest type=sbom --attest type=provenance,mode=max` |
| Pulling Docker Hub anonymously in CI | Authenticate (`docker login`) or use a pull-through cache |
| `--load` for multi-platform builds | `--push` (manifest lists can't live in the local store) |
| `docker history` to "debug" a layer | `docker buildx imagetools inspect --format '{{ json . }}'` plus the BuildKit history API |
| Mixing `docker buildx build` and `docker buildx bake` in the same pipeline | Pick one; bake is the multi-target answer |
