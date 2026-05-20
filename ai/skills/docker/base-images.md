# Base images

Picking a base image is picking an attack surface, a runtime contract, and a maintenance burden in one decision. The 2026 default is **Google distroless** — small, runs as non-root, ships signed and SBOM-attested, no shell, no package manager, glibc-based. Reach for a fuller distro only when you need a package manager or shell at runtime; reach for `scratch` only when the binary is genuinely self-contained.

## The ranking

| Tier | Image | When | Why / caveats |
|---|---|---|---|
| **1** | `gcr.io/distroless/static-debian12:nonroot` | Statically-linked binary, no glibc deps | ~2 MB; CA certs, tzdata, `/etc/passwd` included; UID 65532 by default |
| **1** | `gcr.io/distroless/cc-debian12:nonroot` | Statically-linked + glibc (Rust without musl, C/C++) | Adds glibc, libgcc, libstdc++ |
| **1** | `gcr.io/distroless/base-debian12:nonroot` | Dynamic binary needing glibc | Adds glibc + busybox-shaped basics (no shell) |
| **1** | `gcr.io/distroless/python3-debian12:nonroot` | Python apps | Python 3.x + libs; no pip, no shell |
| **1** | `gcr.io/distroless/nodejs22-debian12:nonroot` | Node apps | Node runtime + libs; no npm, no shell |
| **1** | `gcr.io/distroless/java21-debian12:nonroot` | JVM apps | JRE only |
| **2** | `debian:12-slim` | Need apt + shell at build OR runtime | Real distro, package manager, shell. Larger (~80 MB). |
| **2** | `ubuntu:24.04` | Need Ubuntu-specific packages | Otherwise prefer debian-slim |
| **3** | `alpine:3.20` | Tightly controlled toolchain, accept musl libc | ~7 MB but **read the caveats** below |
| **3** | `scratch` | Binary that needs *literally* nothing else | No CA certs, no tzdata, no `/etc/passwd` — copy what you need |
| **Alt** | `cgr.dev/chainguard/<runtime>:latest-nonroot` | Faster CVE patching than distroless, vendor parity | Vendor-controlled; pin by digest. Wolfi-based, glibc. |

Always pair the tag with a digest pin in production manifests: `gcr.io/distroless/static-debian12:nonroot@sha256:...`. Renovate/Dependabot bumps both together.

## Distroless — the default

Google's distroless ([github.com/GoogleContainerTools/distroless](https://github.com/GoogleContainerTools/distroless)) ships minimal runtime images for common languages with no shell, no package manager, no setuid binaries, and a `:nonroot` variant that drops to UID 65532 automatically. The images are signed (cosign) and ship with SBOMs.

Variants worth knowing:

| Variant | Adds | When |
|---|---|---|
| `:latest` | (default) | Most users |
| `:nonroot` | `USER 65532:65532` | **Production default** |
| `:debug` | busybox shell at `/busybox/sh` | Debug only; never in prod |
| `:debug-nonroot` | Above + nonroot user | Debug with prod permissions |
| `:latest-amd64` / `:latest-arm64` | Per-arch pins | Avoid; use manifest-list tags |

Specific runtime images:

- **`static`** — statically-linked, no glibc. For Go (`CGO_ENABLED=0`), Rust (`musl` target), or any binary that ships its own deps.
- **`cc`** — glibc + libgcc + libstdc++. For Rust with `gnu` target, C/C++, anything dynamically linked to glibc.
- **`base`** — glibc + tzdata + ca-certs. For dynamic binaries needing common libs.
- **`python3`** — Python 3.x runtime. Copy your venv from a builder stage.
- **`nodejs22`** — Node 22 runtime.
- **`java21`** — JRE 21.

What's deliberately not included: shell, package manager, `apt`, `curl`, `wget`. If you need any of those at runtime, you've picked the wrong base — `debian:12-slim` is the right answer.

## Debian slim — when you need a shell or apt

```dockerfile
FROM debian:12-slim
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl tini && \
    groupadd -r -g 65532 nonroot && \
    useradd -r -u 65532 -g 65532 -s /sbin/nologin nonroot
USER 65532:65532
```

Real distro, real package manager, real shell. Cost: ~80 MB vs ~2-30 MB for distroless. Use when:

- The app shells out to system tools at runtime (`git`, `curl`, `ffmpeg`, etc.)
- Healthchecks need a shell or `wget`/`curl`
- You need glibc *and* the ability to install more packages later
- The base for an interactive debugging image

Always create a non-root user (`useradd`) and `USER` to it before `CMD`. Always use cache mounts for apt.

`ubuntu:24.04` is an acceptable alternative; pick debian-slim by default for the smaller size and faster security release cadence.

## Alpine — read this before reaching for it

Alpine Linux uses **musl libc** and **busybox**, not glibc and GNU coreutils. That's the source of every Alpine surprise.

Common breakage:

| Symptom | Cause |
|---|---|
| `pip install pandas/numpy/scipy` rebuilds from source (slow) or fails | Alpine has no glibc wheels on PyPI; musl wheels exist but are rare |
| Go binaries with cgo crash on DNS lookups | musl resolver doesn't honour `/etc/nsswitch.conf` the way glibc does |
| `getent` doesn't behave the same | busybox `getent` is a subset |
| `dig`, `nslookup`, `ping` are missing | Need `apk add bind-tools iputils` |
| `bash` scripts fail with `sh: bad substitution` | Alpine's `/bin/sh` is busybox ash, not bash. Install `bash` or rewrite POSIX. |
| Some Python wheels (binary deps) are unavailable | Use `python:3.13-slim` (debian-based) instead |
| Image size advantage vanishes after installing 10 packages | Pip-rebuilt wheels + extra packages closes the gap with debian-slim |

