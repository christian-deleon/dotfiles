# Dockerfile

A modern Dockerfile is a BuildKit program — heredocs, mount caches, build secrets, multi-platform args, parallel stages, and `COPY --link` are all first-class. The classic builder is gone (since Engine 23.0 `docker build` shells out to buildx), so writing for the legacy interpreter is writing for a machine that no longer exists. Every Dockerfile in 2026 starts with a frontend pin and assumes BuildKit features.

## The skeleton

```dockerfile
# syntax=docker/dockerfile:1
ARG BASE_RUNTIME=gcr.io/distroless/static-debian12:nonroot

FROM --platform=$BUILDPLATFORM <toolchain>:<version> AS build
ARG TARGETOS TARGETARCH
WORKDIR /src

# Dep fetch — bind-mount the source, cache the dep dir
RUN --mount=type=bind,source=.,target=/src,rw \
    --mount=type=cache,target=/root/.cache/<dep-cache> \
    <dep-fetch-command>

# Compile — cache the build cache, output to /out
RUN --mount=type=bind,source=.,target=/src,rw \
    --mount=type=cache,target=/root/.cache/<build-cache> \
    --mount=type=cache,target=/root/.cache/<dep-cache> \
    <build-command> -o /out/app

FROM ${BASE_RUNTIME}
COPY --link --from=build /out/app /app
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app"]
```

Read top-to-bottom: pin the frontend, declare the cross-build args, bind-mount source instead of `COPY .`, mount caches for both dep and build dirs, then a final stage with `COPY --link`, non-root user, and an exec-form entrypoint. The language skills fill in the toolchain-specific blanks.

## The frontend pin

```dockerfile
# syntax=docker/dockerfile:1
```

`docker/dockerfile:1` floats to the latest stable `1.x.x` of the Dockerfile frontend, which BuildKit pulls and runs *independently of the daemon version*. So a 2024-vintage Engine still gets 2026 Dockerfile syntax: heredocs, `COPY --link`, `ADD --checksum`, `--exclude`, `--parents`, all the modern `--mount` types. Pinning a specific minor (`:1.7`) freezes you out of fixes — don't. The `:1-labs` channel exposes experimental features like `RUN --device`; use it only when you need something there.

## Multi-stage builds

Name every stage (`FROM x AS build`), reach across with `COPY --from=<stage>`, and let unused stages get pruned automatically. Two common shapes:

**Compile → minimal runtime** (Go, Rust, C, statically-linked binaries):

```dockerfile
FROM golang:1.26 AS build
# ...compile...
FROM gcr.io/distroless/static-debian12:nonroot
COPY --link --from=build /out/app /app
```

**Build deps → runtime with interpreter** (Python, Node):

```dockerfile
FROM python:3.13-slim AS build
# ...install into /venv with uv...
FROM gcr.io/distroless/python3-debian12:nonroot
COPY --link --from=build /venv /venv
ENV PATH=/venv/bin:$PATH
```

`COPY --link` (Dockerfile 1.4+) creates an independent layer that doesn't depend on the layers below it. The result: rebasing the runtime stage onto a new distroless tag does not invalidate the downstream cache. Use it for every cross-stage copy and for large external file imports. The only catch: `--link` ignores `--chown` if the target path doesn't yet exist — set ownership at the source stage with `chown` or use a `:nonroot` base that already has the user.

## Cache mounts — the modern caching model

The single biggest shift this decade: **`RUN --mount=type=cache` replaces the "copy lockfile first, install, then copy source" idiom.** Cache mounts persist across builds and across branches, and they cache at the granularity of the package manager's own cache (each individual package), not the granularity of the lockfile diff (all-or-nothing).

