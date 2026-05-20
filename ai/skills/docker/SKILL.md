---
name: docker
description: Modern Docker — Dockerfile authoring, BuildKit/buildx/bake, Compose v2, base-image strategy, and the image supply chain (signing, SBOM, scanning). Use when editing `Dockerfile`, `compose.yaml`, `docker-bake.hcl`, or for prompts about containers, multi-arch, distroless, Chainguard, cosign, Trivy, Compose. Defers k8s workloads to `kubernetes`, Helm to `helm`, inner-loop dev to `skaffold`.
compatibility: opencode
---

# Docker

Docker is the tooling around the OCI container format — a Dockerfile is a build recipe that BuildKit compiles into a content-addressed image, an image is a stack of read-only filesystem layers plus a JSON config, and a container is a process running in a namespaced view of that filesystem. The modern toolchain (BuildKit, buildx, bake, cosign, Compose v2) treats every artifact as data: addressable by digest, signed, attested, and reproducible. The work isn't writing a Dockerfile; it's choosing the right base, caching the right layers, signing the result, and orchestrating the runtime in the right place. Production multi-host orchestration belongs to Kubernetes — Docker stops at the image and the single-host runtime.

The most common AI failure mode is producing 2019-era Dockerfiles and compose files: `FROM ubuntu:latest`, `apt-get update` and `apt-get install` in separate `RUN` layers, `COPY package.json` then `RUN npm install` to "fake cache layering" instead of using mount caches, `ARG TOKEN=…` for secrets, no `USER` line, `:latest` tags in production manifests, `version: '3.8'` at the top of compose files, hyphenated `docker-compose` in CI, bind-mounting the source tree where `develop.watch` would do, `depends_on:` as a plain list paired with `sleep 30` in the entrypoint, and no signing/SBOM/provenance anywhere. None of those are syntax errors. All are smells in 2026.

## Decision tree — read the file that matches the task

| User wants to… | Read |
|---|---|
| Write or fix a `Dockerfile` — multi-stage, cache mounts, build secrets, multi-platform, `USER`, security | [dockerfile.md](dockerfile.md) |
| Pick a base image — distroless variants, debian-slim, alpine (musl traps), scratch, Chainguard | [base-images.md](base-images.md) |
| Write or fix a `compose.yaml` — services, networks, volumes, watch, healthchecks, profiles, include | [compose.md](compose.md) |
| Build images — `buildx`, `bake`, multi-platform, cache backends, CI patterns | [build.md](build.md) |
| Supply chain — signing, SBOM, provenance, scanning, admission verification, registry hygiene | [supply-chain.md](supply-chain.md) |

Language-specific Dockerfile patterns (cross-compile flags, cache mount targets, distroless runtime choice) live in the language skill that owns the toolchain — see the table below.

## Canonical Dockerfile examples — where to find them

Each language skill owns the reference Dockerfile for its toolchain. Cross-reference instead of duplicating — when you fix a pattern, fix it once at the source.

| Language | Reference Dockerfile | Skill |
|---|---|---|
| Go | distroless `static-debian12:nonroot` with cross-compiled binary, Go module + build cache mounts | [`go` skill → `project-layout.md`](../go/project-layout.md) |
| Python | distroless `python3-debian12:nonroot` with `uv sync --frozen --no-dev` and a pip cache mount | [`python` skill → `packaging.md`](../python/packaging.md) |
| Rust | distroless `cc-debian12:nonroot` (or `static` with musl) with cargo registry + target cache mounts | [`rust` skill → `packaging.md`](../rust/packaging.md) |

The universal patterns (`# syntax=docker/dockerfile:1`, `COPY --link`, `USER 65532:65532`, `--platform=$BUILDPLATFORM`, multi-stage shape) live in [dockerfile.md](dockerfile.md) — the language skills inherit those and only add the toolchain-specific bits (cache mount targets, `CGO_ENABLED=0`, `cargo build --release --target …`, `uv sync` flags).

## What this skill defers

This is a deliberately narrow skill — image build and single-host runtime only. Adjacent concerns belong to other skills:

| Concern | Defer to |
|---|---|
| Kubernetes workloads — Deployments, Services, probes, RBAC, NetworkPolicy | **`kubernetes`** skill |
| Helm chart authoring and consumption | **`helm`** skill |
| In-cluster inner-loop dev (file sync into a running pod, port-forward, debug) | **`skaffold`** skill |
| GitOps reconciliation (Flux `HelmRelease`, `Kustomization`) | **`flux`** skill |
| EKS / ECR / Karpenter / IAM | **`aws`** skill |
| Language-specific build tools that skip Dockerfile entirely | language skills |