**Use alpine only when you control the entire toolchain** — a static Go binary, a Rust binary with the musl target, or a hand-rolled tooling image where the small base matters and the libc swap is intentional. For Python or Node, **default to distroless or debian-slim.**

## Scratch — for genuinely standalone binaries

```dockerfile
FROM scratch
COPY --link --from=build /out/app /app
COPY --link --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --link --from=build /usr/share/zoneinfo /usr/share/zoneinfo
USER 65532:65532
ENTRYPOINT ["/app"]
```

`scratch` is *nothing*. No `/etc/passwd`, no `/etc/hosts`, no CA bundle, no `/tmp`. You ship exactly what `COPY` puts there.

Use when:

- The binary makes HTTPS calls → you need `/etc/ssl/certs/ca-certificates.crt`
- The binary parses timestamps with tz info → you need `/usr/share/zoneinfo`
- The binary does user lookups → you need `/etc/passwd`
- Anything else the binary explicitly reads from the filesystem

The right answer is usually `distroless/static:nonroot` — it bundles CA certs, tzdata, and `/etc/passwd` already, and the size delta is negligible (a few MB). Reach for `scratch` only when you need the smallest possible image and you've audited every syscall.

## Chainguard — the strong alternative

Chainguard ships [Wolfi](https://wolfi.dev/)-based minimal images at `cgr.dev/chainguard/*`. They run as non-root by default, are signed (Sigstore), ship with SBOMs, and get CVE patches typically faster than Google's distroless. The free tier offers `:latest` tags that float — for reproducibility you still want to pin by digest.

```dockerfile
FROM cgr.dev/chainguard/static:latest-nonroot
COPY --link --from=build /out/app /app
ENTRYPOINT ["/app"]
```

Pick Chainguard over distroless when:

- You need a more aggressive CVE patching cadence
- You want Wolfi-style `apk`-based builder images (`cgr.dev/chainguard/wolfi-base`) for staging
- Your compliance / FedRAMP / FIPS story is easier with Chainguard's enterprise tier

Pick distroless when:

- Vendor neutrality matters (Google distroless is community-maintained on GoogleContainerTools)
- You're already on Google Cloud / Artifact Registry
- The slower CVE cadence of distroless is acceptable

Both are good choices. The skill defaults to distroless because of vendor neutrality, but Chainguard is a fully reasonable swap.

## What about Red Hat UBI?

`registry.access.redhat.com/ubi9/ubi-minimal` is the right pick when:

- Targeting OpenShift / Red Hat support contracts
- Compliance requires RHEL-derived bits
- Your enterprise customers ask for "RHEL-compatible"

For greenfield work without those constraints, distroless or Chainguard is smaller and faster-patched.

## Pinning by digest

Tags are mutable. `gcr.io/distroless/static-debian12:nonroot` can point at a different image tomorrow than today. **In production manifests, always pin by digest:**

```dockerfile
FROM gcr.io/distroless/static-debian12:nonroot@sha256:c2c8a52e...

# Multi-stage Dockerfile — same rule for the build stage
FROM golang:1.26@sha256:7c9e1b... AS build
```

Renovate / Dependabot:

```json
// renovate.json
{
  "extends": ["config:recommended"],
  "docker": {
    "pinDigests": true
  }
}
```

Renovate will open PRs bumping both the tag *and* the digest, so the human-readable tag stays current and the digest stays immutable.

## Size guideline (rough, multi-stage final image)

| Base | Approx final size (Go binary) |
|---|---|
| `scratch` | ~10 MB (binary + CA certs + tzdata) |
| `gcr.io/distroless/static-debian12:nonroot` | ~10-15 MB |
| `gcr.io/distroless/cc-debian12:nonroot` | ~30 MB |
| `gcr.io/distroless/base-debian12:nonroot` | ~45 MB |
| `alpine:3.20` | ~15 MB **but** musl traps |
| `debian:12-slim` | ~80 MB |
| `ubuntu:24.04` | ~100 MB |

Sub-100-MB images are the default in 2026. If your image is 500 MB, something is wrong (probably `apt-get install -y build-essential` running in the final stage instead of a builder stage).

## Don't / Do — base images

| Don't | Do |
|---|---|
| `FROM ubuntu:latest` | `FROM gcr.io/distroless/<runtime>:nonroot@sha256:...` |
| Default to `alpine:` for everything | distroless or debian-slim; alpine only with controlled toolchain |
| `python:3.13` (full) | `gcr.io/distroless/python3-debian12:nonroot` (with venv copied from builder) |
| `FROM node:22` (full) | `gcr.io/distroless/nodejs22-debian12:nonroot` |
| `FROM openjdk:21` | `gcr.io/distroless/java21-debian12:nonroot` |
| Mix dev/prod tags (e.g. `:bookworm` for build, `-slim` for runtime in the same project) | Pick a base family per project; pin both layers by digest |
| `scratch` for a binary that makes HTTPS calls | `distroless/static-debian12:nonroot` (CA certs included) |
| `apt-get install` in a distroless image | Switch to debian-slim or copy bins from a builder stage |
| Floating `:latest` in production | Pin tag + digest; Renovate handles the bump cadence |
| Roll your own non-root user in distroless | Use the `:nonroot` variant — UID 65532 already set |
| Custom Alpine image for "smaller" Python | distroless/python3 is smaller and avoids musl |
| `FROM ... AS final` for the final stage when only one final stage exists | Implicit final stage is fine; only name stages you reference cross-stage |