```dockerfile
# apt — needs sharing=locked so concurrent builds don't fight
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates

# Go — module cache + build cache
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=bind,source=.,target=/src \
    go build -o /out/app ./cmd/app

# Python with uv — uv cache
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# Node with pnpm — pnpm store
RUN --mount=type=cache,target=/pnpm/store,id=pnpm \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=pnpm-lock.yaml,target=pnpm-lock.yaml \
    pnpm install --frozen-lockfile

# Cargo — registry + target dir
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    --mount=type=bind,source=.,target=/src,rw \
    cargo build --release --locked
```

`sharing` modes: `shared` (default, parallel reads + writes), `private` (one writer per build), `locked` (exclusive, the apt requirement). `id=<key>` namespaces caches so two services don't fight over the same dir.

**The old `&& rm -rf /var/lib/apt/lists/*` pattern is obsolete with cache mounts** — you want the lists cached. The `rm -f /etc/apt/apt.conf.d/docker-clean` line disables the base image's auto-deletion so apt actually populates the cache.

## Bind mounts — source without baking it in

`RUN --mount=type=bind,source=.,target=/src,rw` mounts the build context (or a subpath) into a `RUN` *without copying it into the image layer*. Combined with cache mounts, this means the dep-fetch step never produces a layer at all — the only thing that lands in the final stage is the artifact, copied across with `COPY --from`.

The `rw` flag makes the bind writable for tooling that wants to scratch into the source dir; default is read-only. Bind multiple files explicitly when you only need lockfile + manifest (`--mount=type=bind,source=uv.lock,target=uv.lock`) to keep the cache key tight.

## Secret mounts

```dockerfile
# File secret — mounted at /run/secrets/<id> by default
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci --omit=dev

# Environment secret — Dockerfile 1.10+
RUN --mount=type=secret,id=GITHUB_TOKEN,env=GITHUB_TOKEN \
    go mod download

# SSH agent forwarding
RUN --mount=type=ssh \
    git clone git@github.com:acme/private-deps.git
```

CLI side: `docker buildx build --secret id=npmrc,src=$HOME/.npmrc --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN --ssh default .` Secrets are scoped to the `RUN` that mounts them, never appear in layers or the build history, and are unreadable from later stages. **Use this for anything you would have put in `ARG TOKEN=…`.** Build args persist in image metadata and `docker history` and are visible to anyone who pulls the image.

## Multi-platform builds

`docker buildx build --platform linux/amd64,linux/arm64 .` produces a manifest list pointing at one image per arch. Two strategies:

**Cross-compile (preferred when the language supports it)** — pin the build stage to the *builder's* native arch via `--platform=$BUILDPLATFORM` and let the compiler emit the target arch's binary:

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.26 AS build
ARG TARGETOS TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=bind,source=.,target=/src \
    GOOS=$TARGETOS GOARCH=$TARGETARCH CGO_ENABLED=0 \
    go build -o /out/app ./cmd/app
```

Cross-compile is 5-10x faster than QEMU on arm64 builds from an amd64 host. Go is purely flag-driven; Rust uses `--target $TARGETARCH-unknown-linux-musl` or `…-unknown-linux-gnu`.

**QEMU emulation (fallback)** — leave `--platform` off the build stage. BuildKit transparently emulates the target arch. Slower but zero Dockerfile changes; the right answer for Python, Node, and anything with a complex C toolchain.

The auto-injected `ARG`s available in every stage:

| Arg | Value on an amd64 host targeting arm64 |
|---|---|
| `BUILDPLATFORM` | `linux/amd64` |
| `BUILDOS`, `BUILDARCH`, `BUILDVARIANT` | `linux`, `amd64`, `""` |
| `TARGETPLATFORM` | `linux/arm64` |
| `TARGETOS`, `TARGETARCH`, `TARGETVARIANT` | `linux`, `arm64`, `""` |

Declare the ones you reference (`ARG TARGETOS TARGETARCH`) inside the stage that uses them.

## `COPY` flags worth knowing

| Flag | What it does | When |
|---|---|---|
| `--link` | Independent layer, survives base-image rebase | Every cross-stage copy and large external import |
| `--chown=<uid>:<gid>` | Set ownership inline | Skip a separate `RUN chown` layer |
| `--chmod=<octal>` | Set mode inline | Same, for permissions |
| `--from=<stage>` | Copy from another stage | Cross-stage transfers |
| `--from=<image>` | Copy from any image without `FROM`-ing it | Pull a tool or config out of an upstream image |
| `--exclude=<pattern>` | Skip matching files | Big copies where you don't want a `.dockerignore` entry |
| `--parents` | Preserve directory structure relative to the source | Globbed copies of nested files |

`ADD` is reserved for two specific cases in 2026 — pulling a tarball that should auto-extract (rare), and `ADD --checksum=sha256:… <url>` for verified remote downloads. **For local files, always `COPY`.** `ADD` has historical magic behavior around URLs and tarballs that `COPY` cleanly avoids.

## `USER`, working directory, entrypoint

```dockerfile
# Bake the non-root user before CMD/ENTRYPOINT runs
USER 65532:65532