If you find yourself writing Kubernetes manifests, Helm templates, a `HelmRelease`, or a `skaffold.yaml` here — stop, switch skills.

## The default stack

| Concern | Default | Notes |
|---|---|---|
| Dockerfile frontend | `# syntax=docker/dockerfile:1` | Floats to the current `1.x` frontend; ships independent of the engine |
| Builder | **`docker buildx`** with **`docker-container`** driver | `docker build` is a thin shim over buildx since Engine 23.0; legacy builder is dead |
| Caching | **`RUN --mount=type=cache,target=…`** | Replaces the "copy lockfile first" idiom |
| Build secrets | **`RUN --mount=type=secret,id=…`** | Never `ARG`/`ENV` — they persist in layer history |
| Base image | **`gcr.io/distroless/<runtime>:nonroot`** for production; **`debian:12-slim`** when a shell/package manager is needed; **`scratch`** for static binaries | See [base-images.md](base-images.md) for the full ranking |
| User | **`USER 65532:65532`** (`:nonroot` UID) before `CMD` | Never root |
| Image refs | **Digest pin** (`image@sha256:…`) in production manifests | Renovate/Dependabot bumps; `:latest` is never fine |
| Platforms | **`linux/amd64,linux/arm64`** minimum | Cross-compile when the language supports it; QEMU as fallback |
| Build orchestration | **`docker buildx bake`** (HCL) for anything multi-target | One target per image, groups for matrices |
| Compose CLI | **`docker compose`** (v2 plugin) | Hyphenated `docker-compose` (v1, Python) is dead |
| Compose filename | **`compose.yaml`** | Drop the `version:` field — obsolete in the Compose Spec |
| Compose dev loop | **`docker compose watch`** + `develop.watch:` block | Over bind-mounting the source tree |
| Compose composition | **`include:`** for reusable slices; **`compose.override.yaml`** for env tweaks | `extends:` only for true service inheritance |
| Startup order | **`depends_on.condition: service_healthy`** + real `healthcheck:` | Use `start_interval` for faster ready detection |
| Compose secrets | **`secrets:`** top-level + per-service, mounted at `/run/secrets/<name>` | Never plaintext in `environment:` |
| Resource limits | **`deploy.resources.{limits,reservations}`** | Legacy `mem_limit`/`cpus` is shorthand only |
| Signing | **Cosign keyless** via Sigstore (OIDC → Fulcio → Rekor) | Notary v1 / Docker Content Trust is dead |
| Attestations | **`--attest type=sbom --attest type=provenance,mode=max`** | Target SLSA L2; `mode=min` provenance is on by default in buildx |
| Scanning | **Trivy** in CI (or **Grype** for speed + SARIF); **Docker Scout** for the dev UX | Pick one CI scanner |
| Admission | **Kyverno `verifyImages`** | Bundles the Cosign Go library; replaces the Connaisseur stack |
| Linting | **hadolint** (Dockerfile) + **`docker buildx build --call=check`** (BuildKit checks) | Both in CI |
| Compose for prod? | **No.** Dev, CI integration tests, single-host only — defer to `kubernetes`/`flux` | Compose is the inner loop |
| Desktop alternative | **OrbStack** (macOS), **Rancher Desktop** (cross-platform), **Podman** (Linux) | Docker Desktop only if licensed |

## Universal rules