# Set WORKDIR for the runtime — avoid '.' or relative paths
WORKDIR /app

# Exec form — required for proper PID 1 signal handling
ENTRYPOINT ["/app"]
CMD ["--config", "/etc/app/config.yaml"]
```

**Always exec form** (`["cmd", "arg"]`), never shell form (`cmd arg`). Shell form wraps PID 1 in `/bin/sh -c`, which doesn't forward `SIGTERM` to the child — your container ignores `docker stop` and gets `SIGKILL`'d 10 seconds later. Distroless `static` images don't even *have* a shell, so shell form is a hard error.

The `:nonroot` variant of every distroless tag sets `USER 65532:65532` for you. Inherit that — don't override unless the workload genuinely needs a different UID (in which case give it a real UID, not root).

## `HEALTHCHECK`

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --start-interval=2s --retries=3 \
    CMD curl -fsS http://localhost:8080/healthz || exit 1
```

Useful for **standalone `docker run`** and `docker compose` (where it pairs with `depends_on.condition: service_healthy`). In Kubernetes the `HEALTHCHECK` directive is **ignored** — k8s uses its own `livenessProbe`/`readinessProbe`/`startupProbe`. If the image is k8s-only, skip it; if it might be `docker run`'d, include it.

`start_interval` (BuildKit 1.6+, dockerfile:1 frontend) probes more frequently during `start_period` so a service goes healthy seconds after it's actually ready instead of waiting a full `interval`.

## `.dockerignore`

Ship one with every project. Two failure modes it prevents: shipping secrets in the build context, and busting the cache on every commit because `.git/` changed.

```
# Version control
.git/
.gitignore

# Build outputs
target/
dist/
build/
node_modules/

# IDE
.idea/
.vscode/
*.swp

# Tests / docs
**/*.test.go
docs/

# Secrets
.env
.env.*
*.pem
*.key
secrets/

# Compose state
docker-compose.override.yaml
compose.override.yaml

# Dockerfile itself (don't copy it into the image)
Dockerfile
.dockerignore
```

When using `RUN --mount=type=bind,source=.,target=/src`, `.dockerignore` *still* applies — the bind mount sees the same filtered context.

## `ARG` vs `ENV`

- **`ARG`** — build-time only. Available inside `RUN`, not in the final image's env. Gets baked into image metadata (visible in `docker history`). Never put secrets here; use `--mount=type=secret`.
- **`ENV`** — runtime env var. Available to the running container's processes. Use for things the app legitimately reads at runtime (`PATH`, `PYTHONUNBUFFERED=1`, `RUST_LOG`).

`ARG` declared before the first `FROM` is "global" — referenceable as the value of `FROM <image>:${TAG}` but not inside stages unless re-declared. Re-declare with `ARG TAG` inside the stage that needs it.

## Init / PID 1

If the workload doesn't handle signals or reap zombies on its own, the answer in 2026 is `docker run --init` (or Kubernetes `shareProcessNamespace` / the pause container) — Docker bundles tini and exposes it via that flag. **Don't bake tini into the image** unless you can't control the runtime flags. The default recommendation has shifted: tini-in-Dockerfile is acceptable but no longer the right default, since most runtimes provide it.

If you must:

```dockerfile
FROM gcr.io/distroless/cc-debian12:nonroot
COPY --link --from=build /out/app /app
COPY --link --from=tini /tini /tini
ENTRYPOINT ["/tini", "--", "/app"]
```

## BuildKit checks — `--call=check`

```bash
docker buildx build --call=check .
```

Runs BuildKit's built-in Dockerfile linter (rules like `JSONArgsRecommended`, `SecretsUsedInArgOrEnv`, `LegacyKeyValueFormat`, `WorkdirRelativePath`). Fast, no external tool. Pair with `hadolint` in CI for the heavier `DL****` ruleset (and embedded ShellCheck for `RUN` blocks). Run both — they overlap but don't cover the same surface.

```yaml
# .github/workflows/build.yml — pre-build gate
- name: Hadolint
  uses: hadolint/hadolint-action@v3
  with:
    dockerfile: Dockerfile
- name: BuildKit checks
  run: docker buildx build --call=check .
```

## Heredocs

```dockerfile
RUN <<EOF
set -euo pipefail
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
rm -rf /var/lib/apt/lists/*
EOF

COPY <<EOF /etc/app/config.yaml
log:
  level: info
listen: ":8080"
EOF
```

Cleaner than `RUN apt-get update && \ apt-get install … && \ rm -rf …` chains, and you get real shell semantics (set -euo pipefail, multi-line if blocks, etc.). Use for any `RUN` longer than two commands.

## What about `HEALTHCHECK NONE`?

```dockerfile
HEALTHCHECK NONE
```

Explicitly disables an inherited healthcheck. Useful when a parent image set one and your app handles readiness differently — common when extending Debian/Ubuntu base images that ship a default healthcheck.

## Common anti-patterns

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| `RUN apt-get update` and `RUN apt-get install -y foo` in separate layers | If `install` is cached but `update` isn't, you get stale package lists pointing at vanished versions | One `RUN` with both, plus `--mount=type=cache` |
| `COPY package.json package-lock.json ./` then `RUN npm ci` then `COPY . .` | Caches at lockfile granularity; any lockfile change refetches everything | `RUN --mount=type=bind,source=.,target=/src --mount=type=cache,target=/root/.npm npm ci` |
| `ARG TOKEN=…` for an install-time secret | Persists in image metadata, visible to anyone with the image | `RUN --mount=type=secret,id=token …` |
| `ADD ./app /app` for local files | `ADD`'s tarball/URL magic is footgun-prone | `COPY ./app /app` |
| No `USER` line | Defaults to root | `USER 65532:65532` or a `:nonroot` base |
| `:latest` tag in `FROM` for prod | Non-reproducible, breaks rebuilds | Pin tag + digest; let Renovate bump |
| `CMD ["sh", "-c", "exec /app"]` | Wraps PID 1 in a shell; signals don't forward | `CMD ["/app"]` (exec form) |
| One giant chained `RUN` "to save layers" | Layers are cheap; cache granularity is what matters | Split into one `RUN` per logical step |
| `docker export | docker import` to flatten | Destroys provenance, gains nothing under BuildKit | Don't flatten |
| `WORKDIR app` (relative) | Resolved against the previous `WORKDIR`, surprising | `WORKDIR /app` (absolute) |
| Missing `.dockerignore` | Ships `.git/`, `node_modules/`, secrets into the build context | Always include one |
| Trying to install `tzdata` or `ca-certificates` into `distroless` | No package manager exists | Switch to `gcr.io/distroless/base-debian12` (includes both) or copy from a builder stage |