1. **Pin the Dockerfile frontend.** Every Dockerfile starts with `# syntax=docker/dockerfile:1`. It ships independently of the daemon, so older engines still get new syntax (heredocs, `--mount`, `COPY --link`, `ADD --checksum`, `--exclude`).
2. **Multi-stage every time.** A build stage with the toolchain, a final stage with only the artifact. Never ship the compiler, package manager, or build deps in the final image.
3. **Cache mounts over layer-cache tricks.** `RUN --mount=type=cache,target=…` is the modern caching primitive. The "copy lockfile, install, then copy source" idiom is obsolete — it caches at the granularity of the lockfile diff; cache mounts cache at the granularity of each individual package.
4. **Secrets via `--mount=type=secret`, never `ARG`/`ENV`.** Build args and env vars persist in layer history and are visible to anyone who pulls the image.
5. **`USER <non-root>` before `CMD`.** Production images run as a non-root user. `:nonroot` distroless variants already set UID 65532 — keep it.
6. **Digest-pin production images.** `image@sha256:…` in deployment manifests. `:latest` and floating semver tags are for local dev only.
7. **Multi-platform builds are table stakes.** `linux/amd64,linux/arm64` minimum. Apple Silicon, Graviton, and Ampere all care.
8. **`COPY --link` for cross-stage and large file copies.** Independent layers that survive base-image rebases without invalidating downstream caches.
9. **Sign on push, verify on pull.** Cosign keyless on the build side, Kyverno `verifyImages` on the cluster side. SLSA provenance + SBOM as attestations on the same image index.
10. **Compose is dev, CI, and single-host. Period.** Multi-host production orchestration belongs to Kubernetes. Compose does not do HA, rolling updates, autoscaling, or zero-downtime — and shouldn't pretend to.
11. **Healthchecks paired with `service_healthy`.** Never `depends_on` as a plain list combined with `sleep` in entrypoints.
12. **Compose secrets via the `secrets:` block.** Files mount at `/run/secrets/<name>`. The official-image convention is `<VAR>_FILE=/run/secrets/<name>`.
13. **`compose.yaml`, no `version:` field.** The Compose Spec deprecated it; modern Compose ignores it and warns if present.
14. **`docker compose` (v2), not `docker-compose` (v1).** The Python tool was removed from official runners in 2024.
15. **One scanner in CI.** Trivy or Grype, not both. Docker Scout is for the developer UX, not the merge gate.

## Don't / Do

| Don't | Do |
|---|---|
| `FROM ubuntu:latest` | `FROM ubuntu:24.04@sha256:…` (digest pin, immutable tag) |
| `RUN apt-get update` then `RUN apt-get install …` in separate layers (cache poisoning) | One `RUN` with `--mount=type=cache,target=/var/cache/apt,sharing=locked` |
| `COPY package.json package-lock.json ./` then `RUN npm ci` then `COPY . .` | `RUN --mount=type=bind,source=.,target=/src --mount=type=cache,target=/root/.npm npm ci` |
| `ARG NPM_TOKEN=…` or `ENV DATABASE_PASSWORD=…` | `RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci` |
| `ADD ./app /app` for local files | `COPY ./app /app` (`ADD` is for `--checksum`-verified URLs and tar extraction only) |
| One huge `RUN <chain> && \ … && rm -rf /tmp/*` to "save layers" | Multiple small `RUN`s — layers are cheap, cache granularity matters more |
| `CMD ["sh", "-c", "node app.js"]` (shell wraps PID 1, swallows signals) | `CMD ["node", "app.js"]` (exec form) |
| No `USER` line (defaults to root) | `USER 65532:65532` or a `:nonroot` base image |
| `image: myapp:latest` in production manifests | `image@sha256:…` digest pin, Renovate bumps |
| `docker build .` (legacy builder) | `docker buildx build .` |
| `--platform linux/amd64` only | `--platform linux/amd64,linux/arm64` minimum |
| Notary v1 / Docker Content Trust | Cosign keyless via Sigstore |
| `docker export | docker import` to "flatten layers" | Leave layers alone — destroys provenance, gains nothing under BuildKit |
| `version: '3.8'` at the top of compose files | Drop it — the field is obsolete |
| `docker-compose up` (Python v1) | `docker compose up` (v2 plugin) |
| Bind-mounting `./:/app` for dev hot-reload | `develop.watch:` with `sync` / `sync+restart` / `rebuild` actions |
| `depends_on: [db]` paired with `sleep 30` in the entrypoint | `depends_on.db.condition: service_healthy` + a real `healthcheck:` block |
| Plaintext credentials in `environment:` | `secrets:` block + `<VAR>_FILE=/run/secrets/<name>` |
| Compose for multi-host production | Kubernetes (defer to the `kubernetes` skill) |
| `links:` between services | Default network DNS — services resolve each other by service name |
| Anonymous volumes for state you care about | Named volumes |
| `mem_limit: 512m` (legacy shorthand) | `deploy.resources.limits.memory: 512M` |
| Anonymous Docker Hub pulls in CI | Authenticate, or use a pull-through cache (ECR, Harbor, `mirror.gcr.io`) |
| Running `trivy` *and* `grype` *and* `docker scout` in CI | Pick one scanner |
| Building on a single arch when consumers run arm64 | Multi-platform manifest list |

## Adding to this skill

When a new convention lands, add it to the relevant topic file (or create a new one and link it from the decision tree). Keep `SKILL.md` lean — the decision tree is the contract, depth lives in topic files.

After editing anything in this skill, run `dot install` to refresh the symlinks across all three tools. No restart needed for Claude Code or Grok; OpenCode picks up changes on next session.
